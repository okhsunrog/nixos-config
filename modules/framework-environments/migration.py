"""Explicit import of Niri-only settings; never overwrite an existing file."""
from pathlib import Path
import os
import profiles

SETTINGS = [
    ".config/niri/dms", ".config/dms", ".config/dfiles", ".config/dsearch",
    ".config/dankcal", ".config/cava", ".config/dgop",
    ".local/state/dms/session.json", ".local/state/dfiles/session.json",
    ".local/share/dankcal", ".local/share/themes/adw-gtk3", ".local/share/themes/adw-gtk3-dark",
    ".config/gtk-3.0/dank-colors.css", ".config/gtk-4.0/dank-colors.css",
]


def migrate(data, source, apply=False):
    source = Path(source)
    target = profiles.user_home(data)
    if not source.is_absolute() or not source.is_dir() or source.resolve() == target.resolve():
        raise ValueError("Expected an independently mounted source home")
    plan = []
    for rel in SETTINGS:
        path = profiles.safe_path(source, rel)
        if not path.exists():
            continue
        files = sorted(path.rglob("*")) if path.is_dir() else [path]
        for file in files:
            if file.is_symlink():
                raise ValueError(f"Refusing settings symlink: {file}")
            if file.is_dir():
                continue
            relative = str(file.relative_to(source))
            destination = profiles.safe_path(target, relative)
            value = profiles.file_value(file)
            if destination.exists():
                if destination.read_bytes() != file.read_bytes():
                    raise ValueError(f"Conflicting existing settings; choose explicitly: {relative}")
                continue
            plan.append((relative, value))
    for rel, value in plan:
        print(f"IMPORT {rel} ({len(value['content']) // 2} bytes)")
    print(f"{len(plan)} new files; existing files, browser profiles, credentials and repositories are not overwritten.")
    if not apply:
        print("Dry run: use --apply to import this selection.")
        return
    for rel, value in plan:
        destination = profiles.safe_path(target, rel)
        missing = []
        parent = destination.parent
        while not parent.exists():
            missing.append(parent)
            parent = parent.parent
        for parent in reversed(missing):
            parent.mkdir(mode=0o700)
            os.chown(parent, data["uid"], data["gid"])
        if destination.exists():
            raise ValueError(f"Destination appeared during migration: {destination}")
        profiles.put_value(destination, value, (data["uid"], data["gid"]))
    print("Imported selected Niri settings. The source home is unchanged.")
