## Headless tests for the short staging tags, StageActors, the ordered
## presentation history and its restore rules (edit plan, appendix E).
## Run with: godot --headless res://tests/test_staging.tscn
extends Node

var fails: int = 0
var passes: int = 0
var balloon: VNBalloon
var actors: StageActors

const PART1_EXAMPLES := [
	"show=maya", "show=maya:smile", "show=maya@left", "show=maya:smile@left",
	"move=maya@center", "move=maya@center?t=0.8", "move=maya?by=100 0", "move=maya?by=0.5 0 0",
	"move=maya@640 700", "hide=maya", "hide=maya@off_left", "focus=maya", "anim=maya:wave",
	"video=intro", "video=intro:stop", "stage=classroom", "stage=2d",
	# Example scene
	"stage=classroom", "show=maya@door", "move=maya@desk", "anim=maya:wave", "show=maya:sad",
	"show=ken@guest_desk", "focus=ken", "hide=maya@hall",
	# Klima before/after
	"show=maya@maya_spot",
]

const DIALOGUE_2D := """~ two_d
Maya: Hi. [#show=maya@left]
Rook: Yo. [#show=rook@right, #focus=rook]
Maya: Watch. [#show=maya:smile, #move=maya@center?t=0.3]
Maya: Again. [#move=maya?by=100 0&t=3]
Maya: And again. [#move=maya?by=100 0&t=0.1]
[#hide=rook@off_right?t=0.1]
Maya: Alone. [#sprite=rook:right, #bg=rooftop]
Maya: Bad tags are not recorded. [#move=ghost@left, #show=maya:nosuchlook, #move=maya@center?by=1 1]
=> END
"""

const DIALOGUE_3D := """~ three_d
Narrator: The door opens. [#stage=classroom, #show=maya@door]
Maya: Morning! [#move=maya@desk?t=0.2, #anim=maya:wave]
Maya: Oh... you forgot? [#show=maya:sad]
Ken: Sorry! [#show=ken@guest_desk, #focus=ken]
[#hide=maya@hall?t=0.1]
Ken: Where did she go? [#video=intro?loop]
Ken: Back to 2D. [#stage=2d]
=> END
"""


func _ready() -> void:
	var watchdog := get_tree().create_timer(150.0)
	watchdog.timeout.connect(func() -> void:
		printerr("[FAIL] watchdog timeout")
		fails += 1
		finish())
	await get_tree().process_frame
	await run()
	finish()


func finish() -> void:
	print("Staging tests: %d passed, %d failed" % [passes, fails])
	if is_instance_valid(balloon):
		balloon.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(1 if fails > 0 else 0)


func check(cond: bool, what: String) -> void:
	if cond:
		passes += 1
		print("[PASS] %s" % what)
	else:
		fails += 1
		printerr("[FAIL] %s" % what)


func near(a: Variant, b: Variant, eps: float = 0.5) -> bool:
	if a is Vector2 and b is Vector2:
		return (a as Vector2).distance_to(b) <= eps
	if a is Vector3 and b is Vector3:
		return (a as Vector3).distance_to(b) <= eps
	return absf(float(a) - float(b)) <= eps


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func run() -> void:
	_parser_tests()
	_docs_examples_parse()
	await _setup_balloon()
	await _two_d_tests()
	await _many_actors_tests()
	await _three_d_tests()
	await _video_tests()
	await _old_save_tests()
	await _route_tests()
	await _review_regression_tests()
	await _legacy_move_tests()
	await _shipped_route_tests()
	await _silent_2d_tests()


#region Parser


func _parser_tests() -> void:
	for tag: String in PART1_EXAMPLES:
		var p := StageTagParser.parse(tag)
		check(bool(p.ok), "Part 1 example parses: #%s" % tag)
		check(not tag.contains("/"), "first-party example has no node path: #%s" % tag)
	var p := StageTagParser.parse("move=maya@640 700?t=0.8")
	check(p.ok and p.coords == [640.0, 700.0] and p.opts.t == "0.8", "coordinates followed by options")
	p = StageTagParser.parse("move=maya?by=-100 0&t=0.8")
	check(p.ok and p.by == [-100.0, 0.0] and p.opts.t == "0.8", "signed by= vector followed by options")
	p = StageTagParser.parse("move=maya?by=0.5 -0.25 1e1")
	check(p.ok and p.by == [0.5, -0.25, 10.0], "3D by= with decimals and signs")
	p = StageTagParser.parse("show=maya:smile@left")
	check(p.ok and p.actor == "maya" and p.look == "smile" and p.place == "left", "actor:look@place split")
	p = StageTagParser.parse("video=intro:stop")
	check(p.ok and p.stop, "video stop")
	p = StageTagParser.parse("stage=2d")
	check(p.ok and p.name == "2d", "stage=2d")
	for bad: String in [
		"move=maya@center?by=50 0", "move=maya", "move=maya?by=1", "move=maya?by=1 2 3 4",
		"move=maya@1 2 3 4", "move=maya@center?t=1&t=2", "show=maya?by=1 2", "move=maya:smile@left",
		"move=maya@", "show=maya@12abc", "move=maya?t=-1&by=1 1", "move=maya?by=nan 1",
		"anim=maya", "video=intro:play", "focus=a/b", "show=Actors/maya", "move=maya?speed=2&by=1 1",
	]:
		check(not bool(StageTagParser.parse(bad).ok), "rejected: #%s" % bad)
	check(StageTagParser.is_stage_tag("show=maya") and not StageTagParser.is_stage_tag("sprite=maya:left"), "is_stage_tag")
	var cmds := StageTagParser.line_commands(["sprite=maya_smile:left", "voice=m1", "move=maya@left"], "Maya")
	check(cmds == ["sprite=maya_smile:left", "move=maya@left", "focus=left"], "line_commands keeps order, drops transient, appends implicit focus")
	cmds = StageTagParser.line_commands(["sprite=maya_smile:left", "focus=right"], "Maya")
	check(cmds == ["sprite=maya_smile:left", "focus=right"], "explicit focus wins over implicit")


