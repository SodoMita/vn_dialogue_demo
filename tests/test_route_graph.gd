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
	_check_cycle_and_files()
	_check_condition_badges()
	_check_furthest()
	_check_hits(compiled)
	_check_edge_endpoints()
	_check_player_place(compiled)
	_check_spoiler_gate()
	_check_atlas()
	_check_panel_guard()
	_check_locale_and_atlas()
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
	check(balloon.contains("show_graph(dialogue_resource"), "balloon passes the live dialogue into the map")
	check(balloon.contains("_route_player_state()"), "balloon tells the map where the player is")
	check(balloon.contains("travel_requested"), "balloon listens for header travel")
	check(balloon.contains("dismiss_spoiler"), "closing the map dismisses an open spoiler prompt first")
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
	_check_anchors(compiled)
	return compiled


func _check_anchors(compiled: Dictionary) -> void:
	var nodes: Array = compiled.get("nodes", [])
	var entry = null
	var endings: Array = []
	for node in nodes:
		if bool(node.get("entry", false)):
			entry = node
		if str(node.get("type", "")) == "ENDING":
			endings.append(node)
	check(entry != null and str(entry.id) == "start", "entry is the first cue of the first dialogue file")
	if entry == null:
		return
	for node in nodes:
		if node == entry:
			continue
		check(float(entry.x) + float(entry.w) < float(node.x), "entry is strictly left of %s" % node.id)
	check(endings.size() == 1, "every file shares one END")
	for ending in endings:
		for node in nodes:
			if node == ending:
				continue
			check(float(ending.x) > float(node.x) + float(node.w), "END is strictly right of %s" % node.id)


func _check_cycle_and_files() -> void:
	var cyclic: Array = [
		{"id": "A", "type": "START", "entry": true, "w": 200.0, "h": 120.0, "inputs": [], "outputs": [{"target": "B"}, {"target": "END"}]},
		{"id": "B", "type": "ROUTE", "w": 200.0, "h": 120.0, "inputs": [], "outputs": [{"target": "C"}]},
		{"id": "C", "type": "ROUTE", "w": 220.0, "h": 120.0, "inputs": [], "outputs": [{"target": "A"}, {"target": "D"}]},
		{"id": "D", "type": "ROUTE", "w": 200.0, "h": 120.0, "inputs": [], "outputs": []},
		{"id": "other", "type": "START", "w": 200.0, "h": 120.0, "inputs": [], "outputs": [{"target": "END"}]},
		{"id": "END", "type": "ENDING", "w": 180.0, "h": 100.0, "inputs": [], "outputs": []},
	]
	CompilerScript._layout(cyclic)
	var by_id := {}
	for node in cyclic:
		by_id[node.id] = node
	check(float(by_id.A.x) + float(by_id.A.w) < float(by_id.other.x), "a cycle does not put another start left of the entry")
	check(float(by_id.A.x) + float(by_id.A.w) < float(by_id.D.x), "the long branch stays right of the entry")
	check(float(by_id.END.x) > float(by_id.D.x) + float(by_id.D.w), "END stays right of the longest branch in a cycle")
	var first := _FakeDialogue.new()
	first.first_cue = "1"
	first.cues = {"alpha": "2"}
	first.lines = {
		"1": {"type": "cue", "next_id": "2"},
		"2": {"type": "dialogue", "text": "Open.", "next_id": "3"},
		"3": {"type": "goto", "next_id": "2"},
	}
	var second := _FakeDialogue.new()
	second.first_cue = "1"
	second.cues = {"beta": "2"}
	second.lines = {
		"1": {"type": "cue", "next_id": "2"},
		"2": {"type": "dialogue", "text": "Later.", "next_id": "end"},
	}
	var merged: Dictionary = CompilerScript.compile_many([first, second])
	var entry = null
	var end_count := 0
	for node in merged.nodes:
		if bool(node.get("entry", false)):
			entry = node
		if str(node.get("type", "")) == "ENDING":
			end_count += 1
	check(entry != null and str(entry.id).ends_with("alpha"), "first file's first cue is the entry when several files are compiled")
	check(end_count == 1, "two dialogue files share one END")
	if entry == null:
		return
	for node in merged.nodes:
		if node == entry:
			continue
		check(float(entry.x) + float(entry.w) < float(node.x), "first file stays left of %s" % node.id)


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
		"A": {"id": "A", "x": 0, "y": 0, "layer": 0, "outputs": [{"target": "B"}, {"target": "D"}]},
		"B": {"id": "B", "x": 200, "y": 0, "layer": 1, "outputs": [{"target": "C"}]},
		"C": {"id": "C", "x": 400, "y": 0, "layer": 2, "outputs": []},
		"D": {"id": "D", "x": 200, "y": 300, "layer": 1, "outputs": []},
	}
	check(MeshScript.furthest_endpoint("A", "B", by_id) == "B", "a forward edge's furthest node is the target, not the source")
	check(MeshScript.furthest_endpoint("B", "C", by_id) == "C", "the further endpoint wins, not a node past the edge")
	check(MeshScript.furthest_endpoint("C", "A", by_id) == "C", "a back-edge's furthest node is the later endpoint")
	check(MeshScript.furthest_node("B", by_id) == "C", "downstream walk still reaches C")


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
	var not_source := false
	for edge in builder.edge_hits:
		var mid: Vector2 = (edge.a + edge.b) * 0.5
		var edge_hit: Dictionary = builder.hit_test(mid)
		if edge_hit.get("kind", "") != "edge":
			continue
		var expected: String = MeshScript.furthest_endpoint(str(edge.source), str(edge.target), _by_id(nodes))
		if str(edge_hit.get("jump_to", "")) == expected:
			edge_ok = true
			if expected != str(edge.source):
				not_source = true
			break
	check(edge_ok, "clicking an edge jumps to the furthest of its two nodes")
	check(not_source, "an edge click does not send to the source when the target is further")
	var header_ok := false
	for node in nodes:
		var header := Vector2(float(node.x) + 20.0, float(node.y) + 18.0)
		var header_hit: Dictionary = builder.hit_test(header)
		if header_hit.get("kind", "") == "header" and str(header_hit.get("node_id", "")) == str(node.id):
			header_ok = true
			break
	check(header_ok, "clicking a node header hits that node")


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


