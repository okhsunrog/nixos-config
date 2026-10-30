"""Signing an offline system must not write the running system's policy."""
import importlib.util
import os
from pathlib import Path
import tempfile

spec = importlib.util.spec_from_file_location("prepare", os.environ["EFI_PREPARE"])
prepare = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prepare)
plan = {
    "deployment": "/var/lib/zbm-rs-signing/loader/test",
    "pcrKey": "/var/lib/secureboot/pcr.key",
    "pcrPublicKey": "/etc/systemd/pcr.pem",
    "pcrSignatures": "/etc/systemd/pcr.json",
    "certificate": "/nix/store/pinned-public-certificate",
    "image": "/nix/store/unsigned-image",
    "efi": {"certificate": "/var/lib/secureboot/db.pem", "partuuid": "external-esp"},
}
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory).resolve()
    mapped = prepare.plan_for_root(plan, root)
    assert mapped["pcrSignatures"] == str(root / "etc/systemd/pcr.json")
    assert mapped["deployment"] == str(root / "var/lib/zbm-rs-signing/loader/test")
    assert mapped["efi"]["certificate"] == str(root / "var/lib/secureboot/db.pem")
    assert mapped["certificate"] == plan["certificate"]
    assert mapped["image"] == plan["image"]
    assert plan["efi"]["certificate"] == "/var/lib/secureboot/db.pem"
    for value in ("relative/path", "/etc/../var/key"):
        try:
            prepare.runtime_path(root, value)
        except ValueError:
            pass
        else:
            raise AssertionError("Accepted an unsafe runtime path")
    (root / "escape").symlink_to("/etc", target_is_directory=True)
    try:
        prepare.runtime_path(root, "/escape/host-policy")
    except ValueError:
        pass
    else:
        raise AssertionError("Accepted a path outside the offline root")
print("Offline signing keeps runtime keys and policy inside the selected root")