## Every tag in the cheat sheet's code blocks parses (docs PR).
func _docs_examples_parse() -> void:
	var text := FileAccess.get_file_as_string("res://docs/STAGING.md")
	check(text != "", "docs/STAGING.md exists")
	var rx := RegEx.new()
	rx.compile("#((show|move|hide|focus|anim|video|stage)=[^\\s,\\]]+(?: [-0-9.][^\\s,\\]]*)*(?:\\?[^\\s,\\]]+(?: [-0-9.][^\\s,\\]&]*)*)?)")
	# Only fenced code blocks count as examples.
	var blocks := ""
	var parts := text.split("```")
	for i in range(1, parts.size(), 2):
		blocks += parts[i] + "\n"
	var count := 0
	for m: RegExMatch in rx.search_all(blocks):
		var tag := m.get_string(1)
		if tag.contains("<"):
			continue
		count += 1
		var p := StageTagParser.parse(tag)
		check(bool(p.ok), "docs example parses: #%s" % tag)
		check(not tag.contains("/"), "docs short-tag example has no node path: #%s" % tag)
	check(count >= 15, "docs contain the short-tag examples (%d found)" % count)


#endregion


func _setup_balloon() -> void:
	var packed: PackedScene = load("res://scenes/vn_balloon.tscn")
	balloon = packed.instantiate()
	add_child(balloon)
	await frames(2)
	actors = balloon.stage_actors
	# The shipped balloon registers Maya, Rook and Ken with their real sprites;
	# nothing is injected, so the documented Ken example runs as authored.
	check(actors.definitions.has("ken") and actors.sprites.has("ken") and actors.sprites.has("maya_sad"), "shipped balloon registers Ken and the example looks")
	check(actors.definitions.has("maya") and actors.definitions.has("rook"), "character definitions registered from the balloon")
	check(balloon.get_node_or_null("%Anchors") != null and actors.anchor_names().size() == 11, "11 built-in 2D anchors authored in the stage scene")


func _start(text: String, cue: String) -> void:
	var res: Resource = Engine.get_singleton("DialogueManager").create_resource_from_text(text)
	balloon.history.clear()
	balloon.history_cursor = -1
	balloon.start(res, cue)
	await _wait_line()


func _wait_line() -> void:
	for i in 300:
		if is_instance_valid(balloon.dialogue_line) and not balloon.dialogue_label.is_typing:
			return
		if balloon.dialogue_label.is_typing:
			balloon.dialogue_label.skip_typing()
		await get_tree().process_frame


func _advance() -> void:
	var before := str(balloon.dialogue_line.id)
	balloon.next(balloon.dialogue_line.next_id)
	for i in 300:
		if is_instance_valid(balloon.dialogue_line) and str(balloon.dialogue_line.id) != before:
			break
		await get_tree().process_frame
	await _wait_line()


func _actor_pos(id: String) -> Variant:
	var n := actors.resolve(id)
	return null if n == null else n.position


func _anchor(name: String) -> Vector2:
	return actors._anchor_pos(actors._anchor(name))


#region 2D


