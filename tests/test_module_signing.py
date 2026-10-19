"""Disposable signatures and failure tests; no host keys or TPM are accessed."""

import hashlib
import importlib.util
import json
import lzma
import os
import shutil
import struct
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "signing", os.environ["FRAMEWORK_SIGNING_SCRIPT"]
)
signing = importlib.util.module_from_spec(spec)
spec.loader.exec_module(signing)
publisher_spec = importlib.util.spec_from_file_location(
    "publisher", os.environ["SIGNING_PUBLISHER"]
)
publisher = importlib.util.module_from_spec(publisher_spec)
publisher_spec.loader.exec_module(publisher)


class ModuleSigning(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.key, self.cert = self.root / "fixture.key", self.root / "fixture.pem"
        signing.command(
            [
                "openssl",
                "req",
                "-new",
                "-x509",
                "-newkey",
                "rsa:2048",
                "-nodes",
                "-days",
                "1",
                "-subj",
                "/CN=disposable-test",
                "-keyout",
                self.key,
                "-out",
                self.cert,
            ]
        )
        self.certificate_hash = hashlib.sha256(
            publisher.public_der(self.cert)
        ).hexdigest()
        self.source, self.signed = self.root / "unsigned", self.root / "signed"
        self.source.mkdir()
        self.signed.mkdir()
        self.plan = {
            "version": 1,
            "kernel": "/nix/store/test-kernel",
            "module_version": "test",
            "unsigned": str(self.source),
            "certificate": str(self.cert),
            "signer": str(
                Path(os.environ["SIGNING_PUBLISHER"]).with_name("sign-module-tree.py")
            ),
        }
        self.manifest = {
            "version": 1,
            "kernel_store_path": self.plan["kernel"],
            "module_version": "test",
            "certificate_sha256": self.certificate_hash,
            "signed_modules": 2,
        }
        # Only signature framing is exercised here, not kernel ELF loading.
        payload = b"disposable-module-payload"
        raw = self.root / "raw"
        raw.write_bytes(payload)
        signature = signing.command(
            [
                "openssl",
                "cms",
                "-sign",
                "-binary",
                "-noattr",
                "-nocerts",
                "-outform",
                "DER",
                "-signer",
                self.cert,
                "-inkey",
                self.key,
                "-in",
                raw,
            ]
        )
        signed = (
            payload
            + signature
            + bytes([0, 0, 2, 0, 0, 0, 0, 0])
            + struct.pack(">I", len(signature))
            + b"~Module signature appended~\n"
        )
        for name in ("probe.ko", "compressed.ko.xz"):
            old, new = signed, payload
            if name.endswith(".xz"):
                old, new = lzma.compress(old), lzma.compress(new)
            (self.source / name).write_bytes(new)
            (self.signed / name).write_bytes(old)
        for directory in (self.source, self.signed):
            (directory / "modules.dep").write_text("test dependency metadata\n")
        (self.signed / signing.MANIFEST).write_text(json.dumps(self.manifest))

    def adopts(self):
        return signing.can_adopt(
            self.signed, self.plan, self.certificate_hash, publisher, self.root
        )

    def test_adopt_requires_real_signatures_and_identical_payloads(self):
        self.assertTrue(self.adopts())
        (self.source / "probe.ko").write_bytes(b"changed module, same kernel ABI")
        self.assertFalse(self.adopts())

    def test_bad_signature_is_not_adopted(self):
        data = bytearray((self.signed / "probe.ko").read_bytes())
        data[-100] ^= 1
        (self.signed / "probe.ko").write_bytes(data)
        self.assertFalse(self.adopts())

    def test_missing_module_or_changed_metadata_is_not_adopted(self):
        (self.signed / "probe.ko").unlink()
        self.assertFalse(self.adopts())
        (self.source / "probe.ko").unlink()
        (self.signed / "modules.dep").write_text("changed")
        self.assertFalse(self.adopts())

    def test_cache_identity_tracks_source_and_trust(self):
        current = signing.identity(self.plan)
        self.assertEqual(
            current, signing.identity(dict(reversed(list(self.plan.items()))))
        )
        self.assertNotEqual(
            current, signing.identity(self.plan | {"unsigned": "new-source"})
        )
        self.assertNotEqual(
            current, signing.identity(self.plan | {"certificate": "new-trust"})
        )

    def test_unsigned_input_plan_outside_store_is_rejected(self):
        plan = self.root / "plan.json"
        plan.write_text(json.dumps(self.plan))
        with self.assertRaisesRegex(ValueError, "/nix/store"):
            signing.load_plan(plan)

    def test_runtime_certificate_must_match_kernel_trust(self):
        other = self.root / "other.pem"
        signing.command(
            [
                "openssl",
                "req",
                "-new",
                "-x509",
                "-key",
                self.key,
                "-days",
                "1",
                "-subj",
                "/CN=other-trust",
                "-out",
                other,
            ]
        )
        with self.assertRaisesRegex(ValueError, "kernel's public trust"):
            signing.prepare(self.plan, self.root, self.root / "public", self.key, other)

    def test_publish_replaces_real_directory_without_leaving_old_copies(self):
        target = self.root / "public"
        target.mkdir()
        (target / signing.MANIFEST).write_text("{}")
        (target / "old").write_text("old")
        signing.publish(self.signed, target)
        self.assertTrue((target / "probe.ko").exists())
        self.assertFalse((target / "old").exists())
        self.assertFalse(list(self.root.glob(".framework-modules-*")))

    def test_failed_publish_preserves_previous_input(self):
        target = self.root / "public"
        target.mkdir()
        (target / signing.MANIFEST).write_text("{}")
        (target / "old").write_text("old")
        with (
            patch.object(
                signing, "exchange", side_effect=OSError("disposable failure")
            ),
            self.assertRaises(OSError),
        ):
            signing.publish(self.signed, target)
        self.assertEqual((target / "old").read_text(), "old")
        self.assertFalse(list(self.root.glob(".framework-modules-*")))


class RebuildStages(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / "scripts").mkdir()
        (self.root / "bin").mkdir()
        runner = Path(
            os.environ.get(
                "FRAMEWORK_REBUILD_SCRIPT",
                str(
                    Path(os.environ["FRAMEWORK_SIGNING_SCRIPT"]).with_name(
                        "rebuild-framework.sh"
                    )
                ),
            )
        )
        shutil.copyfile(runner, self.root / "scripts/rebuild-framework.sh")
        self.write(
            "scripts/sign-framework-modules.sh",
            'echo sign >> "$REBUILD_LOG"; exit "${FAIL_SIGN:-0}"',
        )
        self.write(
            "scripts/prepare-framework-loader.sh",
            'echo prepare-efi >> "$REBUILD_LOG"; exit "${FAIL_EFI_SIGN:-0}"',
        )
        self.write("bin/sudo", 'exec "$@"')
        self.write(
            "bin/nix",
            """
echo "nix $*" >> "$REBUILD_LOG"
if [[ $1 == build ]]; then
    if [[ $2 == *frameworkModuleSigningPlan ]]; then
        ln -sfn "$PWD/plan" result-module-signing
    elif [[ $2 == *frameworkEfiPlan ]]; then
        ln -sfn "$PWD/plan" result-efi-plan
        exit "${FAIL_EFI_BUILD:-0}"
    else
        exit "${FAIL_BUILD:-0}"
    fi
fi
""",
        )
        (self.root / "plan").write_text("disposable plan")
        self.env = os.environ | {
            "PATH": str(self.root / "bin") + os.pathsep + os.environ["PATH"],
            "REBUILD_LOG": str(self.root / "log"),
        }

    def write(self, name, body):
        file = self.root / name
        file.write_text(f"#!{shutil.which('bash')}\nset -euo pipefail\n" + body + "\n")
        file.chmod(0o755)

    def run_stage(self, **environment):
        return subprocess.run(
            ["bash", self.root / "scripts/rebuild-framework.sh", "build"],
            cwd=self.root,
            env=self.env | environment,
            capture_output=True,
            check=False,
        )

    def test_signing_failure_prevents_lock_refresh_and_system_build(self):
        result = self.run_stage(FAIL_SIGN="42")
        self.assertEqual(result.returncode, 42)
        log = (self.root / "log").read_text()
        self.assertIn("sign\n", log)
        self.assertNotIn("flake update", log)
        self.assertNotIn("system.build.toplevel", log)

    def test_failed_system_build_never_installs(self):
        result = self.run_stage(FAIL_BUILD="43")
        self.assertEqual(result.returncode, 43)
        log = (self.root / "log").read_text()
        self.assertIn("flake update signed-modules", log)
        self.assertIn("system.build.toplevel", log)
        self.assertNotIn("switch-to-configuration", log)
        self.assertNotIn("nix-env", log)

    def test_failed_efi_build_prevents_preparation_and_system_build(self):
        result = self.run_stage(FAIL_EFI_BUILD="44")
        self.assertEqual(result.returncode, 44)
        log = (self.root / "log").read_text()
        self.assertNotIn("prepare-efi", log)
        self.assertNotIn("system.build.toplevel", log)
        self.assertNotIn("switch-to-configuration", log)

    def test_failed_efi_signing_prevents_system_build(self):
        result = self.run_stage(FAIL_EFI_SIGN="45")
        self.assertEqual(result.returncode, 45)
        log = (self.root / "log").read_text()
        self.assertIn("prepare-efi", log)
        self.assertNotIn("system.build.toplevel", log)
        self.assertNotIn("switch-to-configuration", log)


if __name__ == "__main__":
    unittest.main()
