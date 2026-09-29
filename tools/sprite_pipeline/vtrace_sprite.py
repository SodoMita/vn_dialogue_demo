#!/usr/bin/env python3
"""Trace a character on a white background into a SMALL background-free SVG.

vtracer (https://github.com/visioncortex/vtracer), tuned for size vs error:

1. background = near-white connected to the border + enclosed flat pure-white
   gaps (arm/head); the light anti-aliased rim joins it. Background pixels are
   made transparent, which vtracer keys out -> no background paths;
2. BASE layer: the crop is upscaled (2x, sub-pixel vertices), posterised with
   k-means in Lab (K ~ 8 flat colours, like cel shading) and traced in
   **polygon** mode, stacked (splines cost ~3x the bytes for the same error on
   this art - same finding as trace/m3_vtracer vs m3_vtracer_poly). Posterising
   first gives clean region borders, so line art and hue boundaries survive
   instead of being merged by a large layer_difference;
3. every ring is simplified with Douglas-Peucker (eps ~0.5 source px);
4. DETAIL layer: a fine vtracer trace (layer_difference 16, speckle 4) supplies
   small shapes (irises, mouth, badge, highlights). They are added on top by a
   greedy knapsack: squared-error reduction (full-shape coverage, so a shape
   never "wins" on pixels it would wrongly cover) per encoded byte, until the
   byte budget is spent;
5. compact path encoding: integer coordinates in the upscaled space, relative
   commands, h/v for axis moves, no z (fills close implicitly), consecutive
   same-colour shapes merged, #rgb where possible;
6. least-squares colour refit: rendering is linear in the flat colours
   (render = sum_k coverage_k * c_k + uncovered * white, occlusion and
   anti-aliasing included), so the colours minimising the MSE against the
   source are solved exactly (bounded lsq on the sparse coverage matrix);
7. --max-kb: a small grid over (K, speckle, eps) for the base; the detail layer
   fills the rest of the budget; the lowest-MSE result wins.

MSE is measured on the cropped sprite composited over white (cairosvg).

Usage:
    vtrace_sprite.py ken_smile_white.webp assets/characters/ken_smile.svg [--max-kb 48] [--scale 2] [--pad 8] [--preview p.webp]

Requires: pip install vtracer cairosvg scipy opencv-python-headless
"""
from __future__ import annotations

import argparse
import io
import os
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


def prepare(src: str, pad: int = 4, fringe_level: int = 160):
    rgb = np.asarray(Image.open(src).convert("RGB"))
    bg = background_mask(rgb.astype(np.int32), fringe_level=fringe_level)
    ys, xs = np.nonzero(~bg)
    x0, y0 = max(xs.min() - pad, 0), max(ys.min() - pad, 0)
    x1, y1 = min(xs.max() + pad + 1, rgb.shape[1]), min(ys.max() + pad + 1, rgb.shape[0])
    return rgb[y0:y1, x0:x1].copy(), ~bg[y0:y1, x0:x1]


# ---------------------------------------------------------------- vtracer

def _vtrace(rgba: np.ndarray, **kw) -> str:
    import vtracer
    with tempfile.TemporaryDirectory() as d:
        p_in, p_out = os.path.join(d, "i.png"), os.path.join(d, "o.svg")
        Image.fromarray(rgba, "RGBA").save(p_in)
        vtracer.convert_image_to_svg_py(p_in, p_out, **kw)
        return Path(p_out).read_text()


def raw_trace(rgb, fig, *, scale: float, cp: int, ld: int, fs: int) -> tuple[str, int, int]:
    h, w = fig.shape
    tw, th = round(w * scale), round(h * scale)
    im = Image.fromarray(rgb).resize((tw, th), Image.Resampling.LANCZOS)
    a = Image.fromarray((fig * 255).astype(np.uint8)).resize((tw, th), Image.Resampling.LANCZOS)
    rgba = np.dstack([np.asarray(im), np.where(np.asarray(a) >= 128, 255, 0).astype(np.uint8)])
    raw = _vtrace(rgba, colormode="color", hierarchical="stacked", mode="polygon", filter_speckle=fs,
                  color_precision=cp, layer_difference=ld, corner_threshold=60, length_threshold=4.0,
                  max_iterations=10, splice_threshold=45, path_precision=3)
    return raw, tw, th


# ---------------------------------------------------------------- encoding

_TOK = re.compile(r"[MCLZ]|-?\d*\.?\d+(?:e-?\d+)?")
_PATH = re.compile(r'<path d="([^"]*)" fill="(#[0-9A-Fa-f]{6})"(?: transform="translate\(([-\d.]+),([-\d.]+)\)")?/>')