func _two_d_tests() -> void:
	print("== 2D short tags ==")
	await _start(DIALOGUE_2D, "two_d")
	check(actors.has_actor("maya"), "#show=maya created Maya")
	var maya_root: Node = actors.resolve("maya")
	check(near(_actor_pos("maya"), _anchor("left")), "Maya stands at the left anchor")
	check(actors.actors.maya.body.texture == balloon.sprites["maya"], "creation used default_appearance")
	check(balloon.history.size() == 1 and balloon.history[0].get("pfmt") == 1, "entry is presentation format 1")
	check(balloon.history[0].motion[0].tag == "show=maya@left", "entry records the source command")
	check(JSON.parse_string(JSON.stringify(balloon.history[0].motion)) != null, "records are JSON-safe")

	await _advance()  # Rook + focus
	check(actors.has_actor("rook") and near(_actor_pos("rook"), _anchor("right")), "Rook at the right anchor")
	check(actors.focus_id == "rook", "#focus=rook resolves a dynamic actor")
	check(actors.actors.maya.visual.modulate.a < 0.9 and actors.actors.rook.visual.modulate.a == 1.0, "focus dims everyone else")

	await _advance()  # smile + move center 0.3
	check(actors.resolve("maya") == maya_root, "look change kept the same node")
	check(actors.actors.maya.body.texture == balloon.sprites["maya_smile"], "short look smile -> maya_smile")
	check(balloon.motion.is_tweening(maya_root, "position"), "#move tweens rather than snapping")
	await wait(0.45)
	check(near(_actor_pos("maya"), _anchor("center")), "move reached the center anchor")

	await _advance()  # by 100 over 3 s
	await wait(0.15)
	# Look change mid-move keeps node, position and tween.
	var mid: Vector2 = maya_root.position
	var r := actors.apply(StageTagParser.parse("show=maya:smile"))
	check(r.ok and actors.resolve("maya") == maya_root and balloon.motion.is_tweening(maya_root, "position"), "look change mid-move keeps node and tween")
	check(near(maya_root.position, mid, 20.0), "look change mid-move keeps position")
	await _advance()  # by 100 over 0.1 s, interrupting
	await wait(0.3)
	var expect: Vector2 = _anchor("center") + Vector2(200, 0)
	check(near(_actor_pos("maya"), expect), "interrupted ?by= chain ends at the logical destination (live)")
	check(str(balloon.history[balloon.history_cursor].motion[0].resolved.place.kind) == "pos", "?by= records the resolved endpoint")

	await _advance()  # direction-only hide
	check(not actors.has_actor("rook"), "#hide=rook@off_right removes Rook logically at once")
	var hidden: Dictionary = balloon.history[balloon.history_cursor]
	check(hidden.get("display_in_backlog") == false, "direction-only line gets a hidden history entry")
	await wait(0.3)
	check(actors.actors_2d.get_node_or_null("Actor_rook") == null, "exit walk finished and freed the node")

	await _advance()  # legacy mixed
	check(balloon.sprite_right.texture == balloon.sprites["rook"], "legacy #sprite still works next to actors")
	var alone_index := balloon.history_cursor
	var alone_bg := balloon.background.texture
	await _advance()  # bad tags
	var bad_entry: Dictionary = balloon.history[balloon.history_cursor]
	check((bad_entry.motion as Array).is_empty(), "rejected commands are not recorded")

	# Backlog hides the direction-only row; rollback skips it.
	balloon.open_history()
	var rows := 0
	for c: Node in balloon.history_list.get_children():
		if c != balloon.history_entry_template:
			rows += 1
	check(rows == balloon.history.size() - 1, "backlog hides direction-only rows without renumbering")
	balloon.close_history()
	check(balloon._prev_displayed(alone_index) == alone_index - 2, "rollback stops skip the direction-only entry")

	# Rollback to "And again" (before the hide) restores end poses.
	balloon.rollback_to(alone_index - 2)
	await _wait_line()
	check(actors.has_actor("rook"), "rollback before the hide brings Rook back")
	check(near(_actor_pos("maya"), expect), "restore: interrupted ?by= chain lands on the same endpoint")
	check(actors.resolve("maya") != maya_root, "restore rebuilt the actor from records")
	check(balloon.sprite_right.texture == null, "restore: legacy slot matches the story point")
	check(actors.focus_id == "rook" and actors.actors.maya.visual.modulate.a < 0.9, "restore: focus replayed")
	# Roll forward through the hidden entry lands on the displayed one.
	balloon.roll_forward()
	await _wait_line()
	check(balloon.history_cursor == alone_index, "roll-forward skips the hidden entry")
	check(not actors.has_actor("rook") and balloon.sprite_right.texture == balloon.sprites["rook"] and balloon.background.texture == alone_bg, "mixed legacy + new commands keep their order after restore")

	# Rollback onto the hidden entry itself keeps its exact position.
	balloon.rollback_to(alone_index - 1)
	await _wait_line()
	check(balloon.history_cursor == alone_index - 1 and not actors.has_actor("rook"), "restoring onto a direction-only entry keeps its position")

	# Save / load.
	balloon.rollback_to(alone_index)
	await _wait_line()
	var saved_pos: Vector2 = _actor_pos("maya")
	check(balloon.save_to_slot(7) == OK, "save with presentation history")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(balloon._slot_path(7)))
	check(int(data.get("presentation_format", 0)) == 1, "save carries the presentation-format version")
	actors.reset_all()
	balloon.load_from_slot(7)
	await _wait_line()
	check(actors.has_actor("maya") and near(_actor_pos("maya"), saved_pos), "load restores actor end poses")

	# Bare show preserves a live look; re-show after a completed hide uses defaults.
	actors.apply(StageTagParser.parse("show=maya:smile"))
	actors.apply(StageTagParser.parse("show=maya"))
	check(actors.actors.maya.body.texture == balloon.sprites["maya_smile"], "bare #show keeps the live look")
	actors.apply(StageTagParser.parse("move=maya@far_right?t=2"))
	await frames(2)
	actors.apply(StageTagParser.parse("show=maya@left"))
	check(near(_actor_pos("maya"), _anchor("left")) and not balloon.motion.is_tweening(actors.resolve("maya"), "position"), "explicit show placement snaps and cancels movement")
	actors.apply(StageTagParser.parse("hide=maya"))
	actors.apply(StageTagParser.parse("show=maya"))
	check(actors.actors.maya.body.texture == balloon.sprites["maya"] and near(_actor_pos("maya"), _anchor("center")), "re-show after hide follows the creation rule")
	check(not actors.apply(StageTagParser.parse("show=left:smile")).ok, "left/right are reserved IDs")
	check(not actors.apply(StageTagParser.parse("show=nobody")).ok, "creation without a valid default appearance is rejected")
	check(actors.apply(StageTagParser.parse("anim=maya:wave")).ok, "#anim plays an authored 2D animation")
	check(not actors.apply(StageTagParser.parse("anim=maya:dance")).ok, "unknown animation rejected")
	check(not actors.apply(StageTagParser.parse("move=maya@1 2 3")).ok, "3D coordinates rejected on the 2D stage")
	# Legacy focus still dims the other legacy slot; dynamic actors step back.
	balloon._set_sprite("maya:left")
	balloon._set_sprite("rook:right")
	balloon._set_focus("left")
	check(balloon.sprite_left.modulate.a == 1.0 and balloon.sprite_right.modulate.a < 0.9, "legacy #focus=left unchanged")
	check(actors.actors.maya.visual.modulate.a < 0.9, "legacy focus dims dynamic actors too")
	# Resize: anchored actors follow their anchor.
	var stage: Control = balloon.balloon.get_node("Stage")
	var old_size := stage.size
	actors.apply(StageTagParser.parse("show=rook@right"))
	actors.apply(StageTagParser.parse("move=maya@300 400?t=0"))
	stage.size = Vector2(old_size.x * 0.5, old_size.y)
	await frames(3)
	check(near(_actor_pos("rook"), _anchor("right")), "resize re-places anchored actors")
	check(near(_actor_pos("maya"), Vector2(300, 400)), "resize leaves actors at coordinates alone")
	stage.size = old_size
	await frames(2)


