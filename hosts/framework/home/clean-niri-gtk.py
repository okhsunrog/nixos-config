"""Remove Plasma's GTK integration modules from the active Niri profile."""
import os
from pathlib import Path
import re

plasma_modules = {"colorreload-gtk-module", "window-decorations-gtk-module"}


def clean_modules(match):
    modules = [name for name in match[1].split(":") if name and name not in plasma_modules]
    return "gtk-modules=" + ":".join(modules) + "\n" if modules else ""


for version in (3, 4):
    path = Path.home() / f".config/gtk-{version}.0/settings.ini"
    if not path.exists():
        continue
    original = path.read_text()
    cleaned = re.sub(r"^gtk-modules=([^\r\n]*)\r?\n?", clean_modules, original, flags=re.M)
    if cleaned == original:
        continue
    staged = path.with_name(path.name + ".niri-new")
    staged.write_text(cleaned)
    staged.chmod(path.stat().st_mode & 0o777)
    os.replace(staged, path)
