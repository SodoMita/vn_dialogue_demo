#!/usr/bin/env bash
# Asset rules: shipped art is highly packed WebP only. No PNG/JPEG/GIF/BMP/TGA
# anywhere (addons excepted). SVG is not used for art either; the one allowed
# use is a tiny silhouette for a silent background character (<= 8 KB), and the
# project icon. Character sprites stay small.
set -uo pipefail
cd "$(dirname "$0")/.."
fail=0
svg_max=${MAX_SVG_BYTES:-8192}

bad=$(git ls-files | grep -Ei '\.(png|jpe?g|gif|bmp|tga)$' | grep -v '^addons/' || true)
if [ -n "$bad" ]; then
  echo "[FAIL] non-WebP raster images are tracked:"; echo "$bad" | sed 's/^/  /'; fail=1
else
  echo "[OK]   no PNG/JPEG/GIF/BMP/TGA tracked (addons excepted)"
fi

for f in $(git ls-files | grep -Ei '\.svg$' | grep -v '^addons/' | grep -vx 'icon.svg'); do
  size=$(wc -c < "$f")
  if [ "$size" -gt "$svg_max" ]; then
    echo "[FAIL] $f is an SVG of $size bytes (> $svg_max): art must be WebP; SVG is only for tiny silhouettes"; fail=1
  else
    echo "[OK]   $f is a tiny SVG silhouette ($size bytes)"
  fi
done

max=${MAX_SPRITE_BYTES:-153600}
for f in $(git ls-files 'assets/characters/*.webp'); do
  size=$(wc -c < "$f")
  if [ "$size" -gt "$max" ]; then
    echo "[FAIL] $f is $size bytes (> $max)"; fail=1
  fi
done
[ "$fail" -eq 0 ] && echo "[OK]   WebP character sprites are within $max bytes"
exit $fail