func _many_actors_tests() -> void:
	print("== many actors ==")
	actors.reset_all()
	var names := actors.anchor_names()
	var i := 0
	for n: String in names:
		var id := "extra_%d" % i
		check(actors.apply(StageTagParser.parse("show=%s:rook@%s" % [id, n])).ok, "actor %s at %s" % [id, n])
		check(near(_actor_pos(id), _anchor(n)), "%s placed at %s" % [id, n])
		i += 1
	check(actors.actors.size() == names.size(), "%d actors on stage at once" % names.size())
	check(actors.apply(StageTagParser.parse("show=extra_99:rook@off_left")).ok, "entrance from off_left")
	actors.apply(StageTagParser.parse("move=extra_99@center?t=0.1"))
	await wait(0.25)
	check(near(_actor_pos("extra_99"), _anchor("center")), "walked in to center")
	actors.apply(StageTagParser.parse("hide=extra_99@off_right?t=0.1"))
	await wait(0.25)
	check(not actors.has_actor("extra_99") and actors.actors_2d.get_node_or_null("Actor_extra_99") == null, "exit via off_right")
	actors.reset_all()


#endregion


#region 3D


func _three_d_tests() -> void:
	print("== 3D stage ==")
	await _start(DIALOGUE_3D, "three_d")
	check(actors.current_stage == "classroom" and balloon.get_node("%Stage3D").visible, "#stage=classroom shows the 3D stage")
	var marks: Node3D = actors._stage_root.get_node("Marks")
	var door: Node3D = marks.get_node("door")
	check(actors.has_actor("maya") and actors.resolve("maya") is Node3D, "Maya is a 3D actor")
	check(near(actors.resolve("maya").global_position, door.global_position, 0.01), "Maya placed at the door marker")
	check(actors.actors.maya.body is Sprite3DQuad, "3D body is a billboard quad")
	var rec: Dictionary = balloon.history[0].motion[1].resolved
	check(rec.place.kind == "marker" and (rec.place.pos as Array).size() == 3, "marker endpoint recorded")
	check((rec.place.get("rot", []) as Array).size() == 4 and (rec.place.get("scale", []) as Array).size() == 3, "marker rotation and scale recorded")
	await _advance()  # move to desk + wave
	await wait(0.35)
	check(near(actors.resolve("maya").global_position, marks.get_node("desk").global_position, 0.01), "Maya walked to the desk marker")
	var player: AnimationPlayer = actors.actors.maya.player
	check(player != null and player.current_animation == "wave", "#anim=maya:wave plays the authored 3D animation")
	var quad: Sprite3DQuad = actors.actors.maya.body
	await _advance()  # show sad
	check(actors.actors.maya.body == quad and quad.texture == balloon.sprites["maya_sad"], "3D look change keeps the quad")
	await _advance()  # ken + focus
	check(actors.has_actor("ken") and actors.focus_id == "ken", "Ken at guest_desk with focus")
	check(actors.actors.maya.body.modulate != Color.WHITE, "3D focus dims Maya")
	await _advance()  # hide maya @hall (direction-only)
	check(not actors.has_actor("maya"), "Maya left for the hall")
	check(balloon.history[balloon.history_cursor].display_in_backlog == false, "3D direction-only entry hidden")
	await _advance()  # video loop
	check("intro" in actors.video_names(), "looping video started live")
	# Missing / duplicate markers are ignored and not recorded.
	check(not actors.apply(StageTagParser.parse("move=ken@nowhere")).ok, "missing marker rejected")
	var dup_a := Marker3D.new()
	dup_a.name = "twin"
	marks.add_child(dup_a)
	var holder := Node3D.new()
	holder.name = "Group"
	marks.add_child(holder)
	var dup_b := Marker3D.new()
	dup_b.name = "twin"
	holder.add_child(dup_b)
	check(not actors.apply(StageTagParser.parse("move=ken@twin")).ok, "duplicate marker rejected")
	# Marker placement copies the full transform, also under a transformed parent.
	var scaled := Node3D.new()
	scaled.name = "Scaled"
	scaled.scale = Vector3(3, 3, 3)
	scaled.position = Vector3(1, 0, 0)
	marks.add_child(scaled)
	var sm := Marker3D.new()
	sm.name = "big_spot"
	sm.scale = Vector3(2, 2, 2)
	sm.position = Vector3(0.5, 0, 0)
	sm.rotation_degrees = Vector3(0, 90, 0)
	scaled.add_child(sm)
	check(actors.apply(StageTagParser.parse("show=ken@big_spot")).ok, "show at a marker under a scaled parent")
	var ken_root: Node3D = actors.resolve("ken")
	check(near(ken_root.global_position, sm.global_position, 0.01), "placed at the marker's global position")
	check(ken_root.global_transform.is_equal_approx(sm.global_transform), "full marker transform copied (position, rotation, scale)")
	check(near(ken_root.global_transform.basis.get_scale().y, 6.0, 0.001), "marker x parent scale applied (2 x 3)")
	check(near(actors.actors.ken.body.yaw_offset_deg, 90.0, 0.01), "marker yaw is the billboard facing offset")
	# Restore uses the recorded transform, not the live marker.
	var shown: Dictionary = actors.apply(StageTagParser.parse("show=ken@big_spot"))
	var stored: Dictionary = shown.resolved
	sm.rotation_degrees = Vector3(0, 0, 0)
	sm.scale = Vector3.ONE
	sm.position = Vector3(2, 0, 0)
	actors.apply(StageTagParser.parse("show=ken@big_spot"), true, stored)
	check(near(ken_root.global_transform.basis.get_scale().y, 6.0, 0.001) and near(actors.actors.ken.body.yaw_offset_deg, 90.0, 0.01), "restore re-applies the recorded rotation/scale")
	actors.apply(StageTagParser.parse("move=ken@big_spot?t=0.2"))
	await wait(0.35)
	check(ken_root.global_transform.is_equal_approx(sm.global_transform), "#move to a marker tweens to its full transform")
	check(actors.apply(StageTagParser.parse("move=ken?by=0.5 0 0&t=0")).ok, "3D ?by= move")
	check(not actors.apply(StageTagParser.parse("move=ken@1 2")).ok, "2D coordinates rejected on a 3D stage")
	# Rollback inside the 3D scene: endpoints from records, loop video
	# restarted only after reconstruction.
	var cursor := balloon.history_cursor
	balloon.rollback_to(cursor)
	await _wait_line()
	check(actors.current_stage == "classroom" and actors.has_actor("ken") and not actors.has_actor("maya"), "3D restore rebuilds the scene state")
	check("intro" in actors.video_names(), "looping video starts once after reconstruction")
	check(actors.resolve("ken").global_position.distance_to(marks.get_node("guest_desk").global_position) < 0.01, "restore uses recorded endpoint (guest_desk)")
	# Same stage is a no-op; switching clears.
	var ken_node := actors.resolve("ken")
	check(actors.apply(StageTagParser.parse("stage=classroom")).ok and actors.resolve("ken") == ken_node, "selecting the active stage is a no-op")
	balloon._set_sprite("maya:left")
	await _advance()  # stage=2d
	check(actors.current_stage == "2d" and not balloon.get_node("%Stage3D").visible, "#stage=2d returns to the 2D stage")
	check(actors.actors.is_empty() and actors.video_names().is_empty() and actors.focus_id == "", "stage switch cleared actors, videos and focus")
	check(actors.definitions.has("maya") and actors.definitions.has("ken"), "definitions stay registered")
	check(is_instance_valid(balloon.sprite_left) and balloon.sprite_left.texture == null, "legacy slots cleared, not destroyed")
	check(not actors.apply(StageTagParser.parse("stage=nowhere")).ok, "unknown stage rejected")
	check(not actors.apply(StageTagParser.parse("show=maya@door")).ok, "3D marker names are not 2D places")


