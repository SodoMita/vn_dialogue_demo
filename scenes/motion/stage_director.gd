class_name StageDirector extends Node
## Stage motion director: tween any 2D/3D object, run NLA-style animation
## tracks, play frame ranges, shake the stage - all from dialogue tags.
##
## The director is a pure behaviour node: it owns no visuals. The balloon
## forwards stage direction tags to [method apply_tag]; every tag it accepts
## is recorded in the backlog entry so Ren'Py-style rollback and save slots
## can re-dress tweened objects exactly like backgrounds and portraits
## ([method reset_all] + [method replay_tags]).
##
## Tags (comma-free - Dialogue Manager splits line tags on commas, so vectors
## are written with spaces and options are joined with "&"):
##
##   #target=alias:NodePath            register a target alias (once)
##   #nla_track=alias:NodePath         register an animation track
##   #tween=alias:prop=value:dur:trans:ease?opts
##                                     tween a property of any Control,
##                                     Node2D or Node3D (see below)
##   #tween_stop=alias                 kill the alias's running tweens
##   #set=alias:prop=value?opts        set a property instantly
##   #shake=alias:strength:duration?rot
##                                     decaying positional shake, always
##                                     lands back on the origin
##   #nla=track:clip:FROM-TO?opts      NLA-style clip play with crossfade,
##                                     loop, speed and frame range
##   #nla_stop=track                   stop a track
##   #sprite3d=key:alias?path=Node3D&height=1.8&pos=x y z&anchor=bottom|center
##            &yaw=deg&modulate=hex|rgba
##                                     stand a portrait in a 3D scene as a
##                                     quad that faces the camera by rotating
##                                     only around the vertical axis (vertex
##                                     shader); key "none" removes it
##   #place3d=alias:x y z[?height=1.8] place the quad by transform
##   #place3d=alias:copy=NodePath      copy an existing 3D object's full
##                                     global transform (position, rotation,
##                                     scale; its yaw also becomes the
##                                     billboard facing offset)
##
## #tween properties: position, x, y, z (3D), rotation (degrees), scale,
## modulate, alpha, self_modulate, self_alpha, global_position - or any real
## property path with "." instead of ":" (e.g. rotation_degrees.x).
## Values: a number, "x y", "x y z", "x y z w", or a hex color (rgb/rrggbb/
## rrggbbaa). Options: relative, delay=S, speed=X, yoyo, loops=N (0 = ∞).
## Transitions: linear sine quad cubic quart quint expo circ elastic back
## bounce. Ease: in, out, in_out.
##
## #nla options: loop, blend=S (crossfade seconds), speed=X, fps=N (default
## 60, converts frames to seconds), hold (pause at the end frame - default),
## stop (reset instead of holding). A track that is an AnimationTree travels
## to the named state instead.
##
## Aliases resolve as: registered alias → relative NodePath against the
## scope node (the balloon), the current scene, then the scene tree root.
## Unknown aliases are warned about and the tag is rejected, so rollback
## never replays a tag that never applied.

## Emitted for every tag the director accepted (also during rollback replay).
signal tag_applied(tag: String)
## Emitted when a tag was syntactically ours but could not be applied.
signal tag_rejected(tag: String, reason: String)

## Tag prefixes the balloon hands to this director.
const MOTION_PREFIXES: PackedStringArray = [
	"tween=", "tween_stop=", "set=", "shake=", "nla=", "nla_stop=", "nla_track=", "target=",
	"sprite3d=", "place3d=",
]

const TRANSITIONS := {
	"linear": Tween.TRANS_LINEAR,
	"sine": Tween.TRANS_SINE,
	"quad": Tween.TRANS_QUAD,
	"cubic": Tween.TRANS_CUBIC,
	"quart": Tween.TRANS_QUART,
	"quint": Tween.TRANS_QUINT,
	"expo": Tween.TRANS_EXPO,
	"circ": Tween.TRANS_CIRC,
	"elastic": Tween.TRANS_ELASTIC,
	"back": Tween.TRANS_BACK,
	"bounce": Tween.TRANS_BOUNCE,
}
const EASES := {
	"in": Tween.EASE_IN,
	"out": Tween.EASE_OUT,
	"in_out": Tween.EASE_IN_OUT,
}

const DEFAULT_TWEEN_DURATION := 0.5
const DEFAULT_NLA_BLEND := 0.2
const DEFAULT_FPS := 60.0
## Sub-second epsilon so a range end at "the current frame" still triggers.
const RANGE_EPSILON := 0.0005

