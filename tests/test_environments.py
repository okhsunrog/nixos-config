import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("home", os.environ["HOME_HELPER"])
home = importlib.util.module_from_spec(spec)
spec.loader.exec_module(home)

DATA = dict(version=1, primary="kde", current="kde", user="tester", uid=1000, gid=1000,
            sharedDirectories=["code/nixos-config"], requiredDatasets=["pool/home"], entries={
                "kde": dict(dataset="pool/home", enable=True, backup="mira"),
                "test": dict(dataset="pool/home-test", enable=True, backup="local")})


class Homes(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.data = copy.deepcopy(DATA)

    def test_build_only_does_not_query_or_change_host(self):
        with patch.object(home, "run") as run:
            home.preflight(self.data, "build")
            run.assert_not_called()

    def test_failed_unmount_never_recursively_cleans_mountpoint(self):
        def command(*args):
            if args[:2] == ("zfs", "list"):
                return "pool\npool/home"
            if args[0] == "umount":
                raise subprocess.CalledProcessError(1, "umount")
            return ""
        with patch.object(home, "STATE_DIRECTORY", self.root), patch.object(home.os, "geteuid", return_value=0), patch.object(home.os, "chown"), patch.object(home, "run", side_effect=command):
            with self.assertRaises(subprocess.CalledProcessError):
                home.create(self.data, "test", None)
        self.assertTrue(list(self.root.glob("prepare-*/tester")))

    def test_rejects_unsafe_paths_and_duplicate_datasets(self):
        for path in ("../secret", "/etc", "code/../secret", "code//repo", ""):
            self.data["sharedDirectories"] = [path]
            file = self.root / "manifest"
            file.write_text(json.dumps(self.data))
            with self.assertRaises(ValueError):
                home.load(file)
        self.data = copy.deepcopy(DATA)
        self.data["entries"]["test"]["dataset"] = "pool/home"
        file.write_text(json.dumps(self.data))
        with self.assertRaises(ValueError):
            home.load(file)

    def test_existing_dataset_is_never_overwritten(self):
        with patch.object(home.os, "geteuid", return_value=0), patch.object(home, "run", return_value="pool\npool/home-test") as run:
            with self.assertRaisesRegex(ValueError, "Already exists"):
                home.create(self.data, "test", None)
            self.assertEqual(run.call_count, 1)
            self.assertEqual(run.call_args.args[:2], ("zfs", "list"))

    def test_failed_inventory_does_not_create(self):
        with patch.object(home.os, "geteuid", return_value=0), patch.object(home, "run", side_effect=subprocess.CalledProcessError(1, "zfs")) as run:
            with self.assertRaises(subprocess.CalledProcessError):
                home.create(self.data, "test", None)
            self.assertEqual(run.call_count, 1)

    def test_live_home_change_is_refused(self):
        with patch.object(home, "properties", return_value=("noauto", "/home")), patch.object(home, "run", return_value="available"), patch.object(home, "home_source", return_value="pool/home-test"):
            with self.assertRaisesRegex(ValueError, "reboot"):
                home.preflight(self.data, "switch")

    def test_shared_dataset_does_not_allow_cross_desktop_live_switch(self):
        self.data["homeMode"] = "shared"
        self.data["sharedDirectories"] = []
        self.data["entries"]["test"]["dataset"] = "pool/home"
        active = copy.deepcopy(self.data)
        with patch.object(home, "active_environment", return_value=(active, {"current": "kde"})), patch.object(home, "properties", return_value=("noauto", "/home")), patch.object(home, "run", return_value="available"), patch.object(home, "home_source", return_value="pool/home"):
            home.preflight(self.data, "switch")
            self.data["current"] = "test"
            with self.assertRaisesRegex(ValueError, "reboot"):
                home.preflight(self.data, "switch")

    def test_shared_dataset_requires_consistent_backup_policy(self):
        self.data["homeMode"] = "shared"
        self.data["entries"]["test"]["dataset"] = "pool/home"
        file = self.root / "manifest"
        file.write_text(json.dumps(self.data))
        with self.assertRaisesRegex(ValueError, "backup policy"):
            home.load(file)
        self.data["entries"]["test"]["backup"] = "mira"
        file.write_text(json.dumps(self.data))
        self.assertEqual(home.load(file)["homeMode"], "shared")

    def test_auto_mount_and_locked_key_are_refused(self):
        with patch.object(home, "properties", return_value=("on", "/home")):
            with self.assertRaisesRegex(ValueError, "canmount"):
                home.preflight(self.data, "boot")
        with patch.object(home, "properties", return_value=("noauto", "/home")), patch.object(home, "run", return_value="unavailable"):
            with self.assertRaisesRegex(ValueError, "key unavailable"):
                home.preflight(self.data, "boot")

    def test_retained_child_and_pre_manifest_generation_references(self):
        profiles = self.root / "profiles"
        profiles.mkdir()
        parent = self.root / "parent"
        (parent / "etc").mkdir(parents=True)
        (parent / "etc/fstab").write_text("pool/home /home zfs zfsutil 0 0\n")
        child = parent / "specialisation/test"
        (child / "etc").mkdir(parents=True)
        (child / "etc/framework-environments.json").write_text(json.dumps(dict(requiredDatasets=["pool/home-test", "pool/home"])))
        (profiles / "system-7-link").symlink_to(parent)
        refs = home.references(profiles, live=[])
        self.assertEqual(len(refs["pool/home"]), 2)
        self.assertEqual(refs["pool/home-test"], [str(profiles / "system-7-link/specialisation/test")])

    def test_bad_clone_source_is_refused_before_mutation(self):
        with patch.object(home.os, "geteuid", return_value=0), patch.object(home, "run", return_value="pool\npool/home") as run:
            with self.assertRaisesRegex(ValueError, "declared home"):
                home.create(self.data, "test", "pool/root@snap")
            self.assertEqual(run.call_count, 1)


if __name__ == "__main__":
    unittest.main()
