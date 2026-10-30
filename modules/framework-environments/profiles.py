"""Prepared desktop exceptions, switched before login without logout hooks.

An active mutable file always lives at its normal home path. Before replacing
it, persist the outgoing version and a complete incoming transaction. Recovery
replays that transaction, so a power cut never saves half of the incoming
profile as the outgoing one. No application databases are merged.
"""
import fcntl
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

RUNTIME_STATE = Path("/run/framework-desktop-profile.json")


def user_home(data):
    return Path(f"/home/{data['user']}")


def sync_directory(path):
    fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def atomic_json(path, value):
    atomic_file(path, json.dumps(value, indent=2).encode(), 0o600)


def atomic_file(path, content, mode=0o600, owner=None):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".profile-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as out:
            out.write(content)
            os.fchmod(out.fileno(), mode)
            if owner is not None:
                os.fchown(out.fileno(), *owner)
            out.flush()
            os.fsync(out.fileno())
        os.replace(temporary, path)
        sync_directory(path.parent)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def safe_path(root, relative):
    path = root
    if root.is_symlink():
        raise ValueError(f"Refusing symlink root: {root}")
    for part in Path(relative).parts:
        path /= part
        if path.is_symlink():
            raise ValueError(f"Refusing symlink in profile path: {path}")
    return path


def file_value(path):
    if not path.exists():
        return None
    if not path.is_file():
        raise ValueError(f"Expected regular file: {path}")
    return {"content": path.read_bytes().hex(), "mode": path.stat().st_mode & 0o777}


def put_value(path, value, owner=None):
    if value is None:
        if path.exists():
            if not path.is_file():
                raise ValueError(f"Expected regular file: {path}")
            path.unlink()
            sync_directory(path.parent)
    else:
        atomic_file(path, bytes.fromhex(value["content"]), value["mode"], owner)


def dconf(data, home, key, value=...):
    """Use a private bus, as the real user's normal dconf DB, before login."""
    with tempfile.TemporaryDirectory(prefix="framework-dconf-", dir="/run") as runtime:
        os.chown(runtime, data["uid"], data["gid"])
        command = ["dconf", "read", key] if value is ... else (
            ["dconf", "reset", key] if value is None else ["dconf", "write", key, value]
        )
        env = {"PATH": os.environ["PATH"], "HOME": str(home),
               "XDG_CONFIG_HOME": str(home / ".config"), "XDG_RUNTIME_DIR": runtime,
               "XDG_DATA_DIRS": "/run/current-system/sw/share", "XDG_CONFIG_DIRS": "/etc/xdg"}
        result = subprocess.run(
            ["setpriv", "--reuid", str(data["uid"]), "--regid", str(data["gid"]),
             "--clear-groups", "dbus-run-session", "--", *command],
            env=env, check=True, capture_output=True, text=True)
        return result.stdout.strip() or None


def layout(data):
    cfg = data.get("configProfiles", {})
    if not cfg.get("enable"):
        raise ValueError("Desktop configuration profiles are disabled")
    return {key: cfg[key] for key in ("mutableFiles", "bindDirectories", "dconfKeys")}


def prepared(data):
    root = Path(data["configProfiles"]["root"])
    state = json.loads((root / "state.json").read_text())
    if state["layout"] != layout(data):
        raise ValueError("Profile paths changed: prepare the new layout explicitly before boot")
    if state["current"] not in data["entries"]:
        raise ValueError("Prepared active profile is not declared")
    for name, entry in data["entries"].items():
        if entry["enable"]:
            profile = json.loads((root / name / "files.json").read_text())
            if set(profile) != set(state["layout"]["mutableFiles"]):
                raise ValueError(f"Incomplete prepared files: {name}")
            keys = json.loads((root / name / "dconf.json").read_text())
            if set(keys) != set(state["layout"]["dconfKeys"]):
                raise ValueError(f"Incomplete prepared dconf keys: {name}")
            for rel in state["layout"]["bindDirectories"]:
                if not safe_path(root / name / "dirs", rel).is_dir():
                    raise ValueError(f"Unprepared profile directory: {name}/{rel}")
    return root, state


