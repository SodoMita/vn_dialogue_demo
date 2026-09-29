#!/usr/bin/env bash
# Asset rules: shipped art is highly packed WebP only. No PNG/JPEG/GIF/BMP/TGA
# and no SVG art anywhere in the repo (addons and the project icon excepted),
# and every character sprite stays small.
set -uo pipefail
cd "$(dirname "$0")/.."
fail=0
bad=$(git ls-files | grep -Ei '\.(png|jpe?g|gif|bmp|tga|svg)$' | grep -v '^addons/' | grep -vx 'icon.svg' || true)
if [ -n "$bad" ]; then
  echo "[FAIL] non-WebP image files are tracked:"; echo "$bad" | sed 's/^/  /'; fail=1
else
  echo "[OK]   only WebP images tracked (plus icon.svg and addons)"
fi
max=${MAX_SPRITE_BYTES:-153600}
for f in $(git ls-files 'assets/characters/*.webp'); do
  size=$(wc -c < "$f")
  if [ "$size" -gt "$max" ]; then
    echo "[FAIL] $f is $size bytes (> $max)"; fail=1
  fi
done
[ "$fail" -eq 0 ] && echo "[OK]   character sprites are within $max bytes"
exit $fail
