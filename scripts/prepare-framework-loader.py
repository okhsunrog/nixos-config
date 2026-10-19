"""Prepare the owner's main EFI and OS PCR signatures; never install rescue here."""
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile


def command(arguments):
    result = subprocess.run([str(arg) for arg in arguments], capture_output=True, check=True)
    return result.stdout


def load_installer(path):
    spec = importlib.util.spec_from_file_location("efi_installer", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def sections(image):
    """Use PE VirtualSize, excluding file alignment padding from measurements."""
    data = image.read_bytes()
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    count, optional_size = struct.unpack_from("<H", data, pe + 6)[0], struct.unpack_from("<H", data, pe + 20)[0]
    if count > 64:
        raise ValueError("Too many EFI sections")
    result = {}
    measured = {".linux", ".osrel", ".cmdline", ".initrd", ".ucode", ".splash", ".dtb",
                ".uname", ".sbat", ".pcrpkey", ".dtbauto", ".hwids", ".efifw", ".profile"}
    for index in range(count):
        offset = pe + 24 + optional_size + index * 40
        name = data[offset:offset + 8].rstrip(b"\0").decode("ascii")
        if name not in measured:
            continue
        virtual_size, _, raw_size, raw_offset = struct.unpack_from("<IIII", data, offset + 8)
        if name in result or raw_offset + raw_size > len(data) or virtual_size > raw_size:
            raise ValueError("Unsupported EFI section layout")
        result[name] = data[raw_offset:raw_offset + virtual_size]
    if ".profile" in result:
        raise ValueError("Multi-profile UKIs need separate policy handling")
    return result


def signatures(plan, image, directory):
    arguments = [plan["measure"], "sign", "--bank=sha256", "--phase=enter-initrd",
                 "--policyref=initrd", "--private-key=" + plan["pcrKey"],
                 "--public-key=" + plan["pcrPublicKey"], "--json=short"]
    measured = {".linux", ".osrel", ".cmdline", ".initrd", ".ucode", ".splash", ".dtb",
                ".uname", ".sbat", ".pcrpkey", ".dtbauto", ".hwids", ".efifw"}
    content = sections(image)
    if not {".linux", ".initrd", ".osrel", ".uname"}.issubset(content):
        raise ValueError("Expected a complete single-profile UKI")
    for name in measured & content.keys():
        file = directory / name[1:]
        file.write_bytes(content[name])
        arguments.append(f"--{name[1:]}={file}")
    return json.loads(command(arguments))


def write_atomic(path, data):
    fd, temporary = tempfile.mkstemp(prefix=".zbm-policy-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, 0o644)
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def prepare(plan):
    installer = load_installer(plan["installer"])
    deployment = Path(plan["deployment"])
    image = deployment / "esp/EFI/BOOT/BOOTX64.EFI"
    state = deployment.parent
    state.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.environ["TMPDIR"] = str(state)
    tempfile.tempdir = str(state)
    os.environ["PATH"] = plan["toolPath"]
    with (state / "prepare.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        expected_certificate = command(["openssl", "x509", "-in", plan["certificate"], "-outform", "DER"])
        actual_certificate = command(["openssl", "x509", "-in", plan["efi"]["certificate"], "-outform", "DER"])
        if expected_certificate != actual_certificate:
            raise ValueError("Runtime EFI certificate differs from the image's pinned trust")
        if not deployment.exists():
            command(["uv", "run", "--offline", "--no-project", "python", plan["publisher"], plan["image"], deployment,
                     "--efi-key", "/var/lib/secureboot/db.key", "--efi-cert", "/var/lib/secureboot/db.pem",
                     "--ima-key", "/var/lib/secureboot/ima.key", "--ima-cert", "/var/lib/secureboot/ima.pem",
                     "--module-key", "/var/lib/secureboot/db.key", "--module-cert", "/var/lib/secureboot/db.pem",
                     "--sign-file", plan["signFile"], "--evmctl", plan["evmctl"], "--ukify", plan["ukify"]])
        installer.verify(image, plan["efi"]["certificate"])
        private_public = command(["openssl", "pkey", "-in", plan["pcrKey"], "-pubout", "-outform", "DER"])
        expected = command(["openssl", "pkey", "-pubin", "-in", plan["pcrPublicKey"], "-outform", "DER"])
        if private_public != expected:
            raise ValueError("PCR signing key differs from the OS's public policy key")
        policy = Path(plan["pcrSignatures"])
        previous = json.loads(policy.read_text()) if policy.exists() else {}
        with tempfile.TemporaryDirectory(prefix="policy-", dir=state) as temporary:
            directory = Path(temporary)
            policies = [previous, signatures(plan, image, directory)]
            # Keep the currently installed loader authorized during the transition.
            # Already prepared snapshot initrds remain immutable and retain
            # their own policies; merging here only affects new generations.
            with installer.mounted(plan["efi"], state) as esp:
                current = esp / plan["efi"]["path"]
                if current.exists():
                    installer.verify(current, plan["efi"]["certificate"])
                    policies.append(signatures(plan, current, directory))
            merged = {}
            for document in policies:
                for bank, entries in document.items():
                    for record in entries:
                        if record not in merged.setdefault(bank, []):
                            merged[bank].append(record)
            write_atomic(policy, (json.dumps(merged, indent=2) + "\n").encode())
        print("Prepared signed main EFI and merged OS PCR policy; ESP files unchanged")


if __name__ == "__main__":
    if os.geteuid() != 0:
        raise ValueError("Run through sudo with an immutable Nix signing plan")
    plan_path = Path(sys.argv[1]).resolve(strict=True)
    if plan_path.parent != Path("/nix/store"):
        raise ValueError("Expected an immutable Nix plan")
    plan = json.loads(plan_path.read_text())
    if plan["version"] != 1:
        raise ValueError("Unsupported plan")
    prepare(plan)