## Registered aliases: target or track name -> Node.
var _targets: Dictionary = {}
## Scope for relative NodePaths (the balloon), set by [method attach].
var _scope: Node = null
## Running tweens, keyed by "<instance_id>:<property path>" so a new tween
## only replaces one animating the same property of the same node.
var _tweens: Dictionary = {}
## Active shake effects, keyed by instance id.
var _shakes: Dictionary = {}
## Transform/colour snapshot per touched node, restored by [method reset_all].
var _homes: Dictionary = {}
## Active NLA frame-range playbacks.
var _ranged: Array = []
## Tracks looping a clip that has no loop mode of its own: alias -> true.
var _looping: Dictionary = {}
## Players that already have the loop hook connected: instance id -> true.
var _finish_hooked: Dictionary = {}
## Sprite3DQuads spawned by `#sprite3d=`: alias -> quad. Rollback frees them
## all and the replayed tags recreate the ones that belong to the story so far.
var _spawned: Dictionary = {}
## Resolves a `#sprite3d=` key to a portrait texture; the balloon wires this
## to its own `sprites` dictionary so the director stays scene-agnostic.
var texture_resolver: Callable
## Logical destination per running tween key ("<iid>:<prop>"). Relative
## tweens start from here, not from the mid-tween on-screen value, so live
## play, skip and rollback replay all land on the same end value.
var _logical: Dictionary = {}
## Aliases seeded by [method attach] (authored). Aliases registered by story
## tags are dropped on [method reset_all]; replay re-registers the live ones.
var _authored: Dictionary = {}
## AnimationPlayers started by `#nla=` / [method play_clip]: iid -> player.
var _players: Dictionary = {}
## AnimationTrees driven by story tags (stopped on reset / #nla_stop).
var _trees: Dictionary = {}
## Bumped by [method reset_all]; delayed callbacks compare against it so a
## callback scheduled by abandoned history never fires into the new stage.
var generation: int = 0

const SPRITE3D_QUAD := preload("res://scenes/motion/sprite_3d_quad.gd")


## Bind the director to the node relative paths resolve against, and seed
## built-in aliases (the balloon's own stage pieces).
func attach(scope: Node, builtin_aliases: Dictionary = {}) -> void:
	_scope = scope
	for alias: String in builtin_aliases:
		var node: Node = builtin_aliases[alias]
		if node != null:
			_targets[alias] = node
			_authored[alias] = true


## True when [param tag] (already stripped of "#") is one of ours.
func is_motion_tag(tag: String) -> bool:
	for prefix: String in MOTION_PREFIXES:
		if tag.begins_with(prefix):
			return true
	return false


## Apply one tag. Returns true when the tag was accepted. [param instant]
## skips animation (used by rollback replay): tweens and sets land at once,
## shakes are ignored, NLA clips restart at their from-frame.
func apply_tag(tag: String, instant: bool = false) -> bool:
	if tag.begins_with("tween_stop="):
		return _apply_tween_stop(tag)
	if tag.begins_with("tween="):
		return _apply_tween(tag, instant)
	if tag.begins_with("set="):
		return _apply_set(tag, instant)
	if tag.begins_with("shake="):
		return _apply_shake(tag, instant)
	if tag.begins_with("nla_track="):
		return _apply_register(tag, true)
	if tag.begins_with("nla_stop="):
		return _apply_nla_stop(tag)
	if tag.begins_with("nla="):
		return _apply_nla(tag, instant)
	if tag.begins_with("sprite3d="):
		return _apply_sprite3d(tag)
	if tag.begins_with("place3d="):
		return _apply_place3d(tag)
	if tag.begins_with("target="):
		return _apply_register(tag, false)
	return false


## Resolve an alias or inline NodePath to a live node, or null.
func resolve_target(alias: String) -> Node:
	if _targets.has(alias):
		var node = _targets[alias]
		if is_instance_valid(node):
			return node
		_targets.erase(alias)
	if alias == "" or alias == "none":
		return null
	if alias.contains("/") or alias.contains("%"):
		var found: Node = _find_by_path(alias)
		if found != null:
			_targets[alias] = found
		return found
	return null


func _find_by_path(path: String) -> Node:
	for base: Node in [_scope, get_tree().current_scene if get_tree() != null else null, get_tree().root if get_tree() != null else null]:
		if base == null:
			continue
		var found: Node = base.get_node_or_null(NodePath(path))
		if found != null:
			return found
	return null


func _reject(tag: String, reason: String) -> bool:
	tag_rejected.emit(tag, reason)
	push_warning("StageDirector: %s (%s)" % [reason, tag])
	return false


func _accept(tag: String) -> bool:
	tag_applied.emit(tag)
	return true


#region Registration


func _apply_register(tag: String, is_track: bool) -> bool:
	var spec: String = tag.substr(tag.find("=") + 1)
	var parts: PackedStringArray = spec.split(":", true, 1)
	if parts.size() != 2 or parts[0].strip_edges() == "":
		return _reject(tag, "expected alias:NodePath")
	var alias: String = parts[0].strip_edges()
	var node: Node = _find_by_path(parts[1].strip_edges())
	if node == null:
		return _reject(tag, "no node at that path")
	if is_track and not (node is AnimationPlayer or node is AnimationTree):
		return _reject(tag, "an NLA track must be an AnimationPlayer or AnimationTree")
	_targets[alias] = node
	return _accept(tag)


#endregion


#region Tween / set


## Split "main?opt=1&flag" into [main, {opt: "1", flag: true}].
func _split_options(spec: String) -> Array:
	var opts: Dictionary = {}
	var main: String = spec
	var q: int = spec.find("?")
	if q >= 0:
		main = spec.substr(0, q)
		for pair: String in spec.substr(q + 1).split("&"):
			if pair == "":
				continue
			var kv: PackedStringArray = pair.split("=", true, 1)
			opts[kv[0].strip_edges()] = kv[1].strip_edges() if kv.size() == 2 else true
	return [main, opts]


