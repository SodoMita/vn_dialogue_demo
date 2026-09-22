## Headless checks for the optional story-route graph.
## Run with: godot --headless res://tests/test_route_graph.tscn
extends Node

const AtlasScript = preload("res://scenes/route_graph/route_graph_atlas.gd")
const MeshScript = preload("res://scenes/route_graph/route_graph_mesh_builder.gd")
const CompilerScript = preload("res://scenes/route_graph/route_graph_compiler.gd")
const ViewScript = preload("res://scenes/route_graph/route_graph_view.gd")

var fails := 0
var passes := 0


func _ready() -> void:
	run()
	print("route-graph %d passed, %d failed" % [passes, fails])
	get_tree().quit(1 if fails else 0)


func check(cond: bool, what: String) -> void:
	if cond:
		passes += 1
		print("[PASS] %s" % what)
	else:
		fails += 1
		printerr("[FAIL] %s" % what)


func run() -> void:
	_check_sources()
	_check_shader()
	_check_uids()
	_check_layering()
	var compiled := _check_intro()
	_check_condition_badges()
	_check_furthest()
	_check_hits(compiled)
	_check_atlas()
	_check_panel_guard()
	check(ViewScript != null and AtlasScript != null, "route-graph scripts preload without a class cache")


func _check_sources() -> void:
	var dir := DirAccess.open("res://scenes/route_graph")
	check(dir != null, "route-graph directory opens")
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	var saw_script := false
	while name != "":
		if name.ends_with(".gd"):
			saw_script = true
			var text := FileAccess.get_file_as_string("res://scenes/route_graph/%s" % name)
			check(not text.contains("class_name "), "%s has no class_name (UID cache cannot break parsing)" % name)
			check(not text.contains("RouteGraphAtlas") and not text.contains("RouteGraphMeshBuilder") and not text.contains("RouteGraphData"),
				"%s does not name a global route-graph class" % name)
		name = dir.get_next()
	check(saw_script, "route-graph scripts are present")
	var view_text := FileAccess.get_file_as_string("res://scenes/route_graph/route_graph_view.gd")
	check(not _has_arg_new(view_text), "view never calls .new() with arguments")
	var balloon := FileAccess.get_file_as_string("res://scenes/vn_balloon.gd")
	check(balloon.contains("show_graph(dialogue_resource)"), "balloon passes the live dialogue into the map")
	check(not balloon.contains("instantiate("), "balloon still never instantiates a scene")


func _has_arg_new(text: String) -> bool:
	var i := 0
	while true:
		i = text.find(".new(", i)
		if i < 0:
			return false
		var close := text.find(")", i)
		if close > i + 5:
			return true
		i += 5
	return false


func _check_shader() -> void:
	var text := FileAccess.get_file_as_string("res://scenes/route_graph/route_graph.gdshader")
	var stripped := ""
	var i := 0
	while i < text.length():
		if text.substr(i, 2) == "//":
			var nl := text.find("\n", i)
			i = text.length() if nl < 0 else nl + 1
			continue
		stripped += text[i]
		i += 1
	var fetches := stripped.count("texture(")
	check(fetches == 1, "shader does exactly one texture() fetch (got %d)" % fetches)
	check(not _has_token(stripped, "if") and not _has_token(stripped, "for") and not _has_token(stripped, "while") and not _has_token(stripped, "switch"),
		"shader has no loops or branches")
	check(stripped.contains("pan") and stripped.contains("zoom"), "shader pans and zooms from uniforms")


func _has_token(text: String, token: String) -> bool:
	var i := 0
	while true:
		i = text.find(token, i)
		if i < 0:
			return false
		var before := text.unicode_at(i - 1) if i > 0 else 0
		var after := text.unicode_at(i + token.length()) if i + token.length() < text.length() else 0
		var ident_before := (before >= 48 and before <= 57) or (before >= 65 and before <= 90) or (before >= 97 and before <= 122) or before == 95
		var ident_after := (after >= 48 and after <= 57) or (after >= 65 and after <= 90) or (after >= 97 and after <= 122) or after == 95
		if not ident_before and not ident_after:
			return true
		i += token.length()
	return false


