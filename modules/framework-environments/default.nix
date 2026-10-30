{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.framework.environments;
  enabled = lib.filterAttrs (_: env: env.enable) cfg.entries;
  selected = cfg.entries.${cfg.current};
  variants = lib.filterAttrs (name: _: name != cfg.primary) enabled;
  sharedRoot = "/var/lib/framework-environments/primary-home";
  profiles = cfg.configProfiles;
  safePath =
    p:
    p != ""
    && !lib.hasPrefix "/" p
    && lib.all (s: s != "" && s != "." && s != "..") (lib.splitString "/" p);
  profileMounts = map (p: "/home/${cfg.user}/${p}") profiles.bindDirectories;
  required = lib.unique (
    map (fs: fs.device) (lib.filter (fs: fs.fsType == "zfs") (lib.attrValues config.fileSystems))
  );
  manifest = pkgs.writeText "framework-environments.json" (
    builtins.toJSON {
      version = 2;
      inherit (cfg)
        primary
        current
        user
        uid
        gid
        entries
        sharedDirectories
        homeMode
        ;
      configProfiles = profiles // {
        root = "/home/.desktop-profiles/${cfg.user}";
      };
      requiredDatasets = required;
    }
  );
  helper = pkgs.writeShellApplication {
    name = "framework-home";
    runtimeInputs = [
      pkgs.uv
      pkgs.python3
      pkgs.zfs
      pkgs.util-linux
      pkgs.coreutils
      pkgs.dconf
      pkgs.dbus
    ];
    text = ''
      exec uv run --offline --no-cache --no-project --no-managed-python \
        --python ${pkgs.python3}/bin/python3 ${./.}/home.py \
        --manifest /etc/framework-environments.json "$@"
    '';
  };
