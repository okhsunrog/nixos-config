"""Explicit home preparation and rebuild preflight; never destroys datasets."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

DATASET = re.compile(r"[A-Za-z0-9_.:-]+(?:/[A-Za-z0-9_.:-]+)+\Z")
NAME = re.compile(r"[a-z][a-z0-9_-]*\Z")
STATE_DIRECTORY = Path("/var/lib/framework-environments")


def run(*args):
    return subprocess.check_output(args, text=True).strip()


def load(path):
    data = json.loads(Path(path).read_text())
    if data.get("version") != 1:
        raise ValueError("Unsupported environment manifest version")
    entries = data["entries"]
    if data["primary"] not in entries or data["current"] not in entries:
        raise ValueError("Unknown primary/current environment")
    datasets = []
    for name, entry in entries.items():
        if not NAME.fullmatch(name) or not DATASET.fullmatch(entry["dataset"]):
            raise ValueError("Invalid environment name or dataset")
        datasets.append(entry["dataset"])
    if len(datasets) != len(set(datasets)):
        raise ValueError("Home datasets must be distinct")
    user = data["user"]
    if not re.fullmatch(r"[a-z_][a-z0-9_-]*", user):
        raise ValueError("Invalid user name")
    for path in data["sharedDirectories"]:
        if not path or path.startswith("/") or any(p in ("", ".", "..") for p in path.split("/")):
            raise ValueError("Shared directories must be safe relative paths")
    for key in ("uid", "gid"):
        if not isinstance(data[key], int) or data[key] <= 0:
            raise ValueError("Home owner must have a positive UID/GID")
    return data


def properties(dataset):
    line = run("zfs", "list", "-H", "-o", "name,type,canmount,mountpoint", dataset)
    name, kind, canmount, mountpoint = line.split("\t")
    if name != dataset or kind != "filesystem":
        raise ValueError(f"Not a filesystem: {dataset}")
    return canmount, mountpoint


def home_source():
    return run("findmnt", "-n", "-o", "SOURCE", "--mountpoint", "/home")


def references(profiles=Path("/nix/var/nix/profiles"), live=None):
    """Read actual closures, including pre-manifest generations via fstab."""
    roots = list(profiles.glob("system-*-link")) + [profiles / "system"]
    roots += live if live is not None else [Path("/run/current-system"), Path("/run/booted-system")]
    result = {}
    seen = set()
    for root in roots:
        if not root.exists():
            continue
        closures = [root] + sorted((root / "specialisation").glob("*"))
        for closure in closures:
            resolved = closure.resolve()
            if resolved in seen:
                continue
            seen.add(resolved)
            manifest = closure / "etc/framework-environments.json"
            if manifest.exists():
                datasets = json.loads(manifest.read_text())["requiredDatasets"]
            else:
                fstab = closure / "etc/fstab"
                datasets = []
                if fstab.exists():
                    for line in fstab.read_text().splitlines():
                        fields = line.split()
                        if len(fields) >= 3 and not line.lstrip().startswith("#") and fields[2] == "zfs":
                            datasets.append(fields[0])
            for dataset in datasets:
                result.setdefault(dataset, []).append(str(closure))
    return result


def preflight(data, action):
    if action == "build":
        print("Build-only: runtime home checks are deferred until boot/switch.")
        return
    for name, entry in data["entries"].items():
        if not entry["enable"]:
            continue
        dataset = entry["dataset"]
        canmount, mountpoint = properties(dataset)
        if canmount != "noauto" or mountpoint != "/home":
            raise ValueError(f"{name}: require canmount=noauto and mountpoint=/home: {dataset}")
        key = run("zfs", "get", "-H", "-o", "value", "keystatus", dataset)
        if key == "unavailable":
            raise ValueError(f"Encryption key unavailable: {dataset}")
    selected = data["entries"][data["current"]]["dataset"]
    if action == "switch" and home_source() != selected:
        raise ValueError("Changing /home requires boot and a reboot; live switching is refused")
    # The source of shared checkouts must already be available, never fabricated.
    primary = data["entries"][data["primary"]]["dataset"]
    source = Path("/home") if home_source() == primary else Path("/var/lib/framework-environments/primary-home")
    for path in data["sharedDirectories"]:
        if not (source / data["user"] / path).is_dir():
            raise ValueError(f"Shared checkout unavailable: {source / data['user'] / path}")
    print("Home preflight passed; no dataset was created or changed.")


def create(data, name, snapshot):
    if os.geteuid() != 0:
        raise ValueError("Run create with sudo")
    if name == data["primary"]:
        raise ValueError("The primary home must be prepared separately")
    target = data["entries"][name]["dataset"]
    # A non-zero exit is not assumed to mean 'absent': list the parent first.
    parent = target.rsplit("/", 1)[0]
    existing = run("zfs", "list", "-H", "-r", "-o", "name", parent).splitlines()
    if target in existing:
        raise ValueError(f"Already exists; refusing to overwrite: {target}")
    if snapshot:
        source, sep, snap = snapshot.partition("@")
        if not sep or not snap or "/" in snap or "@" in snap:
            raise ValueError("Expected DATASET@SNAPSHOT")
        if source not in {e["dataset"] for e in data["entries"].values()}:
            raise ValueError("Clone source must be a declared home dataset")
        if source.split("/")[0] != target.split("/")[0]:
            raise ValueError("ZFS clones must be in the same pool")
        run("zfs", "list", "-H", "-t", "snapshot", "-o", "name", snapshot)
        run("zfs", "clone", "-o", "canmount=noauto", "-o", "mountpoint=/home", snapshot, target)
    else:
        run("zfs", "create", "-u", "-o", "canmount=noauto", "-o", "mountpoint=/home", target)
    # Mount only the new filesystem at a private path, never over the live home.
    state = STATE_DIRECTORY
    state.mkdir(mode=0o700, parents=True, exist_ok=True)
    mount = tempfile.mkdtemp(prefix="prepare-", dir=state)
    mounted = False
    try:
        run("mount", "-t", "zfs", "-o", "zfsutil", target, mount)
        mounted = True
        home = Path(mount) / data["user"]
        # Do not follow a symlink or recursively chown cloned user data.
        if home.is_symlink() or (home.exists() and not home.is_dir()):
            raise ValueError("User home must be a directory, not a symlink")
        home.mkdir(mode=0o700, exist_ok=True)
        os.chown(home, data["uid"], data["gid"])
        for shared in data["sharedDirectories"]:
            directory = home
            for part in shared.split("/"):
                directory /= part
                if directory.is_symlink() or (directory.exists() and not directory.is_dir()):
                    raise ValueError(f"Shared mountpoint must be a directory: {directory}")
                if not directory.exists():
                    directory.mkdir(mode=0o755)
                    os.chown(directory, data["uid"], data["gid"])
    finally:
        if mounted:
            run("umount", mount)
        # Never recursively clean a mountpoint, including when umount failed.
        os.rmdir(mount)
    print(f"Prepared {target}. Enable {name}, rebuild for boot, then reboot.")
    print("A clone retains its snapshot dependency; user configuration in the snapshot is copied too.")


def status(data):
    refs = references()
    mounts = json.loads(run("findmnt", "--json", "--list", "--output", "SOURCE,TARGET"))["filesystems"]
    for name, entry in data["entries"].items():
        dataset = entry["dataset"]
        print(f"{name}: {dataset} enabled={entry['enable']} backup={entry['backup']}")
        try:
            print("  " + run("zfs", "get", "-H", "-o", "property,value", "origin,canmount,mountpoint", dataset).replace("\n", "; "))
            snapshots = run("zfs", "get", "-H", "-r", "-t", "snapshot", "-o", "name,value", "clones", dataset)
            for line in snapshots.splitlines():
                snapshot, clones = line.split("\t")
                if clones != "-":
                    print(f"  dependent clones: {snapshot}: {clones}")
        except subprocess.CalledProcessError:
            print("  unavailable")
        for mount in mounts:
            if mount["source"] == dataset or mount["source"].startswith(dataset + "["):
                print(f"  mounted: {mount['target']}")
        for closure in refs.get(dataset, []):
            print(f"  referenced: {closure}")
    print("No destroy command is provided. References cover retained system profiles and current/booted closures, not arbitrary snapshots or external profiles.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", default="/etc/framework-environments.json")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("status")
    check = commands.add_parser("preflight")
    check.add_argument("--action", choices=["build", "boot", "switch"], default="boot")
    prepare = commands.add_parser("create")
    prepare.add_argument("name")
    source = prepare.add_mutually_exclusive_group(required=True)
    source.add_argument("--from", dest="snapshot")
    source.add_argument("--empty", action="store_true")
    args = parser.parse_args()
    data = load(args.manifest)
    if args.command == "status":
        status(data)
    elif args.command == "preflight":
        preflight(data, args.action)
    else:
        if args.name not in data["entries"]:
            raise ValueError(f"Unknown environment: {args.name}")
        create(data, args.name, args.snapshot)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"framework-home: {error}", file=sys.stderr)
        sys.exit(1)