## Map a friendly property name onto the node's real property path.
func _resolve_property(node: Node, name: String) -> String:
	match name:
		"x":
			return "position:x"
		"y":
			return "position:y"
		"z":
			return "position:z" if node is Node3D else ""
		"position", "scale", "modulate", "self_modulate", "global_position":
			return name if node is CanvasItem or node is Node3D else ""
		"alpha":
			return "modulate:a" if node is CanvasItem else ""
		"self_alpha":
			return "self_modulate:a" if node is CanvasItem else ""
		"rotation":
			if node is Node2D:
				return "rotation_degrees"
			if node is Control:
				return "rotation"
			if node is Node3D:
				return "rotation_degrees"
			return ""
		"rx", "ry", "rz":
			return "rotation_degrees:%s" % name.substr(1) if node is Node3D else ""
		"sx", "sy", "sz":
			return "scale:%s" % name.substr(1)
		"gx":
			return "global_position:x"
		"gy":
			return "global_position:y"
		"gz":
			return "global_position:z" if node is Node3D else ""
	var dotted: String = name.replace(".", ":")
	var head: String = dotted.get_slice(":", 0)
	if head in node or node.get(head) != null:
		return dotted
	return ""


## Parse "640 360" / "1.2" / "ff88cc" against the property's current value.
func _parse_value(text: String, current: Variant) -> Variant:
	var tokens: PackedStringArray = text.strip_edges().split(" ", false)
	var nums: Array = []
	for token: String in tokens:
		if not token.is_valid_float():
			nums.clear()
			break
		nums.append(float(token))
	var is_hex: bool = tokens.size() == 1 and tokens[0].length() in [3, 6, 8] \
			and tokens[0].is_valid_html_color()
	if current is Color:
		if is_hex:
			return Color.html(tokens[0])
		match nums.size():
			3:
				return Color(nums[0], nums[1], nums[2])
			4:
				return Color(nums[0], nums[1], nums[2], nums[3])
	elif current is Vector2:
		if nums.size() == 1:
			return Vector2(nums[0], nums[0])
		if nums.size() >= 2:
			return Vector2(nums[0], nums[1])
	elif current is Vector3:
		if nums.size() == 1:
			return Vector3(nums[0], nums[0], nums[0])
		if nums.size() == 2:
			return Vector3(nums[0], nums[1], 0.0)
		if nums.size() >= 3:
			return Vector3(nums[0], nums[1], nums[2])
	elif current is float or current is int:
		if nums.size() >= 1:
			return nums[0]
	return null


func _apply_relative(current: Variant, delta: Variant) -> Variant:
	if current is float and delta is float:
		return current + delta
	if current is Vector2 and delta is Vector2:
		return current + delta
	if current is Vector3 and delta is Vector3:
		return current + delta
	if current is Color and delta is Color:
		return Color(current.r + delta.r, current.g + delta.g, current.b + delta.b, current.a + delta.a)
	return delta


## Remember the node's rest state the first time we touch it, so
## [method reset_all] can put everything back for rollback.
func _capture_home(node: Node) -> void:
	var iid: int = node.get_instance_id()
	if _homes.has(iid):
		return
	var home: Dictionary = {}
	var props: PackedStringArray = []
	if node is Node3D:
		props = ["position", "rotation_degrees", "scale"] as PackedStringArray
	elif node is Node2D:
		props = ["position", "rotation_degrees", "scale", "modulate", "self_modulate"] as PackedStringArray
	elif node is Control:
		props = ["position", "rotation", "scale", "modulate", "self_modulate"] as PackedStringArray
	for prop: String in props:
		home[prop] = node.get(prop)
	_homes[iid] = {"node": node, "props": home}


