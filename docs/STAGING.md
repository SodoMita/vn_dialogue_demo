# Staging cheat sheet — short tags

Short, predictable tags for moving characters, switching to a 3D stage,
playing animations and videos. One tag does one thing. No node paths; timing
values only when you want to change the defaults.

## Rules

- `actor` = a character's ID, e.g. `maya`.
- `@place` = where: a 2D anchor name, a 3D scene marker name, or coordinates.
- `:look` = the appearance, e.g. `smile` → sprite key `maya_smile`. A full sprite key also works.
- `?options` are optional overrides, e.g. `?t=0.8`. Join several with `&`.
- Separate tags with commas, as always. No commas inside a tag; numbers inside
  a tag are separated by spaces.

## The tags

```text
#show=maya                 show Maya; keeps her look/place if she is already on stage
#show=maya:smile           change look only - she stays where she is
#show=maya@left            show or put her at the "left" anchor (snaps)
#show=maya:smile@left      both at once
#move=maya@center          walk/slide to "center" (default time and easing)
#move=maya@center?t=0.8    slower
#move=maya?by=100 0        move by an offset (2D px)
#move=maya?by=0.5 0 0      move by an offset (3D units)
#move=maya@640 700         move to exact coordinates (2D: x y, 3D: x y z)
#move=left@center          the legacy portrait slots move too (2D; feet go to the place)
#hide=maya                 remove
#hide=maya@off_left        walk off to the left, then remove
#focus=maya                spotlight the speaker (#focus=left / #focus=right still work)
#anim=maya:wave            play an animation authored on the character
#video=intro               play a video; #video=intro:stop stops it
#stage=classroom           switch to a 3D stage scene; #stage=2d goes back
```

Options: `t=` seconds (move/hide/show), `trans=` and `ease=` for move/hide
(`linear sine quad cubic quart quint expo circ elastic back bounce` /
`in out in_out`), `loop` for anim/video, `on=actor` and `volume=0..1` for
video. A move names exactly one target: `@place`, `@x y` **or** `?by=x y`.

## Example scene

```text
Narrator: The door opens. [#stage=classroom, #show=maya@door]
Maya: Morning! [#move=maya@desk, #anim=maya:wave]
Maya: Oh... you forgot? [#show=maya:sad]
Ken: Sorry! [#show=ken@guest_desk, #focus=ken]
[#hide=maya@hall]
```

`door`, `desk`, `guest_desk` and `hall` are `Marker3D` nodes under the
`Marks` node of `scenes/stages/classroom.tscn`.

## 2D places (built in)

`far_left  left  center  right  far_right`, plus `off_left  off_right` for
entrances and exits, and `top_left  top  top_right  true_center`.

They are the children of `Balloon/Stage/Anchors` in `scenes/vn_balloon.tscn`
(anchored Controls — move them in the editor to retune). They are
destinations, not slots: any number of characters can use them. On resize,
anchored characters follow their anchor; characters at coordinates stay.

## 3D places (per scene)

A stage scene is a `Node3D` with a `Camera3D`, a `Marks` node and optionally
an `Actors` node (where characters are added; defaults to the scene root).
Every `Marker3D` under `Marks` is a place, by name. Placement copies the
marker's **full transform** — position, rotation and scale (relative to the
`Actors` node, so transformed parents count too). A scaled marker makes the
character bigger or smaller on top of its `height_3d`; the marker's yaw also
becomes the billboard's facing offset. `#move=` to a marker tweens all three.
Moves by `?by=` or coordinates keep the current rotation and scale. Missing or duplicate names warn and the tag is ignored (and not
recorded).

Register stages in the balloon's `stage_scenes`, or drop them at
`res://scenes/stages/<name>.tscn`.

## Characters

Define each character once as an `ActorDefinition` resource
(`characters/maya.tres`) and list it in the balloon's `actor_definitions`:

| Field | Meaning |
|---|---|
| `id` | tag ID (`maya`); `left`/`right` are reserved |
| `sprite_prefix` | short looks resolve to `<prefix>_<look>` (default: id) |
| `default_appearance` | look used when `#show` creates the actor without one |
| `default_place` | place used when `#show` creates the actor without `@` |
| `height_2d` / `height_3d` | fraction of stage height / world units |
| `feet_anchor` | feet pivot from the top (1 = bottom edge) |
| `animations_2d` / `animations_3d` | `AnimationLibrary` for `#anim` (tracks relative to the body, `.` = body) |
| `scene` + `animation_player` | optional scene body and its AnimationPlayer/AnimationTree |

`#anim` on an `AnimationTree` supports state travel only (no `?loop`).

### Scene-backed characters (`scene`)

When a definition has a `scene`, that scene is the body (a `Node3D` on 3D stages, a
`Control` on 2D) and owns its own graphics, so no sprite keys are needed. Looks
are delivered to the body by calling its `set_look(key: String)`:

- `#show=bot:happy@spot` calls `set_look("bot_happy")` **on creation**, and every
  later `#show=bot:sad` calls `set_look("bot_sad")` on the same node (a look change
  never rebuilds the character). The key is the prefixed form (`<sprite_prefix>_<look>`),
  or a full key exactly as written.
