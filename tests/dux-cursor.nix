{ pkgs, dms }:
pkgs.runCommand "dux-session-cursor-test"
  {
    nativeBuildInputs = [
      pkgs.uv
      pkgs.python3
      pkgs.coreutils
    ];
    DMS_SETTINGS = "${dms}/share/quickshell/dms/Common/SettingsData.qml";
  }
  ''
    uv run --offline --no-project --no-cache --no-managed-python \
      --python ${pkgs.python3}/bin/python3 ${./test_dux_cursor.py}
    touch $out
  ''
