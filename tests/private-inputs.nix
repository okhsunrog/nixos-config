{ pkgs }:
pkgs.runCommand "framework-private-inputs"
  {
    nativeBuildInputs = with pkgs; [
      bash
      coreutils
      jq
      nix
      python3
      shellcheck
      uv
    ];
    PRIVATE_INPUT_HELPER = ../scripts/prefetch-framework-inputs.sh;
  }
  ''
    shellcheck ${../scripts/prefetch-framework-inputs.sh} ${../scripts/rebuild-framework.sh}
    uv run --no-cache --offline --no-project --no-managed-python \
      --python ${pkgs.python3}/bin/python3 ${./test_private_inputs.py}
    touch "$out"
  ''
