# Android development

`hosts/framework/daily-tools.nix` installs `android-tools` (ADB and fastboot),
`scrcpy` and `jetbrains-toolbox`. The current pinned packages provide Android
tools 37.0.0 and Toolbox 3.8.1.88030. Toolbox runs inside Nixpkgs' FHS environment;
update its installation through NixOS. Its downloaded IDEs and settings remain
in the user's home directory.

The Arch fallback had Android tools 37.0.0.p1, Toolbox 3.6.4.86641 and
`android-udev` 20260922. Its separate `51-android.rules` used a vendor/device list.
That file is not imported into NixOS.

Systemd 262.1 already recognizes Android debug USB interfaces in
`70-uaccess.rules` and grants access to the active local desktop user through
`uaccess`. No additional vendor rules or `adbusers` group are needed for that
case. Remote/headless access without an active local seat is a separate policy.

Enable USB debugging on the phone, connect it, and accept its RSA prompt:

```sh
adb devices -l
adb shell
```

When the phone is already in its bootloader, use `fastboot devices`. Run these
commands as the normal user, without a separate root-owned ADB server or key.

The migrated user Toolbox desktop entry pointed to a copied Arch-era home
binary and shadowed the packaged launcher. It was backed up outside the
application search path when switching to the packaged launcher. The existing
`~/.local/share/JetBrains/Toolbox/apps/android-studio` installation and settings
were preserved.
Launch downloaded IDEs through Toolbox's FHS environment; directly launching
older home binaries may need separate NixOS compatibility fixes.

References:

- <https://wiki.nixos.org/wiki/Android#ADB_setup>
- <https://www.jetbrains.com/help/toolbox-app/installation.html>
