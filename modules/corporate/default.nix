{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.corporate-workstation;
in
{
  imports = [
    ./vkey.nix
    ./agents.nix
  ];
  options.services.corporate-workstation = {
    enable = lib.mkEnableOption "the confined corporate agents and VKey workstation integration";
    user = lib.mkOption {
      type = lib.types.str;
      default = "okhsunrog";
    };
    packages = lib.mkOption {
      type = lib.types.attrsOf lib.types.package;
      default = import ../../packages/corporate.nix { inherit pkgs; };
      description = "Pinned corporate programs; overridable with disposable programs in VM tests.";
    };
    orbitEnvironmentFile = lib.mkOption {
      type = lib.types.str;
      default = "/run/secrets/orbit-environment";
      description = "Runtime-only Orbit environment provisioned by SOPS, never a store file.";
    };
  };
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !(lib.hasPrefix "/nix/store/" cfg.orbitEnvironmentFile);
        message = "Orbit enrollment credentials must be supplied at runtime outside the Nix store.";
      }
    ];
  };
}