func _apply_tween(tag: String, instant: bool) -> bool:
	var parsed: Array = _split_options(tag.substr(tag.find("=") + 1))
	var main: String = parsed[0]
	var opts: Dictionary = parsed[1]
	var fields: PackedStringArray = main.split(":", true, 4)
	if fields.size() < 2:
		return _reject(tag, "expected target:property=value")
	var node: Node = resolve_target(fields[0])
	if node == null:
		return _reject(tag, "unknown tween target")
	var eq: int = fields[1].find("=")
	if eq <= 0:
		return _reject(tag, "expected property=value")
	var prop: String = _resolve_property(node, fields[1].substr(0, eq))
	if prop == "":
		return _reject(tag, "no such property on that node")
	var current: Variant = node.get_indexed(NodePath(prop))
	if current == null:
		return _reject(tag, "property is not readable")
	var to: Variant = _parse_value(fields[1].substr(eq + 1), current)
	if to == null:
		return _reject(tag, "cannot read that value")
	var relative: bool = bool(opts.get("relative", false))
	var key: String = "%d:%s" % [node.get_instance_id(), prop]
	var base: Variant = _logical_at(node, prop, current)
	if relative:
		to = _apply_relative(base, to)
	if fields.size() > 2 and fields[2] != "" and not fields[2].is_valid_float():
		return _reject(tag, "duration must be a number of seconds")
	var loops: int = int(opts.get("loops", 1))
	var yoyo: bool = bool(opts.get("yoyo", false))
	if instant or fields.size() < 3 or fields[2] == "" or float(fields[2]) <= 0.0:
		_capture_home(node)
		_cancel_overlapping(node, prop)
		_logical.erase(key)
		# A yoyo/looping tween logically rests on its start value.
		node.set_indexed(NodePath(prop), base if (yoyo or loops != 1) else to)
		return _accept(tag)
	_capture_home(node)
	var duration: float = float(fields[2])
	var speed: float = float(opts.get("speed", 1.0))
	if speed > 0.0:
		duration /= speed
	var trans_name: String = fields[3].strip_edges() if fields.size() > 3 else ""
	var ease_name: String = fields[4].strip_edges() if fields.size() > 4 else ""
	var trans: int = int(TRANSITIONS.get(trans_name if trans_name != "" else "quad", Tween.TRANS_QUAD))
	var ease: int = int(EASES.get(ease_name if ease_name != "" else "out", Tween.EASE_OUT))
	_cancel_overlapping(node, prop)
	var tween: Tween = create_tween()
	var delay: float = maxf(float(opts.get("delay", 0.0)), 0.0)
	if delay > 0.0:
		tween.tween_interval(delay)
	# Absolute tween from the on-screen value to the logical destination:
	# relative tags resolved against the logical base above, so an
	# interrupted chain of relative moves still ends where replay puts it.
	tween.tween_property(node, prop, to, duration).set_trans(trans).set_ease(ease)
	if yoyo or loops != 1:
		tween.tween_property(node, prop, base, duration).set_trans(trans).set_ease(ease)
		tween.set_loops(loops)
		_logical[key] = base
	else:
		_logical[key] = to
	tween.finished.connect(_on_tween_finished.bind(key, tween))
	_tweens[key] = tween
	return _accept(tag)


func _on_tween_finished(key: String, tween: Tween = null) -> void:
	if tween != null and _tweens.get(key) != tween:
		return
	_tweens.erase(key)
	_logical.erase(key)


## Kill running tweens on [param prop] of [param node] and on any
## overlapping property ("position" vs "position:x"). A tween on a
## different-but-overlapping property is snapped to its logical end first,
## so the new command starts from the same state a restore would.
func _cancel_overlapping(node: Node, prop: String) -> void:
	var iid: int = node.get_instance_id()
	var prefix: String = "%d:" % iid
	var head: String = prop.get_slice(":", 0)
	for key: String in _tweens.keys():
		if not key.begins_with(prefix):
			continue
		var other: String = key.substr(prefix.length())
		if other != prop and not (other.get_slice(":", 0) == head and (other == head or prop == head)):
			continue
		var tween: Tween = _tweens[key]
		if is_instance_valid(tween):
			tween.kill()
		_tweens.erase(key)
		if other != prop and _logical.has(key) and is_instance_valid(node):
			node.set_indexed(NodePath(other), _logical[key])
		if other != prop:
			_logical.erase(key)


#region Public API (used by StageActors)


## Tween [param prop] of [param node] to an absolute [param to]. Same engine,
## overlap rules and rollback homes as `#tween=`.
func tween_to(node: Node, prop: String, to: Variant, duration: float, trans: String = "sine", ease_name: String = "in_out", instant: bool = false) -> void:
	if node == null:
		return
	_capture_home(node)
	var key: String = "%d:%s" % [node.get_instance_id(), prop]
	_cancel_overlapping(node, prop)
	if instant or duration <= 0.0:
		node.set_indexed(NodePath(prop), to)
		_logical.erase(key)
		return
	var tween: Tween = create_tween()
	tween.tween_property(node, prop, to, duration) \
			.set_trans(int(TRANSITIONS.get(trans, Tween.TRANS_SINE))) \
			.set_ease(int(EASES.get(ease_name, Tween.EASE_IN_OUT)))
	_logical[key] = to
	tween.finished.connect(_on_tween_finished.bind(key, tween))
	_tweens[key] = tween


## Set a property instantly, cancelling any tween on it or an overlapping one.
func set_now(node: Node, prop: String, value: Variant) -> void:
	tween_to(node, prop, value, 0.0, "", "", true)


## The value a property is heading to (running tween) or its current value.
func logical_value(node: Node, prop: String) -> Variant:
	return _logical_at(node, prop, node.get_indexed(NodePath(prop)))


## The value [param prop] is heading to, seen through both spellings: a
## component ("position:x") reads out of a pending whole-vector tween, and a
## whole property ("position") overlays pending component tweens on its
## current value. Live play, skip and restore therefore agree.
func _logical_at(node: Node, prop: String, current: Variant) -> Variant:
	var iid: int = node.get_instance_id()
	var key: String = "%d:%s" % [iid, prop]
	if _logical.has(key):
		return _logical[key]
	var head: String = prop.get_slice(":", 0)
	if prop != head:
		var whole_key: String = "%d:%s" % [iid, head]
		if _logical.has(whole_key):
			var whole: Variant = _logical[whole_key]
			return whole[prop.get_slice(":", 1)]
		return current
	var result: Variant = current
	var prefix: String = "%d:%s:" % [iid, head]
	for other: String in _logical.keys():
		if other.begins_with(prefix):
			result[other.substr(prefix.length())] = _logical[other]
	return result


