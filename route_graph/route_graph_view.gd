class_name RouteGraphView extends Control
## One-draw-call route-graph view. The CPU owns the atlas + ArrayMesh; a
## single canvas_item shader samples it and applies pan/zoom uniforms.
## No per-node CanvasItems are created.


signal node_clicked(id: String)

const ZOOM_MIN := 0.25
const ZOOM_MAX := 3.0

var graph: RouteGraph
var atlas: RouteGraphAtlas
var mesh_builder: RouteGraphMeshBuilder
var mesh: ArrayMesh
var atlas_texture: Texture2D
var pan: Vector2 = Vector2.ZERO
var zoom: float = 1.0
var current_id: String = ""
var seen_ids: Dictionary = {}

var _dragging: bool = false
var _shader_mat: ShaderMaterial
var _built_for: String = ""


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_shader_mat = ShaderMaterial.new()
	_shader_mat.shader = load("res://route_graph/route_graph.gdshader")
	material = _shader_mat
	resized.connect(_on_resized)


func load_dialogue(resource: DialogueResource, thumbs: Dictionary = {}) -> void:
	var path := resource.resource_path if resource != null else ""
	if _built_for == path and graph != null and mesh != null:
		return
	graph = RouteGraphCompiler.from_resource(resource)
	RouteGraphLayout.apply(graph)
	atlas = RouteGraphAtlas.new()
	atlas_texture = atlas.bake(graph, thumbs)
	mesh_builder = RouteGraphMeshBuilder.new()
	mesh = mesh_builder.build(graph, atlas, seen_ids, current_id)
	_built_for = path
	_fit()
	_push_uniforms()
	queue_redraw()


func load_graph(g: RouteGraph, thumbs: Dictionary = {}) -> void:
	graph = g
	RouteGraphLayout.apply(graph)
	atlas = RouteGraphAtlas.new()
	atlas_texture = atlas.bake(graph, thumbs)
	mesh_builder = RouteGraphMeshBuilder.new()
	mesh = mesh_builder.build(graph, atlas, seen_ids, current_id)
	_built_for = graph.source_path
	_fit()
	_push_uniforms()
	queue_redraw()


func set_progress(seen: Dictionary, current: String) -> void:
	seen_ids = seen
	current_id = current
	if graph == null or atlas == null:
		return
	if mesh_builder == null:
		mesh_builder = RouteGraphMeshBuilder.new()
	mesh = mesh_builder.build(graph, atlas, seen_ids, current_id)
	queue_redraw()


func _draw() -> void:
	_push_uniforms()
	if mesh != null and atlas_texture != null:
		draw_mesh(mesh, atlas_texture)


func _push_uniforms() -> void:
	if _shader_mat == null:
		return
	_shader_mat.set_shader_parameter("u_pan", pan)
	_shader_mat.set_shader_parameter("u_zoom", zoom)
	_shader_mat.set_shader_parameter("u_origin", size * 0.5)


func _fit() -> void:
	if graph == null or size.x < 8.0 or size.y < 8.0:
		return
	var b := graph.bounds()
	var zx: float = size.x / maxf(1.0, b.size.x)
	var zy: float = size.y / maxf(1.0, b.size.y)
	zoom = clampf(minf(zx, zy) * 0.92, ZOOM_MIN, 1.4)
	var origin := size * 0.5
	var graph_center := b.position + b.size * 0.5
	# screen = (graph - origin) * zoom + origin + pan; want graph_center -> origin
	pan = (origin - graph_center) * zoom


func _on_resized() -> void:
	_push_uniforms()
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(mb.position, 1.12)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(mb.position, 1.0 / 1.12)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				var id := hit_node(mb.position)
				if not id.is_empty():
					node_clicked.emit(id)
					accept_event()
				else:
					_dragging = true
					accept_event()
			else:
				_dragging = false
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = mb.pressed
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		pan += mm.relative
		_push_uniforms()
		queue_redraw()
		accept_event()


func _zoom_at(screen_pt: Vector2, factor: float) -> void:
	var origin := size * 0.5
	var graph_pt := screen_to_graph(screen_pt)
	zoom = clampf(zoom * factor, ZOOM_MIN, ZOOM_MAX)
	# Keep graph_pt under screen_pt: screen = (graph - origin) * zoom + origin + pan
	pan = screen_pt - (graph_pt - origin) * zoom - origin
	_push_uniforms()
	queue_redraw()


func screen_to_graph(screen_pt: Vector2) -> Vector2:
	var origin := size * 0.5
	return (screen_pt - origin - pan) / zoom + origin


func hit_node(screen_pt: Vector2) -> String:
	if graph == null:
		return ""
	var p := screen_to_graph(screen_pt)
	var found := ""
	for n: RouteGraph.RouteNode in graph.nodes:
		if Rect2(n.position, n.size).has_point(p):
			found = n.id
	return found