def _subpaths(d: str, tx: float, ty: float) -> list:
    toks = _TOK.findall(d)
    subs, cur, cmd, i = [], None, None, 0
    while i < len(toks):
        t = toks[i]
        if t in "MCLZ":
            cmd = t
            i += 1
            if cmd == "Z":
                continue
        n = {"M": 2, "L": 2, "C": 6}[cmd]
        v = [float(x) for x in toks[i:i + n]]
        i += n
        pts = [(round(v[k] + tx), round(v[k + 1] + ty)) for k in range(0, n, 2)]
        if cmd == "M":
            cur = [("M", pts)]
            subs.append(cur)
        else:
            cur.append((cmd, pts))
    return subs


def _join(nums: list[int]) -> str:
    out = ""
    for n in nums:
        s = str(n)
        out += s if (not out or s.startswith("-")) else " " + s
    return out


def encode(subs_list) -> str:
    out, last, first = [], None, True
    cx = cy = 0
    for sub in subs_list:
        for cmd, pts in sub:
            if cmd == "M":
                x, y = pts[0]
                out.append(("M" + _join([x, y])) if first else ("m" + _join([x - cx, y - cy])))
                first = False
                cx, cy, last = x, y, "m"
                continue
            if cmd == "L":
                x, y = pts[0]
                dx, dy = x - cx, y - cy
                if dx == 0 and dy == 0:
                    continue
                c, nums = ("h", [dx]) if dy == 0 else ("v", [dy]) if dx == 0 else ("l", [dx, dy])
                cx, cy = x, y
            else:
                c, nums = "c", [v for (px, py) in pts for v in (px - cx, py - cy)]
                cx, cy = pts[-1]
            piece = _join(nums)
            out.append((piece if piece.startswith("-") else " " + piece) if last == c else c + piece)
            last = c
    return "".join(out)


def _hex(c) -> str:
    r, g, b = (int(round(float(v))) for v in c)
    s = f"{r:02x}{g:02x}{b:02x}"
    return "#" + (s[0] + s[2] + s[4] if s[0] == s[1] and s[2] == s[3] and s[4] == s[5] else s)


def parse_items(raw: str) -> list:
    items = []
    for d, f, tx, ty in _PATH.findall(raw):
        subs = _subpaths(d, float(tx or 0), float(ty or 0))
        if subs:
            c = f.lstrip("#")
            items.append([subs, np.array([int(c[i:i + 2], 16) for i in (0, 2, 4)], float)])
    return items


def to_svg(items, vw, vh, ow, oh) -> str:
    groups = []
    for subs, col in items:
        hx = _hex(col)
        if groups and groups[-1][1] == hx:
            groups[-1][0] += subs
        else:
            groups.append([list(subs), hx])
    body = "".join(f'<path fill="{hx}" d="{encode(s)}"/>' for s, hx in groups)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{ow}" height="{oh}" '
            f'viewBox="0 0 {vw} {vh}">{body}</svg>')


# ---------------------------------------------------------------- scoring / refit

def render(svg: str, w: int, h: int) -> np.ndarray:
    import cairosvg
    png = cairosvg.svg2png(bytestring=svg.encode(), output_width=w, output_height=h)
    return np.asarray(Image.open(io.BytesIO(png)).convert("RGBA")).astype(np.float64)


def mse_on_white(svg: str, rgb, fig) -> float:
    h, w = fig.shape
    r = render(svg, w, h)
    a = r[..., 3:] / 255.0
    comp = r[..., :3] * a + 255.0 * (1 - a)
    ref = np.where(fig[..., None], rgb, 255).astype(np.float64)
    return float(((comp - ref) ** 2).mean())


def refit_colours(items, vw, vh, rgb, fig) -> None:
    """In place: exact least-squares flat colours (coverage matrix from renders
    with three shapes at a time in the R/G/B channels, all others black)."""
    import scipy.sparse as sp
    from scipy.optimize import lsq_linear
    h, w = fig.shape
    n = len(items)
    enc = [encode(s) for s, _ in items]
    rows, cols, vals = [], [], []
    for start in range(0, n, 3):
        body = "".join(
            f'<path fill="{("#f00", "#0f0", "#00f")[i - start] if 0 <= i - start < 3 else "#000"}" d="{enc[i]}"/>'
            for i in range(n))
        r = render(f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" '
                   f'viewBox="0 0 {vw} {vh}">{body}</svg>', w, h) / 255.0
        for ch in range(3):
            k = start + ch
            if k >= n:
                break
            wk = (r[..., ch] * r[..., 3]).ravel()
            nz = np.flatnonzero(wk > 1e-3)
            rows.append(nz)
            cols.append(np.full(len(nz), k))
            vals.append(wk[nz])
    A = sp.csr_matrix((np.concatenate(vals), (np.concatenate(rows), np.concatenate(cols))), shape=(h * w, n))
    cover = np.asarray(A.sum(axis=1)).ravel()
    used = np.flatnonzero(cover > 1e-3)
    A = A[used]
    ref = np.where(fig[..., None], rgb, 255).astype(np.float64).reshape(-1, 3)[used]
    for ch in range(3):
        b = ref[:, ch] - (1 - cover[used]) * 255.0
        x = lsq_linear(A, b, bounds=(0, 255), lsmr_tol="auto", max_iter=300).x
        for k in range(n):
            items[k][1][ch] = x[k]


