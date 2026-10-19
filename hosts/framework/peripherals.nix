{ pkgs, ... }:
let
  pantum = pkgs.callPackage ../../packages/pantum-bm1800w.nix { };
  pantumModels = pkgs.runCommand "pantum-bm1800w-models" { } ''
    mkdir -p "$out/share/cups/model/pantum-local"
    cp ${./peripherals/ppd}/*.ppd "$out/share/cups/model/pantum-local/"
  '';
  deviceRules = pkgs.runCommand "framework-device-rules" { } ''
    mkdir -p "$out/etc/udev/rules.d"
    cp ${./peripherals/udev}/*.rules "$out/etc/udev/rules.d/"
    cp ${pkgs.probe-rs-tools.udevRules} "$out/etc/udev/rules.d/69-probe-rs.rules"
  '';
in
{
  services.udev.packages = [ deviceRules ];
  boot.kernelModules = [ "usbmon" ];
  users.groups.plugdev = { };
  users.users.okhsunrog.extraGroups = [ "plugdev" ];

  services.printing = {
    enable = true;
    drivers = [
      pantum
      pantumModels
    ];
  };
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };
  hardware.printers = {
    ensureDefaultPrinter = "Pantum_BM1800W";
    ensurePrinters = [
      {
        name = "Pantum_BM1800W";
        description = "Pantum BM1800W";
        deviceUri = "ipp://Pantum-38362E.local:631/ipp/print";
        model = "pantum-local/Pantum_BM1800W.ppd";
        ppdOptions = {
          PageSize = "A4";
          print-color-mode = "monochrome";
          sides = "one-sided";
          printer-is-shared = "false";
        };
      }
      {
        name = "Pantum_BM1800W_ManualDuplex";
        description = "Pantum BM1800W — ручная двусторонняя";
        deviceUri = "socket://Pantum-38362E.local:9100";
        model = "pantum-local/Pantum_BM1800W_ManualDuplex.ppd";
        ppdOptions = {
          PageSize = "A4";
          Duplex = "DuplexNoTumble";
          printer-is-shared = "false";
        };
      }
    ];
  };
}