#endregion


func _video_tests() -> void:
	print("== video ==")
	actors.reset_all()
	check(not actors.apply(StageTagParser.parse("video=missing_clip")).ok, "missing video warns and is ignored")
	check(actors.apply(StageTagParser.parse("video=intro")).ok and "intro" in actors.video_names(), "#video=intro plays")
	check(actors.apply(StageTagParser.parse("video=intro:stop")).ok and actors.video_names().is_empty(), "#video=intro:stop stops it")
	# Restore: non-looping omitted, looping started after reconstruction only.
	actors.reset_all()
	actors.apply(StageTagParser.parse("video=intro"), true)
	check(actors.video_names().is_empty(), "non-looping video omitted on restore")
	actors.apply(StageTagParser.parse("video=intro?loop"), true)
	check(actors.video_names().is_empty(), "nothing plays during reconstruction")
	actors.finish_restore()
	check(actors.video_names() == ["intro"], "looping video starts once after reconstruction")
	actors.apply(StageTagParser.parse("show=maya@left"))
	check(actors.apply(StageTagParser.parse("video=intro?on=maya&loop")).ok, "video on an actor")
	var tex: Texture2D = actors.actors.maya.body.texture
	check(tex != null and tex != balloon.sprites["maya"], "actor shows the video texture")
	actors.apply(StageTagParser.parse("video=intro:stop"))
	check(actors.actors.maya.body.texture == balloon.sprites["maya"], "stopping restores the actor's look")
	actors.reset_all()
	check(actors.video_layer.get_child_count() == 0 or actors.video_layer.get_children().all(func(c: Node) -> bool: return c.is_queued_for_deletion()), "players freed on reset")


func _old_save_tests() -> void:
	print("== old save -> continue -> save -> load ==")
	var res: Resource = Engine.get_singleton("DialogueManager").create_resource_from_text(DIALOGUE_2D)
	balloon.dialogue_resource = res
	var first: DialogueLine = await res.get_next_dialogue_line("two_d")
	# A pre-presentation-format save: legacy snapshot only.
	balloon.history = [{
		"id": str(first.id), "character": "Maya", "text": "Hi.",
		"bg": "classroom", "left": "maya", "right": "", "focus": "left", "choices": false,
	}]
	balloon.rollback_to(0)
	await _wait_line()
	check(balloon.sprite_left.texture == balloon.sprites["maya"] and balloon.background.texture == balloon.backgrounds["classroom"], "old save restores its legacy snapshot")
	check(not actors.has_actor("maya"), "old save: the line's tags are not re-applied on restore")
	await _advance()  # Rook: new format entry after a legacy one
	check(balloon.history.size() == 2 and not balloon.history[0].has("pfmt") and balloon.history[1].get("pfmt") == 1, "continuing appends new-format entries, old entry kept as checkpoint")
	check(balloon.save_to_slot(8) == OK, "save mixed history")
	actors.reset_all()
	balloon._set_sprite("none:left")
	balloon.load_from_slot(8)
	await _wait_line()
	check(balloon.sprite_left.texture == balloon.sprites["maya"] and balloon.background.texture == balloon.backgrounds["classroom"], "load: legacy checkpoint applied")
	check(actors.has_actor("rook") and actors.focus_id == "rook", "load: new commands replayed on top of the checkpoint")
	balloon.rollback_to(0)
	await _wait_line()
	check(not actors.has_actor("rook") and balloon.sprite_left.texture == balloon.sprites["maya"], "rollback into the old entry still works")