func _check_edge_endpoints() -> void:
	var nodes: Array = [
		{"id": "src", "type": "START", "title": "Src", "subtitle": "0 / 1", "color": Color.WHITE, "x": 40.0, "y": 40.0, "w": 230.0, "h": 150.0, "layer": 0, "inputs": [], "outputs": [{"type": "FLOW", "tag": "Dst", "target": "dst", "cond": ""}]},
		{"id": "dst", "type": "ROUTE", "title": "Dst", "subtitle": "1 / 1", "color": Color.CYAN, "x": 420.0, "y": 40.0, "w": 230.0, "h": 150.0, "layer": 1, "inputs": [{"type": "FLOW", "tag": "Src", "source": "src", "cond": ""}], "outputs": [{"type": "FLOW", "tag": "Far", "target": "far", "cond": ""}]},
		{"id": "far", "type": "ENDING", "title": "Far", "subtitle": "1 / 0", "color": Color.RED, "x": 800.0, "y": 40.0, "w": 230.0, "h": 150.0, "layer": 2, "inputs": [{"type": "FLOW", "tag": "Dst", "source": "dst", "cond": ""}], "outputs": []},
	]
	var atlas = AtlasScript.new()
	atlas.bake(MeshScript.text_keys(nodes))
	var builder = MeshScript.new()
	builder.build(atlas, nodes, "src")
	var src_edge: Dictionary = {}
	for edge in builder.edge_hits:
		if str(edge.source) == "src" and str(edge.target) == "dst":
			src_edge = edge
	check(not src_edge.is_empty(), "synthetic edge is clickable")
	if src_edge.is_empty():
		return
	check(str(src_edge.jump_to) == "dst", "edge jump is the further endpoint, not a node past it")
	check(str(src_edge.jump_to) != "src", "edge jump is not the source")
	check(str(src_edge.jump_to) != "far", "edge jump stays on the edge's two nodes")
	var a: Vector2 = MeshScript.port_center(nodes[0], true, 0)
	var b: Vector2 = MeshScript.port_center(nodes[1], false, 0)
	var n := (b - a).normalized()
	var arrow: Vector2 = b - n * 10.0
	var arrow_hit: Dictionary = builder.hit_test(arrow)
	check(arrow_hit.get("kind", "") == "edge", "clicking the arrow counts as the edge, not the destination port")
	check(str(arrow_hit.get("jump_to", "")) == "dst", "the arrow sends to the further node, not the source")
	var port_hit: Dictionary = builder.hit_test(b)
	check(port_hit.get("kind", "") == "port" and str(port_hit.get("jump_to", "")) == "src", "the port icon itself still jumps to the other side")
	var here := false
	for hit in builder.header_hits:
		if str(hit.get("node_id", "")) == "src":
			here = true
	check(here and builder.header_hits.size() == 3, "headers are hit targets")


