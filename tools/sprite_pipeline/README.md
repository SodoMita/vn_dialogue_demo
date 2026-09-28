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
