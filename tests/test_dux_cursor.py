"""Exercise the installed Dux cursor command without an X server."""
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

source = Path(os.environ["DMS_SETTINGS"]).read_text()
body = source.split("function updateXResources() {", 1)[1].split("function getCursorEnvironment()", 1)[0]
script = json.loads(re.search(r"const script = (\".*\");", body).group(1))
assert "homeDir" not in body and "xresources_file" not in body
assert '"dms-cursor", themeName, String(size)' in body
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    resource = root / ".Xresources"
    resource.write_text("Xft.dpi: 144\nXcursor.theme: KDETheme\n")
    original = resource.read_bytes()
    xrdb = root / "xrdb"
    xrdb.write_text('#!/bin/sh\ncat > "$CURSOR_CAPTURE"\n')
    xrdb.chmod(0o755)
    capture = root / "capture"
    theme = 'A cursor; $(touch UNEXPECTED) " theme'
    env = os.environ | {"HOME": str(root), "PATH": str(root) + ":" + os.environ["PATH"],
                       "CURSOR_CAPTURE": str(capture)}
    subprocess.run(["sh", "-c", script, "dms-cursor", theme, "32"], env=env, cwd=root, check=True)
    assert capture.read_text() == f"Xcursor.theme: {theme}\nXcursor.size: 32\n"
    assert resource.read_bytes() == original
    assert not list(root.glob(".Xresources.backup*"))
    assert not (root / "UNEXPECTED").exists()
print("Dux updates runtime X cursor resources without changing shared files")
