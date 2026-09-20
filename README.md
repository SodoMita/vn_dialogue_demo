# VN Dialogue Demo — classical visual-novel UI on Nathan Hoad's Dialogue Manager

A complete Godot **4.7.2** project using **nathanhoad/godot_dialogue_manager v4.1.0**
(the release built for Godot 4.7) with a fully custom, classical visual-novel balloon:

- full-screen background stage (`#bg=` tag)
- left / right character sprite slots with spotlight dimming (`#sprite=`, `#focus=`)
- gold-trimmed dialogue box + name plate, serif novel font
- typewriter text via the addon's `DialogueLabel`, skip with `Esc`, advance with `Enter`/click
- bobbing "next" indicator
- centred choice buttons via the addon's `DialogueResponsesMenu`
- **history (backlog) panel with rollback**: `H` opens it (scrollable with wheel / keys),
  clicking any logged line jumps back to it and restores the story state + stage exactly as
  they were; Ren'Py-style the rollback is non-destructive — the mouse wheel rolls the game
  back a line and forward again through the kept lines (`docs/05_history.png`)
- **save / load with an arbitrary number of slots**: a Kirikiri/Ren'Py-style **bottom system
  row** under the dialogue box (`QS QL Save Load Auto Skip < Choice Choice > Log Set Panic`,
  including Kirikiri-style jumps to the previous/next choice), save/load menus that list every
  `user://saves/slot_*.json` with a runtime-rendered thumbnail, a `+ New slot` button, and
  `F5`/`F9` quick save/load into slot 0 (`docs/07_system_row.png`, `docs/08_save_menu.png`)
- **auto & skip modes** (skip stops by itself at choices; skip speed configurable; "skip
  seen only" halts with a toast at the first line the player has never read, tracked in
  `user://seen.json`), **full settings screen** (text speed, text size, skip speed,
  skip-everything-vs-seen, auto delay, UI scaling scoped to the UI only (the stage and
  sprites keep their authored size and the settings column keeps a usable width at any
  scale), fullscreen, V-Sync, resolution presets or any custom positive size,
  master/music/voice/SFX volumes, and separate sprite scale / Y-offset settings — applied
  live, persisted to `user://settings.json`), **pause menu**
  (`P` / right click, with Resume/History/Save/Load/Settings/Quit), **panic/boss screen**
  (`F12`) that swaps the whole game for a dry quantum-mechanics lecture page
  (`docs/09_settings.png`, `docs/10_pause.png`, `docs/11_panic.png`)
- **mobile controls**: with `input_devices/pointing/emulate_mouse_from_touch` enabled,
  taps drive the same click/advance path, an upward swipe opens the history backlog, and
  every control is an authored touch target
- **voiced dialogue**: all fourteen spoken character lines carry `#voice=` tags and play
  per-character clips (Maya and Rook) on the Voice bus, silenced again on unvoiced lines;
  the clips were generated as Opus but ship as tightly packed Ogg Vorbis (mono, 32 kbps)
  because Godot 4.7 has no Opus importer
- **compact art**: backgrounds and portraits ship as lossy WebP at quality 0.9 — ~483 KB
  instead of ~4 MB of PNG, with no visible quality loss

Verified headless with `Godot_v4.7.2-stable_linux.x86_64`: **209/209 checks pass**, zero
`SCRIPT ERROR` / `Parse Error` in import, runtime and editor logs. Real rendered frames are
saved in `docs/` (captured under Xvfb).

## The balloon is an authored scene, not a scene-builder script

`scenes/vn_balloon.tscn` contains the *entire* UI as plain nodes you can open and edit in the
Godot editor (theme, margins, sprite slots, name plate, indicator animation, the response
button template, even the `MutationCooldown` timer). `scenes/vn_balloon.gd` only adds
behaviour — it creates **no** nodes, adds **no** children and instantiates **no** scenes (the
test-suite asserts this). All node references use `%UniqueName` lookups.

## Wiring

- Autoloads: `GameState` (story state) + `DialogueManager` (addon runtime).
- Project setting `dialogue_manager/runtime/balloon_path = res://scenes/vn_balloon.tscn`
  makes `DialogueManager.show_dialogue_balloon(...)` use the custom balloon.
- The balloon implements DM's contract: `start(resource, cue, extra_game_states)`.
- `scenes/vn_scene.tscn` is the runnable demo (also the main scene).

## Stage-direction tags (DM v4 syntax: `[#tag, #tag=value]`)

| tag | effect |
| --- | --- |
| `[#bg=key]` / `[#bg=none]` | switch / clear background (keys of `backgrounds` on the balloon) |
| `[#sprite=key:left\|right]`, `[#sprite=none:slot]` | show / clear a portrait (keys of `sprites`) |
| `[#focus=left\|right]` | spotlight one slot, dim the other |
| `[#box=hide]` / `[#box=show]` | hide / show the dialogue box for pure stage moments |

