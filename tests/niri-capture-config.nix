{ pkgs, niri }:
let
  captureConfig = pkgs.writeText "niri-capture-config.kdl" ''
    layer-rule {
      match namespace="^private-overlay$"
      block-out-from "screen-capture" kind="transparent"
    }
    window-rule {
      match app-id="^private-window$"
      block-out-from "screencast" kind="transparent"
    }
    window-rule {
      match app-id="^legacy-window$"
      block-out-from "screen-capture"
    }
  '';
in
pkgs.runCommand "niri-capture-config" { } ''
  ${niri}/bin/niri validate --config ${captureConfig}
  touch $out
''
