"""Render the real CUPS PDF filter output; never submit a printer job."""

import argparse
import os
from pathlib import Path
import subprocess
import tempfile


def run_filter(filter_path, ppd, fixture, output, options):
    env = os.environ.copy()
    env["PPD"] = str(ppd)
    with output.open("wb") as out:
        result = subprocess.run(
            [str(filter_path), "8", "test", "duplex-check", "1", options, str(fixture)],
            env=env,
            stdout=out,
            stderr=subprocess.PIPE,
        )
    if result.returncode or b"ERROR:" in result.stderr:
        raise RuntimeError(result.stderr.decode(errors="replace"))


def check_marker(pdf, page, prefix):
    subprocess.run(
        [
            "pdftoppm", "-f", str(page), "-l", str(page), "-singlefile",
            "-scale-to", "160", "-gray", str(pdf), str(prefix),
        ],
        check=True,
    )
    magic, size, maximum, pixels = prefix.with_suffix(".pgm").read_bytes().split(b"\n", 3)
    width, height = map(int, size.split())
    if magic != b"P5" or maximum != b"255" or len(pixels) != width * height:
        raise RuntimeError("Unexpected rendered PGM format")
    dark = [(i % width, i // width) for i, value in enumerate(pixels) if value < 100]
    if not dark:
        raise RuntimeError("Missing test marker")
    x = sum(p[0] for p in dark) / len(dark)
    y = sum(p[1] for p in dark) / len(dark)
    position = ("left" if x < width / 2 else "right", "top" if y < height / 2 else "bottom")
    if position != ("left", "top"):
        raise RuntimeError(f"{pdf.stem}, page {page}: unexpected marker position {position}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("filter", type=Path)
    parser.add_argument("ppd", type=Path)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="pantum-duplex-") as tmp:
        base = Path(tmp)
        ps = base / "input.ps"
        ps.write_text(
            "%!PS-Adobe-3.0\n<< /PageSize [595 842] >> setpagedevice\n"
            "50 730 60 60 rectfill\nshowpage\n"
            "50 730 60 60 rectfill\nshowpage\n"
        )
        fixture = base / "input.pdf"
        subprocess.run(
            [
                "gs", "-q", "-dSAFER", "-dBATCH", "-dNOPAUSE", "-sDEVICE=pdfwrite",
                f"-sOutputFile={fixture}", str(ps),
            ],
            check=True,
        )
        for edge in ("long", "short"):
            for orientation in ("default", "Normal"):
                name = f"{orientation}-{edge}"
                output = base / f"{name}.pdf"
                options = f"sides=two-sided-{edge}-edge media=A4"
                if orientation != "default":
                    options += f" back-side-orientation={orientation}"
                run_filter(args.filter, args.ppd, fixture, output, options)
                for page in (1, 2):
                    check_marker(output, page, base / f"{name}-page-{page}")
                print(f"PASS {name}: front and back preserve marker orientation")


if __name__ == "__main__":
    main()