- Any short look is accepted for a scene body (the body decides what it means); a
  body without `set_look` simply ignores looks. A bare `#show=bot` creates the body
  without inventing a look.
- Restore rebuilds the body and delivers the recorded looks in order, so the body
  ends on the same look as live play.
- `tests/test_staging.gd::_scene_backed_look_tests` covers both stages, including
  restore. (Before that test existed, the creation look was silently dropped.)

## Stage switching

`#stage=` clears the previous stage's visible actors, movement, local
animations, videos and focus. Definitions stay registered. Characters are not
transferred between 2D and 3D — show them again. The legacy `left`/`right`
portraits are cleared, not destroyed. Selecting the active stage is a no-op.

### Not limited to two sprites (2D)

`SpriteLeft` / `SpriteRight` are only the two built-in actors `left` and `right`.
Any other character is a dynamic actor drawn in the `Actors` layer above them, so
the 2D stage shows any number of sprites at once. The shipped intro demonstrates it:
from its first classroom line a silent third character (`shadow`, the tiny
`assets/characters/shadow.svg` silhouette) stands at `far_right` next to Maya
(left slot) and Rook (right slot), and it follows them to the rooftop (see the
`Wind over the chain-link fence` scene) until the finale hides it. The tests
(`_silent_2d_tests`) also put ten dynamic actors and both legacy slots on stage at
once. An actor needs no `ActorDefinition` when the tag names a sprite key:
`#show=extra3:maya_smile@top_left` creates actor `extra3`.

### Moving `left` / `right`

`#move=left@center`, `#move=right?by=-80 0` and `#move=left@640 700` move the two
legacy portrait slots exactly like a dynamic actor: the slot's feet (bottom centre)
go to the place, `?by=` starts from its logical position, and the resolved place
is recorded for save/rollback/route travel. A moved slot keeps its position when
its expression changes (`#sprite=maya_smile:left`) or the layout re-runs; only
`#sprite=none:left` (or a stage switch) sends it home. A slot without a portrait
rejects the move. `#show=` / `#hide=` still refuse the reserved IDs.

## Video

Ogg Theora (`.ogv`) through `VideoStreamPlayer`; files come from the
balloon's `videos` or `res://assets/video/<name>.ogv`. `#video=intro` plays
over the stage background; `#video=intro?on=maya` plays on a character.
Video never blocks dialogue. On rollback/load, non-looping videos are
omitted; looping videos start once after the stage is rebuilt. Video sound plays
on the SFX bus, so the SFX and Master sliders govern it.

## History, rollback, saves

Every accepted presentation command (`#bg`, `#sprite`, `#focus`, the short
tags and Klima's motion tags) is recorded once, in story order, in the line's
history entry as `{"tag": ..., "resolved": {...}}` (JSON-safe endpoints).
Restore replays that one list through the same dispatcher, instantly: you get
end poses, and relative moves (`?by=`) start from the logical destination, so
live play, skip and restore agree. Direction-only lines (tags, no text) get a
hidden history entry: no blank backlog row, no rollback stop. Saves carry
`presentation_format: 1`; older saves restore from their
`bg/left/right/focus` snapshot and keep working when continued. The balloon
emits `stage_restored` after story state and stage are both restored.

## Klima migration

Klima's detailed motion tags stay available for fine control (docs in
`scenes/motion/stage_director.gd`): `#tween=` `#set=` `#shake=` `#nla=`
`#sprite3d=` `#place3d=` `#target=`. Everyday staging uses the short tags:

```text
Before: #sprite3d=maya:maya?path=World/Actors&height=1.8, #place3d=maya:copy=World/Marks/Maya
After:  #show=maya@maya_spot

Before: #tween=maya:x=0.5:0.6:sine:in_out?relative
After:  #move=maya?by=0.5 0 0
```

Notes:

- Height, feet anchor and animation player come from the `ActorDefinition`;
  the stage decides which node characters are added to; default move time and
  easing are balloon settings (`move_time`, `move_trans`, `move_ease`).
- Short-tag actors are registered as director aliases under their ID, so
  `#tween=maya:...` reaches a character created by `#show=maya`.
- `#place3d=copy=` copies the source's full global transform (position,
  rotation, scale); its yaw is also the billboard facing offset.
- `#sprite3d=newkey:alias` on an existing quad now swaps the texture and keeps
  the node, placement and running tweens.
- Relative `#tween=`/`#set=` start from the logical destination of a running
  tween; a `#set=` on `position:x` cancels a running `position` tween (and
  vice versa) after snapping it to its end.
- `reset_all()` (rollback) stops story animation playback and drops aliases
  registered by story tags; authored aliases (`bg left right box stage`) stay.
- An infinite `#tween=...?loops=0` restores at its rest value and then runs again
  once the stage is rebuilt (the exact phase is not reproduced; a later `#set=`,
  `#tween=` or `#tween_stop=` on that property cancels it). Finite `loops=N` /
  `yoyo` tweens restore at their end value.
- Not ported: Klima's `ShowDirector`, trials, Aurora code/art and its balloon.
