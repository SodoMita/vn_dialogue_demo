extends Control
# Route graph view: single-pass renderer with texture atlas, 1 texture fetch, no loops/branches in shader
# - CPU builds quad soup (nodes, ports, straight edges)
# - Atlas holds glyphs + shape icons + white pixel
# - Clicking on port -> other side, clicking on edge -> furthest node
# - Pan/drag + zoom wheel
# - Data source: runtime compile of dialogue/*.dialogue (if available) else static mockup

@export var dialogue_resource: DialogueResource = preload("res://dialogue/intro.dialogue")

var atlas: RouteGraphAtlas
var mesh_builder: RouteGraphMeshBuilder
var mesh_instance: MeshInstance2D
var route_material: ShaderMaterial

var nodes: Array
var edges: Array
var node_by_id: Dictionary = {}

var pan: Vector2 = Vector2(0,0)
var zoom: float = 0.85
var target_pan: Vector2 = Vector2(0,0)
var target_zoom: float = 0.85

var dragging: bool = false
var drag_start_mouse: Vector2
var drag_start_pan: Vector2

func _ready() -> void:
	# Load data: try runtime compile from dialogue, fallback to static v4
	var compiled: Dictionary = {}
	if dialogue_resource != null and ResourceLoader.exists(dialogue_resource.resource_path):
		compiled = RouteGraphCompiler.compile(dialogue_resource)
		nodes = compiled.get("nodes", [])
		if nodes.is_empty():
			nodes = RouteGraphData.get_nodes()
	else:
		nodes = RouteGraphData.get_nodes()

	node_by_id.clear()
	for n in nodes:
		node_by_id[n.id] = n

	# Build edges from nodes
	edges = _build_edges(nodes)

	# Prepare atlas entries: collect all strings that will be displayed
	var entries: Array = []
	var seen: Dictionary = {}
	# helper to add
	var add_entry = func(key: String, text: String, size: int):
		if text == "" or seen.has(key):
			return
		seen[key] = true
		entries.append({"key": key, "text": text, "size": size})

	for n in nodes:
		var header_txt: String = n.type + " • " + n.id
		add_entry.call(n.id + "_header", header_txt, 10)
		add_entry.call(header_txt, header_txt, 10)
		add_entry.call(n.title + "_title", n.title, 16)
		add_entry.call(n.title, n.title, 14)
		add_entry.call(n.subtitle, n.subtitle, 11)
		add_entry.call(n.type, n.type, 10)
		for inp in n.inputs:
			add_entry.call(inp.label, inp.label, 11)
			add_entry.call(inp.tag, inp.tag, 9)
			if inp.get("cond","") != "":
				add_entry.call(inp.cond, inp.cond, 9)
		for outp in n.outputs:
			add_entry.call(outp.label, outp.label, 11)
			add_entry.call(outp.tag, outp.tag, 9)
			if outp.get("cond","") != "":
				add_entry.call(outp.cond, outp.cond, 9)

	# Add common UI strings
	add_entry.call("IN", "IN", 9)
	add_entry.call("OUT", "OUT", 9)

	atlas = RouteGraphAtlas.new()
	await atlas.bake_with_sizes(entries)

	# Build mesh
	mesh_builder = RouteGraphMeshBuilder.new(atlas)
	var mesh: ArrayMesh = mesh_builder.build(nodes, edges)

	# Create MeshInstance2D
	mesh_instance = MeshInstance2D.new()
	mesh_instance.mesh = mesh
	add_child(mesh_instance)

	# Material with shader, single texture fetch
	var shader: Shader = load("res://scenes/route_graph/route_graph.gdshader")
	route_material = ShaderMaterial.new()
	route_material.shader = shader
	route_material.set_shader_parameter("atlas", atlas.texture)
	route_material.set_shader_parameter("pan", pan)
	route_material.set_shader_parameter("zoom", zoom)
	mesh_instance.material = route_material

	# Initial pan to show center
	pan = Vector2(-200, -50)
	target_pan = pan
	_update_shader_params()

	# Enable input
	mouse_filter = Control.MOUSE_FILTER_STOP