# ---------------------------------------------------------------- base / detail layers

def posterise(rgb, fig, *, scale: float, k: int, seed: int = 1) -> np.ndarray:
    """Upscale, k-means in Lab over the figure, flat mean-RGB per cluster -> RGBA."""
    import cv2
    h, w = fig.shape
    tw, th = round(w * scale), round(h * scale)
    big = np.asarray(Image.fromarray(rgb).resize((tw, th), Image.Resampling.LANCZOS))
    fb = np.asarray(Image.fromarray(fig.astype(np.uint8) * 255).resize((tw, th), Image.Resampling.BILINEAR)) > 127
    lab = cv2.cvtColor(big, cv2.COLOR_RGB2LAB).reshape(-1, 3).astype(np.float32)
    sel = fb.ravel()
    cv2.setRNGSeed(seed)
    crit = (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 20, 0.5)
    _, _, cent = cv2.kmeans(np.ascontiguousarray(lab[sel][::7]), k, None, crit, 2, cv2.KMEANS_PP_CENTERS)
    lbl = ((lab[sel][:, None, :] - cent[None]) ** 2).sum(2).argmin(1)
    cols = np.array([big.reshape(-1, 3)[sel][lbl == c].mean(0) if (lbl == c).any() else (0, 0, 0)
                     for c in range(k)])
    out = np.zeros((th, tw, 4), np.uint8)
    out[fb, :3] = cols[lbl].round()
    out[fb, 3] = 255
    return out


def trace_flat(rgba: np.ndarray, fs: int) -> list:
    """Trace an already-posterised RGBA image (every colour its own layer)."""
    return parse_items(_vtrace(rgba, colormode="color", hierarchical="stacked", mode="polygon",
                               filter_speckle=fs, color_precision=8, layer_difference=1,
                               corner_threshold=60, length_threshold=4.0, max_iterations=10,
                               splice_threshold=45, path_precision=3))


def simplify(items, eps: float) -> list:
    """Douglas-Peucker on every polygon ring (eps in viewBox units)."""
    import cv2
    out = []
    for subs, col in items:
        ns = []
        for sub in subs:
            if any(c == "C" for c, _ in sub):
                ns.append(sub)
                continue
            pts = np.array([p for _, ps in sub for p in ps], np.int32)
            if len(pts) > 3 and eps > 0:
                pts = cv2.approxPolyDP(pts.reshape(-1, 1, 2), eps, True).reshape(-1, 2)
            if len(pts) < 3:
                continue
            ns.append([("M", [tuple(map(int, pts[0]))])] + [("L", [tuple(map(int, q))]) for q in pts[1:]])
        if ns:
            out.append([ns, col.copy()])
    return out


def _composite(svg, w, h):
    r = render(svg, w, h)
    a = r[..., 3:] / 255.0
    return r[..., :3] * a + 255.0 * (1 - a)


def detail_pass(base, fine, vw, vh, rgb, fig, budget_bytes, *, max_area: float = 3000.0):
    """Greedy knapsack: add small shapes of a fine trace on top of the base
    where they cut the squared error most per encoded byte. The gain uses the
    shape's FULL coverage (not only what stays visible), so it is conservative."""
    import cv2
    h, w = fig.shape
    sx, sy = w / vw, h / vh
    ref = np.where(fig[..., None], rgb, 255).astype(np.float64)
    base_err = ((_composite(to_svg(base, vw, vh, w, h), w, h) - ref) ** 2).sum(2)
    gains = []
    for k, (subs, col) in enumerate(fine):
        rings = [np.array([p for _, ps in sub for p in ps], float) * (sx, sy) for sub in subs]
        allp = np.concatenate(rings)
        x0, y0 = np.maximum(np.floor(allp.min(0)).astype(int), 0)
        x1, y1 = np.minimum(np.ceil(allp.max(0)).astype(int), (w - 1, h - 1))
        if x1 < x0 or y1 < y0 or (x1 - x0 + 1) * (y1 - y0 + 1) > max_area:
            continue
        m = np.zeros((y1 - y0 + 1, x1 - x0 + 1), np.uint8)
        cv2.fillPoly(m, [np.round((r - (x0, y0)) * 8).astype(np.int32) for r in rings], 1, cv2.LINE_8, 3)
        mk = m.astype(bool)
        if not mk.any():
            continue
        g = base_err[y0:y1 + 1, x0:x1 + 1][mk].sum() - ((ref[y0:y1 + 1, x0:x1 + 1][mk] - col) ** 2).sum()
        nbytes = len(encode(subs)) + 26
        if g > 0:
            gains.append((g / nbytes, k, nbytes))
    gains.sort(reverse=True)
    chosen, used = [], 0
    for _, k, nbytes in gains:
        if used + nbytes <= budget_bytes:
            chosen.append(k)
            used += nbytes
    return base + [[fine[k][0], fine[k][1].copy()] for k in sorted(chosen)]


