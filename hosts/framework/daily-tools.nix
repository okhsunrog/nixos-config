{
  config,
  pkgs,
  lib,
  zen-browser,
  ...
}:
let
  flyline = import ../../packages/flyline.nix { inherit pkgs; };
in
{
  # Plasma enables the Orca screen reader by default; not part of this host set.
  services.orca.enable = false;
  environment.sessionVariables.LIBCLANG_PATH = "${pkgs.libclang.lib}/lib";
  networking.networkmanager.plugins = with pkgs; [
    networkmanager-openvpn
    networkmanager-openconnect
  ];

  # First migration slice: applications actually present on the Arch host.
  # Project-specific SDKs/libraries belong in project devShells.
  environment.systemPackages = with pkgs; [
    zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.beta
    # Preserve existing launchers/default MIME associations from Arch.
    (pkgs.writeShellScriptBin "zen-browser" ''exec zen-beta "$@"'')
    (pkgs.makeDesktopItem {
      name = "zen";
      desktopName = "Zen Browser";
      noDisplay = true;
      exec = "zen-beta %U";
      icon = "zen-browser";
      categories = [
        "Network"
        "WebBrowser"
      ];
      mimeTypes = [
        "text/html"
        "x-scheme-handler/http"
        "x-scheme-handler/https"
      ];
    })
    # Daily desktop, documents and communication. Firefox is in default.nix.
    google-chrome
    ayugram-desktop
    keepassxc
    nextcloud-client
    easyeffects
    libreoffice
    mpv
    kdePackages.ark
    kdePackages.gwenview
    kdePackages.okular
    kdePackages.spectacle
    kdePackages.kate
    kdePackages.kcalc
    kdePackages.filelight

    # Editors, version control and general development tools.
    vscode
    zed-editor
    codex
    git-lfs
    git-filter-repo
    delta
    gh
    glab
    rustup
    gcc
    clang
    clang-tools
    lldb
    cmake
    ninja
    pkg-config
    gdb
    strace
    ccache
    just
    uv
    python3
    nodejs
    bun
    pnpm
    go
    shellcheck
    ruff

    # Terminal essentials and file transfer.
    ripgrep
    fd
    eza
    zoxide
    btop
    fastfetch
    flyline
    starship
    jq
    yq-go
    tree
    rsync
    curl
    wget
    unzip
    zip
    p7zip
    file
    which
    man-pages
    wl-clipboard
    glib # gdbus for the existing Konsole theme watcher
    kdePackages.qttools # qdbus for existing desktop scripts

    # Android/USB/serial work and network diagnosis. VPN profiles are separate.
    android-tools
    scrcpy
    dfu-util
    tio
    usbutils
    pciutils
    smartmontools
    nfs-utils
    openconnect
    openvpn
    wireguard-tools
    dnsutils
    nmap
    iperf3
    traceroute
    tcpdump
  ];

  programs.bash.interactiveShellInit = lib.mkAfter ''
    if [[ $TERM != linux && ''${FLYLINE:-1} != 0 ]]; then
      enable flyline 2>/dev/null || enable -f ${flyline}/lib/libflyline.so flyline
    fi
  '';

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
  # Downloaded toolchains/editor helpers may expect a conventional ELF loader.
  programs.nix-ld.enable = true;
  # Native bindings in the migrated uv tools (D-Bus / desktop introspection).
  programs.nix-ld.libraries = with pkgs; [
    dbus
    glib
    libffi
    gobject-introspection
  ];
  programs.wireshark = {
    enable = true;
    package = pkgs.wireshark;
  };

  virtualisation.docker.enable = true;
  virtualisation.libvirtd.enable = true;
  # The pool already protects this host key at rest. Libvirt's automatic
  # TPM policy picks the loader's PCR signing key, which does not authorize
  # this OS's current PCR 11 value after kexec.
  systemd.services.virt-secret-init-encryption.serviceConfig.ExecStart = lib.mkForce (
    pkgs.writeShellScript "libvirt-init-encryption" ''
      set -euo pipefail
      ${pkgs.coreutils}/bin/dd if=/dev/urandom status=none bs=32 count=1 |
        ${config.systemd.package}/bin/systemd-creds encrypt --with-key=host \
          --name=secrets-encryption-key - /var/lib/libvirt/secrets/secrets-encryption-key
    ''
  );
  programs.virt-manager.enable = true;
  users.users.okhsunrog.extraGroups = [
    "dialout"
    "docker"
    "libvirtd"
    "wireshark"
  ];

  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
    nerd-fonts.jetbrains-mono
    nerd-fonts.lilex
  ];
}
