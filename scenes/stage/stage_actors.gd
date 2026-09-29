class_name StageActors extends Node
## Short-tag layer: turns #show / #move / #hide / #focus / #anim / #video /
## #stage into StageDirector calls. Knows the actors, the 2D anchors and the
## 3D scene markers; owns no tween code of its own (the director is the only
## motion engine).
##
## Every accepted command returns a JSON-safe "resolved" record (the
## computed endpoint), which the balloon stores in history. Restore passes
## it back with restoring = true: endpoints come from the record (markers are
## not looked up again), nothing animates, and looping videos wait for
## [method finish_restore].
##
## Node layout per actor (responsibilities kept separate):
##   root   - position and movement (tweened by the director)
##   visual - feet pivot, size, user sprite scale / Y offset, focus dim
##   body   - expression (texture) and local animation

## Emitted after a stage switch cleared the previous stage.
signal stage_cleared(new_stage: String)

const RESERVED := ["left", "right"]
const DIM_2D := 0.45
const DIM_3D := Color(0.55, 0.55, 0.6, 1.0)

var director: StageDirector
## Sprite key -> Texture2D (the balloon's `sprites`).
var sprites: Dictionary = {}
## Actor ID -> ActorDefinition.
var definitions: Dictionary = {}
## Stage name -> PackedScene; unknown names try res://scenes/stages/<name>.tscn.
var stage_scenes: Dictionary = {}
## Video name -> VideoStream; unknown names try res://assets/video/<name>.ogv.
var videos: Dictionary = {}
## Legacy portrait slots, reserved IDs "left"/"right".
var legacy: Dictionary = {}

var stage_2d: Control
var actors_2d: Control
var anchors_2d: Control
var video_layer: Control
var viewport_container: SubViewportContainer
var viewport: SubViewport

## Stage defaults (the balloon may override them).
var move_time: float = 0.45
var move_trans: String = "sine"
var move_ease: String = "in_out"
var sprite_scale: float = 1.0
var sprite_y: float = 0.0

var current_stage: String = "2d"
var focus_id: String = ""
## Actor ID -> actor record (see [method _new_actor]).
var actors: Dictionary = {}
## Actors walking off after #hide=id@place; freed when the walk ends.
var _ghosts: Array = []
## Video name -> {player, loop, on}
var _videos: Dictionary = {}
## Looping videos requested during reconstruction; started by finish_restore.
var _pending_videos: Array = []

## Cache of PackedScene roots instantiated ONLY for marker probing when
## the branch travels to a stage we haven't loaded. Never added to the
## SceneTree; freed by _drop_probe_stages on reset.
var _probe_stage_cache: Dictionary = {}
var _stage_root: Node3D = null
var _stage_cache: Dictionary = {}


func setup(p_director: StageDirector, p_stage: Control, p_actors: Control, p_anchors: Control, p_video: Control, p_container: SubViewportContainer, p_viewport: SubViewport) -> void:
	director = p_director
	stage_2d = p_stage
	actors_2d = p_actors
	anchors_2d = p_anchors
	video_layer = p_video
	viewport_container = p_container
	viewport = p_viewport
	if stage_2d != null and not stage_2d.resized.is_connected(_on_stage_resized):
		stage_2d.resized.connect(_on_stage_resized)


func add_definition(def: ActorDefinition) -> void:
	if def == null or def.id == "":
		return
	if RESERVED.has(def.id):
		push_warning("StageActors: '%s' is reserved for the legacy slot" % def.id)
		return
	definitions[def.id] = def


func is_3d() -> bool:
	return current_stage != "2d"


## The node an ID names: a legacy slot or a live actor's root.
func resolve(id: String) -> Node:
	if legacy.has(id):
		return legacy[id]
	if actors.has(id):
		return actors[id].root
	return null


func has_actor(id: String) -> bool:
	return actors.has(id)


func _reject(tag: String, reason: String) -> Dictionary:
	push_warning("StageActors: %s (%s)" % [reason, tag])
	return {"ok": false, "error": reason}


func _accept(resolved: Dictionary = {}) -> Dictionary:
	return {"ok": true, "resolved": resolved}


## Apply one parsed short tag (see StageTagParser.parse). [param resolved]
## is the stored record when restoring. Returns {ok, resolved|error}.
## `focus` for legacy slots is left to the caller (balloon).
func apply(p: Dictionary, restoring: bool = false, resolved: Dictionary = {}) -> Dictionary:
	if not bool(p.get("ok", false)):
		return _reject(str(p.get("tag", "")), str(p.get("error", "bad tag")))
	var tag: String = p.tag
	match str(p.cmd):
		"show":
			return _apply_show(p, restoring, resolved)
		"move":
			return _apply_move(p, restoring, resolved)
		"hide":
			return _apply_hide(p, restoring, resolved)
		"focus":
			return apply_focus(str(p.actor)) if actors.has(p.actor) else _reject(tag, "no actor '%s' on stage" % p.actor)
		"anim":
			return _apply_anim(p, restoring)
		"video":
			return _apply_video(p, restoring)
		"stage":
			return _apply_stage(p)
	return _reject(tag, "unknown command")


#region Looks


