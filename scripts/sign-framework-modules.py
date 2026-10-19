"""Prepare a cached public module input; private keys stay outside derivations."""

import ctypes
import fcntl
import gzip
import hashlib
import importlib.util
import json
import lzma
import os
import shutil
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

sys.dont_write_bytecode = True
MANIFEST = "zbm-module-manifest.json"
SUFFIXES = (".ko", ".ko.gz", ".ko.xz", ".ko.zst")


def command(arguments, **kwargs):
    result = subprocess.run(
        [str(arg) for arg in arguments], capture_output=True, check=True, **kwargs
    )
    return result.stdout


def store_path(value):
    path = Path(value).resolve(strict=True)
    if not path.is_relative_to("/nix/store"):
        raise ValueError("Signing plans and their public inputs must be in /nix/store")
    return path


def load_plan(file):
    plan = json.loads(store_path(file).read_text())
    if plan["version"] != 1:
        raise ValueError("Unsupported module signing plan")
    for name in (
        "kernel",
        "unsigned",
        "certificate",
        "sign_file",
        "signer",
        "python",
        "uv",
        "nix_store",
    ):
        store_path(plan[name])
    for directory in plan["tool_path"].split(os.pathsep):
        store_path(directory)
    if not plan["module_version"] or "/" in plan["module_version"]:
        raise ValueError("Invalid module ABI")
    return plan


def identity(plan):
    return hashlib.sha256(json.dumps(plan, sort_keys=True).encode()).hexdigest()


def manifest_at(tree):
    try:
        return json.loads((Path(tree) / MANIFEST).read_text())
    except (FileNotFoundError, ValueError):
        return {}


def matches(manifest, plan, certificate_hash):
    return (
        manifest.get("version") == 1
        and manifest.get("kernel_store_path") == plan["kernel"]
        and manifest.get("module_version") == plan["module_version"]
        and manifest.get("certificate_sha256") == certificate_hash
        and manifest.get("signed_modules", 0) > 0
    )


def files_in(tree):
    return {
        str((Path(directory) / name).relative_to(tree))
        for directory, _, names in os.walk(tree, followlinks=True)
        for name in names
    }


def module_bytes(file):
    data = file.read_bytes()
    if file.suffix == ".gz":
        return gzip.decompress(data)
    if file.suffix == ".xz":
        return lzma.decompress(data)
    if file.suffix == ".zst":
        return command(["zstd", "-q", "-d", "-c", file])
    return data


def signed_body(data):
    marker = b"~Module signature appended~\n"
    if not data.endswith(marker) or len(data) < len(marker) + 12:
        raise ValueError("Missing module signature")
    header = data[-len(marker) - 12 : -len(marker)]
    size = struct.unpack(">I", header[8:])[0]
    if (
        header[2] != 2
        or header[3:8] != b"\0" * 5
        or size > len(data) - len(marker) - 12
    ):
        raise ValueError("Invalid module signature header")
    return data[: len(data) - len(marker) - 12 - size]


def can_adopt(candidate, plan, certificate_hash, publisher, workspace):
    """Upgrade legacy provenance only after checking actual payloads/signatures."""
    if not matches(manifest_at(candidate), plan, certificate_hash):
        return False
    source = Path(plan["unsigned"])
    names = files_in(source)
    if names != files_in(candidate) - {MANIFEST}:
        return False
    checked = 0
    raw = workspace / "verify.ko"
    try:
        for name in sorted(names):
            old, new = candidate / name, source / name
            if name.endswith(SUFFIXES):
                data = module_bytes(old)
                if signed_body(data) != module_bytes(new):
                    return False
                raw.write_bytes(data)
                publisher.verify_module(raw, Path(plan["certificate"]))
                checked += 1
                if checked % 1000 == 0:
                    print(
                        f"Verified {checked} existing modules",
                        file=sys.stderr,
                        flush=True,
                    )
            elif old.read_bytes() != new.read_bytes():
                return False
    except (ValueError, RuntimeError):
        return False
    return checked == manifest_at(candidate)["signed_modules"]


def exchange(left, right):
    """Atomically replace a real directory; no missing-input interval."""
    libc = ctypes.CDLL(None, use_errno=True)
    rename = libc.renameat2
    rename.argtypes = [
        ctypes.c_int,
        ctypes.c_char_p,
        ctypes.c_int,
        ctypes.c_char_p,
        ctypes.c_uint,
    ]
    rename.restype = ctypes.c_int
    if rename(-100, os.fsencode(left), -100, os.fsencode(right), 2):
        number = ctypes.get_errno()
        raise OSError(number, os.strerror(number))


def publish(tree, public):
    public = Path(public)
    public.parent.mkdir(parents=True, exist_ok=True, mode=0o755)
    if public.is_symlink() or (public.exists() and not public.is_dir()):
        raise ValueError("The public module input must be a real directory")
    if manifest_at(public) == manifest_at(tree) and public.exists():
        return
    temporary = Path(tempfile.mkdtemp(prefix=".framework-modules-", dir=public.parent))
    try:
        shutil.copytree(tree, temporary, dirs_exist_ok=True, symlinks=False)
        temporary.chmod(0o755)
        if public.exists():
            exchange(temporary, public)
        else:
            temporary.rename(public)
        descriptor = os.open(public.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(descriptor)
        finally:
            os.close(descriptor)
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)


