# What is still missing compared with Dialogic / Ren'Py

Status after the `#input=` tag landed (branch `feature/text-input-mochi-q8n`).

## Done in this branch
- **Text input event** (`#input=var?placeholder=&default=&max=&type=&allow_empty=&secret=&ok=`) —
  Dialogic's "Text Input" equivalent: inline field in the dialogue box, validation,
  typed values (`text|int|float`), password mode, storage on `GameState` (so it is saved,
  snapshotted and rolled back) or in the balloon's `input_values`.

## Still missing (ordered by value, each is a self-contained next task)
1. **Timed choices** — a per-response countdown bar with a default branch
   (`[#choice_timer=5?default=2]`). The responses menu already centres and lays out buttons.
2. **`#wait=` / pause tag** — a pure beat between lines; today only `[time]` on a line exists.
3. **Scene transitions** — crossfade / fade-to-colour / wipe between `#bg=` and `#stage=`
   changes (the stage swap is instant; `StageDirector` already tweens sprites).
4. **Glossary / term tooltips** — Dialogic's glossary popups on highlighted words.
5. **CG gallery, music room and an extras/title menu** — `seen.json` already tracks read lines,
   so unlocking is mostly bookkeeping; there is no main menu scene at all yet.
6. **Portrait-level lip-flap / blink animation** while a voiced line plays.
7. **Per-character styling** — name-plate colour and text colour taken from
   `ActorDefinition` instead of one global theme.
8. **Achievements / stats screen** and a playtime counter in save slots.
9. **Text effects in the typewriter** — `[shake]`, `[wave]`, per-word speed, Dialogic's
   `[speed]`/`[pause]` inline tags (DM's own `[wait]` works, the rest does not).
10. **Mobile/controller polish** — on-screen gamepad focus for the system row and a
    settings toggle for tap-to-advance zones.
