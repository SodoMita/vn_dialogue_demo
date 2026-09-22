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
var _fitted := false
var visited_only := true
var player_state: Dictionary = {}
var current_id := ""
var atlas_resolution := 1024


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


func set_atlas_resolution(size: int, rebuild: bool = true) -> void:
	var next := clampi(int(round(float(size) / 64.0)) * 64, 128, 4096)
	var changed := next != atlas_resolution
	atlas_resolution = next
	if rebuild and changed and not full_nodes.is_empty():
		_upload()


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
	atlas.bake(keys, atlas_resolution)
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
	var shader = load("res://scenes/route_graph/route_graph.gdshader")
	if shader != null:
		route_material.shader = shader
	mesh_instance.material = route_material


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


func _to_graph(local: Vector2) -> Vector2:
	return local / zoom - pan


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_WHEEL_UP and button.pressed:
			_zoom_at(button.position, 1.12)
			accept_event()
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN and button.pressed:
			_zoom_at(button.position, 1.0 / 1.12)
			accept_event()
		elif button.button_index == MOUSE_BUTTON_LEFT or button.button_index == MOUSE_BUTTON_MIDDLE:
			if button.pressed:
				dragging = true
				_moved = false
				_press_local = button.position
				_press_graph = _to_graph(button.position)
			else:
				dragging = false
				if not _moved and button.button_index == MOUSE_BUTTON_LEFT:
					_activate_at(_press_graph)
			accept_event()
	elif event is InputEventMouseMotion and dragging:
		var motion := event as InputEventMouseMotion
		if motion.position.distance_to(_press_local) > 4.0:
			_moved = true
		pan = motion.position / zoom - _press_graph
		target_pan = pan
		sync_shader()
		accept_event()


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
