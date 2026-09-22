class_name RouteGraphMeshBuilder
# CPU mesh builder: builds quad soup for single-pass renderer
# Vertices carry position + uv + color, uploaded once

var vertices: PackedVector3Array
var uvs: PackedVector2Array
var colors: PackedColorArray
var indices: PackedInt32Array

var _atlas: RouteGraphAtlas
var _white_uv: Rect2

# Hit test data
var port_hits: Array[Dictionary] = [] # {rect, target_id, source_id, type}
var edge_hits: Array[Dictionary] = [] # {a,b, target_id, furthest_id, rect}

var _node_by_id: Dictionary = {}

func _init(atlas: RouteGraphAtlas):
	_atlas = atlas
	_white_uv = atlas.white_uv
	vertices = PackedVector3Array()
	uvs = PackedVector2Array()
	colors = PackedColorArray()
	indices = PackedInt32Array()

func clear():
	vertices.clear()
	uvs.clear()
	colors.clear()
	indices.clear()
	port_hits.clear()
	edge_hits.clear()

func add_quad(pos: Vector2, size: Vector2, uv_rect: Rect2, color: Color) -> void:
	var base: int = vertices.size()
	# 2 triangles = 6 vertices (or 4 vertices with indices, but we use 6 for simplicity)
	# Triangle 1: TL, BL, BR
	# Triangle 2: TL, BR, TR
	var tl: Vector2 = pos
	var bl: Vector2 = pos + Vector2(0, size.y)
	var br: Vector2 = pos + size
	var tr: Vector2 = pos + Vector2(size.x, 0)

	var uv_tl: Vector2 = uv_rect.position
	var uv_bl: Vector2 = uv_rect.position + Vector2(0, uv_rect.size.y)
	var uv_br: Vector2 = uv_rect.position + uv_rect.size
	var uv_tr: Vector2 = uv_rect.position + Vector2(uv_rect.size.x, 0)

	# tri1
	vertices.append(Vector3(tl.x, tl.y, 0)); uvs.append(uv_tl); colors.append(color)
	vertices.append(Vector3(bl.x, bl.y, 0)); uvs.append(uv_bl); colors.append(color)
	vertices.append(Vector3(br.x, br.y, 0)); uvs.append(uv_br); colors.append(color)
	# tri2
	vertices.append(Vector3(tl.x, tl.y, 0)); uvs.append(uv_tl); colors.append(color)
	vertices.append(Vector3(br.x, br.y, 0)); uvs.append(uv_br); colors.append(color)
	vertices.append(Vector3(tr.x, tr.y, 0)); uvs.append(uv_tr); colors.append(color)

func add_triangle(p1: Vector2, p2: Vector2, p3: Vector2, uv_rect: Rect2, color: Color) -> void:
	# uv mapping: use center of white pixel for all
	var uv_c: Vector2 = uv_rect.get_center()
	vertices.append(Vector3(p1.x, p1.y, 0)); uvs.append(uv_c); colors.append(color)
	vertices.append(Vector3(p2.x, p2.y, 0)); uvs.append(uv_c); colors.append(color)
	vertices.append(Vector3(p3.x, p3.y, 0)); uvs.append(uv_c); colors.append(color)

func add_line(a: Vector2, b: Vector2, thickness: float, uv_rect: Rect2, color: Color) -> void:
	var dir: Vector2 = b - a
	var len: float = dir.length()
	if len < 0.001:
		return
	dir = dir / len
	var perp: Vector2 = Vector2(-dir.y, dir.x) * thickness * 0.5
	var p1: Vector2 = a + perp
	var p2: Vector2 = a - perp
	var p3: Vector2 = b - perp
	var p4: Vector2 = b + perp
	# quad as 2 tris
	var uv_tl: Vector2 = uv_rect.position
	var uv_bl: Vector2 = uv_rect.position + Vector2(0, uv_rect.size.y)
	var uv_br: Vector2 = uv_rect.position + uv_rect.size
	var uv_tr: Vector2 = uv_rect.position + Vector2(uv_rect.size.x, 0)

	var base: int = vertices.size()
	vertices.append(Vector3(p1.x, p1.y, 0)); uvs.append(uv_tl); colors.append(color)
	vertices.append(Vector3(p2.x, p2.y, 0)); uvs.append(uv_bl); colors.append(color)
	vertices.append(Vector3(p3.x, p3.y, 0)); uvs.append(uv_br); colors.append(color)

	vertices.append(Vector3(p1.x, p1.y, 0)); uvs.append(uv_tl); colors.append(color)
	vertices.append(Vector3(p3.x, p3.y, 0)); uvs.append(uv_br); colors.append(color)
	vertices.append(Vector3(p4.x, p4.y, 0)); uvs.append(uv_tr); colors.append(color)

