extends RefCounted
## CPU quad soup for the route graph. One mesh, straight edges, no grid.
## No class_name: a typed _init on a global class fails to parse when that
## class is missing from the UID class cache (route_graph_view.gd:90).


const PORT_TOP := 72.0
const ROW_H := 46.0
const PAD_BOTTOM := 14.0
const PORT_INSET := 16.0

var port_hits: Array = []
var edge_hits: Array = []
var _atlas = null
var _verts := PackedVector3Array()
var _uvs := PackedVector2Array()
var _cols := PackedColorArray()
var _white := Vector2.ZERO


static func measure_height(input_count: int, output_count: int) -> float:
	return PORT_TOP + float(maxi(1, maxi(input_count, output_count))) * ROW_H + PAD_BOTTOM


static func measure_width(node: Dictionary) -> float:
	var longest := str(node.get("title", "")).length()
	for side in ["inputs", "outputs"]:
		for port in node.get(side, []):
			longest = maxi(longest, str(port.get("tag", "")).length())
			longest = maxi(longest, mini(28, str(port.get("cond", "")).length()))
	return clampf(150.0 + float(longest) * 7.4, 230.0, 360.0)


static func port_center(node: Dictionary, is_output: bool, index: int) -> Vector2:
	var y := float(node.get("y", 0.0)) + PORT_TOP + float(index) * ROW_H + ROW_H * 0.5
	var x := float(node.get("x", 0.0)) + float(node.get("w", 0.0)) - PORT_INSET if is_output else float(node.get("x", 0.0)) + PORT_INSET
	return Vector2(x, y)


static func text_keys(nodes: Array) -> Array:
	var entries: Array = []
	for node in nodes:
		entries.append({"key": "title:%s" % node.get("id", ""), "text": str(node.get("title", "")), "size": 18})
		entries.append({"key": "sub:%s" % node.get("id", ""), "text": str(node.get("subtitle", "")), "size": 12})
		for side in ["inputs", "outputs"]:
			var ports: Array = node.get(side, [])
			for i in ports.size():
				var port: Dictionary = ports[i]
				entries.append({
					"key": "tag:%s:%s:%d" % [node.get("id", ""), side, i],
					"text": str(port.get("tag", "")),
					"size": 12,
				})
				var cond := str(port.get("cond", ""))
				if cond != "":
					entries.append({
						"key": "cond:%s:%s:%d" % [node.get("id", ""), side, i],
						"text": cond,
						"size": 10,
					})
	return entries


static func furthest_node(start_id: String, by_id: Dictionary) -> String:
	if not by_id.has(start_id):
		return start_id
	var best := start_id
	var best_depth := 0
	var origin := Vector2(float(by_id[start_id].get("x", 0.0)), float(by_id[start_id].get("y", 0.0)))
	var best_dist := 0.0
	var stack: Array = [{"id": start_id, "depth": 0, "path": {start_id: true}}]
	var guard := 0
	while not stack.is_empty() and guard < 8000:
		guard += 1
		var item: Dictionary = stack.pop_back()
		var id := str(item.get("id", ""))
		var depth := int(item.get("depth", 0))
		var node: Dictionary = by_id.get(id, {})
		var dist := Vector2(float(node.get("x", 0.0)), float(node.get("y", 0.0))).distance_to(origin)
		if depth > best_depth or (depth == best_depth and dist > best_dist + 0.5):
			best = id
			best_depth = depth
			best_dist = dist
		var path: Dictionary = item.get("path", {})
		for outp in node.get("outputs", []):
			var target := str(outp.get("target", ""))
			if target == "" or not by_id.has(target) or path.has(target):
				continue
			var next_path := path.duplicate()
			next_path[target] = true
			stack.append({"id": target, "depth": depth + 1, "path": next_path})
	return best


func build(atlas, nodes: Array) -> ArrayMesh:
	_atlas = atlas
	port_hits.clear()
	edge_hits.clear()
	_verts = PackedVector3Array()
	_uvs = PackedVector2Array()
	_cols = PackedColorArray()
	var white: Rect2 = atlas.white_uv()
	_white = white.position + white.size * 0.5
	var by_id := {}
	for node in nodes:
		by_id[str(node.get("id", ""))] = node
	_draw_edges(nodes, by_id)
	for node in nodes:
		_draw_node(node)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	arrays[Mesh.ARRAY_COLOR] = _cols
	var mesh := ArrayMesh.new()
	if _verts.size() >= 3:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# Shader pan/zoom moves vertices outside the raw graph AABB. A huge custom
	# AABB keeps the canvas item from being culled; the view clips to itself.
	mesh.set_custom_aabb(AABB(Vector3(-100000, -100000, -1), Vector3(200000, 200000, 2)))
	return mesh