## True while a tween drives [param prop] (or an overlapping property).
func is_tweening(node: Node, prop: String) -> bool:
	var prefix: String = "%d:" % node.get_instance_id()
	var head: String = prop.get_slice(":", 0)
	for key: String in _tweens.keys():
		if key.begins_with(prefix) and key.substr(prefix.length()).get_slice(":", 0) == head:
			return true
	return false


## Register a story alias (dropped again by [method reset_all]). StageActors
## registers each actor's root under its ID so advanced tags reach it.
func register_alias(alias: String, node: Node) -> void:
	if alias != "" and node != null and not _authored.has(alias):
		_targets[alias] = node


## Kill every tween on [param node] (it is about to be freed or re-placed).
func kill_node(node: Node) -> void:
	if node != null:
		_kill_tweens_for(node)


## Play a clip on an AnimationPlayer (or travel an AnimationTree state
## machine). [param instant] (restore) lands on the end pose of a
## non-looping clip; looping clips simply start. Returns false on failure.
func play_clip(track: Node, clip: String, loop: bool = false, instant: bool = false) -> bool:
	if track is AnimationTree:
		_trees[track.get_instance_id()] = track
		var playback: Variant = track.get("parameters/playback")
		if playback == null or not playback.has_method("travel"):
			return false
		if instant and playback.has_method("start"):
			playback.start(StringName(clip))
		else:
			playback.travel(StringName(clip))
		return true
	var player := track as AnimationPlayer
	if player == null or not player.has_animation(clip):
		return false
	_players[player.get_instance_id()] = player
	var anim: Animation = player.get_animation(clip)
	if loop and anim.loop_mode == Animation.LOOP_NONE:
		anim = anim.duplicate()
		anim.loop_mode = Animation.LOOP_LINEAR
		var lib_name := "__stage_loops"
		var lib: AnimationLibrary = player.get_animation_library(lib_name) if player.has_animation_library(lib_name) else null
		if lib == null:
			lib = AnimationLibrary.new()
			player.add_animation_library(lib_name, lib)
		var loop_key := clip.replace("/", "_")
		if lib.has_animation(loop_key):
			lib.remove_animation(loop_key)
		lib.add_animation(loop_key, anim)
		clip = "%s/%s" % [lib_name, loop_key]
	player.play(StringName(clip), 0.0 if instant else DEFAULT_NLA_BLEND)
	if instant and not loop:
		player.seek(anim.length, true)
		player.pause()
	return true


#endregion


## Relative deltas keep rollback replay exact: replaying a relative tween
## instantly adds the same delta again, so order accumulates like live play.
func _delta_of(current: Variant, absolute_to: Variant) -> Variant:
	if current is float:
		return absolute_to - current
	if current is Vector2:
		return absolute_to - current
	if current is Vector3:
		return absolute_to - current
	if current is Color:
		return Color(absolute_to.r - current.r, absolute_to.g - current.g, absolute_to.b - current.b, absolute_to.a - current.a)
	return absolute_to


func _apply_set(tag: String, _instant: bool) -> bool:
	var parsed: Array = _split_options(tag.substr(tag.find("=") + 1))
	var fields: PackedStringArray = str(parsed[0]).split(":", true, 1)
	if fields.size() != 2:
		return _reject(tag, "expected target:property=value")
	var node: Node = resolve_target(fields[0])
	if node == null:
		return _reject(tag, "unknown set target")
	var eq: int = fields[1].find("=")
	if eq <= 0:
		return _reject(tag, "expected property=value")
	var prop: String = _resolve_property(node, fields[1].substr(0, eq))
	if prop == "":
		return _reject(tag, "no such property on that node")
	var current: Variant = node.get_indexed(NodePath(prop))
	var to: Variant = _parse_value(fields[1].substr(eq + 1), current)
	if to == null:
		return _reject(tag, "cannot read that value")
	if bool(parsed[1].get("relative", false)):
		to = _apply_relative(_logical_at(node, prop, current), to)
	_capture_home(node)
	_cancel_overlapping(node, prop)
	_logical.erase("%d:%s" % [node.get_instance_id(), prop])
	node.set_indexed(NodePath(prop), to)
	return _accept(tag)


func _apply_tween_stop(tag: String) -> bool:
	var node: Node = resolve_target(tag.substr(tag.find("=") + 1))
	if node == null:
		return _reject(tag, "unknown target")
	_kill_tweens_for(node)
	return _accept(tag)


func _kill_tweens_for(node: Node) -> void:
	var prefix: String = "%d:" % node.get_instance_id()
	for key: String in _tweens.keys():
		if key.begins_with(prefix):
			var tween: Tween = _tweens[key]
			if is_instance_valid(tween):
				tween.kill()
			_tweens.erase(key)
			_logical.erase(key)


#endregion


#region Shake


func _apply_shake(tag: String, instant: bool) -> bool:
	var parsed: Array = _split_options(tag.substr(tag.find("=") + 1))
	var fields: PackedStringArray = str(parsed[0]).split(":")
	var node: Node = resolve_target(fields[0])
	if node == null:
		return _reject(tag, "unknown shake target")
	if not (node is Node2D or node is Node3D or node is Control):
		return _reject(tag, "only Node2D, Node3D and Control can shake")
	if instant:
		return _accept(tag)
	var strength: float = float(fields[1]) if fields.size() > 1 and fields[1] != "" else 10.0
	var duration: float = float(fields[2]) if fields.size() > 2 and fields[2] != "" else 0.6
	_capture_home(node)
	var iid: int = node.get_instance_id()
	_shakes[iid] = {
		"node": node,
		"strength": strength,
		"duration": maxf(duration, 0.05),
		"elapsed": 0.0,
		"rot": bool(parsed[1].get("rot", false)),
		"base_position": node.position,
		"base_rotation": _shake_rotation(node),
	}
	set_process(true)
	return _accept(tag)


