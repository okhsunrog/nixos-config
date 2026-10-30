{ dux-greeter }:
args@{ lib, pkgs, ... }:
let
  source = builtins.readFile "${dux-greeter}/distro/nix/greeter.nix";
  original = "mv dms-colors.json colors.json || :";
  replacement = ''
    if [ -f dms-colors.json ]; then
          mv dms-colors.json colors.json
      fi'';
  patched = builtins.toFile "dux-greeter-module.nix" (
    assert lib.hasInfix original source;
    lib.replaceStrings [ original ] [ replacement ] source
  );
in
import patched (args // { greeterPkgs = dux-greeter.lib.buildGreeterPkgs pkgs; })
