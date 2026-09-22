extends Control
## Optional story-map view. Preload-only: constructing a global class with a
## typed _init fails when that class is absent from the UID class cache.
## One mesh, one atlas, one shader pass (pan/zoom uniform, a single texture fetch).


signal travel_requested(target: Dictionary)

const AtlasScript = preload("res://scenes/route_graph/route_graph_atlas.gd")
const MeshScript = preload("res://scenes/route_graph/route_graph_mesh_builder.gd")
const CompilerScript = preload("res://scenes/route_graph/route_graph_compiler.gd")

## Active dialogue. Left untyped so this script does not depend on the
## DialogueResource global class while the view itself is parsing.
@export var dialogue_resource: Resource

var nodes: Array = []
var full_nodes: Array = []
var node_by_id: Dictionary = {}
var atlas = null
var builder = null
var mesh_instance: MeshInstance2D
var route_material: ShaderMaterial
var pan := Vector2.ZERO
var zoom := 1.0
var target_pan := Vector2.ZERO
var target_zoom := 1.0
var dragging := false
var _press_local := Vector2.ZERO
var _press_graph := Vector2.ZERO
var _moved := false
var _touches: Dictionary = {}
var _pinching := false
var _pinch_dist := 0.0
var _pinch_anchor := Vector2.ZERO
var _fitted := false
var visited_only := true
var player_state: Dictionary = {}
var current_id := ""
var glyph_scale := 2
var map_filter := 1
const FILTER_HINTS: Array[String] = ["filter_nearest", "filter_linear", "filter_nearest_mipmap", "filter_linear_mipmap"]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_ensure_mesh()
	if dialogue_resource != null:
		open_resource(dialogue_resource)
	set_process(true)


func open_resource(resource = null, player: Dictionary = {}) -> void:
	if resource != null:
		dialogue_resource = resource
	elif dialogue_resource == null:
		var loaded = load("res://dialogue/intro.dialogue")
		if loaded != null:
			dialogue_resource = loaded
	player_state = player
	_rebuild()
	_fitted = false
	_fit_if_needed()


func set_glyph_scale(scale: int, rebuild: bool = true) -> void:
	var next := clampi(scale, 1, 4)
	var changed := next != glyph_scale
	glyph_scale = next
	if rebuild and changed and not full_nodes.is_empty():
		_upload()


func set_map_filter(index: int, rebuild: bool = true) -> void:
	var next := clampi(index, 0, FILTER_HINTS.size() - 1)
	var changed := next != map_filter
	map_filter = next
	_apply_map_shader()
	if atlas != null and atlas.has_method("set_mipmaps"):
		atlas.set_mipmaps(next >= 2)
		if route_material != null and atlas.texture != null:
			route_material.set_shader_parameter("atlas", atlas.texture)


func set_visited_only(on: bool) -> void:
	visited_only = on
	if full_nodes.is_empty():
		return
	_upload()
	_fitted = false
	_fit_if_needed()


func refresh_locale() -> void:
	if full_nodes.is_empty():
		return
	_upload()


func here_title() -> String:
	for node in full_nodes:
		if str(node.get("id", "")) == current_id:
			return CompilerScript.localized_title(node)
	return ""


func _rebuild() -> void:
	var compiled: Dictionary = CompilerScript.compile_project()
	if compiled.get("nodes", []).is_empty():
		compiled = CompilerScript.compile(dialogue_resource)
	full_nodes = compiled.get("nodes", [])
	if full_nodes.is_empty():
		full_nodes = [{
			"id": "empty",
			"type": "START",
			"title": "No routes",
			"title_source": "No routes",
			"title_dialogue": false,
			"subtitle": "0 in / 0 out",
			"color": Color("#475569"),
			"x": 40.0,
			"y": 40.0,
			"w": 240.0,
			"h": 132.0,
			"inputs": [],
			"outputs": [],
			"line_ids": [],
			"response_ids": [],
			"jump_key": "",
		}]
	current_id = str(CompilerScript.locate_player(full_nodes, player_state))
	_upload()


func _shown_ids() -> Dictionary:
	var all := {}
	for node in full_nodes:
		all[str(node.get("id", ""))] = true
	if not visited_only or player_state.is_empty():
		return all
	var visited: Dictionary = CompilerScript.visited_node_ids(full_nodes, player_state)
	if visited.is_empty():
		return all
	return visited


func _upload() -> void:
	var shown := _shown_ids()
	var relayout := visited_only and shown.size() < full_nodes.size()
	var picked: Array = CompilerScript.prepare_display(full_nodes, shown, relayout)
	if picked.is_empty():
		picked = full_nodes
	# Translate after the visited filter so port tags and titles follow the locale,
	# then remeasure so a longer translation still fits the node.
	nodes = CompilerScript.fit_localized(picked)
	node_by_id.clear()
	for node in nodes:
		node_by_id[str(node.get("id", ""))] = node
	atlas = AtlasScript.new()
	var keys: Array = MeshScript.text_keys(nodes)
	for entry in keys:
		if str(entry.get("key", "")) == "here_badge":
			entry["text"] = tr("You are here")
	atlas.use_mipmaps = map_filter >= 2
	atlas.bake(keys, float(glyph_scale))
	builder = MeshScript.new()
	_ensure_mesh()
	mesh_instance.mesh = builder.build(atlas, nodes, current_id)
	if atlas.texture != null:
		route_material.set_shader_parameter("atlas", atlas.texture)
	sync_shader()