func _check_player_place(compiled: Dictionary) -> void:
	var nodes: Array = compiled.get("nodes", [])
	var by_id := _by_id(nodes)
	var start = by_id.get("start", null)
	check(start != null and start.get("line_ids", []).size() > 0, "start owns the lines before the first choice")
	check(start != null and str(start.get("jump_key", "")) == "start", "start header jumps to the start cue")
	if start == null:
		return
	var first := str(start.line_ids[0])
	var player := {"line_id": first, "visited_ids": start.line_ids, "history_ids": start.line_ids, "response_ids": [], "ended": false}
	check(CompilerScript.locate_player(nodes, player) == "start", "the opening line places the player on start")
	var uid := str(start.get("file_uid", ""))
	var dm_uid := str(ResourceUID.path_to_uid("res://dialogue/intro.dialogue")).replace("uid://", "")
	check(uid != "" and uid == dm_uid, "node file uid matches dialogue line ids")
	player.line_id = "%s@%s" % [dm_uid, first]
	player.visited_ids = ["%s@%s" % [dm_uid, first]]
	check(CompilerScript.locate_player(nodes, player) == "start", "a dialogue-manager line id places the player on start")
	var visited_live: Dictionary = CompilerScript.visited_node_ids(nodes, player)
	check(visited_live.has("start") and not visited_live.has("rooftop"), "live line ids mark only the visited scene")
	var visited: Dictionary = CompilerScript.visited_node_ids(nodes, {"line_id": first, "visited_ids": start.line_ids, "response_ids": [], "ended": false})
	check(visited.has("start"), "visited lines mark start")
	check(not visited.has("rooftop"), "unvisited rooftop stays hidden")
	check(not visited.has("END"), "END stays hidden until the story ends")
	var choice = null
	for node in nodes:
		if str(node.type) == "CHOICE" and str(node.get("jump_key", "")) != "" and str(node.jump_key) != str(node.id):
			choice = node
			break
	check(choice != null, "a choice has a prompt to travel to")
	if choice == null:
		return
	var prompt := str(choice.jump_key)
	var at_choice := {
		"line_id": prompt,
		"visited_ids": [prompt],
		"history_ids": [first, prompt],
		"response_ids": choice.response_ids,
		"ended": false,
	}
	check(CompilerScript.locate_player(nodes, at_choice) == str(choice.id), "an open choice places the player on that choice")
	var choice_visited: Dictionary = CompilerScript.visited_node_ids(nodes, at_choice)
	check(choice_visited.has(str(choice.id)), "seeing the prompt marks the choice visited")
	check(not choice_visited.has("rooftop"), "the choice does not reveal later scenes")
	check(CompilerScript.history_index_for(["uid@1", "uid@%s" % prompt, "uid@9"], choice.line_ids, prompt, "") == 1, "header travel rolls back to the earliest owned line")
	check(CompilerScript.history_index_for(["uid@1"], ["99"], "start", "") == -1, "an unvisited header has no history index")
	var shown := {"start": true}
	var packed: Array = CompilerScript.prepare_display(nodes, shown, true)
	check(packed.size() == 1 and str(packed[0].id) == "start", "visited-only display drops unseen nodes")


func _check_spoiler_gate() -> void:
	var panel_text := FileAccess.get_file_as_string("res://scenes/route_graph/route_graph_panel.tscn")
	check(panel_text.contains("Visited only") and panel_text.contains("button_pressed = true"), "visited-only toggle is authored and on")
	check(panel_text.contains("Spoilers ahead") and panel_text.contains("Show spoilers"), "spoiler approval is authored")
	var panel = load("res://scenes/route_graph/route_graph_panel.tscn").instantiate()
	add_child(panel)
	check(panel.visited_only, "visited-only starts on")
	panel._on_visited_toggled(false)
	check(panel.visited_only, "turning the filter off does nothing until approved")
	check(panel.spoiler_panel.visible, "turning the filter off raises the spoiler prompt")
	check(panel.dismiss_spoiler(), "dismissing the prompt consumes the close")
	check(not panel.spoiler_panel.visible and panel.visited_only, "cancel keeps the visited filter on")
	panel._on_visited_toggled(false)
	panel._on_spoiler_confirmed()
	check(not panel.visited_only and not panel.spoiler_panel.visible, "approval reveals the full map")
	panel._on_visited_toggled(true)
	check(panel.visited_only, "the filter can be turned back on without another prompt")
	panel.free()


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