def prepare(data, sources, apply=False):
    paths = layout(data)
    root = Path(data["configProfiles"]["root"])
    if root.exists():
        raise ValueError(f"Already prepared or incomplete; refusing overwrite: {root}")
    names = {name for name, entry in data["entries"].items() if entry["enable"]}
    if set(sources) != names:
        raise ValueError("Provide exactly one --source NAME=HOME for every enabled profile")
    if Path(sources[data["current"]]).resolve() != user_home(data).resolve():
        raise ValueError("Prepare from the current live profile; do not select another desktop")
    plans = {}
    for name, directory in sources.items():
        source = Path(directory)
        if not source.is_absolute() or not source.is_dir() or source.is_symlink():
            raise ValueError(f"Invalid source home: {source}")
        files = {rel: file_value(safe_path(source, rel)) for rel in paths["mutableFiles"]}
        for rel in paths["bindDirectories"]:
            if not safe_path(source, rel).is_dir():
                raise ValueError(f"Missing source directory: {name}/{rel}")
        print(f"{name}: prepare {len(files)} mutable files, {len(paths['bindDirectories'])} directories, {len(paths['dconfKeys'])} dconf keys from {source}")
        plans[name] = files
    if not apply:
        print("Dry run: no files changed. Use --apply for explicit preparation.")
        return
    root.mkdir(mode=0o700, parents=True)
    for name, directory in sources.items():
        profile = root / name
        profile.mkdir(mode=0o700)
        atomic_json(profile / "files.json", plans[name])
        atomic_json(profile / "dconf.json", {key: dconf(data, Path(directory), key) for key in paths["dconfKeys"]})
        for rel in paths["bindDirectories"]:
            target = profile / "dirs" / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copytree(Path(directory) / rel, target, symlinks=True)
            for parent, directories, files in os.walk(target):
                os.chown(parent, data["uid"], data["gid"])
                for leaf in directories + files:
                    item = Path(parent) / leaf
                    os.lchown(item, data["uid"], data["gid"])
                    if item.is_file() and not item.is_symlink():
                        with item.open("rb") as contents:
                            os.fsync(contents.fileno())
                sync_directory(parent)
            sync_directory(target.parent)
    atomic_json(root / "state.json", {"current": data["current"], "layout": paths})
    sync_directory(root.parent)
    print("Prepared. No live files, dconf settings or mounts were changed.")


def activate(data):
    if os.geteuid() != 0:
        raise ValueError("Profile activation requires root")
    # A boot-only operation. An active user session must never be remapped.
    if subprocess.run(["systemctl", "is-active", "--quiet", f"user@{data['uid']}.service"]).returncode == 0:
        raise ValueError("Desktop profile activation must run before login")
    root, state = prepared(data)
    with (root / "lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        state = json.loads((root / "state.json").read_text())
        pending = root / "pending.json"
        live_home = user_home(data)

        def finish(transaction):
            for rel, value in transaction["files"].items():
                target = safe_path(live_home, rel)
                if not target.parent.is_dir():
                    raise ValueError(f"Missing prepared destination parent: {target.parent}")
                put_value(target, value, (data["uid"], data["gid"]))
            for key, value in transaction["dconf"].items():
                dconf(data, live_home, key, value)
            state["current"] = transaction["target"]
            atomic_json(root / "state.json", state)
            pending.unlink()
            sync_directory(root)

        if pending.exists():
            finish(json.loads(pending.read_text()))
        selected = data["current"]
        if state["current"] != selected:
            outgoing = root / state["current"]
            files = {rel: file_value(safe_path(live_home, rel)) for rel in state["layout"]["mutableFiles"]}
            keys = {key: dconf(data, live_home, key) for key in state["layout"]["dconfKeys"]}
            atomic_json(outgoing / "files.json", files)
            atomic_json(outgoing / "dconf.json", keys)
            incoming = root / selected
            transaction = {"target": selected,
                           "files": json.loads((incoming / "files.json").read_text()),
                           "dconf": json.loads((incoming / "dconf.json").read_text())}
            atomic_json(pending, transaction)
            finish(transaction)
        atomic_json(RUNTIME_STATE, {
            "current": selected, "layout": state["layout"], "root": str(root)})
    print(f"Desktop configuration ready: {selected}")
