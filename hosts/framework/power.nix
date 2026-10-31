{
  config,
  lib,
  pkgs,
  ...
}:
{
  # Keep Plasma's power profile selector, with the same backend as on Arch.
  # The TuneD module disables power-profiles-daemon and enables UPower.
  services.tuned = {
    enable = true;
    ppdSupport = true;
  };

  services.upower = {
    usePercentageForPolicy = true;
    percentageLow = 20;
    percentageCritical = 10;
    percentageAction = 5;
    criticalPowerAction = lib.mkIf config.boot.loader.zbm-rs.hibernation.enable "Hibernate";
  };

  # Use the guarded hibernation path on the internal installation, while the
  # portable repair system retains ordinary suspend. Leave clamshell use alone.
  services.logind.settings.Login = {
    HandleLidSwitch =
      if config.boot.loader.zbm-rs.hibernation.enable then "suspend-then-hibernate" else "suspend";
    HandleLidSwitchDocked = "ignore";
  };

  # Use the firmware's DPTF tables; Meteor Lake needs no custom thermal XML.
  services.thermald.enable = true;

  # virt-what calls `which` to locate its CPUID helper. The packaged TuneD
  # wrapper supplies virt-what but not which in the service's restricted PATH.
  systemd.services.tuned.path = [ pkgs.which ];
}