# ---------------------------------------------------------------- driver

GRID = [(8, 24, 0.5), (8, 16, 0.75), (8, 24, 0.75), (8, 36, 0.5), (10, 24, 0.5), (10, 36, 0.5), (6, 16, 0.5)]


def trace(src: str, *, max_kb: float = 48.0, scale: float = 2.0, pad: int = 8, grid=GRID,
          fine=(16, 4), refit: bool = True, verbose: bool = True):
    rgb, fig = prepare(src, pad)
    h, w = fig.shape
    budget = int(max_kb * 1024)
    raw_f, vw, vh = raw_trace(rgb, fig, scale=scale, cp=6, ld=fine[0], fs=fine[1])
    fine_items = simplify(parse_items(raw_f), 0.5 * scale)
    posters = {}
    best = None
    for k, fs, epx in grid:
        if k not in posters:
            posters[k] = posterise(rgb, fig, scale=scale, k=k)
        base = simplify(trace_flat(posters[k], fs), epx * scale)
        base_bytes = len(to_svg(base, vw, vh, w, h))
        if base_bytes > budget * 0.9:
            if verbose:
                print(f"  K {k:2d} fs {fs:2d} eps {epx}: base {base_bytes / 1024:5.1f} KB (too big)")
            continue
        # ~2.5% slack: the colour refit can break same-colour merges
        items = detail_pass(base, fine_items, vw, vh, rgb, fig, int(budget * 0.975) - base_bytes)
        svg = to_svg(items, vw, vh, w, h)
        m = mse_on_white(svg, rgb, fig)
        if verbose:
            print(f"  K {k:2d} fs {fs:2d} eps {epx}: base {base_bytes / 1024:5.1f} KB -> {len(svg) / 1024:5.1f} KB"
                  f"  +{len(items) - len(base)} detail  MSE {m:6.1f}", flush=True)
        if len(svg) <= budget and (best is None or m < best[0]):
            best = (m, items)
    if best is None:
        raise SystemExit(f"nothing fits in {max_kb} KB")
    m0, items = best
    svg, m1 = to_svg(items, vw, vh, w, h), m0
    if refit:
        fitted = [[s_, c.copy()] for s_, c in items]
        refit_colours(fitted, vw, vh, rgb, fig)
        svg2 = to_svg(fitted, vw, vh, w, h)
        m2 = mse_on_white(svg2, rgb, fig)
        if len(svg2) <= budget and m2 < m0:
            svg, m1 = svg2, m2
    return svg, dict(w=w, h=h, kb=len(svg) / 1024, mse=m1, mse_before_refit=m0,
                     psnr=10 * np.log10(255.0 ** 2 / max(m1, 1e-9)), paths=svg.count("<path"))


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("white")
    ap.add_argument("output", help=".svg")
    ap.add_argument("--max-kb", type=float, default=48.0)
    ap.add_argument("--scale", type=float, default=2.0, help="upscale before tracing (sub-pixel vertices)")
    ap.add_argument("--pad", type=int, default=8, help="transparent margin around the figure (px)")
    ap.add_argument("--no-refit", action="store_true")
    ap.add_argument("--preview", help="also write a WebP preview (lossless)")
    args = ap.parse_args()
    svg, info = trace(args.white, max_kb=args.max_kb, scale=args.scale, pad=args.pad,
                      refit=not args.no_refit)
    dst = Path(args.output)
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_text(svg)
    print(f"{dst}: {info['w']}x{info['h']}  {info['kb']:.1f} KB  {info['paths']} paths  "
          f"MSE {info['mse']:.1f} (PSNR {info['psnr']:.2f} dB; before refit {info['mse_before_refit']:.1f})")
    if args.preview:
        r = render(svg, info["w"], info["h"]).astype(np.uint8)
        Image.fromarray(r, "RGBA").save(args.preview, "WEBP", lossless=True)


if __name__ == "__main__":
    main()