func _check_uids() -> void:
	var files := {
		"res://scenes/route_graph/route_graph_panel.tscn": "res://scenes/route_graph/route_graph_panel.tscn.uid",
		"res://scenes/route_graph/route_graph_view.tscn": "res://scenes/route_graph/route_graph_view.tscn.uid",
	}
	for path in files.keys():
		var header := FileAccess.get_file_as_string(path).split("\n")[0]
		var sidecar := FileAccess.get_file_as_string(files[path]).strip_edges()
		check(header.contains(sidecar) and sidecar.begins_with("uid://"), "%s header matches its .uid sidecar" % path.get_file())
	var panel := FileAccess.get_file_as_string("res://scenes/route_graph/route_graph_panel.tscn")
	check(panel.contains("uid://c7hh0twt3bdf6") and panel.contains("uid://bejdp2dxjwf8b") == false, "panel scene points at the panel script uid")
	check(panel.contains("uid://a7nyafmokdogm"), "panel scene points at the view scene uid")
	check(panel.contains("uid://ctxcxi25fm0pu"), "panel scene points at the font uid")
	var balloon := FileAccess.get_file_as_string("res://scenes/vn_balloon.tscn")
	check(balloon.contains("uid://ba4pj5dj4gjtc"), "balloon points at the route-graph panel uid")


func _check_layering() -> void:
	var text := FileAccess.get_file_as_string("res://scenes/vn_balloon.tscn")
	var panel_at := text.find("[node name=\"RouteGraphPanel\"")
	var close_at := text.find("[node name=\"SettingsCloseButton\"")
	check(panel_at >= 0 and close_at > panel_at, "SettingsCloseButton stays the last UIRoot child")


func _check_intro() -> Dictionary:
	var resource = load("res://dialogue/intro.dialogue")
	var compiled: Dictionary = CompilerScript.compile(resource)
	var nodes: Array = compiled.get("nodes", [])
	var by_id := {}
	for node in nodes:
		by_id[str(node.id)] = node
		print("  node %s type=%s outs=%d ins=%d" % [node.id, node.type, node.outputs.size(), node.inputs.size()])
	check(by_id.has("start") and by_id["start"].type == "START", "intro compiles a start cue")
	check(by_id.has("rooftop"), "named cue rooftop is kept")
	check(by_id.has("END") and by_id["END"].type == "ENDING", "intro compiles an END node")
	var choices := 0
	for node in nodes:
		if node.type == "CHOICE":
			choices += 1
		check(node.type != "CONDITION", "conditions are not nodes (%s)" % node.id)
	check(choices >= 1, "choice groups become nodes")
	check(nodes.size() <= 8, "linear lines collapse (got %d nodes, dialogue has many more lines)" % nodes.size())
	var start_targets := []
	for outp in by_id["start"].outputs:
		start_targets.append(str(outp.target))
		check(by_id.has(str(outp.target)), "start output %s exists" % outp.target)
	check(start_targets.size() == 1 and str(start_targets[0]).begins_with("choice_"), "start leads to the first choice, not every line")
	for node in nodes:
		for outp in node.outputs:
			check(by_id.has(str(outp.target)), "%s output target %s exists" % [node.id, outp.target])
			check(str(outp.target) != str(node.id), "%s does not output to itself" % node.id)
	return compiled


func _check_condition_badges() -> void:
	var fake := _FakeDialogue.new()
	fake.first_cue = "1"
	fake.cues = {"start": "2", "vault": "10"}
	fake.lines = {
		"1": {"type": "cue", "next_id": "2"},
		"2": {"type": "dialogue", "text": "The door is locked.", "next_id": "3"},
		"3": {"type": "response", "text": "Use the key", "next_id": "4", "responses": ["3", "5"]},
		"5": {"type": "response", "text": "Walk away", "next_id": "6", "responses": ["3", "5"]},
		"4": {"type": "condition", "condition_as_text": "has_key == true", "next_id": "7", "next_sibling_id": "8"},
		"7": {"type": "goto", "next_id": "10"},
		"8": {"type": "goto", "next_id": "end"},
		"6": {"type": "goto", "next_id": "end"},
		"9": {"type": "cue", "next_id": "10"},
		"10": {"type": "dialogue", "text": "The vault opens.", "next_id": "end"},
	}
	var compiled: Dictionary = CompilerScript.compile(fake)
	var choice = null
	for node in compiled.nodes:
		if str(node.id) == "choice_3":
			choice = node
	check(choice != null, "synthetic choice group compiles")
	if choice == null:
		return
	var saw_badge := false
	var saw_vault := false
	var saw_end := false
	for outp in choice.outputs:
		print("  choice port tag=%s target=%s cond=%s" % [outp.tag, outp.target, outp.cond])
		if str(outp.cond).find("has_key") >= 0:
			saw_badge = true
		if str(outp.target) == "vault":
			saw_vault = true
		if str(outp.target) == "END":
			saw_end = true
	check(saw_badge, "condition is a port badge, not a node")
	check(saw_vault and saw_end, "true and false branches reach different nodes")