func _route_tests() -> void:
	print("== route map ==")
	var RouteTravel = load("res://scenes/route_graph/route_graph_travel.gd")
	await _start(DIALOGUE_2D, "two_d")
	await _advance()
	await _advance()
	await _advance()  # by 100 over 3 s
	await _advance()  # by 100 over 0.1 s
	await wait(0.3)
	var before: Vector2 = _actor_pos("maya")
	# Exploring a branch dresses branch-local data only.
	var res: Resource = balloon.dialogue_resource
	var line: DialogueLine = await res.get_next_dialogue_line(str(balloon.dialogue_line.id))
	var dressed: Dictionary = RouteTravel._dress({}, line)
	check((dressed.line_motion as Array).size() == 1 and dressed.line_motion[0].tag == "move=maya?by=100 0&t=0.1", "_dress records the line's commands via the shared parser")
	var rec: Dictionary = RouteTravel._record(line, dressed, null)
	check(rec.get("pfmt") == 1 and (rec.motion as Array).size() == 1, "route records carry presentation commands")
	check(near(_actor_pos("maya"), before), "exploring branches does not touch the screen")
	# Travel from the already-applied relative-move line: not applied twice.
	balloon._commit_replay({"lines": [], "line": balloon.dialogue_line}, balloon.history_cursor)
	await _wait_line()
	check(near(_actor_pos("maya"), before), "route travel from an applied ?by= line does not apply it twice")
	var restored_count := [0]
	balloon.stage_restored.connect(func() -> void: restored_count[0] += 1)
	balloon.rollback_to(balloon.history_cursor)
	await _wait_line()
	check(restored_count[0] == 1, "stage_restored fires once per restore")


## Regressions from the remi-q7x review (items 1, 2 and 4).
func _review_regression_tests() -> void:
	print("== review regressions ==")
	var RouteTravel = load("res://scenes/route_graph/route_graph_travel.gd")
	# 1. Real RouteTravel.replay -> commit: records end up resolved and validated.
	await _start(DIALOGUE_2D, "two_d")
	for i in 4:
		await _advance()
	await wait(0.3)
	var live_pos: Variant = _actor_pos("maya")
	var res: Resource = balloon.dialogue_resource
	var walk: DialogueLine = await res.get_next_dialogue_line("two_d")
	var guard := 0
	while walk != null and not walk.text.begins_with("Bad tags") and guard < 20:
		walk = await res.get_next_dialogue_line(str(walk.next_id))
		guard += 1
	check(walk != null and walk.text.begins_with("Bad tags"), "found the route target line")
	var found: Dictionary = await RouteTravel.replay(res, "", {"line_ids": [str(walk.id)]}, [], 0, null, [], true, true, {})
	check(bool(found.get("ok", false)) and (found.lines as Array).size() >= 6, "RouteTravel.replay walks the whole branch")
	balloon._commit_replay(found, -1)
	await _wait_line()
	check(near(_actor_pos("maya"), live_pos), "committed route reproduces the live-play position")
	var unresolved := 0
	var rejected := 0
	var by_records := 0
	for e: Dictionary in balloon.history:
		for r: Dictionary in e.get("motion", []):
			var tag := str(r.tag)
			var resolved: Dictionary = r.get("resolved", {})
			if (tag.begins_with("show=") or tag.begins_with("move=") or tag.begins_with("hide=")) and resolved.is_empty():
				unresolved += 1
			if tag.contains("ghost") or tag.contains("nosuchlook"):
				rejected += 1
			if tag.contains("?by=") and resolved.has("place"):
				by_records += 1
	check(unresolved == 0, "route travel persists resolved endpoints for every staging command")
	check(rejected == 0, "commands that never applied are not persisted")
	check(by_records == 2, "relative moves persist their resolved destination")
	balloon.rollback_to(balloon.history_cursor)
	await _wait_line()
	check(near(_actor_pos("maya"), live_pos), "restoring the committed route again gives the same position")

	# 2. A bare #show restores its recorded placement, not the moved marker.
	actors.reset_all()
	check(actors.apply(StageTagParser.parse("stage=classroom")).ok, "3D stage for the bare-show check")
	var shown: Dictionary = actors.apply(StageTagParser.parse("show=maya"))
	check(shown.ok and shown.resolved.has("place"), "bare #show records where it placed the actor")
	var placed_at: Vector3 = actors.resolve("maya").global_position
	actors.reset_all()
	actors.apply(StageTagParser.parse("stage=classroom"))
	var mark: Node3D = actors._find_marker("center")
	mark.position += Vector3(2, 0, 0)
	actors.apply(StageTagParser.parse("show=maya"), true, shown.resolved)
	check(near(actors.resolve("maya").global_position, placed_at, 0.01), "bare #show restore consumes the stored placement")
	mark.position -= Vector3(2, 0, 0)

	# 4. A pending looping video dies with its actor.
	actors.reset_all()
	actors.apply(StageTagParser.parse("show=maya@left"), true, {})
	actors.apply(StageTagParser.parse("video=intro?on=maya&loop"), true, {})
	actors.finish_restore()
	check(actors._videos.has("intro"), "control: a pending video on a live actor starts after restore")
	actors.reset_all()
	actors.apply(StageTagParser.parse("show=maya@left"), true, {})
	actors.apply(StageTagParser.parse("video=intro?on=maya&loop"), true, {})
	actors.apply(StageTagParser.parse("hide=maya"), true, {})
	actors.apply(StageTagParser.parse("show=maya@right"), true, {})
	actors.finish_restore()
	check(not actors._videos.has("intro"), "a video pending for a removed actor is not attached to its replacement")
	actors.reset_all()


