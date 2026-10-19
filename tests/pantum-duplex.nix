{ pkgs }:
pkgs.runCommand "pantum-duplex-render-check"
  {
    nativeBuildInputs = with pkgs; [
      ghostscript
      poppler-utils
      python3
      uv
    ];
  }
  ''
    uv run --no-cache --offline --no-project --python ${pkgs.python3}/bin/python \
      ${./pantum-duplex.py} \
      ${pkgs.cups-filters}/lib/cups/filter/pdftopdf \
      ${../hosts/framework/peripherals/ppd/Pantum_BM1800W_ManualDuplex.ppd}
    touch "$out"
  ''
