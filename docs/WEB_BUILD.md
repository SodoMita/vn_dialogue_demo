# Web build and release pipeline

Pushing to a `build/**` branch (or a `v*` tag, or a manual dispatch) runs
`.github/workflows/release.yml`: it exports **Web**, **Linux** and **Windows**
with Godot 4.7, packs the web export, deploys it to GitHub Pages and attaches
the bundles to a GitHub Release. `godot-ci.yml` runs `run_tests.sh` on pushes to
`main`, `chocola-*` and `remi-*`.

## Why a service worker

The web export is threaded (`variant/thread_support=true`) so the audio worklet
and the procedural music run off the main thread. That needs
`SharedArrayBuffer`, i.e. the COOP/COEP headers, which GitHub Pages does not
send. `scripts/pack_web.sh` copies `web/coi-serviceworker.js` next to
`index.html` (the preset's `html/head_include` loads it); on the first visit
it registers, reloads the page once, and re-serves every response with the
headers. Godot's "Cross-Origin Isolation - missing" error on that very first
load is expected and disappears after the reload.

## Web audio

Web defaults to *Sample* playback, which cannot play the `AudioStreamGenerator`
behind the procedural music. `project.godot` sets
`audio/general/default_playback_type.web=0` (Stream), so the web build mixes in
the audio worklet like desktop.

## Checks

```sh
bash tests/check_assets.sh        # WebP-only art + sprite size guard (also run by run_tests.sh)

# real export + browser smoke test (needs the 4.7 export templates)
godot --headless --export-release "Web" build/web/index.html
bash scripts/pack_web.sh build/web 0.0.0-local
PLAYWRIGHT_DIR=/path/with/playwright node tests/web_smoke.mjs build/web /tmp/shot.jpg
```

`tests/web_smoke.mjs` serves the export **without** COOP/COEP headers, boots it
in headless Chromium and fails unless the page is cross-origin isolated, Godot
starts as a multi-threaded build, and the console has no page/script errors and
no "cannot be sampled" warning. The release workflow runs it as a
non-blocking step and uploads the screenshot.

`build/` and `dist/` are git-ignored. The Web preset leaves tests, docs, art
sources, tools, `web/` and `scripts/` out of the `.pck` (about 8 MB).
