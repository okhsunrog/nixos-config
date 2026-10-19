{
  device = "tmpfs";
  fsType = "tmpfs";
  options = [
    "mode=0755"
    "nosuid"
    "nodev"
    "size=256M"
  ];
}
