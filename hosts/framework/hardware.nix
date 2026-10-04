{ pkgs, ... }:
{
  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "thunderbolt"
    "usb_storage"
    "usbhid"
  ];
  boot.kernelModules = [ "kvm-intel" ];
  # Use the supported NixOS kernel/ZFS pair before considering custom kernels.
  boot.kernelPackages = pkgs.linuxPackages;
  hardware.cpu.intel.updateMicrocode = true;
  hardware.enableRedistributableFirmware = true;
  nixpkgs.config.allowUnfree = true;
}