func _ensure_mesh() -> void:
	if mesh_instance != null:
		return
	mesh_instance = MeshInstance2D.new()
	mesh_instance.position = Vector2.ZERO
	add_child(mesh_instance)
	route_material = ShaderMaterial.new()
	mesh_instance.material = route_material
	_apply_map_shader()


func _apply_map_shader() -> void:
	if route_material == null:
		return
	var code := FileAccess.get_file_as_string("res://scenes/route_graph/route_graph.gdshader")
	var hint := FILTER_HINTS[clampi(map_filter, 0, FILTER_HINTS.size() - 1)]
	# Swap only the sampler hint. The fetch and the lack of branches stay as authored.
	code = code.replace("filter_linear,", hint + ",")
	var shader := Shader.new()
	shader.code = code
	route_material.shader = shader
	if atlas != null and atlas.texture != null:
		route_material.set_shader_parameter("atlas", atlas.texture)
	sync_shader()


func _process(delta: float) -> void:
	var t := clampf(delta * 12.0, 0.0, 1.0)
	var next_pan := pan.lerp(target_pan, t)
	var next_zoom := lerpf(zoom, target_zoom, t)
	if next_pan.distance_squared_to(pan) < 0.01 and absf(next_zoom - zoom) < 0.0001:
		return
	pan = next_pan
	zoom = next_zoom
	sync_shader()


func sync_shader() -> void:
	if route_material == null:
		return
	route_material.set_shader_parameter("pan", pan)
	route_material.set_shader_parameter("zoom", zoom)


func _update_shader_params() -> void:
	sync_shader()


func fit_all() -> void:
	if nodes.is_empty():
		return
	var min_p := Vector2(1.0e9, 1.0e9)
	var max_p := Vector2(-1.0e9, -1.0e9)
	for node in nodes:
		min_p.x = minf(min_p.x, float(node.get("x", 0.0)))
		min_p.y = minf(min_p.y, float(node.get("y", 0.0)))
		max_p.x = maxf(max_p.x, float(node.get("x", 0.0)) + float(node.get("w", 0.0)))
		max_p.y = maxf(max_p.y, float(node.get("y", 0.0)) + float(node.get("h", 0.0)))
	var graph := (max_p - min_p) + Vector2(80, 80)
	var view := size
	if view.x < 8.0 or view.y < 8.0:
		view = Vector2(1100, 620)
	var z := minf(view.x / graph.x, view.y / graph.y)
	z = clampf(z, 0.25, 1.5)
	zoom = z
	target_zoom = z
	var center := (min_p + max_p) * 0.5
	pan = view * 0.5 / z - center
	target_pan = pan
	sync_shader()


func pan_to(node_id: String) -> void:
	var node = node_by_id.get(node_id)
	if node == null:
		return
	var center := Vector2(
		float(node.get("x", 0.0)) + float(node.get("w", 0.0)) * 0.5,
		float(node.get("y", 0.0)) + float(node.get("h", 0.0)) * 0.5
	)
	var view := size
	if view.x < 8.0 or view.y < 8.0:
		view = Vector2(1100, 620)
	target_pan = view * 0.5 / zoom - center


func _fit_if_needed() -> void:
	if _fitted:
		return
	if size.x < 8.0 or size.y < 8.0:
		return
	_focus_here()
	_fitted = true


func _focus_here() -> void:
	fit_all()
	if current_id == "" or not node_by_id.has(current_id):
		return
	var node = node_by_id[current_id]
	var center := Vector2(
		float(node.get("x", 0.0)) + float(node.get("w", 0.0)) * 0.5,
		float(node.get("y", 0.0)) + float(node.get("h", 0.0)) * 0.5
	)
	var view := size
	if view.x < 8.0 or view.y < 8.0:
		view = Vector2(1100, 620)
	var screen := (center + pan) * zoom
	var margin := 72.0
	var visible := screen.x > margin and screen.y > margin and screen.x < view.x - margin and screen.y < view.y - margin
	if visible and zoom >= 0.45:
		return
	if zoom < 0.55:
		zoom = 0.55
		target_zoom = zoom
	pan_to(current_id)
	pan = target_pan
	sync_shader()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_fit_if_needed()
	elif what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		_clear_pinch()


func _to_graph(local: Vector2) -> Vector2:
	return local / zoom - pan