const DIALOGUE_LEGACY := """~ legacy
Maya: Hi. [#sprite=maya:left]
Maya: Slide. [#move=left@center?t=0]
Maya: Smile. [#sprite=maya_smile:left]
Maya: More. [#move=left?by=50 0&t=0]
Maya: Ghost. [#move=right@center]
Maya: Gone. [#sprite=none:left]
Maya: Back. [#sprite=maya:left]
=> END
"""


func _legacy_feet() -> Vector2:
	# Feet in actors_2d space: the slot's pivot (bottom centre) through its transform.
	var g: Vector2 = balloon.sprite_left.get_global_transform() * balloon.sprite_left.pivot_offset
	return actors.actors_2d.get_global_transform().affine_inverse() * g


## #move=left / #move=right on the legacy portrait slots.
func _legacy_move_tests() -> void:
	print("== legacy slot moves ==")
	await _start(DIALOGUE_LEGACY, "legacy")
	var home: Vector2 = _legacy_feet()
	await _advance()  # move=left@center
	check(near(_legacy_feet(), _anchor("center"), 1.0), "#move=left@center puts the slot's feet on the anchor")
	check(not near(_legacy_feet(), home, 1.0), "the slot moved away from its authored place")
	await _advance()  # expression change
	check(near(_legacy_feet(), _anchor("center"), 1.0), "an expression change keeps the moved position")
	await _advance()  # ?by=
	check(near(_legacy_feet(), _anchor("center") + Vector2(50, 0), 1.0), "#move=left?by= offsets from the logical feet position")
	var moved_rec := {}
	for e: Dictionary in balloon.history:
		for r: Dictionary in e.get("motion", []):
			if str(r.tag).begins_with("move=left@center") and not (r.get("resolved", {}) as Dictionary).is_empty():
				moved_rec = r.resolved
	check(not moved_rec.is_empty(), "the legacy move is recorded with a resolved place")
	balloon.rollback_to(balloon.history_cursor)
	await _wait_line()
	check(near(_legacy_feet(), _anchor("center") + Vector2(50, 0), 1.0), "restore reproduces the moved slot")
	balloon.rollback_to(1)
	await _wait_line()
	check(near(_legacy_feet(), _anchor("center"), 1.0), "rolling back to an earlier line restores the earlier position")
	balloon.rollback_to(0)
	await _wait_line()
	check(near(_legacy_feet(), home, 1.0), "rolling back before the move restores the home position")
	for i in 4:
		await _advance()
	await _wait_line()
	check(near(_legacy_feet(), _anchor("center") + Vector2(50, 0), 1.0), "control: the story is back at the moved position")
	check(not actors.apply(StageTagParser.parse("move=right@center")).ok, "moving an empty slot is rejected")
	await _advance()  # line 6: #sprite=none:left
	check(balloon.sprite_left.texture == null and near(_legacy_feet(), home, 1.0), "#sprite=none recentres the slot")
	await _advance()  # line 7: the portrait comes back
	check(balloon.sprite_left.texture != null and near(_legacy_feet(), home, 1.0), "the next portrait starts at home")
	# A layout pass keeps the displacement.
	actors.apply(StageTagParser.parse("move=left@far_right?t=0"))
	var far: Vector2 = _legacy_feet()
	balloon.sprite_scale = 1.0
	balloon._apply_sprite_transform()
	check(near(_legacy_feet(), far, 1.0), "a relayout keeps a moved slot where it was put")


## The route from the shipped demo to the 3D scene: the last rooftop choice
## leads to ~ classroom_3d, which exercises #stage / #show / #move / #anim /
## #hide with the shipped characters, and rolls back/forward cleanly.
func _shipped_route_tests() -> void:
	print("== shipped demo -> 3D classroom ==")
	var CompilerScript = load("res://scenes/route_graph/route_graph_compiler.gd")
	var intro: Resource = load("res://dialogue/intro.dialogue")
	check("classroom_3d" in intro.get_cues(), "intro has a classroom_3d cue")
	var graph: Dictionary = CompilerScript.compile(intro)
	var reachable := false
	var has_node := false
	for node: Dictionary in graph.get("nodes", []):
		if str(node.id) == "classroom_3d":
			has_node = true
		for outp: Dictionary in node.get("outputs", []):
			if str(outp.get("target", "")) == "classroom_3d" and str(node.id) != "classroom_3d":
				reachable = true
	check(has_node and reachable, "the route map has an edge from the demo into classroom_3d")

	actors.reset_all()
	balloon.history.clear()
	balloon.history_cursor = -1
	balloon.start(intro, "classroom_3d")
	await _wait_line()
	check(actors.current_stage == "classroom" and actors.has_actor("maya"), "classroom_3d switches to the 3D stage and shows Maya at the door")
	var door: Node3D = actors._find_marker("door")
	check(door != null and near(actors.resolve("maya").global_position, door.global_position, 0.05), "Maya starts at the door marker")
	await _advance()  # walk to the desk + wave
	await wait(1.2)
	var desk: Node3D = actors._find_marker("desk")
	check(near(actors.resolve("maya").global_position, desk.global_position, 0.05), "Maya walked to the desk")
	check(actors.actors.maya.player != null, "the shipped Maya carries an animation player for #anim=wave")
	await _advance()  # rook + focus
	check(actors.has_actor("rook") and actors.focus_id == "rook", "Rook stands at the guest desk with focus")
	# Silent third character (shadow, SVG) stands at the window from the
	# opening line and stays through the whole cue.
	check(actors.has_actor("shadow"), "silent shadow bystander appears in the 3D cue")
	var window_mark: Node3D = actors._find_marker("window")
	check(window_mark != null and near(actors.resolve("shadow").global_position, window_mark.global_position, 0.05), "shadow stands at the window marker")
	var with_rook: int = balloon.history_cursor
	await _advance()  # maya whispers "someone by the window"
	await _advance()  # rook: "A memory. Ignore them."
	await _advance()  # maya smile
	await _advance()  # rook smile
	await _advance()  # all three exit
	await wait(0.9)
	check(not actors.has_actor("maya") and not actors.has_actor("rook") and not actors.has_actor("shadow"), "all three (incl. silent shadow) walked off and were removed")
	await _advance()  # back to 2D
	check(actors.current_stage == "2d" and not actors.has_actor("maya"), "the epilogue returns to the 2D stage")
	balloon.rollback_to(with_rook)
	await _wait_line()
	check(actors.current_stage == "classroom" and actors.has_actor("maya") and actors.has_actor("rook"), "rolling back into the epilogue rebuilds the 3D scene")
	check(near(actors.resolve("maya").global_position, desk.global_position, 0.05), "restore puts Maya at the desk (end pose)")
	balloon.rollback_to(0)
	await _wait_line()
	check(actors.current_stage == "classroom" and actors.has_actor("maya") and not actors.has_actor("rook"), "rolling back to the first line restores the door scene")
	actors.reset_all()


