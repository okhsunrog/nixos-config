{ pkgs, ... }:
{
  # Keep Plasma's power profile selector, with the same backend as on Arch.
  # The TuneD module disables power-profiles-daemon and enables UPower.
  services.tuned = {
    enable = true;
    ppdSupport = true;
  };

  # Use the firmware's DPTF tables; Meteor Lake needs no custom thermal XML.
  services.thermald.enable = true;

  # virt-what calls `which` to locate its CPUID helper. The packaged TuneD
  # wrapper supplies virt-what but not which in the service's restricted PATH.
  systemd.services.tuned.path = [ pkgs.which ];
}
