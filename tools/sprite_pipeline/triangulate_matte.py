#!/usr/bin/env python3
"""Recover straight alpha from a white plate and a black plate.

Ported from the Seirin sprite pipeline (SodoMita/Seirin) for Chrono Nexus.
The difference between the plates is the alpha. See
ai_agent_docs/skills/chrono-sprite/references/sprite-spec.md.
"""
from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image


def triangulate(white_path: Path, black_path: Path, out_path: Path, alpha_path: Path | None = None) -> None:
    white = Image.open(white_path).convert("RGB")
    black = Image.open(black_path).convert("RGB")

    if white.size != black.size:
        raise SystemExit(f"Size mismatch: white={white.size}, black={black.size}")

    w = np.asarray(white, dtype=np.float32) / 255.0
    b = np.asarray(black, dtype=np.float32) / 255.0

    # Classic difference matte:
    #   B = F * a
    #   W = F * a + (1 - a)
    # => a = 1 - (W - B)
    alpha_rgb = 1.0 - (w - b)
    alpha = np.clip(alpha_rgb.mean(axis=2), 0.0, 1.0)

    # Recover foreground color from black plate.
    safe_alpha = np.maximum(alpha, 1e-6)
    fg = np.clip(b / safe_alpha[..., None], 0.0, 1.0)

    rgba = np.dstack([
        (fg * 255.0 + 0.5).astype(np.uint8),
        (alpha * 255.0 + 0.5).astype(np.uint8),
    ])

    out_path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(rgba, "RGBA").save(out_path)

    if alpha_path is not None:
        alpha_path.parent.mkdir(parents=True, exist_ok=True)
        Image.fromarray((alpha * 255.0 + 0.5).astype(np.uint8), "L").save(alpha_path)



def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("white")
    ap.add_argument("black")
    ap.add_argument("output")
    ap.add_argument("--alpha-out")
    args = ap.parse_args()

    triangulate(
        Path(args.white),
        Path(args.black),
        Path(args.output),
        Path(args.alpha_out) if args.alpha_out else None,
    )


if __name__ == "__main__":
    main()