func hit_test(graph_pos: Vector2) -> Dictionary:
	for hit in port_hits:
		if (hit.get("rect", Rect2()) as Rect2).has_point(graph_pos):
			return hit
	var best: Dictionary = {}
	var best_d := 9.0
	for hit in edge_hits:
		var dist := _dist_to_segment(graph_pos, hit.get("a", Vector2.ZERO), hit.get("b", Vector2.ZERO))
		if dist < best_d:
			best_d = dist
			best = hit
	return best


func _draw_edges(nodes: Array, by_id: Dictionary) -> void:
	for node in nodes:
		var used := {}
		var outputs: Array = node.get("outputs", [])
		for i in outputs.size():
			var outp: Dictionary = outputs[i]
			var target_id := str(outp.get("target", ""))
			if not by_id.has(target_id):
				continue
			var target: Dictionary = by_id[target_id]
			var input_index := _match_input(target, str(node.get("id", "")), outp, used)
			var a := port_center(node, true, i)
			var b := port_center(target, false, input_index)
			var color := _type_color(str(outp.get("type", "FLOW")))
			color.a = 0.92
			_line(a, b, 2.6, color)
			edge_hits.append({
				"a": a,
				"b": b,
				"jump_to": furthest_node(target_id, by_id),
				"kind": "edge",
				"source": str(node.get("id", "")),
				"target": target_id,
			})


func _draw_node(node: Dictionary) -> void:
	var rect := Rect2(float(node.get("x", 0.0)), float(node.get("y", 0.0)), float(node.get("w", 230.0)), float(node.get("h", 120.0)))
	var accent: Color = node.get("color", Color(0.2, 0.45, 0.5))
	_solid(rect, Color(0.055, 0.08, 0.14, 0.96))
	_solid(Rect2(rect.position, Vector2(rect.size.x, 4.0)), accent)
	var border := Color(accent.r, accent.g, accent.b, 0.9)
	_solid(Rect2(rect.position, Vector2(rect.size.x, 1.5)), border)
	_solid(Rect2(rect.position + Vector2(0, rect.size.y - 1.5), Vector2(rect.size.x, 1.5)), border)
	_solid(Rect2(rect.position, Vector2(1.5, rect.size.y)), border)
	_solid(Rect2(rect.position + Vector2(rect.size.x - 1.5, 0), Vector2(1.5, rect.size.y)), border)
	_text("title:%s" % node.get("id", ""), rect.position + Vector2(12, 10), Vector2(rect.size.x - 24, 22), Color.WHITE)
	_text("sub:%s" % node.get("id", ""), rect.position + Vector2(12, 34), Vector2(rect.size.x - 24, 16), Color(0.68, 0.75, 0.84, 1))
	_draw_ports(node, "inputs")
	_draw_ports(node, "outputs")


func _draw_ports(node: Dictionary, side: String) -> void:
	var is_output := side == "outputs"
	var ports: Array = node.get(side, [])
	var has_both: bool = node.get("inputs", []).size() > 0 and node.get("outputs", []).size() > 0
	var max_w := (float(node.get("w", 230.0)) - 48.0) * (0.55 if has_both else 0.92)
	for i in ports.size():
		var port: Dictionary = ports[i]
		var center := port_center(node, is_output, i)
		var kind := str(port.get("type", "FLOW"))
		var icon := Rect2(center - Vector2(7, 7), Vector2(14, 14))
		_quad(icon, _atlas.shape_uv(kind), _type_color(kind))
		var has_cond := str(port.get("cond", "")) != ""
		var tag_key := "tag:%s:%s:%d" % [node.get("id", ""), side, i]
		var tag_size := _fitted_size(tag_key, max_w, 14.0)
		var tag_y := center.y - tag_size.y - 1.0 if has_cond else center.y - tag_size.y * 0.5
		var tag_x := center.x - 12.0 - tag_size.x if is_output else float(node.get("x", 0.0)) + 24.0
		_quad(Rect2(Vector2(tag_x, tag_y), tag_size), _atlas.uv_of(tag_key), Color(0.9, 0.93, 1, 1))
		if has_cond:
			var cond_key := "cond:%s:%s:%d" % [node.get("id", ""), side, i]
			var cond_size := _fitted_size(cond_key, max_w, 12.0)
			var cond_x := center.x - 12.0 - cond_size.x if is_output else float(node.get("x", 0.0)) + 24.0
			_quad(Rect2(Vector2(cond_x, center.y + 1.0), cond_size), _atlas.uv_of(cond_key), Color(0.96, 0.78, 0.42, 1))
		var other := str(port.get("target", "")) if is_output else str(port.get("source", ""))
		if other == "":
			continue
		port_hits.append({
			"rect": Rect2(center - Vector2(14, 14), Vector2(28, 28)),
			"jump_to": other,
			"kind": "port",
		})