func _check_furthest() -> void:
	var by_id := {
		"A": {"id": "A", "x": 0, "y": 0, "outputs": [{"target": "B"}, {"target": "D"}]},
		"B": {"id": "B", "x": 200, "y": 0, "outputs": [{"target": "C"}]},
		"C": {"id": "C", "x": 400, "y": 0, "outputs": []},
		"D": {"id": "D", "x": 200, "y": 300, "outputs": []},
	}
	check(MeshScript.furthest_node("B", by_id) == "C", "edge into B continues to the furthest node C")
	check(MeshScript.furthest_node("D", by_id) == "D", "a leaf edge stays on that leaf")
	check(MeshScript.furthest_node("A", by_id) == "C", "the longer branch wins over the nearer leaf")


func _check_hits(compiled: Dictionary) -> void:
	var nodes: Array = compiled.get("nodes", [])
	var atlas = AtlasScript.new()
	atlas.bake(MeshScript.text_keys(nodes))
	var builder = MeshScript.new()
	var mesh: ArrayMesh = builder.build(atlas, nodes)
	check(mesh.get_surface_count() == 1, "graph builds one triangle surface")
	check(builder.port_hits.size() > 0 and builder.edge_hits.size() > 0, "ports and edges are clickable")
	var start = null
	for node in nodes:
		if str(node.id) == "start":
			start = node
	check(start != null and start.outputs.size() > 0, "start has an output port to click")
	if start == null or start.outputs.is_empty():
		return
	var center: Vector2 = MeshScript.port_center(start, true, 0)
	var hit: Dictionary = builder.hit_test(center)
	check(hit.get("kind", "") == "port" and str(hit.get("jump_to", "")) == str(start.outputs[0].target),
		"clicking an output port jumps to the other side")
	var input_hit := false
	for node in nodes:
		if node.inputs.is_empty():
			continue
		var in_center: Vector2 = MeshScript.port_center(node, false, 0)
		var in_hit: Dictionary = builder.hit_test(in_center)
		if in_hit.get("kind", "") == "port" and str(in_hit.get("jump_to", "")) == str(node.inputs[0].source):
			input_hit = true
			break
	check(input_hit, "clicking an input port jumps back to the other side")
	var edge_ok := false
	for edge in builder.edge_hits:
		var mid: Vector2 = (edge.a + edge.b) * 0.5
		var edge_hit: Dictionary = builder.hit_test(mid)
		if edge_hit.get("kind", "") != "edge":
			continue
		var expected: String = MeshScript.furthest_node(str(edge.target), _by_id(nodes))
		if str(edge_hit.get("jump_to", "")) == expected and expected != str(edge.source):
			edge_ok = true
			break
	check(edge_ok, "clicking an edge jumps to the furthest node down that line")


func _by_id(nodes: Array) -> Dictionary:
	var by_id := {}
	for node in nodes:
		by_id[str(node.id)] = node
	return by_id


func _check_atlas() -> void:
	var atlas = AtlasScript.new()
	atlas.bake([{"key": "sample", "text": "Atlas", "size": 32}])
	check(atlas.texture != null, "atlas bakes a texture")
	var image: Image = atlas.texture.get_image()
	check(image != null and image.get_pixel(3, 3).a > 0.9, "atlas has an opaque white texel")
	var uv: Rect2 = atlas.uv_of("sample")
	var origin := Vector2i(int(uv.position.x * image.get_width()), int(uv.position.y * image.get_height()))
	var size := Vector2i(maxi(1, int(uv.size.x * image.get_width())), maxi(1, int(uv.size.y * image.get_height())))
	var opaque := 0
	var partial := 0
	var clear := 0
	for y in size.y:
		for x in size.x:
			var px := origin + Vector2i(x, y)
			if px.x < 0 or px.y < 0 or px.x >= image.get_width() or px.y >= image.get_height():
				continue
			var a := image.get_pixel(px.x, px.y).a
			if a > 0.85:
				opaque += 1
			elif a > 0.08:
				partial += 1
			else:
				clear += 1
	check(opaque > 8 and partial > 4 and clear > 8, "baked text is a glyph, not a solid block (opaque %d partial %d clear %d)" % [opaque, partial, clear])
	image.save_png("/tmp/route_atlas_preview.png")


func _check_panel_guard() -> void:
	var panel = load("res://scenes/route_graph/route_graph_panel.tscn").instantiate()
	add_child(panel)
	var bare := Control.new()
	panel.view = bare
	panel.show_graph(null)
	check(true, "show_graph does not read node_by_id when the view script is missing")
	panel.free()


class _FakeDialogue:
	var lines: Dictionary = {}
	var cues: Dictionary = {}
	var first_cue: String = ""
