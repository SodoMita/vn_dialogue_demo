# Customizing the project

Everything content-related is data; the balloon scene is authored in `scenes/vn_balloon.tscn`
(no UI is built from code).

## Story content (`dialogue/*.dialogue`)

Standard Dialogue Manager syntax plus this project's stage tags:

```
~ start
Some narration. [#bg=classroom, #sprite=none:left, #sprite=none:right]
Rook: Line text [#sprite=rook:right, #focus=right, #voice=r1]
```

- `#bg=key` — switch background (key of the balloon's `backgrounds` dictionary; `none` clears).
- `#sprite=key:slot` — show portrait `key` in slot `left`/`right` (`none:slot` hides it).
- `#focus=slot` — dim the other portrait.
- `#voice=key` — play the voice clip mapped in `VOICES` (`scenes/vn_balloon.gd`); lines
  without a clip stay silent.
- `#box=hide` / `#box=show` — hide/show the dialogue chrome.
- `#music=key` — switch the music: `calm` / `warm` / `tense` / `night` (procedural themes),
  `loop:day` / `loop:night` (a bundled OGG loop from `assets/music/`), or `stop`.
- `#sfx=key` — play `assets/sfx/<key>.ogg`; keys without a file play a synthesized blip.
- BBCode inside the text (`[b] [i] [color=...]`, …) is rendered by the typewriter label.
- `do foo = 1` mutations and `if foo:` conditions run against the `GameState` autoload;
  `~ cue` / `=> cue` jump between sections. Add your own variables to
  `autoloads/game_state.gd` (it also needs them in `snapshot()`/`restore()` for rollback).

## Art

- Put WebP files in `assets/backgrounds/` and `assets/characters/` (lossy q0.9 keeps quality
  and a tiny footprint; PNG imports fine too).
- Assign them in `vn_balloon.tscn`: the balloon node exports `backgrounds` and `sprites`
  dictionaries — add an entry per key and use that key in the tags above.
- Portraits are authored rects on `Balloon/Stage` (`SpriteLeft`, `SpriteRight`); their
  visible height comes from their anchored offsets, and the runtime *sprite scale / Y
  offset* settings are applied as deltas on top, so keep the authored offsets as the
  "100%" pose.

## Voices

- Generate/encode one Ogg Vorbis file per line into `assets/voices/` (Godot 4.7 has **no
  Opus importer**; mono 32 kbps Vorbis is tiny for speech).
- Add the path to the `VOICES` dictionary and tag the line with the same key.
- The clip plays on the **Voice** bus through the authored `VoicePlayer` node; the Voice
  volume slider and "Sync text to voice" both act on it.

## Music & SFX

All music and SFX live in the `AudioDirector` autoload (`autoloads/audio_director.gd`).

- **Procedural themes** are data: the `THEMES` table holds a bpm, a root/scale and a chord
  progression (scale degrees). `play_theme()` schedules pad, bass and arpeggio notes per
  bar into an `AudioStreamGenerator`; tweak the table to retune or add moods. The seed is
  fixed (`music_seed`) so the arpeggios are reproducible.
- **OGG loops** go in `assets/music/` (mono, 22.05 kHz Vorbis; build them so every partial
  is periodic over the loop length — e.g. snap frequencies to multiples of 1/T — for a
  click-free seam) and play via `#music=loop:<file>` or `play_music_loop()`.
- **OGG SFX** go in `assets/sfx/<key>.ogg` and play via `#sfx=<key>` / `play_sfx()`.
- **Synthesized SFX** (`tick*`, `click`, `open`, `close`, `confirm`, `save`, `error`) render
  at first use into cached `AudioStreamWAV`s; `_synth_stream()` is the place to add blip
  shapes. Typewriter ticks come from `typing_tick()` and are throttled there.
- With *Generated music* off, `play_theme()` plays `THEME_LOOPS` instead — remap those to
  point at your own loops.
- Keep new files under 20 KB (the suite enforces it): mono 22 kHz Vorbis at 28–32 kbps is
  a few KB per second. `tools/make_audio_assets.py` regenerates the bundled OGGs
  (numpy + any ffmpeg CLI).

## Look & feel

- Fonts, colors and sizes are theme overrides in `vn_balloon.tscn` (serif display font for
  labels/headers, per-node `theme_override_*` properties).
- The whole UI lives under `Balloon/UIRoot`; the *UI scale* setting scales that subtree.
  Anything you want scaled goes under `UIRoot`, anything scene-related stays on
  `Balloon/Stage`.
- Settings ranges are the slider/spinbox min/max/step values in the tscn; persistence keys
  live in `_save_settings()` / `_load_settings()`.

## Saves

Slots are plain JSON in `user://saves/slot_N.json` (resource, history, cursor, meta). The
menu lists whatever files exist; `+ New slot` just uses the next free number — rename or
delete files freely.
