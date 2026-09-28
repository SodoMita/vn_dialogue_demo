# Edit plan: `vn_dialogue_demo` - movable actors, 3D stage, animation, video

Reviewed source: `SodoMita/vn_dialogue_demo` @ `3b382c5`, `SodoMita/klima-gem` @ `8e0f885` (read, not run).

**How to read this:** Parts 1-3 are the plan (about two pages). Part 4 is an appendix of implementation details for whoever writes the code; you don't need to review it to approve the direction.

---

## Part 1 - Authoring syntax (the part people and LLMs write)

**Goal:** short, predictable tags that are easy to type, read, and edit. One tag does one thing. There are no node paths, and you only give timing values when you want to change the defaults.

### Rules

- `actor` = a character's ID, e.g. `maya`.
- `@place` = where: a 2D anchor name, a 3D scene marker name, or coordinates.
- `:look` = the appearance, e.g. `smile` → sprite key `maya_smile`. A full sprite key also works.
- `?options` are optional overrides, e.g. `?t=0.8`.
- Separate tags with commas, as today. There are no commas inside a tag; numbers inside a tag are separated by spaces.

### The tags

Proposed authoring interface; these short tags are not implemented yet.

```text
#show=maya                 show Maya; preserve existing look/place, defaults on first creation
#show=maya:smile           change look only - she stays where she is
#show=maya@left            show or put her at the "left" anchor
#show=maya:smile@left      both at once
#move=maya@center          walk/slide to "center" (default time and easing)
#move=maya@center?t=0.8    slower
#move=maya?by=100 0        move by an offset (2D px, or 3D units: ?by=0.5 0 0)
#move=maya@640 700         move to exact coordinates
#hide=maya                 remove
#hide=maya@off_left        walk off to the left, then remove
#focus=maya                spotlight the speaker (legacy left/right still work)
#anim=maya:wave            play an animation authored on the character
#video=intro               play a video; #video=intro:stop stops it
#stage=classroom           switch to a 3D stage scene; #stage=2d goes back
```

### Example scene

```text
Narrator: The door opens. [#stage=classroom, #show=maya@door]
Maya: Morning! [#move=maya@desk, #anim=maya:wave]
Maya: Oh... you forgot? [#show=maya:sad]
Ken: Sorry! [#show=ken@guest_desk, #focus=ken]
[#hide=maya@hall]
```

This example uses the markers `door`, `desk`, `guest_desk`, and `hall` — they are Marker3D nodes you place in the `classroom` scene's `Marks` node.

### 2D places (built in, editable in the stage scene)

`far_left  left  center  right  far_right`, plus `off_left  off_right` for entrances and exits, and `top_left  top  top_right  true_center`.

These are destinations, not slots. Any number of characters can use them, and characters can move between them.

### 3D places (made by you, per scene)

In a 3D stage scene, add `Marker3D` nodes under a `Marks` node and name them (for example `door`, `desk`, `hall`). Those names are the places. Nothing is predefined, because every scene is different.

### Stage switching

Switching to a different stage clears the previous stage's visible actors, movement, local animations, videos, and focus. Character definitions remain registered. Show characters explicitly on the new stage; they are not transferred between 2D and 3D. The authored legacy `left`/`right` nodes are cleared, not destroyed. Selecting the already-active stage is a no-op.

### What keeps working unchanged

- Existing tags keep working: `#bg=`, `#sprite=key:left|right`, `#focus=left|right`, `#box=`, `#voice=`, `#music=`, `#sfx=`.
- Klima's detailed motion tags (`#tween=`, `#set=`, `#shake=`, `#nla=`, `#sprite3d=`, `#place3d=`, `#target=`) stay available as an advanced option for fine control. The short tags above cover everyday staging, so authors normally shouldn't need them.

### Before and after (Klima)

```text
Before: #sprite3d=maya:maya?path=World/Actors&height=1.8, #place3d=maya:copy=World/Marks/Maya
After:  #show=maya@maya_spot

Before: #tween=maya:x=0.5:0.6:sine:in_out?relative
After:  #move=maya?by=0.5 0 0
```

Height, feet anchor, and animation player come from the character's definition, which you set once in the editor. The stage decides which node characters are added to. Default move time and easing are stage settings.

---

## Part 2 - What gets built (reusing existing code)

