"""Stage an independent rescue, or promote the explicitly tested candidate."""
import json
import os
from pathlib import Path
import sys

sys.dont_write_bytecode = True
plan_path = Path(sys.argv[1]).resolve(strict=True)
if os.geteuid() != 0 or plan_path.parent != Path("/nix/store"):
    raise ValueError("Expected root and an immutable Nix rescue plan")
plan = json.loads(plan_path.read_text())
if plan["version"] != 2 or plan["efi"]["certificate"] is not None:
    raise ValueError("Expected a guarded unsigned rescue lifecycle plan")
os.environ["PATH"] = plan["toolPath"]
os.execv(sys.executable, [sys.executable, plan["installer"], str(plan_path), *sys.argv[2:]])