func _match_input(target: Dictionary, source_id: String, outp: Dictionary, used: Dictionary) -> int:
	var inputs: Array = target.get("inputs", [])
	for i in inputs.size():
		if used.has(i):
			continue
		var inp: Dictionary = inputs[i]
		if str(inp.get("source", "")) != source_id:
			continue
		if str(inp.get("tag", "")) == str(outp.get("tag", "")) and str(inp.get("cond", "")) == str(outp.get("cond", "")):
			used[i] = true
			return i
	for i in inputs.size():
		if used.has(i):
			continue
		if str(inputs[i].get("source", "")) == source_id:
			used[i] = true
			return i
	return 0


func _line(a: Vector2, b: Vector2, thickness: float, color: Color) -> void:
	var delta := b - a
	var length := delta.length()
	if length < 1.0:
		return
	var n := delta / length
	var p := Vector2(-n.y, n.x) * (thickness * 0.5)
	var start := a + n * 12.0
	var finish := b - n * 18.0
	if start.distance_to(finish) < 4.0:
		start = a
		finish = b
	_tri(start - p, start + p, finish + p, color)
	_tri(start - p, finish + p, finish - p, color)
	var tip := b - n * 8.0
	var base := tip - n * 12.0
	var wing := Vector2(-n.y, n.x) * 6.5
	_tri(tip, base + wing, base - wing, color)


func _fitted_size(key: String, max_w: float, max_h: float) -> Vector2:
	if _atlas == null:
		return Vector2.ZERO
	var px: Vector2 = _atlas.size_of(key)
	if px.x < 1.0 or px.y < 1.0:
		return Vector2.ZERO
	var scale := 1.0
	if px.x > max_w and max_w > 1.0:
		scale = max_w / px.x
	if px.y * scale > max_h and max_h > 1.0:
		scale = minf(scale, max_h / px.y)
	return px * scale


func _text(key: String, pos: Vector2, max_size: Vector2, color: Color) -> void:
	if _atlas == null:
		return
	var px: Vector2 = _atlas.size_of(key)
	if px.x < 1.0 or px.y < 1.0:
		return
	var scale := 1.0
	if px.x > max_size.x and max_size.x > 1.0:
		scale = max_size.x / px.x
	if px.y * scale > max_size.y and max_size.y > 1.0:
		scale = minf(scale, max_size.y / px.y)
	_quad(Rect2(pos, px * scale), _atlas.uv_of(key), color)


func _solid(rect: Rect2, color: Color) -> void:
	_tri(rect.position, rect.position + Vector2(rect.size.x, 0), rect.position + rect.size, color)
	_tri(rect.position, rect.position + rect.size, rect.position + Vector2(0, rect.size.y), color)


func _quad(rect: Rect2, uv: Rect2, color: Color) -> void:
	var a := rect.position
	var b := rect.position + Vector2(rect.size.x, 0)
	var c := rect.position + rect.size
	var d := rect.position + Vector2(0, rect.size.y)
	var uva := uv.position
	var uvb := uv.position + Vector2(uv.size.x, 0)
	var uvc := uv.position + uv.size
	var uvd := uv.position + Vector2(0, uv.size.y)
	_push(a, uva, color)
	_push(b, uvb, color)
	_push(c, uvc, color)
	_push(a, uva, color)
	_push(c, uvc, color)
	_push(d, uvd, color)


func _tri(a: Vector2, b: Vector2, c: Vector2, color: Color) -> void:
	_push(a, _white, color)
	_push(b, _white, color)
	_push(c, _white, color)


func _push(p: Vector2, uv: Vector2, color: Color) -> void:
	_verts.push_back(Vector3(p.x, p.y, 0))
	_uvs.push_back(uv)
	_cols.push_back(color)


func _type_color(kind: String) -> Color:
	match kind:
		"STORY":
			return Color(0.35, 0.82, 0.72, 1)
		"CHOICE":
			return Color(0.95, 0.72, 0.32, 1)
		"BOOL":
			return Color(0.78, 0.56, 0.95, 1)
		"ENDING":
			return Color(0.86, 0.42, 0.48, 1)
		_:
			return Color(0.62, 0.78, 0.96, 1)


func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var denom := ab.length_squared()
	if denom < 0.001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / denom, 0.0, 1.0)
	return p.distance_to(a + ab * t)