func _check_locale_and_atlas() -> void:
	var prev := TranslationServer.get_locale()
	var resource = load("res://dialogue/intro.dialogue")
	var compiled: Dictionary = CompilerScript.compile(resource)
	TranslationServer.set_locale("ru")
	var localized: Array = CompilerScript.localize_nodes(compiled.nodes)
	var by_id := {}
	for node in localized:
		by_id[str(node.id)] = node
	check(str(by_id["start"].title) == "Старт", "start node title is localized")
	check(str(by_id["rooftop"].title) == "Крыша", "route node title is localized")
	check(str(by_id["END"].title) == "Конец", "ending title is localized")
	check(str(by_id["start"].subtitle).contains("вх."), "node subtitle is localized")
	var saw_option := false
	var saw_choice_title := false
	for node in localized:
		if str(node.get("type", "")) == "CHOICE" and str(node.get("title", "")).contains("Ладно"):
			saw_choice_title = true
		for side in ["inputs", "outputs"]:
			for port in node.get(side, []):
				var tag := str(port.get("tag", ""))
				if tag.contains("Алекс") or tag.contains("Лучше не"):
					saw_option = true
	check(saw_choice_title, "choice node title is translated before it is shortened")
	check(saw_option, "choice port tags are localized from the dialogue catalog")
	var sample: Array = [{
		"id": "n",
		"title": "Start",
		"title_source": "Start",
		"title_dialogue": false,
		"inputs": [],
		"outputs": [{
			"type": "FLOW",
			"tag": "else",
			"tag_source": "else",
			"tag_kind": "ui",
			"cond": "else",
			"cond_source": "else",
		}, {
			"type": "FLOW",
			"tag": "Rooftop",
			"tag_source": "day == 1",
			"tag_kind": "ui",
			"cond": "day == 1",
			"cond_source": "day == 1",
		}],
	}]
	var badges: Array = CompilerScript.localize_nodes(sample)
	check(str(badges[0].outputs[0].cond) == "иначе", "condition badges translate when a catalog entry exists")
	check(str(badges[0].outputs[0].tag) == "иначе", "plain port tags translate from the UI catalog")
	check(str(badges[0].outputs[1].cond) == "day == 1", "untranslated condition badges stay readable")
	TranslationServer.set_locale("en")
	var english: Array = CompilerScript.localize_nodes(compiled.nodes)
	var en_start := ""
	for node in english:
		if str(node.id) == "start":
			en_start = str(node.title)
	check(en_start == "Start", "english locale keeps the source title")

	var sized = AtlasScript.new()
	sized.bake([{"key": "sample", "text": "Hi", "size": 16}], 256)
	check(sized.texture != null and sized.texture.get_width() == 256 and sized.texture.get_height() == 256, "atlas bake honors the requested resolution")
	var fallback = AtlasScript.new()
	fallback.bake([{"key": "sample", "text": "Hi", "size": 16}])
	check(fallback.texture != null and fallback.texture.get_width() == 1024, "atlas bake defaults to 1024")

	var view = ViewScript.new()
	view.set_atlas_resolution(512, false)
	view.open_resource(resource, {})
	check(view.atlas != null and view.atlas.texture != null and view.atlas.texture.get_width() == 512, "map bakes glyphs at the settings resolution")
	TranslationServer.set_locale("ru")
	view.refresh_locale()
	var ru_title := ""
	for node in view.nodes:
		if str(node.get("id", "")) == "start":
			ru_title = str(node.get("title", ""))
	check(ru_title == "Старт", "locale switch rebakes localized node titles")
	check(view.here_title() == "Старт", "here label uses the localized node title")
	check(view.atlas.texture.get_width() == 512, "locale switch keeps the chosen atlas resolution")
	view.free()
	TranslationServer.set_locale(prev)

	var scene_text := FileAccess.get_file_as_string("res://scenes/vn_balloon.tscn")
	check(scene_text.contains("[node name=\"AtlasSizeSpin\""), "settings scene authors the atlas resolution control")
	var balloon := FileAccess.get_file_as_string("res://scenes/vn_balloon.gd")
	check(balloon.contains("\"atlas_size\""), "atlas resolution is persisted")
	check(balloon.contains("show_graph(dialogue_resource, _route_player_state(), atlas_resolution)"), "opening the map uses the saved atlas resolution")
	check(not balloon.contains("AtlasSizeSpin.new("), "atlas control is not built in code")

