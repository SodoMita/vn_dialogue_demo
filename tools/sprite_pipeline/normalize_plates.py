#!/usr/bin/env python3
"""Clamp a matte plate's background to the exact plate colour.

Ported from the Seirin sprite pipeline (SodoMita/Seirin) for Chrono Nexus.

Generators often answer "pure #FFFFFF" with 250-tone haze or "pure #000000"
with a green/blue-tinted near-black. tools/triangulate_matte.py assumes the
background is EXACTLY the plate colour, so any haze lands in the alpha as
partial transparency everywhere ("almost nothing is transparent" WARN).

This tool measures the dominant background colour from corner patches and
maps pixels close to it onto the exact plate colour. Figure pixels differ
from the background by more than the threshold and are untouched.

Usage:
    normalize_plates.py white.png black.png
    normalize_plates.py plate.png --target white --threshold 40
"""
import argparse

import numpy as np
from PIL import Image


def background_colour(a: np.ndarray, patch: int = 12) -> np.ndarray:
    corners = np.concatenate([
        a[:patch, :patch].reshape(-1, 3),
        a[:patch, -patch:].reshape(-1, 3),
        a[-patch:, :patch].reshape(-1, 3),
        a[-patch:, -patch:].reshape(-1, 3),
    ])
    return np.median(corners, axis=0)


def normalize(path: str, target: int, threshold: float) -> dict:
    im = Image.open(path).convert("RGB")
    a = np.asarray(im).astype(np.float64)
    bg = background_colour(a)
    dist = np.sqrt(((a - bg) ** 2).sum(axis=2))
    mask = dist <= threshold
    a[mask] = target
    Image.fromarray(a.astype(np.uint8)).save(path)
    return {
        "file": path,
        "detected_bg": bg.round(1).tolist(),
        "target": target,
        "clamped_pct": round(100.0 * mask.mean(), 2),
    }


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("plates", nargs="+")
    ap.add_argument("--target", choices=["auto", "white", "black"], default="auto")
    ap.add_argument("--threshold", type=float, default=40.0)
    args = ap.parse_args()
    for path in args.plates:
        if args.target == "auto":
            bg = background_colour(
                np.asarray(Image.open(path).convert("RGB")).astype(np.float64))
            target = 255 if bg.mean() > 127 else 0
        else:
            target = 255 if args.target == "white" else 0
        print(normalize(path, target, args.threshold))


if __name__ == "__main__":
    main()