func _shake_rotation(node: Node) -> float:
	if node is Node3D:
		return node.rotation_degrees.z
	return node.rotation


func _process(delta: float) -> void:
	if not _shakes.is_empty():
		for iid: int in _shakes.keys():
			var shake: Dictionary = _shakes[iid]
			var node: Node = shake.node
			if not is_instance_valid(node):
				_shakes.erase(iid)
				continue
			shake.elapsed += delta
			var t: float = clampf(shake.elapsed / shake.duration, 0.0, 1.0)
			if t >= 1.0:
				node.position = shake.base_position
				_set_shake_rotation(node, shake.base_rotation)
				_shakes.erase(iid)
				continue
			# Decaying noise: strong at the start, exactly home at the end.
			var amp: float = shake.strength * (1.0 - t) * (1.0 - t)
			var offset := Vector2(randf_range(-amp, amp), randf_range(-amp, amp))
			if node is Node3D:
				node.position = shake.base_position + Vector3(offset.x, offset.y, 0.0)
			else:
				node.position = shake.base_position + offset
			if bool(shake.rot):
				_set_shake_rotation(node, shake.base_rotation + randf_range(-amp, amp) * 0.15)
	if not _ranged.is_empty():
		_process_ranged(delta)
	if _shakes.is_empty() and _ranged.is_empty():
		set_process(false)


func _set_shake_rotation(node: Node, degrees: float) -> void:
	if node is Node3D:
		node.rotation_degrees = Vector3(node.rotation_degrees.x, node.rotation_degrees.y, degrees)
	else:
		node.rotation = degrees


#endregion


#region NLA


## Parse a "FROM-TO" frame-range field; "" means no range.
func _parse_range(text: String, fps: float) -> Variant:
	if text.strip_edges() == "":
		return null
	var rx := RegEx.new()
	rx.compile("^(\\d+)?-(\\d+)?$")
	var match: RegExMatch = rx.search(text.strip_edges())
	if match == null:
		return null
	var from_s: float = float(match.get_string(1)) / fps if match.get_string(1) != "" else 0.0
	var to_s: float = float(match.get_string(2)) / fps if match.get_string(2) != "" else -1.0
	if to_s >= 0.0 and to_s <= from_s:
		return null
	return {"from": from_s, "to": to_s}


func _apply_nla(tag: String, instant: bool) -> bool:
	var parsed: Array = _split_options(tag.substr(tag.find("=") + 1))
	var fields: PackedStringArray = str(parsed[0]).split(":", true, 2)
	if fields.size() < 2 or fields[1].strip_edges() == "":
		return _reject(tag, "expected track:clip")
	var track: Node = resolve_target(fields[0])
	if track == null:
		return _reject(tag, "unknown NLA track")
	var opts: Dictionary = parsed[1]
	var fps: float = maxf(float(opts.get("fps", DEFAULT_FPS)), 1.0)
	var loop: bool = bool(opts.get("loop", false))
	_looping[fields[0]] = loop
	if track is AnimationTree:
		_trees[track.get_instance_id()] = track
		var playback: Variant = track.get("parameters/playback")
		if playback == null or not playback.has_method("travel"):
			return _reject(tag, "AnimationTree track has no state machine playback")
		playback.travel(StringName(fields[1].strip_edges()))
		return _accept(tag)
	var player: AnimationPlayer = track as AnimationPlayer
	var clip: String = fields[1].strip_edges()
	if not player.has_animation(clip):
		return _reject(tag, "player has no clip '%s'" % clip)
	var blend: float = 0.0 if instant else maxf(float(opts.get("blend", DEFAULT_NLA_BLEND)), 0.0)
	var speed: float = float(opts.get("speed", 1.0))
	if speed == 0.0:
		speed = 1.0
	# A new clip on the track replaces any frame-range watcher for it.
	_drop_ranged(fields[0])
	var span: Variant = _parse_range(fields[2] if fields.size() > 2 else "", fps)
	if loop and not _finish_hooked.has(player.get_instance_id()):
		# Hooked once per player; the alias is derived when the clip ends,
		# so re-registering the same player under a new name keeps working.
		player.animation_finished.connect(_on_track_finished.bind(player))
		_finish_hooked[player.get_instance_id()] = true
	_players[player.get_instance_id()] = player
	player.play(StringName(clip), blend, speed)
	if span != null:
		player.seek(span.from, true)
		var to_s: float = span.to
		if to_s < 0.0:
			to_s = player.get_animation(clip).length
		_ranged.append({
			"alias": fields[0],
			"player": player,
			"from": span.from,
			"to": minf(to_s, player.get_animation(clip).length) if loop else to_s,
			"loop": loop,
			"stop_at_end": bool(opts.get("stop", false)),
		})
		set_process(true)
	return _accept(tag)


