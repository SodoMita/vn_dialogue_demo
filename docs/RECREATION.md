# Recreating this balloon from scratch with Dialogue Manager

A build-order for the whole front end, engine-first. Versions used: Godot **4.7.2**, addon
**v4.1.0** (the release that targets 4.7).

## 1. Project skeleton

1. New project; install the addon into `addons/dialogue_manager`.
2. Create the balloon scene (a `CanvasLayer` root owning a full-rect `Control` named
   `Balloon`) and point *Project Settings → Dialogue Manager → Balloon* at it. The addon
   instantiates whatever scene that setting names — the script never builds UI.
3. Add a `GameState` autoload for mutations/conditions and rollback snapshots.

## 2. Scene layout (authored, not code-built)

```
Balloon (Control, full rect, gui_input = advance/click/wheel)
├─ Stage (Control)                 # never scaled by UI scale
│  ├─ Background (TextureRect, full rect)
│  ├─ SpriteLeft / SpriteRight (TextureRect, bottom-anchored, expand+keep-aspect)
└─ UIRoot (Control, full rect, mouse_filter=IGNORE)   # everything below scales with UI
   ├─ ResponsesCenter/ResponsesMenu (+ hidden template Button)
   ├─ HistoryPanel (ScrollContainer backlog + hidden entry template)
   ├─ SaveMenuPanel (slot list + hidden slot template, + New slot)
   ├─ SettingsPanel (Margin > ScrollContainer > VBox of rows)
   ├─ PausePanel, PanicScreen, ToastLabel
   └─ BottomUI (NamePlate, DialogueBox > DialogueLabel, NextIndicator, SystemRow)
```

- `DialogueLabel` is the addon's typewriter node (instance its scene); set
  `bbcode_enabled = true` for styled text.
- Timers (`AutoTimer`, `SkipTimer`, `ToastTimer`, …) and the `VoicePlayer`
  (AudioStreamPlayer, bus `Voice`) sit on the root.
- Give every node the script needs `unique_name_in_owner` and use `%Name` onready vars.

## 3. The script, in this order

1. `apply(dialogue_line)`: hide/show chrome, log to history, dress stage tags, start
   typing, then branch: responses → show menu; else wait for input; skip/auto timers.
2. Advance via `next(dialogue_line.next_id)`; the addon's `dialogue_ended` signal frees the
   balloon.
3. Stage tags: read `line.tags` (`bg=`, `sprite=slot`, `focus=`, `voice=`, `box=`).
4. History/rollback: append `{id, character, text(stripped), bg/left/right/focus, choices,
   state}` per line; `rollback_to(i)` re-applies through the same `apply()` path with a
   `_restoring` flag; wheel up/down moves the cursor (forward stack kept).
5. Saves: JSON `{resource, history, cursor, meta}`; thumbnails rendered at runtime from the
   stored keys — never stored as pixels.
6. Settings: sliders/checkboxes apply live + persist to `user://settings.json`; create the
   `Music`/`Voice`/`SFX` buses at runtime sending to Master.

## 4. Pitfalls this project already paid for

- **OptionButton in .tscn**: items serialize as `item_count` + `popup/item_N/text|id`; a
  hand-written `items = [...]` array loads as *zero* items.
- **Signals**: `HSlider.set_value()` emits `value_changed`; `SpinBox.set_value()`,
  `OptionButton.selected=` and `Button.set_pressed()` do **not** — tests must emit by hand.
- **UI scale**: don't use `content_scale_factor` (it scales the scene and shrinks the
  logical viewport). Scale a dedicated `UIRoot` and set its anchors to `1/scale` so
  edge-anchored UI stays on screen; shrink settings margins by `1/scale` to keep the column
  usable.
- **Sprite offsets**: portrait height lives in authored `offset_*`; runtime Y offset must be
  a delta or the rect collapses to zero height (invisible sprites).
- **Audio**: Godot 4.7 imports Ogg/MP3/WAV only — no Opus.
- **Headless CI**: guard every `DisplayServer.window_*` call with a `headless` name check.
- **Scrolling lists**: `ScrollContainer.follow_focus` only scrolls when content actually
  overflows.
- **Choices placement**: anchor the responses menu in a band *above* the dialogue box
  (child of the bottom UI with negative top offset), not centered on the screen — with a
  tall/wrapped box the centered menu slips behind it.
- **Portrait**: settings rows authored as `BoxContainer` so the runtime can flip
  `vertical` and wrap sliders under their labels.

## 5. Verification

The suite (`tests/test_vn_ui.gd`, run by `run_tests.sh`) drives the real balloon with
synthetic input headless and asserts every behavior above; `tools/capture_shots.tscn`
renders real frames under Xvfb into `docs/`. Keep both — they are the regression net that
makes the scene safely editable by hand.