def prepare(plan, state, public, key, certificate):
    if public.is_symlink():
        raise ValueError("The public module input must be a real directory")
    if key.resolve().is_relative_to("/nix/store"):
        raise ValueError("Private signing keys must stay outside Nix")
    spec = importlib.util.spec_from_file_location(
        "framework_publisher", Path(plan["signer"]).with_name("publish-loader.py")
    )
    publisher = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(publisher)
    expected = publisher.public_der(Path(plan["certificate"]))
    if publisher.public_der(certificate) != expected:
        raise ValueError(
            "Runtime signing certificate differs from the kernel's public trust"
        )
    public_key = command(["openssl", "x509", "-in", certificate, "-pubkey", "-noout"])
    if command(["openssl", "pkey", "-in", key, "-pubout"]) != public_key:
        raise ValueError("Private signing key does not match the trusted certificate")
    certificate_hash = hashlib.sha256(expected).hexdigest()
    fingerprint = identity(plan)
    roots = state / "roots"
    roots.mkdir(mode=0o700, exist_ok=True)
    root = roots / fingerprint
    if root.exists():
        tree = store_path(root)
        manifest = manifest_at(tree)
        if (
            not matches(manifest, plan, certificate_hash)
            or manifest.get("signing_plan_sha256") != fingerprint
        ):
            raise ValueError("Cached signed module provenance is invalid")
        print("Reusing cached signed modules", file=sys.stderr)
    else:
        with tempfile.TemporaryDirectory(prefix="modules-", dir=state) as directory:
            workspace = Path(directory)
            previous_temp = tempfile.tempdir
            tempfile.tempdir = str(workspace)
            try:
                signed = workspace / "signed"
                candidate = public
                if can_adopt(candidate, plan, certificate_hash, publisher, workspace):
                    print(
                        "Existing signatures and all source payloads match; retaining them",
                        file=sys.stderr,
                    )
                    shutil.copytree(candidate, signed, symlinks=False)
                    signed.chmod(0o755)
                else:
                    print(
                        "Signing and verifying the changed module tree",
                        file=sys.stderr,
                        flush=True,
                    )
                    subprocess.run(
                        [
                            plan["uv"],
                            "run",
                            "--offline",
                            "--no-project",
                            "--python",
                            plan["python"],
                            plan["signer"],
                            plan["unsigned"],
                            str(signed),
                            "--kernel",
                            plan["kernel"],
                            "--key",
                            str(key),
                            "--cert",
                            str(certificate),
                            "--sign-file",
                            plan["sign_file"],
                        ],
                        check=True,
                        env=os.environ
                        | {
                            "TMPDIR": str(workspace),
                            "PYTHONDONTWRITEBYTECODE": "1",
                        },
                    )
                manifest = manifest_at(signed)
                if not matches(manifest, plan, certificate_hash):
                    raise ValueError("Signed module result does not match the plan")
                manifest.update(
                    unsigned_module_store_path=plan["unsigned"],
                    signing_plan_sha256=fingerprint,
                )
                (signed / MANIFEST).write_text(json.dumps(manifest) + "\n")
                tree = store_path(
                    command([plan["nix_store"], "--add", signed]).decode().strip()
                )
                if root.is_symlink():
                    root.unlink()  # Recover only a dangling private cache root.
                command(
                    [
                        plan["nix_store"],
                        "--add-root",
                        root,
                        "--indirect",
                        "--realise",
                        tree,
                    ]
                )
            finally:
                tempfile.tempdir = previous_temp
    publish(tree, public)
    print(f"Prepared signed module input for {plan['module_version']}", flush=True)


def main():
    if os.geteuid() != 0 or len(sys.argv) != 2:
        raise ValueError(
            "Run through sudo scripts/sign-framework-modules.sh SIGNING_PLAN"
        )
    plan = load_plan(sys.argv[1])
    os.environ["PATH"] = plan["tool_path"] + os.pathsep + os.environ["PATH"]
    state = Path("/var/lib/zbm-rs-signing")
    state.mkdir(mode=0o700, exist_ok=True)
    if state.stat().st_uid != 0 or state.stat().st_mode & 0o077:
        raise ValueError("Signing state must be root-owned mode 0700")
    with (state / ".lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        keys = Path("/var/lib/secureboot")
        if not (keys / "db.key").exists():
            keys = Path("/var/lib/sbctl/keys/db")
        prepare(
            plan,
            state,
            Path("/var/lib/zbm-rs-public/framework-modules"),
            keys / "db.key",
            keys / "db.pem",
        )
        # The derivation-backed plan retains its unsigned tree, kernel.dev and
        # signing tools even if result links are removed before a later GC.
        plan_root = state / "roots" / f"{identity(plan)}.plan"
        command(
            [
                plan["nix_store"],
                "--add-root",
                plan_root,
                "--indirect",
                "--realise",
                store_path(sys.argv[1]),
            ]
        )


if __name__ == "__main__":
    main()
