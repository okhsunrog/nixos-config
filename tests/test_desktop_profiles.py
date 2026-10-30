import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(os.environ["HOME_HELPER"]).parent))
import home
import profiles
import migration


class DesktopProfiles(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.live = self.root / "home"
        self.other = self.root / "niri"
        for directory, text in [(self.live, "kde"), (self.other, "niri")]:
            (directory / ".config/gtk").mkdir(parents=True)
            (directory / ".config/gtk/settings.ini").write_text(text)
            (directory / ".config/gtk/bookmarks").write_text("shared")
        self.data = dict(version=2, homeMode="shared", primary="kde", current="kde",
                         user="tester", uid=os.getuid(), gid=os.getgid(), sharedDirectories=[],
                         entries={n: dict(dataset="pool/home", enable=True, backup="mira") for n in ["kde", "niri"]},
                         configProfiles=dict(enable=True, root=str(self.root / "profiles"),
                           mutableFiles=[".config/gtk/settings.ini"], bindDirectories=[], dconfKeys=[]))
        self.patches = [patch.object(profiles, "user_home", return_value=self.live),
                        patch.object(profiles, "RUNTIME_STATE", self.root / "runtime.json"),
                        patch.object(profiles.os, "geteuid", return_value=0),
                        patch.object(profiles.os, "fchown"),
                        patch.object(profiles, "dconf", return_value=None),
                        patch.object(profiles.subprocess, "run", return_value=subprocess.CompletedProcess([], 3))]
        for p in self.patches:
            p.start()
            self.addCleanup(p.stop)

    def prepare(self):
        profiles.prepare(self.data, {"kde": str(self.live), "niri": str(self.other)}, apply=True)

    def test_dry_run_does_not_prepare_or_change_files(self):
        profiles.prepare(self.data, {"kde": str(self.live), "niri": str(self.other)})
        self.assertFalse(Path(self.data["configProfiles"]["root"]).exists())
        self.assertEqual((self.live / ".config/gtk/settings.ini").read_text(), "kde")

    def test_roundtrip_preserves_atomic_gui_edits_and_shared_bookmarks(self):
        self.prepare()
        self.data["current"] = "niri"
        profiles.activate(self.data)
        settings = self.live / ".config/gtk/settings.ini"
        staged = settings.with_suffix(".new")
        staged.write_text("niri GUI edit")
        staged.replace(settings)
        (self.live / ".config/gtk/bookmarks").write_text("new shared bookmark")
        self.data["current"] = "kde"
        profiles.activate(self.data)
        self.assertEqual(settings.read_text(), "kde")
        self.data["current"] = "niri"
        profiles.activate(self.data)
        self.assertEqual(settings.read_text(), "niri GUI edit")
        self.assertEqual((self.live / ".config/gtk/bookmarks").read_text(), "new shared bookmark")

    def test_interrupted_switch_replays_before_saving_outgoing_profile(self):
        self.data["configProfiles"]["mutableFiles"].append(".config/gtk/colors.css")
        (self.live / ".config/gtk/colors.css").write_text("kde-colors")
        (self.other / ".config/gtk/colors.css").write_text("niri-colors")
        self.prepare()
        self.data["current"] = "niri"
        original = profiles.put_value
        def interrupted(*args, **kwargs):
            original(*args, **kwargs)
            raise OSError("simulated power loss after replacing file")
        with patch.object(profiles, "put_value", side_effect=interrupted):
            with self.assertRaises(OSError):
                profiles.activate(self.data)
        self.data["current"] = "kde"
        profiles.activate(self.data)
        self.assertEqual((self.live / ".config/gtk/settings.ini").read_text(), "kde")
        self.assertEqual((self.live / ".config/gtk/colors.css").read_text(), "kde-colors")
        self.data["current"] = "niri"
        profiles.activate(self.data)
        self.assertEqual((self.live / ".config/gtk/settings.ini").read_text(), "niri")
        self.assertEqual((self.live / ".config/gtk/colors.css").read_text(), "niri-colors")

    def test_reject_symlink_and_layout_changes(self):
        settings = self.other / ".config/gtk/settings.ini"
        settings.unlink()
        settings.symlink_to(self.live / ".config/gtk/settings.ini")
        with self.assertRaisesRegex(ValueError, "symlink"):
            self.prepare()
        settings.unlink()
        settings.write_text("niri")
        self.prepare()
        self.data["configProfiles"]["mutableFiles"].append(".config/new")
        with self.assertRaisesRegex(ValueError, "changed"):
            profiles.activate(self.data)

    def test_refuse_activation_while_user_manager_is_running(self):
        self.prepare()
        with patch.object(profiles.subprocess, "run", return_value=subprocess.CompletedProcess([], 0)):
            with self.assertRaisesRegex(ValueError, "before login"):
                profiles.activate(self.data)

    def test_dconf_switch_touches_only_declared_keys(self):
        self.data["configProfiles"]["dconfKeys"] = ["/org/gnome/desktop/interface/color-scheme"]
        self.prepare()
        self.data["current"] = "niri"
        with patch.object(profiles, "dconf", return_value="'prefer-dark'") as dconf:
            profiles.activate(self.data)
            self.assertTrue(dconf.called)
            self.assertTrue(all(c.args[2] == "/org/gnome/desktop/interface/color-scheme" for c in dconf.call_args_list))

    def test_settings_migration_is_dry_by_default_and_refuses_conflicts(self):
        source = self.other / ".config/dms/settings.json"
        source.parent.mkdir()
        source.write_text('{"preference":true}')
        migration.migrate(self.data, str(self.other))
        dest = self.live / ".config/dms/settings.json"
        self.assertFalse(dest.exists())
        with patch.object(migration.os, "chown"):
            migration.migrate(self.data, str(self.other), apply=True)
        self.assertEqual(dest.read_bytes(), source.read_bytes())
        dest.write_text("different")
        with self.assertRaisesRegex(ValueError, "Conflicting"):
            migration.migrate(self.data, str(self.other), apply=True)


if __name__ == "__main__":
    unittest.main()