in
{
  options.framework.environments = {
    enable = lib.mkEnableOption "boot environments with separate home datasets";
    homeMode = lib.mkOption {
      type = lib.types.enum [
        "separate"
        "shared"
      ];
      default = "separate";
    };
    configProfiles = {
      enable = lib.mkEnableOption "explicitly prepared desktop configuration profiles";
      mutableFiles = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Relative home paths exchanged before login; regular files remain writable and support atomic replacement.";
      };
      bindDirectories = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
      dconfKeys = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Individual desktop appearance keys; other dconf application data stays shared.";
      };
    };
    primary = lib.mkOption {
      type = lib.types.str;
      default = "kde";
    };
    current = lib.mkOption {
      type = lib.types.str;
      default = cfg.primary;
    };
    user = lib.mkOption { type = lib.types.str; };
    uid = lib.mkOption { type = lib.types.int; };
    gid = lib.mkOption { type = lib.types.int; };
    sharedDirectories = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "code/nixos-config"
        "code/nixos-secrets"
      ];
      description = "Paths relative to the user's primary home, bind-mounted in variants.";
    };
    entries = lib.mkOption {
      default = { };
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = true;
            };
            dataset = lib.mkOption { type = lib.types.str; };
            backup = lib.mkOption {
              type = lib.types.enum [
                "none"
                "local"
                "mira"
              ];
              default = "local";
            };
          };
        }
      );
    };
    variants = lib.mkOption {
      type = lib.types.attrsOf lib.types.deferredModule;
      default = { };
      description = "Desktop/configuration modules for non-primary entries.";
    };
  };
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion =
          builtins.hasAttr cfg.user config.users.users
          && config.users.users.${cfg.user}.uid == cfg.uid
          && config.users.groups.${config.users.users.${cfg.user}.group}.gid == cfg.gid;
        message = "Environment UID/GID must match the configured user's primary group.";
      }
      {
        assertion = builtins.hasAttr cfg.primary cfg.entries && cfg.entries.${cfg.primary}.enable;
        message = "The primary home environment must exist and be enabled.";
      }
      {
        assertion = builtins.hasAttr cfg.current enabled;
        message = "The selected home environment must be enabled.";
      }
      {
        assertion =
          if cfg.homeMode == "separate" then
            builtins.length (lib.unique (map (e: e.dataset) (lib.attrValues cfg.entries)))
            == builtins.length (lib.attrNames cfg.entries)
          else
            lib.all (
              e: e.dataset == cfg.entries.${cfg.primary}.dataset && e.backup == cfg.entries.${cfg.primary}.backup
            ) (lib.attrValues enabled);
        message = "Separate homes require unique datasets; shared homes require one dataset and backup policy.";
      }
      {
        assertion =
          !profiles.enable
          || (
            cfg.homeMode == "shared"
            && lib.all safePath (profiles.mutableFiles ++ profiles.bindDirectories)
            && lib.all (k: builtins.match "/([a-zA-Z0-9_-]+/)+[a-zA-Z0-9_-]+" k != null) profiles.dconfKeys
            && lib.all (
              p:
              lib.all (q: p == q || !(lib.hasPrefix "${p}/" q || lib.hasPrefix "${q}/" p)) (
                profiles.mutableFiles ++ profiles.bindDirectories
              )
            ) (profiles.mutableFiles ++ profiles.bindDirectories)
            &&
              builtins.length (lib.unique (profiles.mutableFiles ++ profiles.bindDirectories))
              == builtins.length (profiles.mutableFiles ++ profiles.bindDirectories)
          );
        message = "Desktop profiles require shared home and safe, unique, non-overlapping relative paths and dconf keys.";
      }
      {
        assertion = lib.all (name: builtins.match "[a-z][a-z0-9_-]*" name != null) (
          lib.attrNames cfg.entries
        );
        message = "Environment names must match [a-z][a-z0-9_-]*.";
      }
      {
        assertion = lib.all (e: builtins.match "[A-Za-z0-9_.:-]+(/[A-Za-z0-9_.:-]+)+" e.dataset != null) (
          lib.attrValues cfg.entries
        );
        message = "Home datasets must be filesystem names within a ZFS pool.";
      }
      {
        assertion = lib.all (
          p:
          p != ""
          && !lib.hasPrefix "/" p
          && lib.all (s: s != "" && s != "." && s != "..") (lib.splitString "/" p)
        ) cfg.sharedDirectories;
        message = "Shared directories must be safe relative paths.";
      }
      {
        assertion = lib.all (name: builtins.hasAttr name cfg.variants) (lib.attrNames variants);
        message = "Every enabled variant needs a configuration module.";
      }
    ];
    fileSystems = {
      "/home" = {
        device = lib.mkForce selected.dataset;
        fsType = "zfs";
        options = [ "zfsutil" ];
        neededForBoot = true;
      };
    }
    // lib.optionalAttrs (cfg.homeMode == "separate" && cfg.current != cfg.primary) (
      {
        ${sharedRoot} = {
          device = cfg.entries.${cfg.primary}.dataset;
          fsType = "zfs";
          options = [ "zfsutil" ];
        };
      }
      // lib.listToAttrs (
        map (
          path:
          lib.nameValuePair "/home/${cfg.user}/${path}" {
            device = "${sharedRoot}/${cfg.user}/${path}";
            fsType = "none";
            options = [ "bind" ];
            depends = [
              sharedRoot
              "/home"
            ];
          }
        ) cfg.sharedDirectories
      )
    )
    // lib.optionalAttrs profiles.enable (
      lib.listToAttrs (
        map (
          path:
          lib.nameValuePair "/home/${cfg.user}/${path}" {
            device = "/home/.desktop-profiles/${cfg.user}/${cfg.current}/dirs/${path}";
            fsType = "none";
            options = [ "bind" ];
            depends = [ "/home" ];
          }
        ) profiles.bindDirectories
      )
    );
    system.preSwitchChecks.frameworkEnvironment = ''
      case "$2" in
        switch|test|dry-activate)
          ${helper}/bin/framework-home --manifest "$1/etc/framework-environments.json" preflight --action switch
          ;;
      esac
    '';
    systemd.services.framework-desktop-profile = lib.mkIf profiles.enable {
      description = "Select prepared desktop files before any user session";
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" ];
      before = [
        "systemd-user-sessions.service"
        "display-manager.service"
        "greetd.service"
        "user@${toString cfg.uid}.service"
        "home-manager-${cfg.user}.service"
      ];
      unitConfig.RequiresMountsFor = [ "/home" ] ++ profileMounts;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${helper}/bin/framework-home activate-profile";
      };
      restartIfChanged = false;
      stopIfChanged = false;
    };
    systemd.services.systemd-user-sessions = lib.mkIf profiles.enable {
      requires = [ "framework-desktop-profile.service" ];
      after = [ "framework-desktop-profile.service" ];
    };
    systemd.services."user@${toString cfg.uid}" = lib.mkIf profiles.enable {
      overrideStrategy = "asDropin";
      requires = [ "framework-desktop-profile.service" ];
      after = [ "framework-desktop-profile.service" ];
    };
    systemd.services."home-manager-${cfg.user}" = lib.mkIf profiles.enable {
      requires = [ "framework-desktop-profile.service" ];
      after = [ "framework-desktop-profile.service" ];
    };
    systemd.services.display-manager =
      lib.mkIf (profiles.enable && config.services.displayManager.enable)
        {
          requires = [ "framework-desktop-profile.service" ];
          after = [ "framework-desktop-profile.service" ];
        };
    systemd.services.greetd = lib.mkIf (profiles.enable && config.services.greetd.enable) {
      requires = [ "framework-desktop-profile.service" ];
      after = [ "framework-desktop-profile.service" ];
    };
    environment.etc."framework-environments.json".source = manifest;
    environment.systemPackages = [ helper ];
    system.build.frameworkEnvironments = manifest;
    specialisation = lib.mapAttrs (name: _: {
      configuration = {
        imports = [ cfg.variants.${name} ];
        framework.environments.current = lib.mkForce name;
        system.nixos.tags = [ name ];
      };
    }) variants;
  };
}
