{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.corporate-workstation;
  home = config.users.users.${cfg.user}.home;
  runtime = cfg.packages.vkey-runtime;
  dns = pkgs.writeShellApplication {
    name = "barbos-dns";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnused
      config.systemd.package
    ];
    text = builtins.replaceStrings [ "@RESOLVECTL@" ] [ "${config.systemd.package}/bin/resolvectl" ] (
      builtins.readFile ./scripts/barbos-dns.sh
    );
  };
  setup = pkgs.writeShellApplication {
    name = "vkey-runtime-setup";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
      pkgs.gnugrep
      pkgs.nssTools
    ];
    text = ''
      state="$HOME/.local/share/vkey-x509"
      mkdir -p "$state" "$HOME/.tpm2_pkcs11"
      chmod 700 "$state" "$HOME/.tpm2_pkcs11"
      ln -sfn ${config.security.wrapperDir}/vkey-openvpn "$state/openvpn"
      ln -sfn ${runtime}/lib/libtpm2-pkcs11.so "$state/libtpm2-pkcs11.so"
      ln -sfn ${runtime}/bin/barbos-tray "$state/barbos-tray"
      ln -sfn ${runtime}/bin/vkey-fp "$state/vkey-fp"
      ln -sfn ${dns}/bin/barbos-dns "$state/barbos.ovpn.sh"
      # Preserve both vendor database locations. Existing browser and VPN
      # copies can differ; activation must not merge or overwrite either.
      db="$HOME/.pki/nssdb"
      mkdir -p "$db"
      chmod 700 "$db"
      if [[ ! -e $db/cert9.db && ! -e $db/key4.db ]]; then
        certutil -N -d "sql:$db" --empty-password
      fi
      register() {
        local directory=$1
        # Preserve existing browser module registrations and NSS credentials.
        if [[ -f $directory/pkcs11.txt ]] && grep -Fq "$state/libtpm2-pkcs11.so" "$directory/pkcs11.txt"; then
          return
        fi
        # Register exactly as the vendor documents, without initializing the
        # TPM provider during login (the imported token may not yet be present).
        printf '\n\nlibrary=%s\nname=vkey-x509\n\n' "$state/libtpm2-pkcs11.so" >> "$directory/pkcs11.txt"
      }
      register "$db"
      # Existing Firefox/Zen profiles may arrive with the later home clone.
      for browser in "$HOME/.mozilla/firefox" "$HOME/.zen"; do
        [[ -d $browser ]] || continue
        while IFS= read -r -d "" profile; do
          [[ ! -f $profile/cert9.db ]] || register "$profile"
        done < <(find "$browser" -mindepth 1 -maxdepth 1 -type d -print0)
      done
    '';
  };
in
lib.mkIf cfg.enable {
  security.tpm2 = {
    enable = true;
    abrmd.enable = true;
  };
  users.users.${cfg.user}.extraGroups = [ "tss" ];
  security.wrappers.vkey-openvpn = {
    source = "${runtime}/bin/openvpn";
    owner = "root";
    group = "tss";
    permissions = "u+rx,g+rx,o-rwx";
    capabilities = "cap_net_admin+eip";
  };
  services.resolved.enable = true;
  networking.networkmanager.dns = "systemd-resolved";
  # Keep noncorporate DNS on its own link; do not introduce a ~. catch-all.
  environment.etc."openvpn/barbos-dns-domains".text = ''
    vk.team
    vkteam.ru
    corp.mail.ru
    devmail.ru
    bid.max.ru
    assistant.mail.ru
  '';
  security.sudo.extraRules = [
    {
      users = [ cfg.user ];
      commands = [
        {
          command = "${config.systemd.package}/bin/resolvectl";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];
  environment.systemPackages = [
    cfg.packages.vkey-client
    runtime
    setup
    pkgs.nssTools
    pkgs.tpm2-tools
  ];
  programs.firefox = {
    enable = true;
    policies.SecurityDevices.Add.VKey = "${home}/.local/share/vkey-x509/libtpm2-pkcs11.so";
  };
  systemd.user.services.vkey-runtime-setup = {
    description = "Prepare immutable VKey programs and browser registrations";
    wantedBy = [ "default.target" ];
    before = [
      "barbos.service"
      "barbos-tray.service"
    ];
    unitConfig.ConditionUser = cfg.user;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = lib.getExe setup;
      UMask = "0077";
    };
  };
  systemd.user.services.barbos = {
    description = "VKey Barbos VPN";
    requires = [ "vkey-runtime-setup.service" ];
    after = [ "vkey-runtime-setup.service" ];
    unitConfig = {
      ConditionUser = cfg.user;
      ConditionPathExists = "${home}/.local/share/vkey-x509/barbos.ovpn";
    };
    environment = {
      TPM2_PKCS11_STORE = "${home}/.local/share/vkey-x509";
      PATH = lib.mkForce "${config.security.wrapperDir}:${config.systemd.package}/bin:${pkgs.coreutils}/bin:/run/current-system/sw/bin";
    };
    serviceConfig = {
      Type = "simple";
      WorkingDirectory = "${home}/.local/share/vkey-x509";
      ExecStart = "${config.security.wrapperDir}/vkey-openvpn --config ${home}/.local/share/vkey-x509/barbos.ovpn";
      Restart = "no";
    };
  };
  systemd.user.services.barbos-tray = {
    description = "Barbos VPN tray";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    requires = [ "vkey-runtime-setup.service" ];
    after = [
      "graphical-session.target"
      "vkey-runtime-setup.service"
    ];
    unitConfig.ConditionUser = cfg.user;
    path = [ config.systemd.package ];
    serviceConfig = {
      ExecStart = "${runtime}/bin/barbos-tray";
      Restart = "on-failure";
      RestartSec = 3;
    };
  };
}
