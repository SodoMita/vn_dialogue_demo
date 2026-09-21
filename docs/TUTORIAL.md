# Playing the demo — a user tutorial

A classical visual-novel front end (fullscreen background, left/right portraits, name plate,
typewriter box, centered choices) built on the
[nathanhoad Dialogue Manager](https://github.com/nathanhoad/godot_dialogue_manager) addon.

## Running it

- Editor: open `project.godot` in Godot 4.7.x and press F5 (main scene `scenes/vn_scene.tscn`).
- Headless/CI: `Godot --path . res://scenes/vn_scene.tscn` (add `--headless` for tests only;
  the game itself wants a window).

## Basic controls

| Action | Input |
| --- | --- |
| Advance / finish typing | click, `Space`, `Enter` |
| Choose an option | `Up`/`Down` then `Enter` (or click) |
| Roll back one line | mouse wheel up (Ren'Py-style, non-destructive) |
| Roll forward again | mouse wheel down |
| Pause menu | `P` or right click |
| Quick save / quick load (slot 0) | `F5` / `F9` |
| Panic / boss screen | `F12` or the `Panic` button (press again to return) |
| Mobile | tap = advance, swipe up = backlog |

The bottom system row mirrors Kirikiri/Ren'Py toolbars:
`QS QL Save Load Auto Skip < Choice Choice > Log Set Panic`.
`< Choice` / `Choice >` jump straight to the previous/next decision point; `Log` opens the
scrolling backlog; `Set` opens settings.

## Modes

- **Auto** — the game advances by itself after the configured auto delay.
- **Skip** — paces through lines at the configured skip speed and always stops at choices.
  In *seen only* mode it halts with a toast at the first line you have never read
  (read lines are remembered in `user://seen.json` across sessions).

## Save / load

`Save`/`Load` open a slot menu with as many slots as you like (`+ New slot`). Slots store the
dialogue resource, the full history, the history cursor and a small stage snapshot; the slot
rows show a runtime-rendered thumbnail. Loading restores story state, stage dressing and the
exact line. `QS`/`QL` and `F5`/`F9` always use slot 0.

## Settings (`Set`)

Everything applies live and persists to `user://settings.json`:

- *Text*: speed, size, **Sync text to voice** (typewriter finishes when the clip ends),
  skip speed, skip *Everything* vs *Seen only*, auto delay.
- *Display*: UI scale (scales only the UI, never the scene; the settings column keeps a
  usable width at any scale), fullscreen, V-Sync, resolution presets or any custom positive
  width/height, "Portrait layout" to force the wrapped portrait settings, and Rotation
  (0/90/180/270): the whole view turns and its logical resolution flips X/Y so it fills
  the window with no gaps — a portrait preview on platforms whose window never rotates.
- *Audio*: master / music / voice / SFX volumes (voices play on the Voice bus).
- *Sprites*: portrait scale and Y offset.

## Styled text

Dialogue lines support BBCode — `Rook: This is [b]bold[/b], [i]italic[/i],
[color=#ff6666]colored[/color].` — rendered by the typewriter label; the backlog stores the
same lines without the markup.
