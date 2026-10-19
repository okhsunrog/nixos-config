{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.corporate-workstation;
  home = config.users.users.${cfg.user}.home;
  profiles = import ./profiles.nix { inherit lib home; };
  shellTool =
    name: file: inputs:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = inputs;
      text = builtins.readFile file;
    };
  proxy = shellTool "corporate-agent-dbus" ./scripts/dbus-proxy.sh [ pkgs.xdg-dbus-proxy ];
  ready = shellTool "corporate-agent-dbus-ready" ./scripts/dbus-ready.sh [ pkgs.coreutils ];
  inspect = shellTool "agent-audit" ./scripts/agent-audit.sh [
    pkgs.coreutils
    pkgs.findutils
    pkgs.gawk
    pkgs.gnused
    pkgs.jq
    pkgs.audit
    config.systemd.package
  ];
  firewall = pkgs.writeShellApplication {
    name = "firewall-cmd";
    runtimeInputs = [
      config.systemd.package
      pkgs.jq
    ];
    text = builtins.replaceStrings [ "@FIREWALL_CMD@" ] [ "${pkgs.firewalld}/bin/firewall-cmd" ] (
      builtins.readFile ./scripts/firewall-cmd.sh
    );
  };
  paths = with pkgs; [
    bash
    coreutils
    getent
    findutils
    gnugrep
    gnused
    gawk
    util-linux
    iproute2
    iptables
    nftables
    systemd
    dbus
    dmidecode
    openssl
    python3
  ];
  guard = profile: work: {
    requires = [
      "apparmor.service"
      "auditd.service"
      "audit-rules-nixos.service"
      "agent-script-archive.service"
      "corporate-agent-dbus.service"
    ];
    after = [
      "network-online.target"
      "apparmor.service"
      "auditd.service"
      "audit-rules-nixos.service"
      "agent-script-archive.service"
      "corporate-agent-dbus.service"
    ];
    bindsTo = [
      "agent-script-archive.service"
      "corporate-agent-dbus.service"
    ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    path = paths;
    environment = {
      TMPDIR = "/var/lib/corporate-agent-work/${work}";
      FLEET_PREVENT_SCRIPT_TEMPDIR_DELETION = "1";
      DBUS_SYSTEM_BUS_ADDRESS = "unix:path=/run/corporate-agent-dbus/system-bus";
    };
    serviceConfig = {
      AppArmorProfile = profile;
      Restart = "always";
      RestartSec = 10;
      TimeoutStopSec = 35;
      KillMode = "control-group";
      NoNewPrivileges = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      # Vendor scripts commonly name these interpreters explicitly. Provide
      # them only inside the agent's mount namespace, without host FHS aliases.
      TemporaryFileSystem = [
        "/bin:ro"
        "/usr/bin:ro"
      ];
      BindReadOnlyPaths = [
        "${pkgs.bash}/bin/bash:/bin/bash"
        "${pkgs.bash}/bin/bash:/bin/sh"
        "${pkgs.bash}/bin/bash:/usr/bin/bash"
        "${pkgs.coreutils}/bin/env:/usr/bin/env"
        "${pkgs.python3}/bin/python3:/usr/bin/python3"
      ];
      ReadWritePaths = [ "/var/lib/corporate-agent-work/${work}" ];
      InaccessiblePaths = [
        "-/mnt/nfs"
        "-/etc/zfs/zroot.key"
        "-/var/lib/sops-nix"
        "-/var/lib/secureboot"
        "-/var/lib/sbctl"
        "-/var/lib/corporate-agent-archive"
        "-/var/lib/floppa-vpn"
        "-/run/dbus/system_bus_socket"
        "-/run/systemd/private"
        "-/run/user"
        "-/run/secrets"
        "-/run/secrets.d"
        "-/run/secrets-for-users"
        "-/run/secrets-for-users.d"
      ];
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectKernelLogs = true;
      ProtectControlGroups = true;
      RestrictSUIDSGID = true;
      LockPersonality = true;
      RestrictNamespaces = true;
      CapabilityBoundingSet = [
        "CAP_DAC_OVERRIDE"
        "CAP_DAC_READ_SEARCH"
      ];
    };
  };
in
lib.mkIf cfg.enable {
  security.apparmor.enable = true;
  security.apparmor.policies = lib.mapAttrs (_: profile: {
    inherit profile;
    state = "enforce";
  }) profiles;
  security.audit = {
    enable = true;
    backlogLimit = 8192;
    rules =
      lib.concatMap
        (profile: [
          "-a always,exit -F arch=b64 -S execve,execveat -F subj_role=${profile} -k corp_exec"
          "-a always,exit -F arch=b32 -S execve,execveat -F subj_role=${profile} -k corp_exec"
          "-a always,exit -F arch=b64 -S clone,clone3,fork,vfork -F subj_role=${profile} -k corp_fork"
        ])
        [
          "corporate-nac"
          "corporate-orbit"
        ];
  };
  security.auditd = {
    enable = true;
    settings = {
      max_log_file = 64;
      num_logs = 8;
      max_log_file_action = "ROTATE";
      log_group = "root";
    };
  };
  # Resolve AppArmor audit subjects before loading subject-filtered rules.
  systemd.services.audit-rules-nixos = {
    after = [ "apparmor.service" ];
    requires = [ "apparmor.service" ];
  };
  services.firewalld.enable = true;
  networking.nftables.enable = true;
  programs.nix-ld.enable = true;
  networking.firewall = {
    enable = true;
    backend = "firewalld";
    checkReversePath = "loose";
  };
  environment.systemPackages = [ inspect ];
  systemd.tmpfiles.rules = [
    "d /var/lib/corporate-agent-archive 0700 root root -"
    "d /var/lib/corporate-agent-work 0755 root root -"
    "d /opt/orbit 0755 root root -"
    "d /var/lib/nac-agent 0700 root root -"
    "d /var/cache/nac-agent 0700 root root -"
    "d /var/log/nac-agent 0750 root root -"
    "d /var/log/orbit 0750 root root -"
    "d /var/log/osquery 0750 root root -"
  ];
  fileSystems."/var/lib/corporate-agent-work" = import ./work-filesystem.nix;
  systemd.services.agent-script-archive = {
    description = "Archive Fleet scripts before permitting file open";
    unitConfig.RequiresMountsFor = "/var/lib/corporate-agent-work";
    after = [
      "apparmor.service"
      "auditd.service"
    ];
    before = [
      "orbit.service"
      "nac-agent.service"
    ];
    preStart = ''
      install -d -m0700 /var/lib/corporate-agent-work/{orbit,nac}
    '';
    serviceConfig = {
      Type = "notify";
      ExecStart = "${cfg.packages.agent-script-archive}/bin/agent-script-archive";
      Restart = "on-failure";
      RestartSec = 3;
      TimeoutStopSec = 5;
      UMask = "0077";
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ReadWritePaths = [
        "/var/lib/corporate-agent-archive"
        "/var/lib/corporate-agent-work"
      ];
      CapabilityBoundingSet = [
        "CAP_SYS_ADMIN"
        "CAP_DAC_READ_SEARCH"
        "CAP_DAC_OVERRIDE"
      ];
      RestrictAddressFamilies = [ "AF_UNIX" ];
    };
  };
  systemd.services.corporate-agent-dbus = {
    description = "Read-only system D-Bus proxy for corporate checks";
    requires = [ "dbus.service" ];
    after = [ "dbus.service" ];
    before = [
      "orbit.service"
      "nac-agent.service"
    ];
    serviceConfig = {
      Type = "exec";
      RuntimeDirectory = "corporate-agent-dbus";
      RuntimeDirectoryMode = "0755";
      ExecStart = lib.getExe proxy;
      ExecStartPost = lib.getExe ready;
      Restart = "on-failure";
      RestartSec = 3;
      UMask = "0077";
      NoNewPrivileges = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      PrivateTmp = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      CapabilityBoundingSet = "";
      RestrictAddressFamilies = [ "AF_UNIX" ];
      RestrictNamespaces = true;
    };
  };
  systemd.services.nac-agent = lib.mkMerge [
    (guard "corporate-nac" "nac")
    {
      description = "Corporate NAC agent";
      path = lib.mkBefore [
        firewall
        pkgs.shadow
        pkgs.kdePackages.kconfig
      ];
      wants = [ "corporate-screenlock-watch.path" ];
      after = [
        "corporate-screenlock-watch.path"
        "firewalld.service"
      ];
      serviceConfig = {
        ExecStart = "${cfg.packages.nac-agent}/bin/nac-agent";
        ProtectHome = lib.mkForce "tmpfs";
        BindReadOnlyPaths = [ "-${home}/.config/kscreenlockerrc" ];
        ReadWritePaths = [
          "/var/log/nac-agent"
          "/var/lib/nac-agent"
          "/var/cache/nac-agent"
        ];
        CapabilityBoundingSet = [
          "CAP_SETUID"
          "CAP_SETGID"
        ];
        StandardOutput = "append:/var/log/nac-agent/nac-agent.log";
        StandardError = "append:/var/log/nac-agent/nac-checker.log";
      };
    }
  ];
  systemd.services.orbit = lib.mkMerge [
    (guard "corporate-orbit" "orbit")
    {
      description = "Corporate Fleet osquery";
      preStart = ''
        # Seed missing programs from pinned artifacts, preserving Orbit's signed
        # update cache. Downloaded ELF programs use nix-ld, not a mutable store link.
          mkdir -p /opt/orbit/bin/{orbit,osqueryd}/linux/stable
        for program in orbit osqueryd; do
          target="/opt/orbit/bin/$program/linux/stable/$program"
          if test ! -e "$target"; then
            install -m0755 ${cfg.packages.fleet-orbit}/bin/"$program" "$target"
          fi
        done
        for program in orbit osqueryd; do
          # Orbit owns these links after a signed update. Only seed a missing
          # entry; resetting it on restart would create an update loop.
          if test ! -e "/opt/orbit/bin/$program/$program"; then
            ln -sfn "linux/stable/$program" "/opt/orbit/bin/$program/$program"
          fi
        done
        for file in certs.pem osquery.flags tuf-metadata.json; do
          test -e "/opt/orbit/$file" || cp ${cfg.packages.fleet-orbit}/libexec/fleet-orbit/"$file" /opt/orbit/
          done
      '';
      serviceConfig = {
        ExecStart = "/opt/orbit/bin/orbit/orbit";
        EnvironmentFile = cfg.orbitEnvironmentFile;
        WorkingDirectory = "/opt/orbit";
        CPUQuota = "20%";
        UMask = "0022";
        ReadWritePaths = [
          "/opt/orbit"
          "/var/log/orbit"
          "/var/log/osquery"
        ];
      };
      environment = {
        ORBIT_ROOT_DIR = "/opt/orbit";
        NIX_LD = config.environment.sessionVariables.NIX_LD;
        NIX_LD_LIBRARY_PATH = config.environment.sessionVariables.NIX_LD_LIBRARY_PATH;
      };
    }
  ];
  systemd.paths.corporate-screenlock-watch = {
    wantedBy = [ "multi-user.target" ];
    pathConfig = {
      PathChanged = "${home}/.config/kscreenlockerrc";
      Unit = "corporate-screenlock-refresh.service";
    };
  };
  systemd.services.corporate-screenlock-refresh = {
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${config.systemd.package}/bin/systemctl try-restart nac-agent.service";
    };
  };
  services.logrotate.settings.corporate-agents = {
    files = [
      "/var/log/nac-agent/*.log"
      "/var/log/orbit/*.log"
      "/var/log/osquery/*.log"
    ];
    rotate = 7;
    daily = true;
    compress = true;
    copytruncate = true;
    missingok = true;
    notifempty = true;
  };
}
