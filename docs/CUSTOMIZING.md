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