func _build_edges(nodes_arr: Array) -> Array:
	var by_id: Dictionary = {}
	for n in nodes_arr:
		by_id[n.id] = n
	var port_pos: Dictionary = {}
	for n in nodes_arr:
		var num_in: int = n.inputs.size()
		var num_out: int = n.outputs.size()
		var rows: int = max(num_in, num_out)
		if rows == 0:
			rows = 1
		var row_h: float = 46.0 # consistent for all nodes to keep edges aligned
		var base_y: float = n.y + 90.0
		var ins: Array = []
		var outs: Array = []
		for i in range(rows):
			var py: float = base_y + i*row_h + 14.0
			if i < num_in:
				ins.append(py)
			if i < num_out:
				outs.append(py)
		port_pos[n.id] = {"in_y": ins, "out_y": outs, "base": base_y, "row_h": row_h}

	var result: Array = []
	for n in nodes_arr:
		for oi in range(n.outputs.size()):
			var outp: Dictionary = n.outputs[oi]
			var target_id: String = outp.target
			var tgt: Dictionary = by_id.get(target_id, {})
			if tgt.is_empty():
				continue
			# find input index
			var in_idx: int = 0
			var existing: int = 0
			for e in result:
				if e.source_id == n.id and e.target_id == target_id:
					existing += 1
			var count: int = 0
			var found: bool = false
			for ii in range(tgt.inputs.size()):
				if tgt.inputs[ii].get("source","") == n.id:
					if count == existing:
						in_idx = ii
						found = true
						break
					count += 1
			if not found:
				for ii in range(tgt.inputs.size()):
					var used: bool = false
					for e in result:
						if e.target_id == target_id and e.target_in_idx == ii:
							used = true
							break
					if not used:
						in_idx = ii
						break
			var src_y: float = port_pos[n.id].out_y[oi] if oi < port_pos[n.id].out_y.size() else port_pos[n.id].base
			var tgt_y: float = port_pos[target_id].in_y[in_idx] if in_idx < port_pos[target_id].in_y.size() else port_pos[target_id].base
			result.append({
				"source_id": n.id,
				"source_out_idx": oi,
				"source_type": outp.type,
				"source_x": n.x + n.w,
				"source_y": src_y,
				"target_id": target_id,
				"target_in_idx": in_idx,
				"target_x": tgt.x,
				"target_y": tgt_y,
				"label": outp.label,
				"tag": outp.tag,
				"cond": outp.get("cond",""),
				"full_dest": outp.full_dest,
				"is_false": outp.get("cond","").contains("false")
			})
	return result

func _update_shader_params() -> void:
	if route_material:
		route_material.set_shader_parameter("pan", pan)
		route_material.set_shader_parameter("zoom", zoom)

func _process(delta: float) -> void:
	# smooth pan/zoom lerp
	var lerp_speed: float = 8.0 * delta
	pan = pan.lerp(target_pan, clamp(lerp_speed, 0, 1))
	zoom = lerp(zoom, target_zoom, clamp(lerp_speed, 0, 1))
	_update_shader_params()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				dragging = true
				drag_start_mouse = mb.position
				drag_start_pan = target_pan
				# check click on port / edge
				var local: Vector2 = (mb.position / zoom) - pan
				# ports first
				for hit in mesh_builder.port_hits:
					if hit.rect.has_point(local):
						var other_id: String = hit.target_id
						if other_id != "" and node_by_id.has(other_id):
							_pan_to_node(other_id)
							get_viewport().set_input_as_handled()
							return
				# edges
				for hit in mesh_builder.edge_hits:
					if hit.rect.has_point(local):
						# distance to segment
						var dist: float = _dist_to_segment(local, hit.a, hit.b)
						if dist < 12.0:
							var furthest: String = hit.furthest_id
							if furthest == "":
								furthest = hit.target_id
							_pan_to_node(furthest)
							get_viewport().set_input_as_handled()
							return
			else:
				dragging = false
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			target_zoom = clamp(target_zoom * 1.1, 0.3, 2.5)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			target_zoom = clamp(target_zoom / 1.1, 0.3, 2.5)
			get_viewport().set_input_as_handled()

	if event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		if dragging:
			var delta: Vector2 = (mm.position - drag_start_mouse) / zoom
			target_pan = drag_start_pan + delta
			get_viewport().set_input_as_handled()

func _pan_to_node(node_id: String) -> void:
	if not node_by_id.has(node_id):
		return
	var n: Dictionary = node_by_id[node_id]
	var node_center: Vector2 = Vector2(n.x + n.w*0.5, n.y + n.h*0.5)
	var viewport_size: Vector2 = get_viewport_rect().size
	# center node in view: pan = viewport_center/zoom - node_center
	var view_center: Vector2 = viewport_size * 0.5 / zoom
	target_pan = view_center - node_center

	# flash highlight? we could modulate material for a moment, but keep simple
	# print
	print("RouteGraph: pan to ", node_id)

func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var ap: Vector2 = p - a
	var ab_len2: float = ab.length_squared()
	if ab_len2 == 0:
		return ap.length()
	var t: float = clamp(ap.dot(ab) / ab_len2, 0.0, 1.0)
	var proj: Vector2 = a + ab * t
	return p.distance_to(proj)

func rebuild() -> void:
	if atlas == null:
		return
	var mesh: ArrayMesh = mesh_builder.build(nodes, edges)
	mesh_instance.mesh = mesh
