#!/usr/bin/env python3
"""Trace a character on a white background into a background-free SVG.

Alternative to plate triangulation that needs only ONE render (the white
plate). Uses vtracer (https://github.com/visioncortex/vtracer):

1. background mask = near-white connected to the border, plus enclosed
   near-white regions that are flat pure white (gaps between arm and head)
   - the shirt is shaded (~243), the paper background is ~255;
2. the light anti-aliased fringe next to the background joins it, so no
   white outline gets traced;
3. background pixels become transparent; vtracer keys transparent pixels out,
   so the SVG contains only the figure;
4. the viewBox is cropped to the figure (+ --pad).

Usage:
    vtrace_sprite.py ken_neutral_white.png assets/characters/ken.svg [--png preview.png]

Requires: pip install vtracer (and cairosvg for --png).
"""
from __future__ import annotations

import argparse
import re
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage


def background_mask(rgb: np.ndarray, *, near_white: int = 240, flat_white: float = 251.0,
                    min_gap: int = 150, fringe: int = 2, fringe_level: int = 200) -> np.ndarray:
    nw = rgb.min(axis=2) >= near_white
    lab, n = ndimage.label(nw)
    border = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    bg = np.isin(lab, list(border))
    if n:
        idx = np.arange(1, n + 1)
        sizes = ndimage.sum(nw, lab, idx)
        mins = np.min(np.stack([ndimage.mean(rgb[..., c], lab, idx) for c in range(3)]), axis=0)
        gaps = idx[(sizes >= min_gap) & (mins >= flat_white)]
        bg |= np.isin(lab, gaps)
    # Anti-aliased rim: light pixels touching the background are background.
    near = ndimage.binary_dilation(bg, iterations=fringe)
    bg |= near & (rgb.min(axis=2) >= fringe_level)
    # Drop specks of "figure" floating in the background.
    fig = ndimage.binary_opening(~bg, iterations=1)
    lab, n = ndimage.label(fig)
    if n > 1:
        sizes = ndimage.sum(fig, lab, range(1, n + 1))
        fig = np.isin(lab, 1 + np.flatnonzero(sizes >= max(64, sizes.max() * 0.001)))
    return ~fig


def trace(src: Path, dst: Path, *, pad: int, color_precision: int, layer_difference: int,
          filter_speckle: int, upscale: float = 1.0, fringe_level: int = 200) -> tuple[int, int]:
    import vtracer

    rgb = np.asarray(Image.open(src).convert("RGB"))
    bg = background_mask(rgb.astype(np.int32), fringe_level=fringe_level)
    rgba = np.dstack([rgb, np.where(bg, 0, 255).astype(np.uint8)])
    ys, xs = np.nonzero(~bg)
    x0, y0 = max(xs.min() - pad, 0), max(ys.min() - pad, 0)
    x1, y1 = min(xs.max() + pad + 1, rgb.shape[1]), min(ys.max() + pad + 1, rgb.shape[0])
    crop = Image.fromarray(rgba[y0:y1, x0:x1], "RGBA")
    if upscale != 1.0:
        # Tracing a 2x image gives smoother curves; the viewBox keeps the
        # original pixel size. Alpha is re-thresholded to stay binary.
        big = crop.resize((round(crop.width * upscale), round(crop.height * upscale)), Image.Resampling.LANCZOS)
        a = np.asarray(big.getchannel("A"))
        big.putalpha(Image.fromarray(np.where(a >= 128, 255, 0).astype(np.uint8)))
        crop = big
    with tempfile.TemporaryDirectory() as tmp:
        tmp_png = Path(tmp) / "in.png"
        crop.save(tmp_png)
        vtracer.convert_image_to_svg_py(
            str(tmp_png), str(dst), colormode="color", hierarchical="stacked", mode="spline",
            filter_speckle=filter_speckle, color_precision=color_precision,
            layer_difference=layer_difference, corner_threshold=60, length_threshold=4.0,
            max_iterations=10, splice_threshold=45, path_precision=0)
    svg = dst.read_text()
    w, h = x1 - x0, y1 - y0
    tw, th = crop.width, crop.height
    svg = re.sub(r'(<svg[^>]*?)width="\d+" height="\d+"', rf'\1width="{w}" height="{h}"', svg, count=1)
    # vtracer writes width/height only; add a viewBox so it scales cleanly.
    svg = re.sub(r"<svg([^>]*)>", lambda m: "<svg" + m.group(1).rstrip() +
                 (f' viewBox="0 0 {tw} {th}"' if "viewBox" not in m.group(1) else "") + ">", svg, count=1)
    dst.write_text(svg)
    return w, h


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("white")
    ap.add_argument("output", help=".svg")
    ap.add_argument("--png", help="also rasterize a preview PNG (needs cairosvg)")
    ap.add_argument("--pad", type=int, default=8)
    ap.add_argument("--color-precision", type=int, default=8)
    ap.add_argument("--layer-difference", type=int, default=12)
    ap.add_argument("--filter-speckle", type=int, default=6)
    ap.add_argument("--upscale", type=float, default=2.0, help="trace at this scale for smoother curves")
    ap.add_argument("--fringe-level", type=int, default=160,
                    help="light rim pixels (min channel >= this) next to the background are dropped")
    args = ap.parse_args()
    dst = Path(args.output)
    dst.parent.mkdir(parents=True, exist_ok=True)
    w, h = trace(Path(args.white), dst, pad=args.pad, color_precision=args.color_precision,
                 layer_difference=args.layer_difference, filter_speckle=args.filter_speckle,
                 upscale=args.upscale, fringe_level=args.fringe_level)
    paths = dst.read_text().count("<path")
    print(f"{dst}: {w}x{h} viewBox, {paths} paths, {dst.stat().st_size // 1024} KB")
    if args.png:
        import cairosvg
        cairosvg.svg2png(url=str(dst), write_to=args.png)


if __name__ == "__main__":
    main()