func _drop_ranged(alias: String) -> void:
	for i: int in range(_ranged.size() - 1, -1, -1):
		if _ranged[i].alias == alias:
			_ranged.remove_at(i)


func _on_track_finished(_anim: StringName, from_player: AnimationPlayer) -> void:
	var alias := _alias_of(from_player)
	if alias == "" or not bool(_looping.get(alias, false)):
		return
	if is_instance_valid(from_player) and not from_player.is_playing():
		from_player.play(from_player.current_animation, 0.0, 1.0)


## The alias a node was registered under, or "".
func _alias_of(node: Node) -> String:
	for alias: String in _targets:
		if _targets[alias] == node:
			return alias
	return ""


func _process_ranged(_delta: float) -> void:
	for i: int in range(_ranged.size() - 1, -1, -1):
		var entry: Dictionary = _ranged[i]
		var player: AnimationPlayer = entry.player
		if not is_instance_valid(player):
			_ranged.remove_at(i)
			continue
		if not player.is_playing():
			# Paused or finished elsewhere: keep the watcher dormant.
			continue
		var position: float = player.current_animation_position
		if position >= float(entry.to) - RANGE_EPSILON:
			if bool(entry.loop):
				var overshoot: float = maxf(position - float(entry.to), 0.0)
				player.seek(float(entry.from), true)
				if overshoot > 0.0:
					player.seek(float(entry.from) + overshoot, true)
			else:
				if bool(entry.stop_at_end):
					player.stop()
				else:
					player.seek(float(entry.to), true)
					player.pause()
				_ranged.remove_at(i)


func _stop_tree(tree: Node) -> void:
	var playback: Variant = tree.get("parameters/playback")
	if playback != null and playback.has_method("stop"):
		playback.stop()


func _apply_nla_stop(tag: String) -> bool:
	var alias: String = tag.substr(tag.find("=") + 1).strip_edges()
	var track: Node = resolve_target(alias)
	if track == null:
		return _reject(tag, "unknown NLA track")
	_drop_ranged(alias)
	_looping[alias] = false
	if track is AnimationPlayer:
		track.stop()
	elif track is AnimationTree:
		_stop_tree(track)
		_trees.erase(track.get_instance_id())
	return _accept(tag)


#endregion


#region Sprite3D quads


## Spawn (or replace) a Y-billboard portrait quad in a 3D scene.
func spawn_quad(alias: String, tex: Texture2D, parent: Node3D, height: float, anchor_bottom: bool, pos: Variant = null) -> Sprite3DQuad:
	var existing = _spawned.get(alias)
	var quad: Sprite3DQuad = null
	if is_instance_valid(existing) and existing is Sprite3DQuad:
		# Same alias: update in place (keeps placement and running tweens).
		quad = existing
		if quad.get_parent() != parent:
			quad.reparent(parent, true)
	else:
		remove_quad(alias)
		quad = SPRITE3D_QUAD.new()
		quad.name = "Sprite3D_%s" % alias
		parent.add_child(quad)
	quad.world_height = height
	quad.bottom_anchored = anchor_bottom
	quad.texture = tex
	if pos is Vector3:
		quad.position = pos
	_spawned[alias] = quad
	_targets[alias] = quad
	return quad


## Remove a spawned quad; tweens on it die with it.
func remove_quad(alias: String) -> void:
	if _spawned.has(alias):
		# Untyped on purpose: after a scene teardown the entry may point at a
		# freed object, and assigning that to a typed Node is itself an error.
		var quad = _spawned[alias]
		if is_instance_valid(quad):
			_kill_tweens_for(quad)
			# queue_free alone leaves old portraits visible/countable until the
			# next frame. Detach now, then release safely at frame end.
			if quad.get_parent() != null:
				quad.get_parent().remove_child(quad)
			quad.queue_free()
		_spawned.erase(alias)
	var target = _targets.get(alias)
	if not is_instance_valid(target) or target is Sprite3DQuad:
		_targets.erase(alias)