func _look_key(id: String, look: String) -> String:
	if look == "":
		return ""
	if sprites.has(look):
		return look
	var def: ActorDefinition = definitions.get(id)
	var prefix: String = def.prefix() if def != null else id
	var key := "%s_%s" % [prefix, look]
	if sprites.has(key):
		return key
	# Scene-backed appearance adapter: the scene body owns its own graphics,
	# so any short look is accepted here and delivered by _set_look via the
	# body's set_look(key) method. Prefixed form is preserved so the record
	# survives restore identically for both scene- and texture-backed actors.
	if def != null and def.scene != null:
		return key
	return ""


func _default_key(id: String) -> String:
	var def: ActorDefinition = definitions.get(id)
	if def == null or def.default_appearance == "":
		return ""
	return _look_key(id, def.default_appearance)


#endregion


#region Places


## Resolve a show/move/hide target into {ok, resolved, pos, yaw}. Restoring
## with a stored record uses the record (no marker lookup).
func _target(p: Dictionary, a: Variant, restoring: bool, stored: Variant) -> Dictionary:
	if restoring and stored is Dictionary and not (stored as Dictionary).is_empty():
		return _from_record(stored)
	var three := is_3d()
	if p.coords != null:
		var c: Array = p.coords
		if c.size() != (3 if three else 2):
			return {"ok": false, "error": "coordinates need %d numbers on a %s stage" % [3 if three else 2, "3D" if three else "2D"]}
		return _from_record({"kind": "pos", "pos": c})
	if p.by != null:
		var b: Array = p.by
		if a == null:
			return {"ok": false, "error": "?by= needs an actor on stage"}
		if b.size() != (3 if three else 2):
			return {"ok": false, "error": "?by= needs %d numbers on a %s stage" % [3 if three else 2, "3D" if three else "2D"]}
		# Start from the LOGICAL destination, not the mid-tween position.
		var from: Variant = director.logical_value(a.root, "position")
		if not three and a is Dictionary and a.has("feet_offset"):
			from = (from as Vector2) + (a.feet_offset as Vector2)  # legacy slot: feet, not corner
		var dest: Array = []
		if three:
			var v: Vector3 = from + Vector3(b[0], b[1], b[2])
			dest = [v.x, v.y, v.z]
		else:
			var v2: Vector2 = from + Vector2(b[0], b[1])
			dest = [v2.x, v2.y]
		return _from_record({"kind": "pos", "pos": dest})
	var name: String = p.place
	if three:
		var mark: Node3D = _find_marker(name)
		if mark == null:
			return {"ok": false, "error": "no single marker '%s' under Marks" % name}
		# Markers place with their FULL transform: position, rotation and
		# scale, expressed in the actor parent's space (so a transformed
		# parent is honoured too).
		var parent := _actor_parent_3d()
		var local: Transform3D = mark.global_transform
		if parent != null:
			local = parent.global_transform.affine_inverse() * mark.global_transform
		var q: Quaternion = local.basis.get_rotation_quaternion()
		var sc: Vector3 = local.basis.get_scale()
		var yaw := rad_to_deg(mark.global_transform.basis.get_euler().y)
		return _from_record({"kind": "marker", "name": name,
				"pos": [local.origin.x, local.origin.y, local.origin.z],
				"rot": [q.x, q.y, q.z, q.w], "scale": [sc.x, sc.y, sc.z], "yaw": yaw})
	if _anchor(name) == null:
		return {"ok": false, "error": "no 2D anchor '%s'" % name}
	return _from_record({"kind": "anchor", "name": name})


func _from_record(r: Dictionary) -> Dictionary:
	var kind := str(r.get("kind", "pos"))
	if kind == "anchor":
		var anchor := _anchor(str(r.get("name", "")))
		if anchor == null:
			return {"ok": false, "error": "no 2D anchor '%s'" % r.get("name", "")}
		return {"ok": true, "resolved": r.duplicate(), "pos": _anchor_pos(anchor), "yaw": null}
	var arr: Array = r.get("pos", [])
	var pos: Variant = null
	if arr.size() == 2:
		pos = Vector2(float(arr[0]), float(arr[1]))
	elif arr.size() == 3:
		pos = Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
	else:
		return {"ok": false, "error": "bad stored position"}
	if (pos is Vector3) != is_3d():
		return {"ok": false, "error": "stored position does not match the stage"}
	var rot: Variant = null
	var rarr: Array = r.get("rot", [])
	if rarr.size() == 4:
		rot = Quaternion(float(rarr[0]), float(rarr[1]), float(rarr[2]), float(rarr[3])).normalized()
	var scl: Variant = null
	var sarr: Array = r.get("scale", [])
	if sarr.size() == 3:
		scl = Vector3(float(sarr[0]), float(sarr[1]), float(sarr[2]))
	return {"ok": true, "resolved": r.duplicate(), "pos": pos, "yaw": r.get("yaw"), "rot": rot, "scale": scl}


func _anchor(name: String) -> Control:
	if anchors_2d == null or name == "":
		return null
	return anchors_2d.get_node_or_null(NodePath(name)) as Control


func _anchor_pos(anchor: Control) -> Vector2:
	var rel := actors_2d.get_global_transform().affine_inverse() * anchor.get_global_transform()
	return rel.origin


func anchor_names() -> PackedStringArray:
	var out: PackedStringArray = []
	if anchors_2d != null:
		for c: Node in anchors_2d.get_children():
			out.append(c.name)
	return out


