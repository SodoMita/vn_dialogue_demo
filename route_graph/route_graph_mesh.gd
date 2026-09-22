class_name RouteGraphMeshBuilder extends RefCounted
## Builds one ArrayMesh of atlas-sampled quads / arrow ribbons.
## Vertices carry position + uv only. Rebuilt when the graph or highlight set
## changes; pan/zoom stays on the shader.


const EDGE_WIDTH := 2.4
const EDGE_SAMPLES := 14
const PORT_R := 5.5
const BORDER := 2.0
const TITLE_H := 22.0


var vertex_count: int = 0
var triangle_count: int = 0
var surface_count: int = 0

var _verts := PackedVector2Array()
var _uvs := PackedVector2Array()
var _indices := PackedInt32Array()


func build(graph: RouteGraph, atlas: RouteGraphAtlas, seen_ids: Dictionary = {}, current_id: String = "") -> ArrayMesh:
	_verts = PackedVector2Array()
	_uvs = PackedVector2Array()
	_indices = PackedInt32Array()
	vertex_count = 0
	triangle_count = 0

	# Edges first so node bodies paint over the ribbons.
	for e: RouteGraph.RouteEdge in graph.edges:
		_emit_edge(graph, atlas, e)

	for n: RouteGraph.RouteNode in graph.nodes:
		_emit_node(atlas, n, seen_ids, current_id)

	var mesh := ArrayMesh.new()
	if _verts.is_empty():
		surface_count = 0
		return mesh
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	arrays[Mesh.ARRAY_INDEX] = _indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	surface_count = mesh.get_surface_count()
	vertex_count = _verts.size()
	triangle_count = _indices.size() / 3
	return mesh


func _emit_node(atlas: RouteGraphAtlas, n: RouteGraph.RouteNode, seen_ids: Dictionary, current_id: String) -> void:
	var r := Rect2(n.position, n.size)
	var fill := "swatch_%s" % n.kind
	if not atlas.has(fill):
		fill = "swatch_dialogue"
	var border := "swatch_gold" if n.id == current_id else "swatch_border"
	var bw := 3.0 if n.id == current_id else BORDER
	_quad(r.grow(bw), atlas.uv_rect(border))
	_quad(r, atlas.uv_rect(fill))
	_quad(Rect2(r.position, Vector2(r.size.x, TITLE_H)), atlas.uv_rect("swatch_title"))

	var thumb_name := ""
	if not n.sprite_key.is_empty() and atlas.has(atlas.thumb_key(n.sprite_key)):
		thumb_name = atlas.thumb_key(n.sprite_key)
	elif not n.bg_key.is_empty() and atlas.has(atlas.thumb_key(n.bg_key)):
		thumb_name = atlas.thumb_key(n.bg_key)
	if not thumb_name.is_empty():
		_quad(Rect2(r.position + Vector2(6, TITLE_H + 4), Vector2(RouteGraphAtlas.THUMB_W, RouteGraphAtlas.THUMB_H)), atlas.uv_rect(thumb_name))

	_emit_label(atlas, n.title, r.position + Vector2(8, 4), r.size.x - 16)
	var body := RouteGraphAtlas._ellipsis(n.body, 42)
	if not body.is_empty():
		var body_x := 8.0 + (float(RouteGraphAtlas.THUMB_W) + 6.0 if not thumb_name.is_empty() else 0.0)
		_emit_label(atlas, body, r.position + Vector2(body_x, TITLE_H + 8), r.size.x - body_x - 8)

	for p: RouteGraph.RoutePort in n.inputs:
		_emit_port(atlas, n.position + p.offset, false)
	for p: RouteGraph.RoutePort in n.outputs:
		_emit_port(atlas, n.position + p.offset, true)
		if p.label != "out" and p.label != "in":
			var lp := n.position + p.offset + Vector2(-60, -10)
			_emit_label(atlas, p.label, lp, 56)

	if not seen_ids.is_empty() and not seen_ids.has(n.id) and n.id != current_id and n.kind != "end":
		_quad(r, atlas.uv_rect("swatch_dim"))


func _emit_port(atlas: RouteGraphAtlas, center: Vector2, is_output: bool) -> void:
	var name := "circle_out" if is_output else "circle_in"
	var d := PORT_R * 2.0
	_quad(Rect2(center - Vector2(PORT_R, PORT_R), Vector2(d, d)), atlas.uv_rect(name))


