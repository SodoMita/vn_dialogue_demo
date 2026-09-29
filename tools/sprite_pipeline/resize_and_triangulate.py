#!/usr/bin/env python3
"""Resize the white plate to the black plate if needed, then triangulate.

Ported from the Seirin sprite pipeline (SodoMita/Seirin) for Chrono Nexus.

Usage:
    resize_and_triangulate.py white.png black.png out_matted.png [alpha_out.png]

Runs with whatever python executes this script (needs Pillow + numpy),
instead of a hardcoded venv path, so the pipeline survives environment moves.
"""
import os
import subprocess
import sys

from PIL import Image


def align_and_triangulate(white_path, black_path, out_matted, alpha_out=None):
    w_img = Image.open(white_path)
    b_img = Image.open(black_path)

    if w_img.size != b_img.size:
        print(f"Resizing white {w_img.size} to match black {b_img.size}...")
        w_img = w_img.resize(b_img.size, Image.Resampling.LANCZOS)
        w_img.save(white_path)

    py = sys.executable
    here = os.path.dirname(os.path.abspath(__file__))

    cmd = [py, os.path.join(here, "triangulate_matte.py"),
           white_path, black_path, out_matted]
    if alpha_out:
        cmd += ["--alpha-out", alpha_out]
    subprocess.run(cmd, check=True)

    subprocess.run([py, os.path.join(here, "check_matte.py"),
                    out_matted, "--checks", "--report"], check=False)


if __name__ == "__main__":
    if len(sys.argv) >= 4:
        align_and_triangulate(sys.argv[1], sys.argv[2], sys.argv[3],
                              sys.argv[4] if len(sys.argv) > 4 else None)
    else:
        print(__doc__)
        sys.exit(1)
