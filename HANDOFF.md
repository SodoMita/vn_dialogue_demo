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

## Audio details

- Music plays on the **Music** bus, SFX on **SFX**, voices on **Voice** (all → Master).
- Pause / Panic keep ducking the Master bus and pausing `VoicePlayer` in place; music state
  (theme / loop) is preserved across Pause/Resume (asserted in the suite).
- `AudioDirector` and the balloon both create the Music/Voice/SFX buses idempotently.

## Verification

`bash run_tests.sh` on this branch: **296 passed, 9 failed**. The 9 failures are the same
pre-existing failures of `main` @ `07d8378` (baseline before this work: 268 passed, same 9
failed) — all around the held-skip-mode behavior changes of recent mainline commits
(`07d8378`, `87d33aa`, `ad2a181`, …): skip toggling, skip-to-choices, seen-only skip,
voice-resume, panic-resume, backlog seek and history scroll. **No new failures** were
introduced; all 28 new audio checks pass. Script checks cover
`autoloads/audio_director.gd` as well.

The runner still reports shutdown resource-leak warnings (engine-side Ogg/generator
playback objects at forced quit); the counts grew with the number of streams played. They
are cosmetic: the process exit code and all assertions are unaffected.

## Relevant files

- `autoloads/audio_director.gd` — procedural music engine, loops, SFX (new).
- `assets/music/*.ogg`, `assets/sfx/*.ogg` — tiny generated loops and SFX (new).
- `scenes/vn_balloon.gd` — tag handling, typing ticks, UI/overlay/save SFX hooks,
  settings toggle.
- `scenes/vn_balloon.tscn` — authored `ProceduralMusicRow` settings row + connection.
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
- Defaults are `Ctrl` for Skip mode, `Backspace` for Close, and `Esc` for Pause.
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
