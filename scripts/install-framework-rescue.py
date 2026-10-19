"""Install only the explicitly requested unsigned rescue image."""
import json
import os
from pathlib import Path
import sys

from importlib.util import module_from_spec, spec_from_file_location

plan_path = Path(sys.argv[1]).resolve(strict=True)
if os.geteuid() != 0 or plan_path.parent != Path("/nix/store"):
    raise ValueError("Expected root and an immutable Nix rescue plan")
plan = json.loads(plan_path.read_text())
if plan["version"] != 1 or plan["efi"]["certificate"] is not None:
    raise ValueError("Rescue must remain unsigned")
os.environ["PATH"] = plan["toolPath"]
spec = spec_from_file_location("efi_installer", plan["installer"])
installer = module_from_spec(spec)
spec.loader.exec_module(installer)
installer.deploy(plan["efi"] | {"image": plan["image"]})