| Piece | Source | Change |
|---|---|---|
| Tag handling | demo `vn_balloon.gd::_apply_stage_tags()` | Add the new tags here; keep all existing tags. |
| Motion engine | Klima `StageDirector`, `Sprite3DQuad` + shader, and their tests | Port and fix. This stays the **only** tween/animation engine. |
| Short-tag layer | **new**, small: `StageActors` | Turns the short tags into director calls, knows actors, anchors, and markers, and is used by `#focus=` for both actor IDs and `left`/`right`. |
| 2D stage | demo `Balloon/Stage`, `SpriteLeft`/`SpriteRight` | Keep both nodes as the built-in actors `left` and `right`; add anchors and extra actors. |
| History / save / rollback / route map | demo's existing code plus Klima's motion replay hook | Extended, not replaced: one ordered list of stage commands per line. |
| Character definition | **new** small resource | Sprite keys or a scene, `default_appearance`, height, feet anchor, animation player. |
| 3D stage | **new**, owned by the balloon | Your 3D scene rendered behind the dialogue UI; `Marks` holds its places. |
| Video | **new**, small | `VideoStreamPlayer` as a background or on a character quad. |

Not ported: Klima's `ShowDirector`, trials, Aurora code and art, and its whole balloon.

## Part 3 - Order of work

| PR | What | Done when |
|---|---|---|
| 0 | Freeze syntax (Part 1), stage switching, and appendix contracts: coordinate parsing, history membership, explicit placement, conflicting targets, and default appearance | Authoring direction approved; parsing/contract test cases specified before implementation |
| 1 | Baseline: run the current tests; pin current behaviour | Known failures listed |
| 2 | Port the director, quad, and tests. Look changes no longer rebuild a character. Marker placement ignores marker scale. | Klima tags work in the demo |
| 3 | Make save, rollback, and route map reliable with motion (Appendix A) | Restore tests pass |
| 4 | 2D: `#show`/`#move`/`#hide`/`#focus`, anchors, character definitions | Old dialogue unchanged; many characters movable |
| 5 | 3D: `#stage`, markers, sample scene | Example staging works without the `#anim` tag |
| 6 | `#anim` | Full example works, including the authored `wave` animation |
| 7 | `#video` | |
| 8 | Docs: tag cheat sheet (Part 1) and Klima migration notes | Every example is parsed in tests |

---

## Part 4 - Appendix for implementers (details; skippable)

### A. Restore rules

