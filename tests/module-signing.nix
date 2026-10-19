{ pkgs, zbm-rs }:
pkgs.runCommand "framework-module-signing-tests"
  {
    nativeBuildInputs = [
      pkgs.uv
      pkgs.python3
      pkgs.openssl
      pkgs.bash
      pkgs.util-linux
    ];
    FRAMEWORK_SIGNING_SCRIPT = ../scripts/sign-framework-modules.py;
    FRAMEWORK_REBUILD_SCRIPT = ../scripts/rebuild-framework.sh;
    SIGNING_PUBLISHER = "${zbm-rs}/nix/publish-loader.py";
  }
  ''
    # Test-only keys stay in the disposable build directory and are not outputs.
    uv run --no-cache --offline --no-project --no-managed-python \
      --python ${pkgs.python3}/bin/python3 ${./test_module_signing.py}
    touch $out
  ''
