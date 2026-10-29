{ pkgs, framework }:
let
  lib = pkgs.lib;
  evaluated = import "${pkgs.path}/nixos/lib/eval-config.nix" {
    system = pkgs.stdenv.hostPlatform.system;
    modules = [
      ../modules/framework-environments
      {
        boot.loader.grub.enable = false;
        fileSystems."/" = {
          device = "test/root";
          fsType = "zfs";
        };
        system.stateVersion = "26.05";
        users.users.tester = {
          isNormalUser = true;
          uid = 1000;
          group = "tester";
        };
        users.groups.tester.gid = 1000;
        framework.environments = {
          enable = true;
          user = "tester";
          uid = 1000;
          gid = 1000;
          entries = {
            kde = {
              dataset = "test/home";
              backup = "mira";
            };
            experiment = {
              dataset = "test/experiment";
            };
          };
          variants.experiment = {
            environment.etc.variant.text = "experiment";
          };
        };
      }
    ];
  };
  cfg = evaluated.config;
  child = cfg.specialisation.experiment.configuration;
  preview =
    (framework.extendModules {
      modules = [ ({ lib, ... }: { framework.environments.entries.niri.enable = lib.mkForce true; }) ];
    }).config;
  niri = preview.specialisation.niri.configuration;
  backups = import ../modules/framework-environments/backups.nix {
    inherit lib;
    entries = cfg.framework.environments.entries // {
      disabled = {
        enable = false;
        dataset = "test/disabled";
        backup = "mira";
      };
    };
    base.jobs = [
      {
        type = "snap";
        name = "snap";
      }
      {
        type = "push";
        name = "push";
      }
    ];
  };
in
assert preview.services.desktopManager.plasma6.enable;
assert niri.programs.niri.enable;
assert !niri.services.desktopManager.plasma6.enable;
assert !niri.services.displayManager.plasma-login-manager.enable;
assert !niri.framework.plasmaLoginAuth.enable;
assert !(niri.security.pam.services ? plasmalogin);
assert niri.services.greetd.enable;
assert niri.security.pam.services.greetd.rules.auth.login.modulePath == "greetd-password";
assert !niri.security.pam.services.greetd-password.fprintAuth;
assert !niri.security.pam.services.greetd-password.allowNullPassword;
assert !niri.security.pam.services.dankshell.fprintAuth;
assert !niri.security.pam.services.dankshell.allowNullPassword;
assert !preview.security.pam.services.plasmalogin-auth.fprintAuth;
assert !preview.security.pam.services.kde-fingerprint.unixAuth;
assert preview.home-manager.users == { };
assert niri.programs.dms-greeter.enable;
assert niri.programs.dms-greeter.compositor.name == "niri";
assert !niri.security.pam.services.login.kwallet.enable;
assert !(niri.systemd.user.services ? plasma-kwallet-pam);
assert niri.home-manager.users.okhsunrog.home.homeDirectory == "/home/okhsunrog";
assert niri.home-manager.users.okhsunrog.programs.dank-material-shell.enable;
assert niri.home-manager.users.okhsunrog.programs.dank-calendar.enable;
assert niri.home-manager.users.okhsunrog.programs.dux-files.enable;
assert niri.home-manager.users.okhsunrog.programs.dsearch.enable;
assert !(niri.systemd.user.services ? dms);
assert niri.xdg.portal.config.niri."org.freedesktop.impl.portal.FileChooser" == "dfiles";
assert lib.all (
  p:
  !(builtins.elem (lib.getName p) [
    "foot"
    "fuzzel"
    "waybar"
    "mako"
    "swaylock"
    "tuigreet"
  ])
) niri.environment.systemPackages;
assert !niri.services.gnome.gnome-keyring.enable;
assert niri.xdg.portal.config.niri."org.freedesktop.impl.portal.Secret" == "kwallet";
assert niri.fileSystems."/home".device == "novafs/nixos0/data/home-niri";
assert lib.all (a: a.assertion) niri.assertions;
assert cfg.fileSystems."/home".device == "test/home";
assert cfg.fileSystems."/home".neededForBoot;
assert child.fileSystems."/home".device == "test/experiment";
assert child.fileSystems."/home".neededForBoot;
assert child.fileSystems."/home/tester/code/nixos-config".fsType == "none";
assert child.fileSystems."/var/lib/framework-environments/primary-home".device == "test/home";
assert
  (builtins.elemAt backups.jobs 0).filesystems == {
    "test/home" = true;
    "test/experiment" = true;
  };
assert (builtins.elemAt backups.jobs 1).filesystems == { "test/home" = true; };
pkgs.runCommand "framework-environments-tests"
  {
    nativeBuildInputs = [
      pkgs.uv
      pkgs.python3
    ];
    HOME_HELPER = ../modules/framework-environments/home.py;
  }
  ''
    uv run --offline --no-project --no-managed-python --no-cache \
      --python ${pkgs.python3}/bin/python3 ${./test_environments.py}
    touch $out
  ''