1. **One ordered history.** In the new presentation format, each line's `"motion"` list contains accepted presentation commands in story order, including legacy `bg=`, `sprite=`, and `focus=` alongside the new stage tags. Those legacy commands also update `bg/left/right/focus` compatibility fields, but those fields are not independently reapplied after replay. Live play and restore use the same dispatcher with a `restoring` flag. Record each source command once, not its generated operations. Transient `voice=` and `sfx=` playback is not replayed by this presentation history; existing audio/UI handling is retained.
2. **Command records are JSON.** Each record is `{"tag": "move=maya@door", "resolved": {...}}`, where `resolved` holds the computed endpoint (position, yaw) and is JSON-safe: numbers, arrays, IDs, no nodes. Add a presentation-format version to saves. Restore uses `resolved` and does not look up markers again.
3. **Relative moves** (`?by=`) start from the actor's *logical destination*, not its on-screen position mid-tween, so live play, skip, and restore agree.
4. **Direction-only lines** get a history entry with `display_in_backlog: false`. The backlog hides these entries without renumbering indices. Player rollback and roll-forward stop only on displayed entries, but reconstruction includes every entry. Saving on one keeps its exact position.
5. **Line context is preserved.** The implicit-focus rule (a speaker's `#sprite=` brings them forward) runs after all of a line's tags, as it does now.
6. **Old saves:** entries without the new presentation format use their legacy `bg/left/right/focus` snapshot. When continuing an old save, persist that snapshot as the baseline checkpoint for subsequent ordered commands, preserving older entries for rollback. Select the restore path by format/checkpoint, not by whether the `"motion"` list is empty. Test old save → continue → save → load.
7. **Route map:** `_dress()` updates branch-local data only, through the shared parser. It never touches the visible stage. The balloon's existing `_commit_replay()` → `_restore_stage()` materializes the chosen route. If the starting line is already applied, do not apply its commands again (a relative move would otherwise run twice).
8. **Reset:** `reset_all()` stops animation playback and drops aliases registered by abandoned history, while keeping authored aliases. Instant set or placement cancels a tween on the same or an overlapping property (`position` vs `position:x`). Delayed hide and cleanup callbacks check a generation counter.
9. **`stage_restored`** signal fires after story state and stage are both restored. Game code listens to it; the balloon never calls game-specific controllers.
10. Restoration gives **end poses**, not the exact point mid-animation.

### B. Actors and layout

- An appearance-only `#show` keeps the same node, position, and running movement. `#show=maya:smile@left` always snaps to the resolved anchor, even if Maya is already there, and cancels conflicting movement. `#move=maya@left` still tweens rather than snapping; it retargets any conflicting movement.
- `#show=maya` without a look preserves a live actor's appearance and placement. A newly created actor uses `ActorDefinition.default_appearance` (a validated registered sprite key or scene appearance); missing/invalid defaults warn and reject rather than creating a blank actor. Once `#hide` has completed removal, a later `#show` creates a new actor using defaults unless appearance/placement is explicit.
- `#focus=` resolves both reserved legacy slot names and dynamic actor IDs through `StageActors.resolve(id)`, then applies shared focus behavior.
- Keep three responsibilities separate: the actor root owns position and movement; the visual child owns feet pivot, size, and the user's scale and Y-offset settings; the body owns expression and local animation. Reuse the math from `_apply_sprite_transform()`, but don't call it unchanged per actor, because it re-lays out both legacy slots.
- On resize, anchored actors are re-placed; actors at coordinates stay where they are.
- `left`/`right` are reserved IDs. Animation-track aliases are separate from actor aliases.
- `AnimationTree` in `#nla`/`#anim` supports state travel only. Reject or document other options.

### C. 3D

- The 3D stage is a `SubViewport` under the balloon's stage. `#stage=` switches it and never replaces the game's current scene.
- Markers come from `Marks/` by name. Duplicate or missing names produce a warning, and the command is ignored and not recorded.
- Placement copies position and facing, not scale; height sets size. The quad's yaw is a billboard offset. `copy_transform_from()` currently copies scale, so add a variant that doesn't.

### D. Video (first version)

- Formats and platforms: Ogg Theora through `VideoStreamPlayer`. On a 3D quad, use `get_video_texture()` directly; a viewport is only needed for compositing.
- There is no `wait` option yet, so video never blocks dialogue.
- On restore, **all non-looping videos are omitted** (finished or interrupted). Looping videos start once after reconstruction, using their normal audio settings, and nothing plays during reconstruction.
- A missing file produces a warning and is ignored. Players are freed on stop, stage switch, rollback, and teardown.

### E. Tests

- Legacy `#sprite`/`#focus` behave identically.
- Parser tests start with the relevant implementation PR, not only the docs PR: every Part 1 example, vectors followed by options, signed coordinates, and rejection of `@place` plus `?by=`. Many characters at all 2D anchors; entrances and exits via `off_*`.
- Stage change clears actors/playback/focus but retains definitions and legacy nodes; selecting the same stage is a no-op.
- Bare `#show` preserves an existing look; creation uses `default_appearance`; explicit show placement always snaps; re-show after completed hide follows the creation rule.
- A look change keeps the node, position, and tween (2D and 3D).
- An interrupted `?by=` move ends at the logical destination under live play and restore.
- Route travel from an already-applied relative-move line doesn't apply it twice; exploring branches doesn't change the screen.
- Mixed legacy and new commands keep their order after restore.
- Old save → continue → save → load works.
- Direction-only entries persist, don't show blank backlog rows, and don't add rollback stops.
- Missing and duplicate markers; marker scale ignored under transformed parents.
- Video restore rules; missing file.
- **Authoring check:** first-party examples that use the short tags contain no node paths. The check inspects parsed tags. Low-level compatibility fixtures and advanced examples may use paths; the runtime does not forbid them.

### F. Parsing contract (no new author-facing syntax)

- Start with one complete tag supplied by Dialogue Manager. Split the command name at the **first** `=`; split its payload at the first `?`; parse options as `&`-separated items, each split at its first `=`. Spaces do not terminate the tag.
- For show/move targets, `@` ends the actor/appearance portion. Its value runs up to `?` or the end of the payload. A named target is a nonnumeric identifier without spaces or grammar delimiters. Otherwise it must be a whitespace-separated numeric vector: exactly two finite components for 2D, three for 3D.
- `by=` consumes its option value up to the next `&` or end of tag and uses the same numeric-vector rule. Signs and decimals are allowed. Thus `#move=maya@640 700?t=0.8` and `#move=maya?by=-100 0&t=0.8` are unambiguous. Do **not** parse everything after the last `=` as coordinates: it may be a timing option.
- A move must specify exactly one target: `@place`/`@coordinates` **or** `?by=vector`. Reject `#move=maya@center?by=50 0`, missing targets, wrong dimensions, and duplicate options before modifying the actor.
- For appearance lookup, use an exact full sprite key if registered; otherwise resolve the short look through the actor definition (e.g. `smile` to `maya_smile`). Reject an unknown look.
