#!/usr/bin/env python3
"""Check a triangulated RGBA sprite: composite it over solid colours.

Ported from the Seirin sprite pipeline (SodoMita/Seirin) for Chrono Nexus.

White and black are the two backgrounds a triangulated sprite is guaranteed to
look correct over, because they are the inputs. Fringing and colour error show
up over everything else — mid-grey and saturated colours especially. Always
check there before shipping a sprite.

Not to be confused with tools/composite_over.py, which composites an overlay
image onto a base image (sprite over background). This tool takes ONE sprite
and lays it over flat colours to expose matting defects.

Usage:
    check_matte.py sprite.png --report
    check_matte.py sprite.png --checks --out check.png
    check_matte.py sprite.png --colors "#808080" "#FF00FF" --out check.png

Requires Pillow and numpy (same as tools/triangulate_matte.py).
"""
from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image

# Backgrounds that expose different defects:
#   mid grey      - the classic fringe test; halos invisible on white/black show here
#   magenta/green - reveal colour contamination from an unmatted background
#   teal          - close to Splash/Aquaforge hues; shows tint errors on cool art
#   warm tan      - shows tint errors on skin
DEFAULT_CHECKS = ["#FFFFFF", "#000000", "#808080", "#FF00FF", "#00B140",
                  "#0F5F63", "#C8A882"]


def parse_hex(value: str) -> tuple[int, int, int]:
    v = value.strip().lstrip("#")
    if len(v) == 3:
        v = "".join(ch * 2 for ch in v)
    if len(v) != 6:
        raise SystemExit(f"bad colour '{value}': expected #RRGGBB")
    try:
        return tuple(int(v[i:i + 2], 16) for i in (0, 2, 4))  # type: ignore[return-value]
    except ValueError:
        raise SystemExit(f"bad colour '{value}': not hexadecimal") from None


def composite(im: Image.Image, rgb: tuple[int, int, int]) -> Image.Image:
    src = np.asarray(im.convert("RGBA"), dtype=np.float32) / 255.0
    a = src[..., 3:4]
    bg = np.array(rgb, dtype=np.float32) / 255.0
    out = src[..., :3] * a + bg * (1.0 - a)
    return Image.fromarray((np.clip(out, 0, 1) * 255.0 + 0.5).astype(np.uint8), "RGB")


def report(im: Image.Image) -> int:
    """Flag mattes that are suspicious before they reach a scene."""
    rgba = np.asarray(im.convert("RGBA"), dtype=np.float32) / 255.0
    a = rgba[..., 3]
    total = a.size
    opaque = float((a > 0.99).sum()) / total
    clear = float((a < 0.01).sum()) / total
    soft = 1.0 - opaque - clear

    print(f"size            {im.size[0]} x {im.size[1]}")
    print(f"fully opaque    {opaque * 100:6.2f}%")
    print(f"fully clear     {clear * 100:6.2f}%")
    print(f"partial alpha   {soft * 100:6.2f}%")

    problems = 0
    if clear < 0.005:
        print("WARN  almost nothing is transparent — the background may not have "
              "been removed, or the plates were flattened before triangulation")
        problems += 1
    if soft < 0.001:
        print("WARN  no soft edges at all — alpha looks binary. Anti-aliased hair "
              "and any glass/glow should produce partial alpha")
        problems += 1

    # Edge contamination: compare the colour of near-transparent pixels against
    # the colour of the solid body. A clean matte keeps roughly the same hue at
    # the edge; a contaminated one pulls toward the old background. Comparing
    # against the body (rather than against neutral) avoids flagging art that is
    # simply saturated.
    edge = (a > 0.02) & (a < 0.35)
    body = a > 0.9
    if edge.any() and body.any():
        e = rgba[..., :3][edge].mean(axis=0)
        b = rgba[..., :3][body].mean(axis=0)
        print(f"soft-edge mean colour  R{e[0]:.2f} G{e[1]:.2f} B{e[2]:.2f}")
        print(f"body mean colour       R{b[0]:.2f} G{b[1]:.2f} B{b[2]:.2f}")
        drift = float(np.abs(e - b).max())
        if drift > 0.35:
            print(f"WARN  soft edges drift {drift:.2f} from the body colour — likely "
                  "background contamination (green spill from a sheet, or a bad "
                  "plate pair)")
            problems += 1
    elif edge.any():
        print("note  no fully opaque region to compare edge colour against "
              "(expected for a fully transparent character such as Splash)")
    return problems


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("sprite")
    ap.add_argument("--colors", "-c", nargs="*", help="hex backgrounds to composite over")
    ap.add_argument("--checks", action="store_true",
                    help="use the standard defect-revealing background set")
    ap.add_argument("--out", "-o", help="write a contact sheet of all backgrounds")
    ap.add_argument("--report", action="store_true", help="print alpha statistics")
    args = ap.parse_args()

    path = Path(args.sprite)
    if not path.exists():
        raise SystemExit(f"not found: {path}")
    im = Image.open(path)

    if im.mode not in ("RGBA", "LA", "PA"):
        print(f"WARN  {path.name} has no alpha channel (mode {im.mode}); "
              "compositing is a no-op")

    rc = 0
    if args.report or not (args.colors or args.checks or args.out):
        rc = 1 if report(im) else 0
        if not (args.colors or args.checks or args.out):
            return rc

    colors = list(args.colors or [])
    if args.checks or not colors:
        colors = DEFAULT_CHECKS + colors
    rgbs = [parse_hex(c) for c in colors]

    if args.out:
        pad = 16
        w, h = im.size
        sheet = Image.new("RGB", (len(rgbs) * (w + pad) + pad, h + 2 * pad), (34, 34, 34))
        for i, rgb in enumerate(rgbs):
            sheet.paste(composite(im, rgb), (pad + i * (w + pad), pad))
        out = Path(args.out)
        out.parent.mkdir(parents=True, exist_ok=True)
        sheet.save(out)
        print(f"wrote {out}  ({len(rgbs)} backgrounds: {', '.join(colors)})")
    else:
        stem = path.with_suffix("")
        for c, rgb in zip(colors, rgbs):
            dst = Path(f"{stem}_over_{c.lstrip('#')}.png")
            composite(im, rgb).save(dst)
            print(f"wrote {dst}")
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