func build(nodes: Array, edges: Array) -> ArrayMesh:
	clear()
	_node_by_id.clear()
	for n in nodes:
		_node_by_id[n.id] = n

	# Precompute furthest for each edge
	var furthest_map: Dictionary = {}
	for e in edges:
		furthest_map[e.source_id + "->" + e.target_id + str(e.source_out_idx)] = _find_furthest(e.target_id)

	# Edges first (behind)
	for e in edges:
		var a: Vector2 = Vector2(e.source_x, e.source_y)
		var b: Vector2 = Vector2(e.target_x, e.target_y)
		var col: Color
		match e.source_type:
			"FLOW": col = Color("#E2E8F0")
			"STORY": col = Color("#38BDF8")
			"CHOICE": col = Color("#FBBF24")
			_: col = Color("#A78BFA")
		if e.is_false:
			col.a = 0.7
		# straight line
		add_line(a, b, 2.5, _white_uv, col)

		# arrowhead at b
		var dir: Vector2 = (b - a).normalized()
		var perp: Vector2 = Vector2(-dir.y, dir.x)
		var arrow_len: float = 10
		var arrow_w: float = 6
		var tip: Vector2 = b
		var base1: Vector2 = b - dir * arrow_len + perp * arrow_w
		var base2: Vector2 = b - dir * arrow_len - perp * arrow_w
		add_triangle(tip, base1, base2, _white_uv, col)

		# hit test for edge: bounding rect expanded + line segment
		var minx: float = min(a.x, b.x) - 8
		var maxx: float = max(a.x, b.x) + 8
		var miny: float = min(a.y, b.y) - 8
		var maxy: float = max(a.y, b.y) + 8
		edge_hits.append({
			"a": a, "b": b,
			"rect": Rect2(Vector2(minx, miny), Vector2(maxx-minx, maxy-miny)),
			"target_id": e.target_id,
			"furthest_id": furthest_map[e.source_id + "->" + e.target_id + str(e.source_out_idx)],
			"source_id": e.source_id
		})

	# Nodes
	for n in nodes:
		var x: float = n.x
		var y: float = n.y
		var w: float = n.w
		var h: float = n.h
		var col_bg: Color = Color("#131B2E")
		var col_header: Color = n.color

		# main body
		add_quad(Vector2(x,y), Vector2(w,h), _white_uv, col_bg)
		# header
		add_quad(Vector2(x,y), Vector2(w,30), _white_uv, col_header)

		# port columns background lines? we draw as thin rects using white pixel with dark color
		# horizontal separator at 78
		add_quad(Vector2(x, y+78), Vector2(w,1), _white_uv, Color("#1E293B"))
		# vertical divider
		add_quad(Vector2(x+w*0.5, y+78), Vector2(1, h-78), _white_uv, Color("#1E293B", 0.8))

	# Second pass for text and port shapes (on top of rects)
	for n in nodes:
		var x: float = n.x
		var y: float = n.y
		var w: float = n.w
		var h: float = n.h

		# title
		var title_key: String = n.title + "_title"
		if not _atlas.uvs.has(title_key):
			title_key = n.title
		if _atlas.uvs.has(title_key):
			var uv: Rect2 = _atlas.get_uv(title_key)
			var sz: Vector2 = _atlas.get_size(title_key)
			add_quad(Vector2(x+12, y+20), sz, uv, Color.WHITE)

		# subtitle
		var sub_key: String = n.subtitle
		if _atlas.uvs.has(sub_key):
			var uv: Rect2 = _atlas.get_uv(sub_key)
			var sz: Vector2 = _atlas.get_size(sub_key)
			add_quad(Vector2(x+12, y+40), sz, uv, Color("#94A3B8"))

		# type/id header text (small)
		var header_txt: String = n.type + " • " + n.id
		if _atlas.uvs.has(header_txt):
			var uv: Rect2 = _atlas.get_uv(header_txt)
			var sz: Vector2 = _atlas.get_size(header_txt)
			add_quad(Vector2(x+12, y+6), sz, uv, Color.WHITE)

		# ports
		var num_in: int = n.inputs.size()
		var num_out: int = n.outputs.size()
		var rows: int = max(num_in, num_out)
		if rows == 0:
			rows = 1
		var row_h: float = 46.0 # consistent for alignment
		var base_y: float = y + 90.0

		for i in range(rows):
			if i < num_in:
				var inp: Dictionary = n.inputs[i]
				var py: float = base_y + i*row_h + 14.0
				var sx_shape: float = x + 14.0
				# shape
				var shape_kind: String = "FLOW"
				match inp.type:
					"FLOW": shape_kind = "FLOW"
					"STORY": shape_kind = "STORY"
					"CHOICE": shape_kind = "CHOICE"
					_: shape_kind = "BOOL"
				var shape_uv: Rect2 = _atlas.shape_uvs.get(shape_kind, _white_uv)
				var shape_col: Color = Color.WHITE
				match inp.type:
					"FLOW": shape_col = Color.WHITE
					"STORY": shape_col = Color("#38BDF8")
					"CHOICE": shape_col = Color("#FBBF24")
					_: shape_col = Color("#A78BFA")
				add_quad(Vector2(sx_shape-6, py-6), Vector2(12,12), shape_uv, shape_col)

				# label
				var lbl: String = inp.label
				if _atlas.uvs.has(lbl):
					var uv: Rect2 = _atlas.get_uv(lbl)
					var sz: Vector2 = _atlas.get_size(lbl)
					add_quad(Vector2(x+26, py-4), sz, uv, Color("#CBD5E1"))

				# tag
				var tag: String = inp.tag
				if _atlas.uvs.has(tag):
					var uv: Rect2 = _atlas.get_uv(tag)
					var sz: Vector2 = _atlas.get_size(tag)
					add_quad(Vector2(x+26, py-16), sz, uv, Color("#64748B"))

				# cond badge
				var cond: String = inp.get("cond","")
				if cond != "" and _atlas.uvs.has(cond):
					# badge bg
					var bw: float = _atlas.get_size(cond).x + 12
					add_quad(Vector2(x+26, py+8), Vector2(bw, 13), _white_uv, Color("#1E1B4B"))
					var uv: Rect2 = _atlas.get_uv(cond)
					var sz: Vector2 = _atlas.get_size(cond)
					add_quad(Vector2(x+32, py+8), sz, uv, Color("#C4B5FD"))

				# hit rect for input port
				var hit_rect: Rect2 = Rect2(Vector2(x, py-12), Vector2(w*0.5, row_h))
				port_hits.append({
					"rect": hit_rect,
					"target_id": inp.get("source",""),
					"source_id": n.id,
					"type": "in",
					"port_idx": i
				})

			if i < num_out:
				var outp: Dictionary = n.outputs[i]
				var py: float = base_y + i*row_h + 14.0
				var sx_shape: float = x + w - 14.0
				var shape_kind: String = "FLOW"
				match outp.type:
					"FLOW": shape_kind = "FLOW"
					"STORY": shape_kind = "STORY"
					"CHOICE": shape_kind = "CHOICE"
					_: shape_kind = "BOOL"
				var shape_uv: Rect2 = _atlas.shape_uvs.get(shape_kind, _white_uv)
				var shape_col: Color = Color.WHITE
				match outp.type:
					"FLOW": shape_col = Color.WHITE
					"STORY": shape_col = Color("#38BDF8")
					"CHOICE": shape_col = Color("#FBBF24")
					_: shape_col = Color("#A78BFA")
				add_quad(Vector2(sx_shape-6, py-6), Vector2(12,12), shape_uv, shape_col)

				var lbl: String = outp.label
				if _atlas.uvs.has(lbl):
					var uv: Rect2 = _atlas.get_uv(lbl)
					var sz: Vector2 = _atlas.get_size(lbl)
					add_quad(Vector2(x+w-26 - sz.x, py-4), sz, uv, Color("#CBD5E1"))

				var tag: String = outp.tag
				if _atlas.uvs.has(tag):
					var uv: Rect2 = _atlas.get_uv(tag)
					var sz: Vector2 = _atlas.get_size(tag)
					add_quad(Vector2(x+w-26 - sz.x, py-16), sz, uv, Color("#94A3B8"))

				var cond: String = outp.get("cond","")
				if cond != "" and _atlas.uvs.has(cond):
					var bw: float = _atlas.get_size(cond).x + 12
					add_quad(Vector2(x+w-26 - bw, py+8), Vector2(bw, 13), _white_uv, Color("#1E1B4B"))
					var uv: Rect2 = _atlas.get_uv(cond)
					var sz: Vector2 = _atlas.get_size(cond)
					add_quad(Vector2(x+w-26 - bw + 6, py+8), sz, uv, Color("#FDE68A"))

				# hit rect for output port
				var hit_rect: Rect2 = Rect2(Vector2(x+w*0.5, py-12), Vector2(w*0.5, row_h))
				port_hits.append({
					"rect": hit_rect,
					"target_id": outp.target,
					"source_id": n.id,
					"type": "out",
					"port_idx": i
				})

	# Build mesh
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	# indices not needed, we already have 6 verts per quad

	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _find_furthest(start_id: String) -> String:
	# Follow first output recursively until ending (0 outputs)
	var cur: String = start_id
	var visited: Dictionary = {}
	var steps: int = 0
	while steps < 20:
		if visited.has(cur):
			break
		visited[cur] = true
		var node: Dictionary = _node_by_id.get(cur, {})
		if node.is_empty():
			break
		var outs: Array = node.get("outputs", [])
		if outs.is_empty():
			break
		cur = outs[0].target
		steps += 1
	return cur