func _visible_sprites() -> int:
	# Every portrait drawn on the 2D stage: the two legacy slots plus dynamic actors.
	var n := 0
	for slot: TextureRect in [balloon.sprite_left, balloon.sprite_right]:
		if slot.texture != null and slot.modulate.a > 0.01:
			n += 1
	for id: String in actors.actors:
		var a: Dictionary = actors.actors[id]
		if a.mode == "2d" and a.visual.visible and (a.body as TextureRect).texture != null:
			n += 1
	return n


## The shipped 2D intro shows a silent third character (the shadow) next to the
## two legacy slots, and the system is not limited to two sprites.
func _silent_2d_tests() -> void:
	print("== silent third character on the 2D stage ==")
	var intro: Resource = load("res://dialogue/intro.dialogue")
	actors.reset_all()
	balloon.history.clear()
	balloon.history_cursor = -1
	balloon.start(intro, "start")
	await _wait_line()
	check(actors.current_stage == "2d" and actors.has_actor("shadow"), "the shipped 2D classroom shows the silent shadow")
	check(near(_actor_pos("shadow"), _anchor("far_right"), 1.0), "the shadow stands at the far_right anchor")
	check(actors.actors.shadow.body.texture == balloon.sprites["shadow"], "the shadow uses its own sprite")
	check(balloon.sprite_left.texture == null and balloon.sprite_right.texture == null, "no legacy portrait yet, but the shadow is already up")
	check(_visible_sprites() == 1, "one sprite on stage from the first line")
	await _advance()  # Rook (right slot)
	await _advance()  # Maya (left slot)
	check(balloon.sprite_left.texture != null and balloon.sprite_right.texture != null and actors.has_actor("shadow"), "both legacy slots and the shadow are on stage")
	check(_visible_sprites() == 3, "three sprites at once on the 2D stage")
	var shadow_rect: Rect2 = Rect2(actors.actors.shadow.visual.get_global_rect())
	var rook_rect: Rect2 = balloon.sprite_right.get_global_rect()
	check(shadow_rect.position.x >= 0.0 and shadow_rect.end.x <= balloon.balloon.get_global_rect().end.x + 1.0, "the shadow is fully on screen")
	check(actors.actors.shadow.visual.modulate.a < 1.0 and actors.focus_id != "shadow", "a silent bystander steps back while others speak")
	var bystander: int = balloon.history_cursor
	# Any number of sprites: four more dynamic actors on top of the three.
	for tag: String in ["show=ken@far_left", "show=rook:smile@left", "show=maya:sad@center", "show=ken:sad@right"]:
		actors.apply(StageTagParser.parse(tag))
	check(actors.actors.size() >= 5 and _visible_sprites() >= 6, "the stage keeps six or more sprites at once (%d)" % _visible_sprites())
	balloon.rollback_to(0)
	await _wait_line()
	check(actors.has_actor("shadow") and actors.actors.size() == 1 and _visible_sprites() == 1, "rollback to the first line leaves only the shadow")
	check(near(_actor_pos("shadow"), _anchor("far_right"), 1.0), "rollback restores the shadow's place")
	balloon.rollback_to(bystander)
	await _wait_line()
	check(_visible_sprites() == 3, "rolling forward again shows all three")

	# Route travel to the rooftop keeps the silent bystander (records get resolved).
	var RouteTravel = load("res://scenes/route_graph/route_graph_travel.gd")
	actors.reset_all()
	balloon.history.clear()
	balloon.history_cursor = -1
	balloon.start(intro, "start")
	await _wait_line()
	var found: Dictionary = await RouteTravel.replay(intro, "", {"jump_key": "rooftop", "line_ids": []}, [], 0, null, [], true, true, {})
	check(bool(found.get("ok", false)), "route walk reaches the rooftop")
	balloon._commit_replay(found, -1)
	await _wait_line()
	check(actors.has_actor("shadow") and near(_actor_pos("shadow"), _anchor("far_right"), 1.0), "route travel to the rooftop still shows the shadow at its place")
	var recorded := false
	for e: Dictionary in balloon.history:
		for r: Dictionary in e.get("motion", []):
			if str(r.tag).begins_with("show=shadow") and not (r.get("resolved", {}) as Dictionary).is_empty():
				recorded = true
	check(recorded, "the shadow's show command is stored with a resolved place")
	actors.reset_all()
