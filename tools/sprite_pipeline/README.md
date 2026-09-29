# Sprite pipeline (white/black plate triangulation)

Full-body character sprites are cut out of two renders of the same image:
one on pure white, one on pure black ("plates").

Credit: `triangulate_matte.py`, `normalize_plates.py`, `check_matte.py` and
`resize_and_triangulate.py` are copied unchanged from
[SodoMita/klima-gem](https://github.com/SodoMita/klima-gem) `tools/`
(originally from the Seirin pipeline). `plate_matte.py` is new here.

## Why `plate_matte.py`

The klima difference matte (`alpha = 1 - (W - B)`) is exact only when the two
plates are pixel-identical apart from the background. AI image editors redraw
the figure slightly when they swap the background, so the pure difference
matte left see-through seams inside the body (9.6% opaque on Maya).

`plate_matte.py` uses the white plate (the original render) for shape and
colour and the black plate only to decide whether enclosed near-white areas
(white shirt, highlights) are figure or background:

1. figure mask = pixels clearly not white on the white plate;
2. enclosed holes kept only where the difference alpha says "figure"
   (gaps between hair and arm stay transparent);
3. anti-aliased rim: `a = sum(1 - W) / sum(1 - C)`, with `C` the nearest
   solid interior colour, so a shifted black plate cannot create halos;
4. crop to the figure (+ `--pad`) and save as WebP (exact alpha).

## Making a character

```sh
# 1. full-body neutral on pure white (portrait), then edits of it:
#    <id>_neutral_white.png, <id>_<expr>_white.png  (change ONLY the face)
#    <id>_neutral_black.png                         (background -> #000)
# 2. cut out every expression
python3 tools/sprite_pipeline/plate_matte.py maya_smile_white.png maya_neutral_black.png \
        assets/characters/maya_smile.webp
# 3. verify on 7 backgrounds
python3 tools/sprite_pipeline/check_matte.py assets/characters/maya_smile.webp --report --out /tmp/chk.png
```

Expression edits only touch the face, so one black plate per character is
enough (the black plate is used only for enclosed near-white regions, and the
face sits inside the solid mask anyway). A per-expression black plate works
too.

Install as `assets/characters/<id>.webp` (neutral) and `<id>_<expr>.webp`,
then add the keys to the `sprites` dictionary in `scenes/vn_balloon.tscn`.
`#show=maya:sad` resolves to the `maya_sad` key.

Source plates (lossless WebP) live in `art_src/sprite_plates/` (ignored by
Godot via `art_src/.gdignore`) so sprites can be re-cut without regenerating.

## Vector route: `vtrace_sprite.py` (used for Ken, then rasterized)

> Shipped art is **webp only**. Ken's traced SVGs (~2 MB each) were rasterized to
> 475x1259 lossy webp (~40 KB, quality 0.8, alpha kept) with Godot's
> `Image.load_svg_from_string(svg, 1.0)` + `save_webp(path, true, 0.8)` and the
> SVGs removed from the repo. Keep a traced SVG only outside `assets/`.

Needs only the white render. Traces it with
[vtracer](https://github.com/visioncortex/vtracer) (`pip install vtracer`)
into an SVG that has **no background paths**:

1. background = near-white connected to the border, plus enclosed regions
   that are flat pure white (gap between Ken's raised arm and head); the shirt
   is shaded (~243) and survives;
2. light anti-aliased rim pixels next to the background are dropped
   (`--fringe-level`, default 160) so no white outline is traced;
3. background becomes transparent, which vtracer keys out;
4. the image is traced at 2x (`--upscale`) for smoother curves, viewBox cropped
   to the figure.

```sh
python3 tools/sprite_pipeline/vtrace_sprite.py ken_smile_white.png assets/characters/ken_smile.svg --png /tmp/preview.png
```

Defaults: `--color-precision 8 --layer-difference 12 --filter-speckle 6`.
Colour precision 7 merged one jacket panel of `ken_surprised` into a grey
cluster; 8 fixed it. Look at every trace. Each SVG is ~2 MB (about 4000
paths); Godot imports it as a normal Texture2D (raise `svg/scale` in the
`.import` file for a sharper texture on big screens).

## No usable black plate: single-plate raster mode

`plate_matte.py white.png - out.webp` builds the figure mask from the white
render alone (background analysis of `vtrace_sprite.py`) and keeps the same
white-plate rim alpha. Handy when the image generator refuses to produce a
clean black plate (it failed several times for Rook).
