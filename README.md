# VN Dialogue Demo — classical visual-novel UI on Nathan Hoad's Dialogue Manager

A complete Godot **4.7.2** project using **nathanhoad/godot_dialogue_manager v4.1.0**
(the release built for Godot 4.7) with a fully custom, classical visual-novel balloon:

- full-screen background stage (`#bg=` tag)
- left / right character sprite slots with spotlight dimming (`#sprite=`, `#focus=`)
- gold-trimmed dialogue box + name plate, serif novel font
- typewriter text via the addon's `DialogueLabel`, skip with `Esc`, advance with `Enter`/click
- bobbing "next" indicator
- centred choice buttons via the addon's `DialogueResponsesMenu`
- **history (backlog) panel with rollback**: `H` opens it, clicking any logged line jumps
  back to it and restores the story state + stage exactly as they were (`docs/05_history.png`)
- **save / load**: authored `Save`/`Load` buttons (top-right) plus `F5`/`F9`; the slot stores the
  backlog + story state as JSON in `user://` and loading reuses the rollback path
  (`docs/06_saved_toast.png`)

Verified headless with `Godot_v4.7.2-stable_linux.x86_64`: **75/75 checks pass**, zero
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
`GameState` snapshot and the dressed-stage keys). The panel itself is authored in
`vn_balloon.tscn` (`HistoryPanel` / `HistoryList` / `HistoryEntry` template); entries duplicate
the template the same way the choices menu does. Clicking an entry:

1. truncates the backlog after that entry,
2. restores the `GameState` snapshot (`snapshot()`/`restore()` in `autoloads/game_state.gd`),
3. re-dresses the stage from the stored `#bg`/`#sprite`/`#focus` keys,
4. re-fetches the line by ID and types it out again.

Scope note: snapshots cover `GameState`'s exported variables; ephemeral balloon `locals` and
other autoloads are not snapshotted.

## Save / load

`Save` (or `F5`) writes `user://save_slot_1.json`:

```json
{ "resource": "res://dialogue/intro.dialogue", "history": [ {id, character, text, bg, left,
  right, focus, state}, ... ] }
```

`Load` (or `F9`) parses the slot, restores `dialogue_resource`, replaces the backlog and calls
`rollback_to(history.size() - 1)` - so story state, stage dressing and the current line all come
back through the same code path the history panel uses. A toast (`%ToastLabel` + `%ToastTimer`,
authored) confirms each action. The slot path is exported (`save_path`) so extra slots are a
project tweak away.

## Run it

```bash
# import assets / compile dialogue (headless)
Godot_v4.7.2-stable_linux.x86_64 --headless --import

# play (needs a display; use xvfb-run on a server)
Godot_v4.7.2-stable_linux.x86_64 res://scenes/vn_scene.tscn
```

Controls: `Enter` / click = advance or pick a focused choice, `↓/↑` = move between choices,
`Esc` / click = skip typing, `H` = open history, click a history line = roll back to it,
`Esc` = close history without rolling back, `F5` / Save button = save, `F9` / Load button = load.

## Test & verify

```bash
./run_tests.sh            # import + per-script checks + headless UI test-suite (exit 0 = pass)
```

The suite (`tests/test_vn_ui.gd`) drives the *real* balloon with synthetic keyboard input and
checks: authored-scene structure, no code-built UI, balloon routing via project setting,
tags → stage, typewriter + skip, next indicator, choices via keyboard, mutations, conditions,
cue jumps, `dialogue_ended`, and balloon self-freeing.

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