func _gui_input(event: InputEvent) -> void:
	if _pinching and event is InputEventMouseButton:
		dragging = false
		_moved = true
		accept_event()
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_WHEEL_UP and button.pressed:
			apply_pinch(button.position, 1.12)
			accept_event()
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN and button.pressed:
			apply_pinch(button.position, 1.0 / 1.12)
			accept_event()
		elif button.button_index == MOUSE_BUTTON_LEFT or button.button_index == MOUSE_BUTTON_MIDDLE:
			if _pinching:
				dragging = false
				_moved = true
			elif button.pressed:
				dragging = true
				_moved = false
				_press_local = button.position
				_press_graph = _to_graph(button.position)
			else:
				dragging = false
				if not _moved and button.button_index == MOUSE_BUTTON_LEFT:
					_activate_at(_press_graph)
			accept_event()
	elif event is InputEventMouseMotion and dragging and not _pinching:
		var motion := event as InputEventMouseMotion
		if motion.position.distance_to(_press_local) > 4.0:
			_moved = true
		pan = motion.position / zoom - _press_graph
		target_pan = pan
		sync_shader()
		accept_event()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or _pinch_blocked():
		if _pinching or not _touches.is_empty():
			_clear_pinch()
		return
	if event is InputEventMagnifyGesture and not _pinching:
		var magnify := event as InputEventMagnifyGesture
		var local := _screen_to_local(magnify.position)
		if Rect2(Vector2.ZERO, size).has_point(local):
			apply_pinch(local, magnify.factor)
			get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if _touches.is_empty() and not _touch_on_view(touch.position):
				return
			_touches[touch.index] = touch.position
		else:
			if not _touches.has(touch.index):
				return
			_touches.erase(touch.index)
		_sync_pinch()
		if _pinching:
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if not _touches.has(drag.index):
			return
		_touches[drag.index] = drag.position
		if _pinching:
			_apply_two_finger()
			get_viewport().set_input_as_handled()


## Zoom around a local point. Wheel and trackpad pinch both come through here.
func apply_pinch(local: Vector2, factor: float) -> void:
	if factor <= 0.0 or is_equal_approx(factor, 1.0):
		return
	_zoom_at(local, factor)


## Keep a graph point under the moving midpoint while the finger distance changes.
func apply_two_finger(local_mid: Vector2, factor: float, anchor: Vector2) -> void:
	var next := clampf(zoom * factor, 0.2, 2.6)
	zoom = next
	target_zoom = next
	pan = local_mid / zoom - anchor
	target_pan = pan
	sync_shader()


func _pinch_blocked() -> bool:
	var node: Node = get_parent()
	while node != null:
		var spoiler := node.get_node_or_null("SpoilerPanel")
		if spoiler is CanvasItem and (spoiler as CanvasItem).visible:
			return true
		node = node.get_parent()
	return false


func _touch_on_view(screen_pos: Vector2) -> bool:
	return Rect2(Vector2.ZERO, size).has_point(_screen_to_local(screen_pos))


func _screen_to_local(screen_pos: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * screen_pos


func _clear_pinch() -> void:
	_touches.clear()
	_pinching = false
	_pinch_dist = 0.0


func _sync_pinch() -> void:
	if _touches.size() >= 2:
		if not _pinching:
			_pinching = true
			dragging = false
			_moved = true
			var mid := _screen_to_local(_touch_mid())
			_pinch_anchor = _to_graph(mid)
			_pinch_dist = _touch_dist()
		else:
			_apply_two_finger()
	else:
		_pinching = false
		_pinch_dist = 0.0


func _apply_two_finger() -> void:
	if _touches.size() < 2:
		return
	var dist := _touch_dist()
	# A tiny span is not a pinch yet. Adopt it as the baseline instead of zooming.
	if dist < 12.0 or _pinch_dist < 12.0:
		_pinch_dist = dist
		_pinch_anchor = _to_graph(_screen_to_local(_touch_mid()))
		return
	var factor := dist / _pinch_dist
	var mid := _screen_to_local(_touch_mid())
	apply_two_finger(mid, factor, _pinch_anchor)
	_pinch_dist = dist


func _touch_mid() -> Vector2:
	var pts := _two_points()
	return (pts[0] + pts[1]) * 0.5


func _touch_dist() -> float:
	var pts := _two_points()
	return pts[0].distance_to(pts[1])


func _two_points() -> Array:
	var pts: Array = []
	for key in _touches:
		pts.append(_touches[key])
		if pts.size() == 2:
			break
	return pts


func _zoom_at(local: Vector2, factor: float) -> void:
	var before := _to_graph(local)
	target_zoom = clampf(target_zoom * factor, 0.2, 2.6)
	zoom = target_zoom
	pan = local / zoom - before
	target_pan = pan
	sync_shader()


func _activate_at(graph_pos: Vector2) -> void:
	if builder == null:
		return
	var hit: Dictionary = builder.hit_test(graph_pos)
	if str(hit.get("kind", "")) == "header":
		var line_ids: Array = hit.get("line_ids", [])
		var jump_key := str(hit.get("jump_key", ""))
		var index := CompilerScript.history_index_for(
			player_state.get("history_ids", []),
			line_ids,
			jump_key,
			str(hit.get("file_uid", ""))
		)
		travel_requested.emit({
			"id": str(hit.get("node_id", "")),
			"jump_key": jump_key,
			"file_path": str(hit.get("file_path", "")),
			"title": str(hit.get("title", "")),
			"history_index": index,
		})
		return
	var dest := str(hit.get("jump_to", ""))
	if dest != "" and node_by_id.has(dest):
		pan_to(dest)