## #sprite3d=key:alias?path=Node3D&height=1.8&pos=x y z&anchor=bottom|center
##            &yaw=deg&modulate=hex|rgba  -  key "none" removes the quad.
func _apply_sprite3d(tag: String) -> bool:
	var parsed: Array = _split_options(tag.substr(tag.find("=") + 1))
	var fields: PackedStringArray = str(parsed[0]).split(":", true, 1)
	var opts: Dictionary = parsed[1]
	var key: String = fields[0].strip_edges()
	var alias: String = (fields[1] if fields.size() > 1 else key).strip_edges()
	if alias == "":
		return _reject(tag, "sprite3d needs key:alias")
	if key == "none":
		remove_quad(alias)
		return _accept(tag)
	if not texture_resolver.is_valid():
		return _reject(tag, "no texture resolver is attached")
	var tex: Variant = texture_resolver.call(key)
	if not (tex is Texture2D):
		return _reject(tag, "unknown sprite3d key '%s'" % key)
	var parent: Node3D = null
	if opts.has("path"):
		parent = _find_by_path(str(opts.path)) as Node3D
	elif is_instance_valid(_spawned.get(alias)):
		parent = (_spawned[alias] as Node).get_parent() as Node3D
	if parent == null:
		var scene: Node = get_tree().current_scene if get_tree() != null else null
		parent = scene as Node3D
	if parent == null:
		return _reject(tag, "sprite3d needs a Node3D parent (path=... or a 3D current scene)")
	var pos: Variant = _parse_value(str(opts.pos), Vector3.ZERO) if opts.has("pos") else null
	var quad: Sprite3DQuad = null
	var existing = _spawned.get(alias)
	if is_instance_valid(existing) and existing is Sprite3DQuad:
		# A look change keeps the node, its placement and running tweens.
		quad = existing
		quad.texture = tex
		if opts.has("path") and quad.get_parent() != parent:
			quad.reparent(parent, true)
		if opts.has("height"):
			quad.world_height = float(opts.height)
		if opts.has("anchor"):
			quad.bottom_anchored = str(opts.anchor) != "center"
		if pos is Vector3:
			set_now(quad, "position", pos)
	else:
		quad = spawn_quad(alias, tex, parent, float(opts.get("height", 1.8)), str(opts.get("anchor", "bottom")) != "center", pos)
	if opts.has("yaw"):
		quad.yaw_offset_deg = float(opts.yaw)
	if opts.has("modulate"):
		var tinted: Variant = _parse_value(str(opts.modulate), quad.modulate)
		if tinted is Color:
			quad.modulate = tinted
	return _accept(tag)


## #place3d=alias:x y z[?height=1.8]          - place by transform
## #place3d=alias:copy=NodePath[?height=1.8]  - copy an existing object's
## global transform (position, rotation, scale; its yaw is also the facing offset).
func _apply_place3d(tag: String) -> bool:
	var parsed: Array = _split_options(tag.substr(tag.find("=") + 1))
	var fields: PackedStringArray = str(parsed[0]).split(":", true, 1)
	if fields.size() != 2:
		return _reject(tag, "expected alias:x y z or alias:copy=NodePath")
	var node: Node = resolve_target(fields[0])
	if node == null or not (node is Node3D):
		return _reject(tag, "place3d needs a registered Node3D target")
	var rest: String = fields[1].strip_edges()
	var opts: Dictionary = parsed[1]
	if rest.begins_with("copy="):
		var source: Node = _find_by_path(rest.substr(5).strip_edges())
		if not (source is Node3D):
			return _reject(tag, "no Node3D at the copy path")
		_kill_tweens_for(node)
		if node is Sprite3DQuad:
			(node as Sprite3DQuad).copy_transform_from(source)
		else:
			# Full transform: position, rotation and scale.
			(node as Node3D).global_transform = (source as Node3D).global_transform
	else:
		var to: Variant = _parse_value(rest, Vector3.ZERO)
		if not (to is Vector3):
			return _reject(tag, "cannot read that position")
		_kill_tweens_for(node)
		node.global_position = to
	if opts.has("height") and node is Sprite3DQuad:
		node.world_height = float(opts.height)
	return _accept(tag)


#endregion


#region Rollback


## Stop every tween, shake and range watcher, and put each touched node back
## on its captured rest state. Playback stays wherever the reset found it;
## [method replay_tags] re-dresses the stage right after.
func reset_all() -> void:
	generation += 1
	_logical.clear()
	# Stop authored animation playback started by story tags.
	for iid: int in _players.keys():
		var player = _players[iid]
		if is_instance_valid(player):
			player.stop()
	_players.clear()
	for tid: int in _trees.keys():
		if is_instance_valid(_trees[tid]):
			_stop_tree(_trees[tid])
	_trees.clear()
	# Drop aliases registered by (possibly abandoned) history; keep authored.
	for alias: String in _targets.keys():
		if not _authored.has(alias):
			_targets.erase(alias)
	# Rollback frees every spawned quad; the replayed tags recreate exactly
	# the ones the story so far asked for.
	for alias: String in _spawned.keys():
		remove_quad(alias)
	_spawned.clear()
	for key: String in _tweens.keys():
		var tween: Tween = _tweens[key]
		if is_instance_valid(tween):
			tween.kill()
	_tweens.clear()
	for iid: int in _shakes.keys():
		var shake: Dictionary = _shakes[iid]
		if is_instance_valid(shake.node):
			shake.node.position = shake.base_position
			_set_shake_rotation(shake.node, shake.base_rotation)
	_shakes.clear()
	_ranged.clear()
	_looping.clear()
	for iid: int in _finish_hooked.keys():
		if not is_instance_id_valid(iid):
			_finish_hooked.erase(iid)
	set_process(false)
	for iid: int in _homes.keys():
		var home: Dictionary = _homes[iid]
		if not is_instance_valid(home.node):
			_homes.erase(iid)
			continue
		for prop: String in home.props:
			home.node.set(prop, home.props[prop])


## Re-apply motion tags in order, instantly. Used by rollback and save-load:
## the balloon replays the tags of every line up to the restored one.
func replay_tags(tags: Array) -> void:
	for tag: Variant in tags:
		apply_tag(str(tag), true)


## Re-capture the rest state of an alias after the layout moved it (the
## balloon re-homes sprite slots when a new portrait texture is dressed).
func rehome(alias: String) -> void:
	var node: Node = resolve_target(alias)
	if node == null:
		return
	_homes.erase(node.get_instance_id())
	_capture_home(node)


#endregion