func _find_marker(name: String) -> Node3D:
	if _stage_root == null:
		return null
	var marks := _stage_root.get_node_or_null("Marks")
	if marks == null:
		return null
	var found: Array = marks.find_children(name, "Node3D", true, false)
	if found.size() != 1:
		if found.size() > 1:
			push_warning("StageActors: duplicate marker '%s'" % name)
		return null
	return found[0] as Node3D



## Find a Marker3D by name under a stage scene we have NOT added to the
## tree. Instantiates the scene once (cached in _probe_stage_cache) and
## walks its Marks/. Duplicates or misses return null. Used by the route
## walker so a branch that #stage=other_room can still record marker
## endpoints without ever showing that room.

## Effective global-like transform for a node in a scene that is NOT in
## the tree. Multiplies local transforms from [param root] down to
## [param node], so probed markers still deliver a real world transform.
static func _transform_up_to(node: Node3D, root: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var chain: Array[Node3D] = []
	var cursor: Node = node
	while cursor != null and cursor != root:
		if cursor is Node3D:
			chain.push_front(cursor)
		cursor = cursor.get_parent()
	if cursor == root and root is Node3D:
		t = (root as Node3D).transform
	for n: Node3D in chain:
		t = t * n.transform
	return t


func _find_marker_in_scene(scene_name: String, marker_name: String) -> Node3D:
	if scene_name == "" or scene_name == "2d" or marker_name == "":
		return null
	var root: Node3D = _probe_stage_cache.get(scene_name)
	if not is_instance_valid(root):
		var packed: PackedScene = stage_scenes.get(scene_name)
		if packed == null:
			var path := "res://scenes/stages/%s.tscn" % scene_name
			if ResourceLoader.exists(path):
				packed = load(path)
		if packed == null:
			return null
		root = packed.instantiate() as Node3D
		if root == null:
			return null
		_probe_stage_cache[scene_name] = root
	var marks := root.get_node_or_null("Marks")
	if marks == null:
		return null
	var found: Array = marks.find_children(marker_name, "Node3D", true, false)
	if found.size() != 1:
		return null
	return found[0] as Node3D


func _drop_probe_stages() -> void:
	for key: String in _probe_stage_cache.keys():
		var root = _probe_stage_cache[key]
		if is_instance_valid(root) and root.get_parent() == null:
			root.free()
	_probe_stage_cache.clear()


func _actor_parent_3d() -> Node3D:
	if _stage_root == null:
		return null
	var n := _stage_root.get_node_or_null("Actors") as Node3D
	return n if n != null else _stage_root


#region Branch-local resolver (route walker)


## Compute a JSON-safe record for [param parsed] against the branch shadow
## without touching any actor on stage. Returns {ok, resolved, shadow},
## where [param shadow] carries per-actor logical placement so a `?by=`
## chain in a branch adds to the branch's last endpoint, not the live one.
##
## Shadow shape: {"_stage": String, actor_id: {"place": Dictionary,
## "look": String}}.  Called by RouteTravel._dress() through a Callable
## the balloon supplies. Resolution of 3D markers is only attempted when
## the branch's tracked stage matches the currently-loaded 3D scene; a
## branch that switches to another stage leaves subsequent markers
## unresolved (restore, which loads the stage first, will look them up).
func resolve_record(parsed: Dictionary, shadow: Dictionary) -> Dictionary:
	if not bool(parsed.get("ok", false)):
		return {"ok": false, "resolved": {}, "shadow": shadow}
	var next: Dictionary = shadow.duplicate(true)
	var cmd: String = str(parsed.cmd)
	match cmd:
		"focus", "anim", "video":
			return {"ok": true, "resolved": {}, "shadow": next}
		"stage":
			var sname: String = str(parsed.get("name", "2d"))
			next = {"_stage": sname}
			return {"ok": true, "resolved": {}, "shadow": next}
		"show":
			return _resolve_show_record(parsed, next)
		"move":
			return _resolve_move_record(parsed, next)
		"hide":
			return _resolve_hide_record(parsed, next)
	return {"ok": false, "resolved": {}, "shadow": shadow}


func _branch_is_3d(shadow: Dictionary) -> bool:
	var s: String = str(shadow.get("_stage", current_stage))
	return s != "2d" and s != ""


func _branch_matches_live(shadow: Dictionary) -> bool:
	return str(shadow.get("_stage", current_stage)) == current_stage


## Look-key check without live sprites (sprites dictionary is shared with
## the balloon, so it is safe to read; no scene mutation).
func _record_look(id: String, look: String) -> String:
	return _look_key(id, look)


func _resolve_place_record(parsed: Dictionary, shadow_place: Variant, shadow: Dictionary) -> Dictionary:
	var three: bool = _branch_is_3d(shadow)
	var live_ok: bool = _branch_matches_live(shadow)
	if parsed.coords != null:
		var c: Array = parsed.coords
		if c.size() != (3 if three else 2):
			return {"ok": false, "error": "coordinates need %d numbers on a %s stage" % [3 if three else 2, "3D" if three else "2D"]}
		return {"ok": true, "record": {"kind": "pos", "pos": c.duplicate()}}
	if parsed.by != null:
		var b: Array = parsed.by
		if b.size() != (3 if three else 2):
			return {"ok": false, "error": "?by= needs %d numbers on a %s stage" % [3 if three else 2, "3D" if three else "2D"]}
		var base: Variant = _record_position(shadow_place, three)
		if base == null:
			return {"ok": false, "error": "?by= needs an actor on stage"}
		var dest: Array = []
		if three:
			var v: Vector3 = (base as Vector3) + Vector3(b[0], b[1], b[2])
			dest = [v.x, v.y, v.z]
		else:
			var v2: Vector2 = (base as Vector2) + Vector2(b[0], b[1])
			dest = [v2.x, v2.y]
		return {"ok": true, "record": {"kind": "pos", "pos": dest}}
	var name: String = str(parsed.place)
	if name == "":
		return {"ok": true, "record": {}}
	if three:
		var stage_name: String = str(shadow.get("_stage", current_stage))
		if stage_name == "":
			stage_name = current_stage
		var m: Node3D = null
		var probe_root: Node3D = null
		if live_ok:
			m = _find_marker(name)
		else:
			# Branch travels through another 3D stage: instantiate that scene
			# once (cached) and query its Marks so records still carry the
			# computed endpoint. The instance never enters the tree so it is
			# invisible; it is freed by [method _drop_probe_stages] on reset.
			m = _find_marker_in_scene(stage_name, name)
			probe_root = _probe_stage_cache.get(stage_name)
		if m == null:
			return {"ok": false, "error": "no single marker '%s' under Marks" % name}
		var world_t: Transform3D
		if live_ok:
			world_t = m.global_transform
		else:
			# Probed scene is not in the tree: global_transform would return
			# identity and warn. Multiply local transforms up to the scene root.
			world_t = _transform_up_to(m, probe_root)
		# Express the marker in the actor parent's space, as live play does.
		# The parent is the scene's "Actors" node (or the scene root when it
		# has none) - with its own transform, which is why "relative to the
		# scene root" would place actors somewhere else on a stage whose
		# Actors node is moved, rotated or scaled.
		var local: Transform3D = world_t
		if live_ok:
			var par := _actor_parent_3d()
			if par != null:
				local = par.global_transform.affine_inverse() * world_t
		elif probe_root != null:
			var probe_actors := probe_root.get_node_or_null("Actors") as Node3D
			local = _transform_up_to(probe_actors if probe_actors != null else probe_root, probe_root).affine_inverse() * world_t
		var q: Quaternion = local.basis.get_rotation_quaternion()
		var sc: Vector3 = local.basis.get_scale()
		var yaw := rad_to_deg(world_t.basis.get_euler().y)
		return {"ok": true, "record": {"kind": "marker", "name": name,
				"pos": [local.origin.x, local.origin.y, local.origin.z],
				"rot": [q.x, q.y, q.z, q.w],
				"scale": [sc.x, sc.y, sc.z], "yaw": yaw}}
	if _anchor(name) == null:
		return {"ok": false, "error": "no 2D anchor '%s'" % name}
	return {"ok": true, "record": {"kind": "anchor", "name": name}}


func _record_position(rec: Variant, three: bool) -> Variant:
	if not (rec is Dictionary) or (rec as Dictionary).is_empty():
		return null
	var kind: String = str(rec.get("kind", ""))
	if kind == "anchor":
		var anchor := _anchor(str(rec.get("name", "")))
		if anchor == null:
			return null
		return _anchor_pos(anchor)
	var arr: Array = rec.get("pos", [])
	if three:
		if arr.size() != 3:
			return null
		return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
	if arr.size() != 2:
		return null
	return Vector2(float(arr[0]), float(arr[1]))


func _resolve_show_record(parsed: Dictionary, shadow: Dictionary) -> Dictionary:
	var id: String = parsed.actor
	if RESERVED.has(id):
		return {"ok": false, "resolved": {}, "shadow": shadow}
	var three: bool = _branch_is_3d(shadow)
	var live_ok: bool = _branch_matches_live(shadow)
	var existing: Variant = shadow.get(id)
	var out: Dictionary = {}
	var look_key := ""
	if parsed.look != "":
		look_key = _record_look(id, str(parsed.look))
		if look_key == "":
			# Unknown look for a defined actor: still record the tag so live
			# play (with the same rejection) matches the walker.
			return {"ok": true, "resolved": {}, "shadow": shadow}
		out["look"] = look_key
	var has_place: bool = parsed.place != "" or parsed.coords != null
	if has_place:
		var r: Dictionary = _resolve_place_record(parsed, existing.get("place") if existing is Dictionary else null, shadow)
		if not r.ok:
			return {"ok": false, "resolved": {}, "shadow": shadow}
		if not (r.record as Dictionary).is_empty():
			out["place"] = r.record
	elif existing == null:
		# New actor without @place: use default_place if we can resolve it.
		var def: ActorDefinition = definitions.get(id)
		var def_place := def.default_place if def != null else "center"
		var synth := {"ok": true, "tag": parsed.tag, "actor": id, "look": "",
				"place": def_place, "coords": null, "by": null}
		var r2: Dictionary = _resolve_place_record(synth, null, shadow)
		if r2.ok and not (r2.record as Dictionary).is_empty():
			out["place"] = r2.record
	var rec: Dictionary = (existing as Dictionary).duplicate() if existing is Dictionary else {}
	if out.has("look"):
		rec["look"] = out.look
	if out.has("place"):
		rec["place"] = out.place
	shadow[id] = rec
	return {"ok": true, "resolved": out, "shadow": shadow}


func _resolve_move_record(parsed: Dictionary, shadow: Dictionary) -> Dictionary:
	var id: String = parsed.actor
	var existing: Variant = shadow.get(id)
	if existing == null:
		return {"ok": false, "resolved": {}, "shadow": shadow}
	var three: bool = _branch_is_3d(shadow)
	var live_ok: bool = _branch_matches_live(shadow)
	var r: Dictionary = _resolve_place_record(parsed, existing.get("place"), shadow)
	if not r.ok:
		return {"ok": false, "resolved": {}, "shadow": shadow}
	var out: Dictionary = {}
	if not (r.record as Dictionary).is_empty():
		out["place"] = r.record
		existing["place"] = r.record
		shadow[id] = existing
	return {"ok": true, "resolved": out, "shadow": shadow}


func _resolve_hide_record(parsed: Dictionary, shadow: Dictionary) -> Dictionary:
	var id: String = parsed.actor
	var existing: Variant = shadow.get(id)
	if existing == null:
		return {"ok": false, "resolved": {}, "shadow": shadow}
	var three: bool = _branch_is_3d(shadow)
	var live_ok: bool = _branch_matches_live(shadow)
	var has_place: bool = parsed.place != "" or parsed.coords != null
	var out: Dictionary = {}
	if has_place:
		var r: Dictionary = _resolve_place_record(parsed, existing.get("place"), shadow)
		if not r.ok:
			return {"ok": false, "resolved": {}, "shadow": shadow}
		if not (r.record as Dictionary).is_empty():
			out["place"] = r.record
	shadow.erase(id)
	return {"ok": true, "resolved": out, "shadow": shadow}


#endregion


#endregion


#region Actors


func _new_actor(id: String, key: String) -> Dictionary:
	var def: ActorDefinition = definitions.get(id)
	var a := {"id": id, "def": def, "look": key, "place": {}, "mode": current_stage, "player": null}
	if is_3d():
		var root := Node3D.new()
		root.name = "Actor_%s" % id
		_actor_parent_3d().add_child(root)
		var visual := Node3D.new()
		visual.name = "Visual"
		root.add_child(visual)
		var body: Node3D
		if def != null and def.scene != null:
			body = def.scene.instantiate() as Node3D
		if body == null:
			var quad := Sprite3DQuad.new()
			quad.world_height = def.height_3d if def != null else 1.7
			quad.bottom_anchored = true
			quad.texture = sprites.get(key)
			body = quad
			var feet: float = def.feet_anchor if def != null else 1.0
			visual.position.y = -quad.world_height * (1.0 - feet)
		body.name = "Body"
		visual.add_child(body)
		a.root = root
		a.visual = visual
		a.body = body
	else:
		var root := Control.new()
		root.name = "Actor_%s" % id
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		actors_2d.add_child(root)
		var visual := Control.new()
		visual.name = "Visual"
		visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(visual)
		var body: Control
		if def != null and def.scene != null:
			body = def.scene.instantiate() as Control
		if body == null:
			var rect := TextureRect.new()
			rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			rect.texture = sprites.get(key)
			body = rect
		body.name = "Body"
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		visual.add_child(body)
		a.root = root
		a.visual = visual
		a.body = body
	# A scene body owns its own graphics: deliver the creation look to it, as
	# later looks are (a texture body already got it above).
	if key != "" and def != null and def.scene != null and a.body.has_method("set_look"):
		a.body.set_look(key)
	a.player = _make_player(a)
	actors[id] = a
	director.register_alias(id, a.root)
	if not is_3d():
		_layout_2d(a)
	_apply_dim(a)
	return a


func _make_player(a: Dictionary) -> Node:
	var def: ActorDefinition = a.def
	if def == null:
		return null
	if def.scene != null and not def.animation_player.is_empty():
		return a.body.get_node_or_null(def.animation_player)
	var lib: AnimationLibrary = def.animations_3d if is_3d() else def.animations_2d
	if lib == null:
		return null
	var player := AnimationPlayer.new()
	player.name = "Anim"
	a.root.add_child(player)
	player.root_node = player.get_path_to(a.body)
	player.add_animation_library("", lib)
	return player


## Size and feet pivot of a 2D actor from the stage height, its texture
## aspect and the user's sprite scale / Y offset (same math as the legacy
## slots, but per actor - it never re-lays out the legacy pair).
func _layout_2d(a: Dictionary) -> void:
	if stage_2d == null:
		return
	var def: ActorDefinition = a.def
	var h: float = stage_2d.size.y * (def.height_2d if def != null else 0.95)
	var feet: float = def.feet_anchor if def != null else 1.0
	var aspect := 0.6
	var tex: Texture2D = a.body.get("texture") if a.body is TextureRect else null
	if tex != null and tex.get_height() > 0:
		aspect = float(tex.get_width()) / float(tex.get_height())
	var size := Vector2(h * aspect, h)
	var visual: Control = a.visual
	visual.size = size
	visual.position = Vector2(-size.x * 0.5, -size.y * feet + sprite_y)
	visual.pivot_offset = Vector2(size.x * 0.5, size.y * feet)
	visual.scale = Vector2(sprite_scale, sprite_scale)
	var body: Control = a.body
	body.position = Vector2.ZERO
	body.size = size


func relayout() -> void:
	for id: String in actors:
		var a: Dictionary = actors[id]
		if a.mode == "2d":
			_layout_2d(a)


func _set_look(a: Dictionary, key: String) -> void:
	a.look = key
	# A body that implements set_look() owns its own graphics (scene-backed
	# actors), even when its root happens to be a TextureRect or a quad.
	if a.body.has_method("set_look"):
		a.body.set_look(key)
		return
	var tex: Texture2D = sprites.get(key)
	if a.body is Sprite3DQuad:
		(a.body as Sprite3DQuad).texture = tex
	elif a.body is TextureRect:
		(a.body as TextureRect).texture = tex
		_layout_2d(a)
	elif a.body.has_method("set_look"):
		a.body.set_look(key)


func _place(a: Dictionary, t: Dictionary, duration: float, trans: String, ease_name: String, instant: bool) -> void:
	a.place = t.resolved
	director.tween_to(a.root, "position", t.pos, duration, trans, ease_name, instant)
	# Marker placement also carries rotation and scale (root transform).
	if t.get("rot") != null and a.root is Node3D:
		director.tween_to(a.root, "quaternion", t.rot, duration, trans, ease_name, instant)
	if t.get("scale") != null and a.root is Node3D:
		director.tween_to(a.root, "scale", t.scale, duration, trans, ease_name, instant)
	# The billboard shader ignores node rotation, so the marker's yaw also
	# travels to the quad as its facing offset.
	if t.get("yaw") != null and a.body is Sprite3DQuad:
		director.tween_to(a.body, "yaw_offset_deg", float(t.yaw), duration, trans, ease_name, instant)


func _apply_show(p: Dictionary, restoring: bool, stored: Dictionary) -> Dictionary:
	var id: String = p.actor
	if RESERVED.has(id):
		return _reject(p.tag, "'%s' is a legacy slot - use #sprite=key:%s" % [id, id])
	var a: Variant = actors.get(id)
	var key := ""
	if restoring and stored.has("look"):
		key = str(stored.look)
	elif p.look != "":
		key = _look_key(id, p.look)
		if key == "":
			return _reject(p.tag, "unknown look '%s' for %s" % [p.look, id])
	var has_place: bool = p.place != "" or p.coords != null
	var t: Dictionary = {}
	if has_place:
		t = _target(p, a, restoring, stored.get("place"))
		if not t.ok:
			return _reject(p.tag, str(t.error))
	var out := {}
	if a == null:
		var def: ActorDefinition = definitions.get(id)
		var scene_body := def != null and def.scene != null
		if key == "":
			key = _default_key(id)
		if key == "" and not scene_body:
			return _reject(p.tag, "%s has no valid default_appearance - give a look" % id)
		if not has_place:
			# On restore a bare #show creates the actor at its RECORDED
			# placement (from the saved record); a later #move would otherwise
			# override the destination and drift the actor to a fresh anchor.
			if restoring and stored is Dictionary and (stored as Dictionary).has("place") and stored.place is Dictionary and not (stored.place as Dictionary).is_empty():
				t = _from_record(stored.place)
			else:
				var fallback := {"ok": true, "tag": p.tag, "place": def.default_place if def != null else "center", "coords": null, "by": null}
				if is_3d() and _find_marker(str(fallback.place)) == null:
					t = _from_record({"kind": "pos", "pos": [0.0, 0.0, 0.0]})
				else:
					t = _target(fallback, null, false, null)
			if not t.ok:
				return _reject(p.tag, str(t.error))
		a = _new_actor(id, key)
		_place(a, t, 0.0, "", "", true)
		out.look = key
		out.place = t.resolved
	else:
		if key != "":
			_set_look(a, key)
			out.look = key
		if has_place:
			# Explicit show placement always snaps and cancels movement.
			_place(a, t, 0.0, "", "", true)
			out.place = t.resolved
	return _accept(out)


## A legacy portrait slot as a movable actor: its root is the slot control and
## "feet_offset" is where its feet sit inside it (bottom centre), so places and
## ?by= work on feet exactly like they do for a dynamic actor.
func _legacy_actor(id: String) -> Variant:
	var node := legacy.get(id) as TextureRect
	if node == null or is_3d() or node.texture == null:
		return null
	return {"id": id, "root": node, "feet_offset": Vector2(node.size.x * 0.5, node.size.y)}


func _apply_move(p: Dictionary, restoring: bool, stored: Dictionary) -> Dictionary:
	var a: Variant = actors.get(p.actor)
	if a == null and RESERVED.has(str(p.actor)):
		a = _legacy_actor(str(p.actor))
		if a == null:
			return _reject(p.tag, "legacy slot '%s' has no portrait on the 2D stage - #sprite=key:%s first" % [p.actor, p.actor])
	if a == null:
		return _reject(p.tag, "no actor '%s' on stage" % p.actor)
	var t := _target(p, a, restoring, stored.get("place"))
	if not t.ok:
		return _reject(p.tag, str(t.error))
	var dur: float = float(p.opts.get("t", move_time))
	if a.has("feet_offset"):
		var to: Vector2 = (t.pos as Vector2) - (a.feet_offset as Vector2)
		director.tween_to(a.root, "position", to, dur, str(p.opts.get("trans", move_trans)), str(p.opts.get("ease", move_ease)), restoring)
		return _accept({"place": t.resolved})
	_place(a, t, dur, str(p.opts.get("trans", move_trans)), str(p.opts.get("ease", move_ease)), restoring)
	return _accept({"place": t.resolved})


func _apply_hide(p: Dictionary, restoring: bool, stored: Dictionary) -> Dictionary:
	var id: String = p.actor
	var a: Variant = actors.get(id)
	if a == null:
		return _reject(p.tag, "no actor '%s' on stage" % id)
	var has_place: bool = p.place != "" or p.coords != null
	var out := {}
	if has_place:
		var t := _target(p, a, restoring, stored.get("place"))
		if not t.ok:
			return _reject(p.tag, str(t.error))
		out.place = t.resolved
		if not restoring:
			# Logically gone right away (a later #show creates a new actor,
			# exactly as restore does); the node walks off as a ghost.
			actors.erase(id)
			if focus_id == id:
				focus_id = ""
			var dur: float = float(p.opts.get("t", move_time))
			_place(a, t, dur, str(p.opts.get("trans", move_trans)), str(p.opts.get("ease", move_ease)), false)
			_ghosts.append(a)
			var gen := director.generation
			get_tree().create_timer(maxf(dur, 0.0) + 0.02).timeout.connect(_on_ghost_done.bind(a, gen))
			return _accept(out)
	_remove(id)
	return _accept(out)


func _on_ghost_done(a: Dictionary, gen: int) -> void:
	if gen != director.generation or not _ghosts.has(a):
		return
	_ghosts.erase(a)
	_free_actor(a)


func _remove(id: String) -> void:
	var a: Variant = actors.get(id)
	if a == null:
		return
	actors.erase(id)
	if focus_id == id:
		focus_id = ""
	_free_actor(a)


func _free_actor(a: Dictionary) -> void:
	# Tie pending video reconstruction to actor lifetime: an actor gone from
	# the shadow must not resurrect a looping video on a replacement instance
	# (finish_restore would otherwise reattach after re-#show).
	var aid: String = str(a.id)
	_pending_videos = _pending_videos.filter(func(v: Dictionary) -> bool: return str(v.get("on", "")) != aid)
	for name: String in _videos.keys():
		if str(_videos[name].get("on", "")) == aid:
			_stop_video(name)
	if is_instance_valid(a.root):
		director.kill_node(a.root)
		director.kill_node(a.body)
		if a.root.get_parent() != null:
			a.root.get_parent().remove_child(a.root)
		a.root.queue_free()


#endregion


#region Focus


## Spotlight [param id] (a live actor or a legacy slot name; "" clears).
## Everyone else on stage is dimmed; the focused actor draws in front.
func apply_focus(id: String) -> Dictionary:
	focus_id = id
	for aid: String in actors:
		_apply_dim(actors[aid])
	if actors.has(id):
		var a: Dictionary = actors[id]
		if a.mode == "2d" and a.root.get_parent() != null:
			a.root.get_parent().move_child(a.root, -1)
	return _accept({})


func _apply_dim(a: Dictionary) -> void:
	var lit: bool = focus_id == "" or focus_id == "none" or focus_id == a.id
	if a.visual is Control:
		(a.visual as Control).modulate.a = 1.0 if lit else DIM_2D
	elif a.body is Sprite3DQuad:
		(a.body as Sprite3DQuad).modulate = Color.WHITE if lit else DIM_3D


#endregion


#region Animation


func _apply_anim(p: Dictionary, restoring: bool) -> Dictionary:
	var a: Variant = actors.get(p.actor)
	if a == null:
		return _reject(p.tag, "no actor '%s' on stage" % p.actor)
	var player: Node = a.player
	if player == null:
		return _reject(p.tag, "%s has no animations" % p.actor)
	if player is AnimationTree and p.opts.has("loop"):
		return _reject(p.tag, "AnimationTree supports state travel only (no ?loop)")
	if not director.play_clip(player, str(p.clip), p.opts.has("loop"), restoring):
		return _reject(p.tag, "%s has no animation '%s'" % [p.actor, p.clip])
	return _accept({})


#endregion


#region Video


func _video_stream(name: String) -> VideoStream:
	if videos.has(name):
		return videos[name]
	for ext: String in ["ogv", "tres"]:
		var path := "res://assets/video/%s.%s" % [name, ext]
		if ResourceLoader.exists(path):
			return load(path) as VideoStream
	return null


func _apply_video(p: Dictionary, restoring: bool) -> Dictionary:
	var name: String = p.name
	if bool(p.stop):
		_stop_video(name)
		_pending_videos = _pending_videos.filter(func(v: Dictionary) -> bool: return v.name != name)
		return _accept({})
	var stream := _video_stream(name)
	if stream == null:
		return _reject(p.tag, "no video '%s'" % name)
	var on := str(p.opts.get("on", ""))
	if on != "" and not actors.has(on):
		return _reject(p.tag, "no actor '%s' to play the video on" % on)
	var loop: bool = p.opts.has("loop")
	if restoring:
		# Non-looping videos are omitted on restore; looping ones start once
		# after reconstruction (finish_restore), never during it.
		_pending_videos = _pending_videos.filter(func(v: Dictionary) -> bool: return v.name != name)
		if loop:
			_pending_videos.append({"name": name, "stream": stream, "on": on, "volume": p.opts.get("volume")})
		return _accept({})
	_start_video(name, stream, on, loop, p.opts.get("volume"))
	return _accept({})


func _start_video(name: String, stream: VideoStream, on: String, loop: bool, volume: Variant) -> void:
	_stop_video(name)
	var player := VideoStreamPlayer.new()
	player.name = "Video_%s" % name
	player.stream = stream
	player.loop = loop
	player.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if AudioServer.get_bus_index(&"SFX") != -1:
		player.bus = &"SFX"  # video sound follows the SFX volume (and Master)
	if volume != null and str(volume).is_valid_float():
		player.volume_db = linear_to_db(clampf(str(volume).to_float(), 0.0, 1.0))
	video_layer.add_child(player)
	if on != "":
		player.modulate.a = 0.0  # decode only; the texture shows on the actor
		player.size = Vector2(2, 2)
	else:
		player.expand = true
		player.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	player.play()
	_videos[name] = {"player": player, "loop": loop, "on": on}
	if on != "":
		var a: Dictionary = actors[on]
		var tex := player.get_video_texture()
		if a.body is Sprite3DQuad:
			(a.body as Sprite3DQuad).texture = tex
		elif a.body is TextureRect:
			(a.body as TextureRect).texture = tex
	if not loop:
		player.finished.connect(_on_video_finished.bind(name, player))


func _on_video_finished(name: String, player: VideoStreamPlayer) -> void:
	if _videos.has(name) and _videos[name].player == player:
		_stop_video(name)


func _stop_video(name: String) -> void:
	if not _videos.has(name):
		return
	var v: Dictionary = _videos[name]
	_videos.erase(name)
	if is_instance_valid(v.player):
		v.player.stop()
		v.player.queue_free()
	var on: String = v.get("on", "")
	if on != "" and actors.has(on):
		_set_look(actors[on], str(actors[on].look))


func video_names() -> Array:
	return _videos.keys()


#endregion


#region Stage switching


func _apply_stage(p: Dictionary) -> Dictionary:
	var name: String = p.name
	if name == current_stage:
		return _accept({})
	var root: Node3D = null
	if name != "2d":
		root = _load_stage(name)
		if root == null:
			return _reject(p.tag, "no stage scene '%s'" % name)
	_clear_stage()
	if _stage_root != null and _stage_root.get_parent() != null:
		_stage_root.get_parent().remove_child(_stage_root)
	_stage_root = root
	current_stage = name
	if root != null:
		viewport.add_child(root)
		viewport_container.show()
		var cam := root.find_children("*", "Camera3D", true, false)
		if not cam.is_empty():
			(cam[0] as Camera3D).make_current()
	else:
		viewport_container.hide()
	stage_cleared.emit(name)
	return _accept({})


func _load_stage(name: String) -> Node3D:
	if _stage_cache.has(name) and is_instance_valid(_stage_cache[name]):
		return _stage_cache[name]
	var packed: PackedScene = stage_scenes.get(name)
	if packed == null:
		var path := "res://scenes/stages/%s.tscn" % name
		if ResourceLoader.exists(path):
			packed = load(path)
	if packed == null:
		return null
	var root := packed.instantiate() as Node3D
	if root == null:
		return null
	_stage_cache[name] = root
	return root


## Free actors, ghosts, videos and focus of the current stage. Definitions
## stay registered.
func _clear_stage() -> void:
	for id: String in actors.keys():
		_remove(id)
	for a: Dictionary in _ghosts:
		_free_actor(a)
	_ghosts.clear()
	for name: String in _videos.keys():
		_stop_video(name)
	_pending_videos.clear()
	focus_id = ""


#endregion


#region Restore


## Drop everything the story put on stage and return to the 2D stage.
## Called before replaying history. Definitions stay registered.
func reset_all() -> void:
	_clear_stage()
	_drop_probe_stages()
	if _stage_root != null and _stage_root.get_parent() != null:
		_stage_root.get_parent().remove_child(_stage_root)
	_stage_root = null
	current_stage = "2d"
	if viewport_container != null:
		viewport_container.hide()


## Reconstruction is done: start looping videos once.
func finish_restore() -> void:
	var pending := _pending_videos
	_pending_videos = []
	for v: Dictionary in pending:
		if v.on != "" and not actors.has(v.on):
			continue
		_start_video(v.name, v.stream, v.on, true, v.volume)


func _exit_tree() -> void:
	for name: String in _videos.keys():
		_stop_video(name)
	for key: String in _stage_cache:
		var root = _stage_cache[key]
		if is_instance_valid(root) and root.get_parent() == null:
			root.free()
	_stage_cache.clear()
	_drop_probe_stages()


func _on_stage_resized() -> void:
	call_deferred("_replace_anchored")


## On resize, anchored actors are re-placed; actors at coordinates stay.
func _replace_anchored() -> void:
	for id: String in actors:
		var a: Dictionary = actors[id]
		if a.mode != "2d":
			continue
		_layout_2d(a)
		if str(a.place.get("kind", "")) == "anchor":
			var anchor := _anchor(str(a.place.name))
			if anchor != null:
				director.set_now(a.root, "position", _anchor_pos(anchor))


#endregion
