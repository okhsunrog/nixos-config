{ pkgs, ... }:
{
  # Plasma enables the Orca screen reader by default; not part of this host set.
  services.orca.enable = false;

  # First migration slice: applications actually present on the Arch host.
  # Project-specific SDKs/libraries belong in project devShells.
  environment.systemPackages = with pkgs; [
    # Daily desktop, documents and communication. Firefox is in default.nix.
    google-chrome
    ayugram-desktop
    keepassxc
    nextcloud-client
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

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
  # Downloaded toolchains/editor helpers may expect a conventional ELF loader.
  programs.nix-ld.enable = true;
  programs.wireshark = {
    enable = true;
    package = pkgs.wireshark;
  };

  virtualisation.docker.enable = true;
  virtualisation.libvirtd.enable = true;
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
