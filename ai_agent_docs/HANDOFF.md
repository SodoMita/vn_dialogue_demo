# VN Dialogue Demo — Handoff

Date: 2026-09-22
Project: Godot 4.7.2, nathanholland Dialogue Manager v4.1.0
Branch: `feature/procedural-audio` (based on `main` @ `07d8378`)

## Current state

The branch adds runtime music and SFX to the project (previously: voices only, "no music
player in the project"). Working tree contents of the branch:

- **Procedural music** — `autoloads/audio_director.gd` (autoload `AudioDirector`) renders
  music at runtime into an `AudioStreamGenerator` (22.05 kHz): pad chords, bass pulse and
  arpeggio per 4/4 bar, scheduled `LOOKAHEAD` seconds ahead of the playhead from the
  `THEMES` table (`calm`, `warm`, `tense`, `night` — bpm, root/scale, chord progression as
  scale degrees). Synthesis is phasor rotation (no per-sample `sin`), voices live in
  parallel `PackedFloat64Array`s, and the RNG is seeded (`music_seed`) so runs are
  reproducible.
- **Tiny OGG loops** — `assets/music/day.ogg` / `night.ogg` (4 s, ~12 KB each), seamless by
  construction (every partial is an integer multiple of 1/T). `play_music_loop()`
  crossfades between two loop players; OGG `loop` is enabled at load.
- **SFX** — OGG assets in `assets/sfx/` (click, open, close, confirm, save, error —
  3.7–4.4 KB each) played by key; keys without a file are synthesized at runtime into
  cached `AudioStreamWAV`s (`tick0-5` typewriter blips, `click`, sweeps, chimes, `error`).
  The typewriter ticks per character via `DialogueLabel.spoke` (throttled, pitch-varied,
  suppressed in skip mode); chrome buttons, overlays, choices and save/load each play a
  cue. All SFX ride the existing SFX bus.
- **Dialogue tags** — `#music=calm|warm|tense|night|stop`, `#music=loop:<file>`,
  `#sfx=<key>`; `dialogue/intro.dialogue` uses them (calm classroom → tense secret →
  warm rooftop → `loop:night` outro).
- **Settings** — authored `ProceduralMusicCheck` row ("Generated music") in
  `vn_balloon.tscn` (default on); off = the same themes fall back to mood-matched loops
  (`THEME_LOOPS`). Persisted as `procedural_music` in `user://settings.json`.
  RU translation added (`Генерируемая музыка`).

Every generated audio file is **under 20 KB** (enforced by the test suite); the largest is
`assets/music/day.ogg` at 12 853 bytes.

Follow-up iteration on the same branch adds the UI-sound layer:

- **Sound toggles** — Settings/ Audio gains **Typewriter sound** and **Button sound**
  checkboxes (default on, persisted as `sfx_typewriter` / `sfx_buttons`). Typewriter gates
  the per-character ticks; Button gates all UI feedback (clicks, overlay open/close,
  save/error, choice picks). Story `#sfx=` tags bypass the toggle on purpose.
- **Per-choice sounds** — each response plays the `confirm` chime at its own pitch
  (`CHOICE_PITCHES`, ascending per option index, wrap-around); a response may tag
  `#sfx=<key>` to pick its own clip (`DialogueResponse.tags`).
- **Hold-to-close** — the four full-rect menu panels (history, save/load, settings,
  pause) connect `gui_input`; container/label defaults (PASS / IGNORE) bubble empty-area
  presses up to the panel. Dismissal is a **press-and-hold** (0.55 s): an authored
  `HoldIndicator` golden ring (`scenes/hold_indicator.gd`, 4x size — RADIUS 104,
  solid gold stroke) fills at the press point after a 0.12 s grace and a continuous
  synthesized tone falls from high to low pitch and swells loudest at the end
  (pitch 1.4 → 0.75, gain −18 → 0 dB; `hold_start/hold_progress/hold_stop` in
  AudioDirector), so the sound itself indicates hold progress; release closes the top
  overlay.
  Quick taps are ignored (accidental-tap protection) and any move/swipe > 10 px cancels
  the hold (tracked in `_input` so GUI-consumed drag events still cancel) — touch
  scrolling is unaffected. The panic screen is intentionally excluded.
- **Touch scrolling** — rows and key/rotation buttons inside the three ScrollContainers
  use `mouse_filter = PASS` with `scroll_deadzone = 24`, so drags pan the lists (STOP
  buttons used to swallow the press and block scrolling on touch); `_press_dragged`
  guards the row handlers so a swipe never activates a button, and presses on interactive
  controls never start the hold (they bubble up with mouse_filter PASS).
- **Save/Load close button** — the save menu title becomes `SaveMenuTitleRow` with an
  authored `SaveCloseButton` (`X`), same pattern as `SettingsCloseButton`.

`tests/test_vn_ui.gd` covers all of it (suite at **336 passed** with the same 9
pre-existing held-skip failures as `main`): hold-to-close on the load/settings/pause
menus, quick-tap guard, indicator + falling hold tone (continuity, pitch fall, gain swell, stop),
swipe-cancel, non-left guard, the save menu `X`, PASS row filters, scroll deadzones,
the drag-gesture no-activate guard and interactive-press discrimination.

## Audio details

- Music plays on the **Music** bus, SFX on **SFX**, voices on **Voice** (all → Master).
- Pause / Panic keep ducking the Master bus and pausing `VoicePlayer` in place; music state
  (theme / loop) is preserved across Pause/Resume (asserted in the suite).
- `AudioDirector` and the balloon both create the Music/Voice/SFX buses idempotently.

## Verification

`bash run_tests.sh` on this branch: **336 passed, 9 failed**. The 9 failures are the same
pre-existing failures of `main` @ `07d8378` (baseline before this work: 268 passed, same 9
failed) — all around the held-skip-mode behavior changes of recent mainline commits
(`07d8378`, `87d33aa`, `ad2a181`, …): skip toggling, skip-to-choices, seen-only skip,
voice-resume, panic-resume, backlog seek and history scroll. **No new failures** were
introduced; all new audio, hold-gesture and scroll-guard checks pass. Script checks cover
`autoloads/audio_director.gd` as well.

The runner still reports shutdown resource-leak warnings (engine-side Ogg/generator
playback objects at forced quit); the counts grew with the number of streams played. They
are cosmetic: the process exit code and all assertions are unaffected.

## Relevant files

- `autoloads/audio_director.gd` — procedural music engine, loops, SFX (new).
- `scenes/hold_indicator.gd` — animated hold-to-close ring (new).
- `assets/music/*.ogg`, `assets/sfx/*.ogg` — tiny generated loops and SFX (new).
- `scenes/vn_balloon.gd` — tag handling, typing ticks, UI/overlay/save SFX hooks,
  settings toggle.
- `scenes/vn_balloon.tscn` — authored settings rows (`ProceduralMusicRow`,
  `TypewriterSfxRow`, `ButtonSfxRow`), `SaveMenuTitleRow` + `SaveCloseButton`, and the
  `gui_input` dismiss connections on the four menu panels.
- `dialogue/intro.dialogue` — `#music=` / `#sfx=` tags.
- `tests/test_vn_ui.gd` — audio region of checks (sizes, scheduler, tags, fallbacks,
  settings persistence, pause ducking).
- `run_tests.sh` — now check-onlys `autoloads/audio_director.gd` too.
- `tools/make_audio_assets.py` — regenerates the bundled OGG loops/SFX (provenance).
- `README.md`, `docs/CUSTOMIZING.md` — feature + authoring documentation.

## Carried-over release note (from the 2026-09-21 handoff)

The user intends to release the project now. Do not claim the audio-resume issue is fixed.
If creating a tag for the latest commit, use the next project version according to the
user's release convention; the latest existing release is `v1.16.0`. No tag was created by
the audio work.

## Previous handoff (2026-09-21) — verbatim

Date: 2026-09-21
Project: Godot 4.7.2, nathanholland Dialogue Manager v4.1.0

### Current state

The project is ready for the user's release. The working tree was clean after commit `3a34101`:

`Add configurable Ctrl skip input binding`

Previous release: `v1.16.0` (`d1e12e9`). The project has tags `v1.0.0` through `v1.16.0`; the Ctrl binding change has not been tagged yet.

### Latest input-binding change

The former static `Skip key: Ctrl` display has been replaced by real runtime rebinding:

- Settings has separate authored binding buttons for Advance, Skip mode, Close, History,
  Quick save, Quick load, Pause and Panic.
- Defaults are `Ctrl` for Skip mode, and `Esc` for both Close and Pause. They stay separate actions so each can be rebound; an open menu backs out instead of also pausing. Backspace is not the Close default.
- Clicking a binding button captures the next keyboard key, updates `InputMap` immediately,
  and persists the choice in `user://settings.json`.
- Saved bindings are restored at startup; mouse/touch bindings are preserved.
- The authored scene remains editable; no scene-builder script was introduced.

### Verification

`bash run_tests.sh` completed successfully with the existing suite: **259/259**.

The test runner still reports Godot resource-leak warnings at shutdown, but the process exit code is 0 and all assertions pass.

### Audio-resume follow-up

The Pause/Resume audio issue has been fixed after the original handoff:

- `_silence_audio(true)` now pauses `VoicePlayer` in place and mutes the Master bus.
- Resume unpauses the same clip, continuing from its previous playback position.
- Nested Pause/Panic state keeps both the voice and Master bus paused until both overlays are closed.
- The headless UI suite includes a regression assertion for voice playback across Resume.

Audio details:

- There is no music player in the project.
- Dialogue audio uses `VoicePlayer` on the `Voice` bus.
- `Music`, `Voice`, and `SFX` route to `Master`.

### Relevant files

- `scenes/vn_balloon.gd` — input handling, pause/panic audio silencing, settings persistence.
- `scenes/vn_balloon.tscn` — authored VN UI and Settings controls.
- `project.godot` — input actions, including `dialogue_skip`.
- `tests/test_vn_ui.gd` — UI and behavior assertions.
- `README.md` and `docs/TUTORIAL.md` — user documentation.

### Release note

The user intends to release the project now. Do not claim the audio-resume issue is fixed. If creating a tag for the latest commit, use the next project version according to the user's release convention; the latest existing release is `v1.16.0`.

---

## 2026-09-29 — branch `remi-q7x` (Remi-q7x): edit plan PR1–PR8

Implements `ai_agent_docs/EDIT_PLAN.md`. Baseline in `ai_agent_docs/BASELINE.md`.

- `scenes/motion/` — Klima `StageDirector` + `Sprite3DQuad` + shader, ported with fixes:
  logical destinations for relative tweens, overlapping-property cancel (snap first),
  `copy_placement_from` (no scale), look change keeps quads, `reset_all` stops playback and
  drops story aliases, `generation` counter, public API (`tween_to`, `set_now`,
  `logical_value`, `play_clip`, `register_alias`).
- `scenes/stage/` — `StageTagParser` (pure, appendix F), `ActorDefinition`, `StageActors`.
- `vn_balloon.gd` — `_apply_presentation()` single dispatcher; entries get `pfmt`,
  `motion` [{tag, resolved}], `display_in_backlog`; `_restore_presentation()` replays from the
  last legacy checkpoint; `stage_restored` signal; saves carry `presentation_format`.
- `route_graph_travel.gd` — `_dress` / `_record` add branch-local records (resolved `{}`:
  restore resolves those live).
- `vn_balloon.tscn` — `Stage3D` SubViewport, `VideoLayer`, `Actors`, `Anchors` (11), nodes
  `MotionDirector`, `StageActors`; `characters/maya.tres`, `rook.tres` (wave anim).
- `scenes/stages/classroom.tscn` sample; `assets/video/intro.ogv` (11 KB test pattern).
- Tests: motion PASS, staging 265/0; UI suite unchanged vs baseline (391/8).

Decision change (user, 2026-09-29): placing a character at a marker copies the
marker's FULL transform (position, rotation, scale) - this overrides the edit plan's
"placement ignores marker scale" (PR2, appendix C). Records store `rot` (quaternion) and
`scale` next to `pos`/`yaw`; `#move=` to a marker tweens `quaternion` and `scale` too;
`#place3d=copy=` / `Sprite3DQuad.copy_transform_from()` copy the full global transform.

Open / not done: route-travel records have no resolved endpoints (markers looked up on
restore); legacy `left`/`right` cannot be moved with `#move` (use `#sprite=`/`#tween=`);
yoyo/infinite `#tween=` restores to its rest value, not a running loop.

## Sprites (Remi-q7x)
- Full-body, 4 expressions each (neutral = bare id, `_smile`, `_sad`, `_surprised`).
- Maya, Rook: plate triangulation, `tools/sprite_pipeline/plate_matte.py` (klima tools credited). WebP.
- Ken (new, `characters/ken.tres`): traced with vtracer (`tools/sprite_pipeline/vtrace_sprite.py`), then rasterized to ~40 KB lossy webp (webp-only rule); the 2 MB SVGs are gone from `assets/`.
- Source plates in `art_src/sprite_plates/` (`.gdignore`d). See `tools/sprite_pipeline/README.md`.
- Staging demo uses all three; docs/18, docs/19 recaptured. Older README screenshots (intro) still show the old waist-up art.
- `staging_demo.dialogue` lives in `examples/`: inside `res://dialogue/` the route map compiled it too, prefixing every node id and failing route-graph "locale switch rebakes localized node titles" (regression since a9d9c33; 189/0 again after the move).
- Two parallel Remi-q7x sessions pushed sprite work; bbd7d8d (Rook triangulated, Ken vtrace SVG) is kept; the other session's alternative (vector_sprite.py clipPath variant, ~600 KB SVGs) is on local branch only, not pushed.


## 2026-09-29 — branch `chocola-18-dev` (Chocola-9b2): audit + integration

Audit of `remi-q7x@3e1d028`. Must-fixes 1-5 and should-fixes 6 & scene-
appearance adapter landed; `#move=left/#move=right` still deferred (legacy
slots keep their layout hook — a proper adapter needs anchor sync).

- **Fix #1 — route travel produces resolved records.** `route_graph_travel`
  now carries a `_resolver` Callable + `_shadow` in the branch stage dict.
  `_dress` runs every parsed command through `StageActors.resolve_record`,
  which computes anchor/marker/pos endpoints against the branch shadow (so
  `?by=` chains add to the branch's own destination, not the live logical
  value). All three `RouteTravel.replay` call sites in the balloon supply
  the resolver via `_travel_stage` / `_travel_stage_seed`. Restore now uses
  the stored endpoint without a second marker lookup.
- **Fix #2 — bare `#show` on restore honours the recorded placement.**
  `_apply_show`'s "new actor, no @place" branch now consumes `stored.place`
  before falling back to `default_place`, so a moved marker cannot drift
  the actor to a new destination on reconstruction.
- **Fix #3 — snap overlapping tweens BEFORE reading the relative base.**
  Both `_apply_tween` and `_apply_set` cancel overlapping property tweens
  and re-read the on-screen value before computing the destination, so a
  relative `position:x=+5` sees the whole-position logical value instead
  of a mid-tween sample.
- **Fix #4 — video pending is tied to actor lifetime.** `_free_actor`
  filters `_pending_videos` by the vanishing actor id, so `finish_restore`
  can no longer reattach a looping video to a replacement instance.
- **Fix #5 — AnimationTree playback is tracked and stopped by `reset_all`
  / `nla_stop`.** `play_clip` registers the tree in `_players`; the reset
  path calls `RESET` on state-machine playback and clears `active`.
- **Fix #6 — `spawn_quad()` refreshes in place.** The in-place update
  previously living only inside `_apply_sprite3d()` now lives in
  `spawn_quad` itself; callers no longer force a remove + respawn.
- **Scene-backed appearance adapter.** `_look_key` now accepts any short
  look on a scene-backed actor: the prefixed key is returned and delivered
  by `_set_look` via the body's `set_look(key)` method. Texture-backed
  actors still take the sprite lookup path.

Integration:

- **Demo route to the 3D scene.** `dialogue/intro.dialogue`'s final rooftop
  line ends with a two-choice branch: "Head home" ends the day, "Take one
  last look at the classroom" jumps to a new `~ classroom_3d` cue that
  exercises `#stage=classroom`, `#show=@door`, `#move=@desk?t=0.9`,
  `#anim=maya:wave`, `#show=rook@guest_desk`, `#focus=`, `#hide=@hall` and
  a `#stage=2d` return. Route-graph tests: 189 → 201, no regressions.
- **`build/*` release pipeline.** `.github/workflows/release.yml` (adapted
  from klima-gem) triggers on `build/**` pushes and `v*` tags: web export
  → GitHub Pages, Linux + Windows bundles → GitHub Release. On PRs and
  main, `.github/workflows/godot-ci.yml` runs the headless suite.
- **SharedArrayBuffer on GitHub Pages.** `web/coi-serviceworker.js`
  (vendored from https://github.com/gzuidhof/coi-serviceworker, MIT)
  registers a service worker that re-serves every response with COOP/COEP
  headers. `export_presets.cfg` enables `variant/thread_support=true` and
  ships the shim via `html/head_include`.
- **Post-export packaging.** `scripts/pack_web.sh` copies the shim next
  to `index.html` and calls `scripts/stamp_release.py` which writes
  `version.json` and injects a build badge.
- **`version.txt` -> 1.16.1-chocola.**

### Verification

- `bash run_tests.sh` (Godot 4.7-stable): motion PASS, staging 298/0,
  route-graph 201/0, panic-return PASS. UI suite 428/2 (up from
  baseline 391/8 — the 6 fewer failures include the Voice-bus fix and
  7f3's audio + hold-skip cleanups; the 2 remaining are the same
  pre-existing skip-timing + portrait-layout quirks as `main`).
- Web export was not run locally (no export templates in the sandbox);
  workflow validated via YAML parse only. First `build/*` push in CI
  will produce the first Pages deploy.

### Left for follow-up

- ~~Route walker cannot resolve 3D markers when the branch travels to a
  stage that is not the currently-loaded one.~~ **Done (Chocola-9b2,
  2026-09-29).** `StageActors._find_marker_in_scene` instantiates the
  candidate scene invisibly (never enters the tree), reads its `Marks/`,
  and caches the probe root; `resolve_record` uses it whenever the
  branch shadow's `_stage` doesn't match the currently-loaded one.
  Probes are freed by `_drop_probe_stages` on `reset_all` and
  `_exit_tree`. Regression test in `tests/test_staging.gd::
  _cross_stage_marker_tests` (325 pass).
- Sprite plates: Rook / Ken black-plate mattes are still the earlier
  generation; the image-gen quota is spent. Follow-up when generator
  quality returns.
- Yoyo/infinite loop *phase* is not reproduced on restore (only the
  rest value / loop starts fresh). By design per handoff.
- Two pre-existing UI failures (skip-mode timing, portrait layout) that
  predate the plan — noted, unfixed.

## Audio levels + open items (Chocola-7f3, branch `chocola-18-7f3-audio`)

- **Voice slider never applied**: `%VoicePlayer` had no `bus` (it played on Master), so the Voice bus level
  affected nothing. The scene now sets `bus = &"Voice"`. The old UI-suite failure "Rook's voiced line plays a
  voice clip on the Voice bus" was this bug, not a pre-existing quirk.
- **Volume 0 = subsystem off** (`vn_balloon.gd::_apply_volumes`, `AudioDirector.set_levels`): Music 0 stops the
  generator and loop players and synthesizes nothing; SFX 0 drops `play_sfx` / typewriter ticks / hold tone and
  frees the synth cache (`sfx_suppressed` counts drops); Voice 0 stops the clip and `_play_voice` loads nothing;
  Master 0 does all of it and mutes the Master bus. The director remembers the story's last `#music=` request and
  resumes it when the level rises; `#music=stop` clears it. Pause/Resume goes through `_refresh_master_mute()`, so
  resuming never unmutes a Master that is at 0. Video sound plays on the SFX bus.
- **`#move=left|right`** work on the legacy slots (`StageActors._legacy_actor`): feet-based, recorded/resolved
  like other moves. `_apply_sprite_transform` now keeps a slot's displacement across layout passes and re-homes
  the director's captured position/scale; `#sprite=none` recentres.
- **Infinite `#tween=...?loops=0`** runs again after a restore (`StageDirector.finish_restore`).
- **Stale test fixed**: keyboard skip is a hold gesture on main, but the UI test pressed Ctrl twice and expected a
  toggle, leaving skip latched; that cascaded into "Resume continues the current voice clip", the panic resume and
  more. The test now presses and releases.

- **Ken art is webp** (4 x ~40 KB instead of 4 x ~2 MB SVG); no PNG and no scene-builder scripts are tracked.
- **Demo -> 3D route is tested**: the shipped intro's last rooftop choice reaches `~ classroom_3d`
  (`tests/test_staging.gd::_shipped_route_tests`: route-map edge, 3D stage, walk, exit, rollback into it).
- Suites: UI 426/0 (every former "baseline" failure is fixed or was a stale test), route-graph 201/0,
  motion PASS, staging 310/0.

Still open: Rook/Ken black-background plate redo (image generator unavailable, current sprites are usable);
yoyo/infinite loop phase is not reproduced on restore (by design).


## 2026-09-29 (second round) — branch `chocola-18-dev` (Chocola-9b2)

Merged `chocola-18-7f3-audio` on top of the first-round audit fixes:

- `%VoicePlayer` now has `bus = &"Voice"` (was Master → Voice slider was
  a no-op). This was mis-labelled a pre-existing failure in the baseline.
- Volume 0 on any slider switches the corresponding subsystem OFF
  (`AudioDirector.set_levels` + `vn_balloon._apply_volumes`): Music 0
  stops the procedural generator + loop players, SFX 0 drops
  `play_sfx`/typewriter/hold synth (`sfx_suppressed` counter), Voice 0
  stops the current clip and skips loads, Master 0 does all of them
  plus mutes the Master bus. Story `#music=` last request is remembered
  and resumes when the slider rises. Pause/Resume routes through
  `_refresh_master_mute()` so Resume never un-mutes a Master at 0.
- Video audio plays on the SFX bus.
- Regression tests for all of the above (`tests/test_vn_ui.gd`).
- `#move=left|right` on the legacy slots (via
  `StageActors._legacy_actor`): feet-based, recorded + resolved like
  normal actor moves. Slot displacement survives layout passes; a
  `#sprite=none` recentres.
- Infinite `#tween=?loops=0` restarts after restore
  (`StageDirector.finish_restore`).
- Stale UI test fix: keyboard skip is a press-and-hold gesture on main,
  but the test pressed Ctrl twice and expected a toggle; the latched
  skip cascaded into three other spurious failures.

### Verification (second round)

- Godot 4.7-stable headless: motion PASS, staging 298/0, route-graph
  201/0, panic-return PASS, **UI 428/2** (was 391/8 in the baseline).
- Those 2 UI failures were NOT pre-existing quirks of `main`: "portrait sprites sit apart" was a bug in the first
  version of the legacy-slot tracking (displacement measured in `position`, so a rotate-to-portrait resize counted
  as a move; now measured in offsets), and "skip mode stops at choices" was a stale test (skip stays armed across a
  choice by design). Both are fixed in the merge below (UI 426/0).

## Web build verified in a real browser (Chocola-7f3, branch `chocola-18-7f3-audio`)

9b2's build/CI/SAB work was never run. Now it was: a real `godot --export-release "Web"` (Godot 4.7 web templates),
`scripts/pack_web.sh`, then headless Chromium against a plain static server with NO COOP/COEP headers.

- The service worker works: first load shows Godot's isolation error, the worker registers, the page reloads, then
  `crossOriginIsolated` is true, Godot boots as "multi-threaded", the classroom + dialogue box render.
- **Found and fixed:** on web, `ProceduralMusic` logged "trying to play a sample from a stream that cannot be sampled"
  (web defaults to Sample playback, which cannot play `AudioStreamGenerator`). `project.godot` now sets
  `audio/general/default_playback_type.web=0`; the warning is gone in the rerun.
- **Found and fixed (desktop too):** `AudioDirector._synth_stream` had no `"holdtone"` branch, so the hold gesture's
  "falling tone" was always the 12 ms click (`_synth_holdtone()` was dead code). It is now the real ~1 s tone, looped
  while the gesture lasts, with a regression test. This also explains the intermittently failing check
  "the hold tone plays continuously while charging".
- New: `tests/web_smoke.mjs` (isolation + threaded boot + no page/script errors + no sample warning), wired into
  `release.yml` as a non-blocking step; `tests/check_assets.sh` (WebP-only + sprite size guard, run first by
  `run_tests.sh`); `build/` and `dist/` gitignored; Web preset excludes `web/*` and `scripts/*`; `docs/WEB_BUILD.md`.
- Not verified from here: the GitHub Actions run itself (workflows parse; Pages must be enabled in the repo settings).
- Asset rule (human, chat ids 18/36/38): art is highly packed WebP, never PNG; SVG is "awful and bad and not used" for
  real art, but a tiny SVG may show a silent third character. `tests/check_assets.sh` enforces exactly that (SVG <= 8 KB
  allowed, larger rejected). Ken stays WebP (~40 KB); Remi's 47 KB-SVG Ken branch must not be merged.


Still open: Rook/Ken black-background plate redo (image generator unavailable, current sprites are usable);
yoyo/infinite loop phase is not reproduced on restore (by design).

- Ken stays WebP: the human said SVG is "awful and bad and not used" (chat id 36); Remi's SVG branch must not be merged.

## 2D demonstration of "any number of sprites" (Chocola-7f3, human chat id 42)

The human's point: on the **2D** scene the system has no dependency on `SpriteLeft`/`SpriteRight` and can show any
number of sprites. 9b2 had only put the silent `shadow` in the 3D classroom (and, in parallel, on the rooftop).
Now both exist and are kept: `dialogue/intro.dialogue` shows `#show=shadow@far_right` on the very first classroom line
(persisting to the rooftop, hidden on the finale), and the rooftop still re-shows it at sunset, so the rooftop scene is
self-contained when reached without replaying the classroom.

- `tests/test_staging.gd::_silent_2d_tests`: shadow on the first line at the far_right anchor; three sprites at once
  once Rook and Maya appear; the shadow steps back while others speak; ten definition-less dynamic actors plus both
  legacy slots = twelve sprites at once; rollback/roll-forward; a real `RouteTravel.replay` to the rooftop keeps the
  shadow and stores a resolved place. 9b2's `_shipped_rooftop_shadow_tests` also stays.
- **Checked in a real browser**: real Web export, headless Chromium, advanced through the intro: Maya (left slot),
  Rook (right slot, dimmed while Maya speaks) and the shadow (`far_right`) are on screen together. The isolation +
  threaded boot also worked in that run.
- Gotchas found on the way: (1) `.dialogue` files are compiled at import, so edit -> `godot --headless --import` before
  running tests, otherwise the old line is played; (2) `balloon.start()` is async and a previous test can leave a valid
  `dialogue_line`, so `_wait_line()` alone can return before the new first line was applied (`_wait_for_shadow()`);
  (3) `intro.cues["rooftop"]` is the bare line number ("29"), full ids look like `33rodbi2bnnh@29`.
- Art follow-up (not done): in the screenshot the silhouette reads as a heavy dark blob (wide torso, big head) rather than
  a person, and it is dimmed to 45% while others speak. It is <= 8 KB SVG by the human's rule; a slimmer shape would look better.

## Audit of 9b2's cross-stage probe and scene-backed looks (Chocola-7f3)

Two more things that were claimed done but had no test that could fail:

- **Cross-stage marker probe** (`StageActors._find_marker_in_scene`, `_resolve_place_record`): for a branch on a stage
  that is not loaded, the record was computed relative to the scene ROOT, while live play expresses the marker relative
  to the scene's `Actors` node. On the real `classroom.tscn` the two coincide (Actors is at identity), which is the only
  scene the original test used. On a stage whose `Actors` node is moved/rotated/scaled the walker placed the actor at
  (8.6, 0.15, -0.26) where live play puts it at (0.74, -0.93, 0.55). Fixed (marker relative to the probe scene's
  `Actors`), and the hidden `_walker_shadow_ref` member was replaced by passing the shadow explicitly.
  `_probe_matches_live_tests` builds a stage with transforms on root, `Marks`, a holder around the marker and `Actors`,
  and compares walker vs live (pos, rot, scale, yaw, a `?by=` chain) and the resulting global transform after restore.
- **Scene-backed appearances** (`ActorDefinition.scene`): the creation look was never delivered to the body's
  `set_look` (only later looks were), so the record said `happy` while the body never saw it, also after restore.
  Fixed in `_new_actor`; contract documented in `docs/STAGING.md` ("Scene-backed characters").
- **Shadow art**: 9b2's redraw ("slimmer human silhouette") was checked against Ken/Maya at equal height: legs merged into
  one column with a rectangular hole, a pedestal-like foot block and an unaligned pale halo. Redrawn as a single closed
  outline at Ken's 0.38 aspect (imported 475x1250, `svg/scale=2.5`): head, neck, shoulders, arms hanging apart, two legs.
  1.8 KB, generated once by a throwaway script (not shipped).
- Suites: UI 433/0, route-graph 201/0, motion PASS, staging 383/0.
