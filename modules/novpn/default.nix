{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.novpn;
  uid = config.users.users.${cfg.user}.uid;
  cgroup = "user.slice/user-${toString uid}.slice/user@${toString uid}.service/novpn.slice";
  rules = pkgs.writeText "novpn.nft" ''
    table inet novpn
    delete table inet novpn
    table inet novpn {
      chain output {
        type route hook output priority mangle; policy accept;
        socket cgroupv2 level 4 "${cgroup}" counter meta mark set 0xca6c
      }
      chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        meta mark 0xca6c oifname != "lo" counter masquerade
      }
    }
  '';
  refresh = pkgs.writeShellApplication {
    name = "novpn-refresh";
    runtimeInputs = [
      pkgs.iproute2
      pkgs.jq
      pkgs.nftables
      pkgs.util-linux
    ];
    text = builtins.replaceStrings [ "@cgroup@" "@rules@" ] [ cgroup (toString rules) ] (
      builtins.readFile ./refresh.sh
    );
  };
  launcher = pkgs.writeShellApplication {
    name = "novpn-ff";
    runtimeInputs = [
      pkgs.systemd
      pkgs.coreutils
      pkgs.util-linux
    ];
    text = ''
      export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
      export DBUS_SESSION_BUS_ADDRESS="''${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"
      systemctl --user start novpn-anchor.service
      # Resolve the current cgroup inode before the browser creates any socket.
      /run/wrappers/bin/sudo ${pkgs.systemd}/bin/systemctl restart novpn-firewall.service
      if systemctl --user is-active --quiet firefox-novpn.service; then
        echo 'Firefox novpn is already running.'
        exit 0
      fi
      systemctl --user reset-failed firefox-novpn.service 2>/dev/null || true
      exec systemd-run --user --slice=novpn.slice --unit=firefox-novpn --collect \
        ${pkgs.coreutils}/bin/env -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
        -u http_proxy -u https_proxy -u all_proxy \
        ${pkgs.firefox}/bin/firefox --no-remote -P novpn "$@"
    '';
  };
in
{
  options.services.novpn = {
    enable = lib.mkEnableOption "a Firefox cgroup routed outside personal and corporate VPNs";
    user = lib.mkOption { type = lib.types.str; };
  };
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = uid != null;
        message = "services.novpn.user must have a fixed numeric uid";
      }
    ];
    environment.systemPackages = [ launcher ];
    systemd.services.novpn-firewall = {
      description = "Direct network access for novpn.slice";
      after = [
        "NetworkManager.service"
        "firewalld.service"
      ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe refresh;
        RemainAfterExit = true;
      };
    };
    networking.networkmanager.dispatcherScripts = [
      {
        source = pkgs.writeShellScript "90-novpn" ''
          case "''${2:-}" in
            up|down|dhcp4-change|dhcp6-change|reapply|connectivity-change|vpn-up|vpn-down)
              ${lib.getExe refresh}
              ;;
          esac
        '';
      }
    ];
    systemd.user.slices.novpn = {
      description = "Applications routed outside VPN tunnels";
      unitConfig.ConditionUser = cfg.user;
    };
    systemd.user.services.novpn-anchor = {
      description = "Keep the novpn cgroup alive for socket matching";
      wantedBy = [ "default.target" ];
      unitConfig.ConditionUser = cfg.user;
      serviceConfig = {
        Slice = "novpn.slice";
        ExecStart = "${pkgs.coreutils}/bin/sleep infinity";
        Restart = "always";
      };
    };
    security.sudo.extraRules = [
      {
        users = [ cfg.user ];
        commands = [
          {
            command = "${pkgs.systemd}/bin/systemctl restart novpn-firewall.service";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];
  };
}
