#!/usr/bin/env python3
"""White/black plate triangulation that survives imperfect plate pairs.

Based on klima-gem's tools/triangulate_matte.py (difference matte, ported
from the Seirin pipeline). An image generator never reproduces the figure
pixel-for-pixel when it swaps the background, so the pure difference matte
leaves faint partial alpha INSIDE the body (every line that moved a pixel
becomes a see-through seam). This tool keeps the difference matte where it
is right - soft edges, hair strands, anti-aliasing - and makes the interior
solid:

1. normalize both plates (background clamped to exact #FFF / #000),
2. alpha_d = 1 - mean(W - B)                       (klima difference matte),
3. core   = figure mask from the WHITE plate (the original render); holes in
            it (white shirt, highlights) are kept only where alpha_d says the
            black plate agrees it is figure,
4. alpha  = 1 in the core, alpha_d (capped) on a --edge px rim; colour is
            the white-plate pixel, bled outward onto the rim,
5. crop to the figure with --pad px, optional --height resize, save.

Usage:
    plate_matte.py white.png black.png out.webp [--height 1400] [--pad 24]
"""
from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage


def _clamp_bg(a: np.ndarray, target: float, threshold: float) -> np.ndarray:
    patch = 12
    corners = np.concatenate([
        a[:patch, :patch].reshape(-1, 3), a[:patch, -patch:].reshape(-1, 3),
        a[-patch:, :patch].reshape(-1, 3), a[-patch:, -patch:].reshape(-1, 3),
    ])
    bg = np.median(corners, axis=0)
    dist = np.sqrt(((a - bg) ** 2).sum(axis=2))
    out = a.copy()
    out[dist <= threshold] = target
    return out


def matte(white: Image.Image, black: Image.Image, *, threshold: float = 24.0,
          edge: int = 2, core_threshold: float = 20.0) -> Image.Image:
    if white.size != black.size:
        black = black.resize(white.size, Image.Resampling.LANCZOS)
    w = _clamp_bg(np.asarray(white.convert("RGB"), dtype=np.float64), 255.0, threshold) / 255.0
    b = _clamp_bg(np.asarray(black.convert("RGB"), dtype=np.float64), 0.0, threshold) / 255.0

    # klima difference matte. Only trusted where both plates agree, i.e.
    # to decide whether an ambiguous (near-white) region is figure and for
    # the anti-aliased rim.
    alpha_d = np.clip(1.0 - (w - b).mean(axis=2), 0.0, 1.0)

    # The white plate is the original render and the source of truth for
    # shape and colour; the black plate is an edit and may be shifted by a
    # pixel or two, so it never adds figure on its own (that is what made
    # white slivers next to hair strands).
    mask = np.sqrt(((w - 1.0) ** 2).sum(axis=2)) * 255.0 > core_threshold
    # Near-white parts (shirt, highlights) are holes in that mask: keep the
    # ones the black plate confirms as figure; enclosed background (gap
    # between hair and arm) is background on both plates, alpha_d ~ 0.
    holes = ndimage.binary_fill_holes(mask) & ~mask
    hole_lab, n = ndimage.label(holes)
    if n:
        mean_a = ndimage.mean(alpha_d, hole_lab, range(1, n + 1))
        mask |= np.isin(hole_lab, 1 + np.flatnonzero(mean_a > 0.5))
    core = ndimage.binary_opening(mask, iterations=1)
    labels, n = ndimage.label(core)
    if n > 1:  # drop specks
        sizes = ndimage.sum(core, labels, range(1, n + 1))
        core = np.isin(labels, 1 + np.flatnonzero(sizes >= max(64, sizes.max() * 0.001)))

    # Rim: a thin band just outside the core keeps the difference alpha
    # (anti-aliasing / hair tips), capped so a shifted black plate cannot
    # create a halo, and takes the colour of the nearest core pixel.
    # Rim alpha comes from the white plate alone: an anti-aliased pixel is
    # w = a*c + (1-a)*white, with c the nearest solid interior colour, so
    # a = sum(1-w) / sum(1-c). No black-plate shift can create a halo.
    inner = ndimage.binary_erosion(core, iterations=edge)
    if not inner.any():
        inner = core
    rim = ndimage.binary_dilation(core, iterations=edge) & ~inner
    _, (iy, ix) = ndimage.distance_transform_edt(~inner, return_indices=True)
    c = w[iy, ix]
    denom = (1.0 - c).sum(axis=2)
    a_rim = np.clip((1.0 - w).sum(axis=2) / np.maximum(denom, 1e-6), 0.0, 1.0)
    a_rim = np.where(denom > 0.3, a_rim, core.astype(np.float64))
    alpha = np.where(inner, 1.0, np.where(rim, a_rim, 0.0))
    alpha = np.where(alpha < 0.03, 0.0, alpha)
    # Straight colour: the plate pixel where solid, un-premultiplied
    # against white on the rim (falls back to the interior colour).
    safe = np.maximum(alpha, 1e-6)[..., None]
    unmixed = np.clip((w - (1.0 - alpha[..., None])) / safe, 0.0, 1.0)
    fg = np.where((alpha >= 0.99)[..., None], w, np.where((alpha > 0.35)[..., None], unmixed, c))
    rgba = np.dstack([(fg * 255.0 + 0.5).astype(np.uint8), (alpha * 255.0 + 0.5).astype(np.uint8)])
    return Image.fromarray(rgba, "RGBA")


def crop(im: Image.Image, pad: int) -> Image.Image:
    a = np.asarray(im.getchannel("A"))
    ys, xs = np.nonzero(a > 8)
    if len(xs) == 0:
        return im
    x0, x1 = max(xs.min() - pad, 0), min(xs.max() + pad + 1, im.width)
    y0, y1 = max(ys.min() - pad, 0), min(ys.max() + pad + 1, im.height)
    return im.crop((x0, y0, x1, y1))


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("white")
    ap.add_argument("black")
    ap.add_argument("output")
    ap.add_argument("--height", type=int, default=0, help="resize to this height (keeps aspect)")
    ap.add_argument("--pad", type=int, default=16)
    ap.add_argument("--edge", type=int, default=2, help="soft rim width in px")
    ap.add_argument("--quality", type=int, default=88, help="WebP quality (lossy RGB, exact alpha)")
    args = ap.parse_args()
    out = crop(matte(Image.open(args.white), Image.open(args.black), edge=args.edge), args.pad)
    if args.height and out.height != args.height:
        out = out.resize((round(out.width * args.height / out.height), args.height), Image.Resampling.LANCZOS)
    path = Path(args.output)
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.suffix.lower() == ".webp":
        out.save(path, "WEBP", quality=args.quality, alpha_quality=100, method=6)
    else:
        out.save(path)
    a = np.asarray(out.getchannel("A"), dtype=np.float32) / 255.0
    print(f"{path}: {out.width}x{out.height}  opaque {100 * (a > 0.99).mean():.1f}%  "
          f"partial {100 * ((a > 0.01) & (a <= 0.99)).mean():.1f}%  {path.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