func _emit_edge(graph: RouteGraph, atlas: RouteGraphAtlas, e: RouteGraph.RouteEdge) -> void:
	var src: RouteGraph.RouteNode = graph.get_node(e.from_id)
	var dst: RouteGraph.RouteNode = graph.get_node(e.to_id)
	if src == null or dst == null:
		return
	var p0 := graph.port_position(src, e.from_port, true)
	var p3 := graph.port_position(dst, e.to_port, false)
	var dx := clampf((p3.x - p0.x) * 0.45, 48.0, 160.0)
	var p1 := p0 + Vector2(dx, 0)
	var p2 := p3 - Vector2(dx, 0)
	var swatch := "swatch_edge"
	if e.kind == "choice":
		swatch = "swatch_edge_choice"
	elif e.kind == "condition":
		swatch = "swatch_edge_condition"
	var uv := atlas.uv_rect(swatch)
	var pts := PackedVector2Array()
	for i in EDGE_SAMPLES:
		var t := float(i) / float(EDGE_SAMPLES - 1)
		pts.append(_cubic(p0, p1, p2, p3, t))
	for i in pts.size() - 1:
		_ribbon_segment(pts[i], pts[i + 1], EDGE_WIDTH, uv)
	_arrow_head(pts[pts.size() - 2], pts[pts.size() - 1], uv)
	if not e.label.is_empty():
		var mid := _cubic(p0, p1, p2, p3, 0.5)
		_emit_label(atlas, RouteGraphAtlas._ellipsis(e.label, 36), mid + Vector2(-40, -14), 80)


func _emit_label(atlas: RouteGraphAtlas, text: String, pos: Vector2, max_width: float) -> void:
	if text.is_empty():
		return
	var key := atlas.label_key(text)
	if not atlas.has(key):
		return
	var pr: Rect2i = atlas.pixel_rects.get(key, Rect2i())
	var w := float(pr.size.x)
	var h := float(pr.size.y)
	if max_width > 0.0:
		w = minf(w, max_width)
	_quad(Rect2(pos, Vector2(w, h)), atlas.uv_rect(key))


func _quad(rect: Rect2, uv: Rect2) -> void:
	var i := _verts.size()
	_verts.append(rect.position)
	_verts.append(rect.position + Vector2(rect.size.x, 0))
	_verts.append(rect.position + rect.size)
	_verts.append(rect.position + Vector2(0, rect.size.y))
	_uvs.append(uv.position)
	_uvs.append(uv.position + Vector2(uv.size.x, 0))
	_uvs.append(uv.position + uv.size)
	_uvs.append(uv.position + Vector2(0, uv.size.y))
	_indices.append(i)
	_indices.append(i + 1)
	_indices.append(i + 2)
	_indices.append(i)
	_indices.append(i + 2)
	_indices.append(i + 3)


func _ribbon_segment(a: Vector2, b: Vector2, width: float, uv: Rect2) -> void:
	var d := b - a
	if d.length_squared() < 0.0001:
		return
	var n := Vector2(-d.y, d.x).normalized() * (width * 0.5)
	var i := _verts.size()
	_verts.append(a - n)
	_verts.append(a + n)
	_verts.append(b + n)
	_verts.append(b - n)
	var mid := uv.position + uv.size * 0.5
	_uvs.append(mid)
	_uvs.append(mid)
	_uvs.append(mid)
	_uvs.append(mid)
	_indices.append(i)
	_indices.append(i + 1)
	_indices.append(i + 2)
	_indices.append(i)
	_indices.append(i + 2)
	_indices.append(i + 3)


func _arrow_head(from_pt: Vector2, tip: Vector2, uv: Rect2) -> void:
	var dir := tip - from_pt
	if dir.length_squared() < 0.0001:
		dir = Vector2.RIGHT
	dir = dir.normalized()
	var n := Vector2(-dir.y, dir.x)
	var back := tip - dir * 10.0
	var i := _verts.size()
	_verts.append(tip)
	_verts.append(back + n * 5.0)
	_verts.append(back - n * 5.0)
	var mid := uv.position + uv.size * 0.5
	_uvs.append(mid)
	_uvs.append(mid)
	_uvs.append(mid)
	_indices.append(i)
	_indices.append(i + 1)
	_indices.append(i + 2)


static func _cubic(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var u := 1.0 - t
	return p0 * (u * u * u) + p1 * (3.0 * u * u * t) + p2 * (3.0 * u * t * t) + p3 * (t * t * t)