Dialogue also uses v4 features: `{{var}}` interpolation, `do x = true` mutations, `if/else`,
cues (`~ start`, `~ rooftop`), choices, and `[speed=0.5]...[/speed]` bbcode. See
`dialogue/intro.dialogue`.

## History & rollback

Every shown line is logged into the balloon's `history` (text, character, the line's ID, a
`GameState` snapshot, the dressed-stage keys and whether the line offered choices). The panel
itself is authored in `vn_balloon.tscn` (`HistoryPanel` / `HistoryScroll` / `HistoryList` /
`HistoryEntry` template); entries duplicate the template the same way the choices menu does,
and the `ScrollContainer` scrolls with the mouse wheel or by moving focus.

Rollback is **non-destructive** (Ren'Py-style): a `history_cursor` marks the line on screen,
entries past it form a forward stack, and wheel-up / wheel-down roll the game back / forward
one entry at a time. Advancing from a rolled-back position starts a new branch and drops the
forward stack. Clicking an entry (or rolling the wheel):

1. moves the cursor to that entry,
2. restores the `GameState` snapshot (`snapshot()`/`restore()` in `autoloads/game_state.gd`),
3. re-dresses the stage from the stored `#bg`/`#sprite`/`#focus` keys,
4. re-fetches the line by ID and types it out again.

Scope note: snapshots cover `GameState`'s exported variables; ephemeral balloon `locals` and
other autoloads are not snapshotted.

## Save / load, settings, pause & panic

The bottom system row (authored in `vn_balloon.tscn`, `Balloon/BottomUI/SystemRow`) mirrors the
control bars of Kirikiri / Ren'Py / Monogatari-style engines: `QS`/`QL` quick-save/load slot 0,
`Save`/`Load` open the slot menu, `Auto`/`Skip` toggle modes (the button tints gold while on),
`Log` opens the backlog, `Set` the settings panel, `Panic` the boss screen, and `< Choice` /
`Choice >` jump back to the previous choice / forward to the next one (Kirikiri-style). The
same actions work from the keyboard: `F5`/`F9` quick save/load, `P` or right-click pauses,
`F12` panics, mouse wheel rolls the game back/forward through the backlog.

Slots live in `user://saves/slot_<n>.json`, one file each — any number of them:

```json
{ "resource": "res://dialogue/intro.dialogue", "cursor": 7,
  "meta": { "label": "Maya: Fine, you win...", "when": "2026-09-20T19:19:00",
            "bg": "classroom", "left": "maya_smile", "right": "rook", "focus": "left" },
  "history": [ {id, character, text, bg, left, right, focus, choices, state}, ... ] }
```

The save menu lists every slot file found on disk (sorted, labelled with the saved line and
timestamp) and shows a **thumbnail** per slot: no image data is stored in the JSON — the menu
composes a small 160x90 `ImageTexture` at runtime from the stage keys in `meta` (background +
sprite portraits, cached per unique stage) and sets it as the row's icon. `+ New slot` creates
the next free index and saves into it. Loading parses a slot, restores `dialogue_resource`,
replaces the backlog and rolls back to the saved cursor — story state, stage dressing and the
current line all come back through the same code path the history panel uses. A toast confirms
each action.

**Settings** (`Set`): a scrolling, sectioned screen with everything a VN player expects —
*Text*: speed (typewriter seconds-per-step), size (applied to the dialogue and name labels),
skip speed, skip-everything vs skip-seen-only, auto delay; *Display*: UI scale (scales only
the UI subtree — the background and character sprites stay untouched — while the settings
margins shrink with the scale so the panel keeps a constant, usable width at any size),
fullscreen, V-Sync, a resolution dropdown of presets (1280×720 … 2560×1440) plus a custom
width/height accepting any positive numbers (custom sizes flip the dropdown to "Custom",
matching sizes re-select their preset); *Audio*: master, music, voice and SFX volumes
driving runtime-created buses (0 mutes, 100 = 0 dB); *Sprites*: character-sprite scale
(pivoted at the bottom centre) and a Y offset, independent of the UI scale. Every control
applies live and is
persisted to `user://settings.json`, and lines the player has read are recorded in
`user://seen.json` so seen-only skip knows where to halt. The panel notes that `Esc` closes
it; `docs/12_settings_at_150.png` shows it at 150% UI scale, still fully usable.

**Voices**: every spoken line in `dialogue/intro.dialogue` tags its clip with `#voice=key`;
the balloon plays it through an authored `VoicePlayer` node routed to the Voice bus (so the
Voice volume slider governs it) and stops it whenever an unvoiced line shows. Clips live in
`assets/voices/*.ogg`, one per character voice; a missing clip simply stays silent. **Pause** (`P` / right click) freezes the typewriter and offers Resume / History /
Save / Load / Settings / Quit.
**Panic** (`F12` / `Panic`) overlays an opaque, completely unrelated physics-lecture page and
swallows every input except the boss key itself, so nothing underneath leaks through.

**Mobile**: `input_devices/pointing/emulate_mouse_from_touch = true` is enabled in
`project.godot`, so touch taps become the mouse clicks the balloon already understands; all
system-row buttons are authored ≥ 44 px tall touch targets.

## Run it

```bash
# import assets / compile dialogue (headless)
Godot_v4.7.2-stable_linux.x86_64 --headless --import

# play (needs a display; use xvfb-run on a server)
Godot_v4.7.2-stable_linux.x86_64 res://scenes/vn_scene.tscn
```

Controls: `Enter` / click / tap = advance or pick a focused choice, `↓/↑` = move between
choices, `Esc` / click = skip typing, `H` or swipe up = open history, wheel / arrow keys =
scroll the history, click a history line = roll back to it, wheel up / down in-game = roll
back / forward one line, `Esc` = close any open panel without side effects, `F5` / `QS` =
quick save, `F9` / `QL` = quick load, `Save`/`Load` = slot menus, `Auto`/`Skip` = modes,
`< Choice`/`Choice >` = jump to previous/next choice, `P` or right-click = pause,
`F12` / `Panic` = boss screen.

## Test & verify

```bash
./run_tests.sh            # import + per-script checks + headless UI test-suite (exit 0 = pass)
```

The suite (`tests/test_vn_ui.gd`) drives the *real* balloon with synthetic keyboard input and
checks: authored-scene structure, no code-built UI, balloon routing via project setting,
tags → stage, typewriter + skip, next indicator, choices via keyboard, mutations, conditions,
cue jumps, `dialogue_ended`, balloon self-freeing, history & rollback, quick save/load (slot 0),
the save/load slot menu (New slot, slot rows, mode titles, Esc-close), settings sliders
(persisted + applied live), auto mode advancing on its own, skip mode running to choices and
stopping there, pause freezing input and resuming cleanly (with its Quit entry present), the
panic screen swallowing everything except the boss key, the fullscreen preference persisting,
and a mobile swipe-up opening the history without advancing the dialogue. v1.5 adds checks
for the Ren'Py-style wheel (roll back one line, roll forward again), the scrolling backlog
panel, the Kirikiri `< Choice` / `Choice >` jumps, and runtime-rendered slot thumbnails with
no image data persisted in the saves. v1.6 adds checks for the full settings surface: text
size applied to both labels, skip speed driving the skip timer, both skip modes, UI scale on
the window, resolution presets ↔ custom spinbox sync with persistence of any custom positive
size, V-Sync persistence, the runtime audio buses with dB conversion and mute at zero, the
scrolling settings container, and seen-only skip advancing through read lines and halting
with a toast on the first unread line. v1.7 checks that UI scaling touches only the UI
subtree (the stage and sprites keep their authored size), that the settings column keeps a
constant rendered width as the scale grows, and that the separate sprite scale / Y offset
settings apply to both sprites and persist. v1.8 checks that a voiced line actually plays on
the Voice bus, that unvoiced narration stops it, that every `#voice=` clip is loadable, and
that the WebP-swapped backgrounds still switch and re-dress on rollback. v1.8.1 adds
regressions for the two field bugs it fixes: portraits keep their authored height (the
sprite Y offset is a delta on the authored rect, never a flatten), and settings rows fill
the scrollable column instead of stopping at their minimum width.

Rendered screenshots (under Xvfb + software GL):

```bash
xvfb-run -a -s "-screen 0 1280x720x24" Godot_v4.7.2-stable_linux.x86_64 \
  --rendering-driver opengl3 --rendering-method gl_compatibility \
  res://tools/capture_shots.tscn
```

## Notes / patches

- `addons/dialogue_manager/utilities/theme_values.gd` carries one 2-line headless-compat
  guard: `interface/editor/code_font_size` can be `Nil` outside the GUI editor, which crashed
  the addon's editor UI on headless import. Everything else in `addons/` is stock v4.1.0.
- The two "resources still in use at exit" lines you may see are teardown bookkeeping of the
  *test harness* (forced `get_tree().quit()`); the game scene itself exits clean.
- Art in `assets/` is AI-generated placeholder imagery (magenta-keyed to transparency for the
  sprites); swap in your own PNGs and re-point the balloon's exported `backgrounds` /
  `sprites` dictionaries in the inspector.
