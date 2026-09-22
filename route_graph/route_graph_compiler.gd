class_name RouteGraphCompiler extends RefCounted
## Compile Dialogue Manager lines into a port-and-arrow route graph.
## Prefers an already-imported [DialogueResource]; can also compile source text.


const SKIP_TYPES := {
	"": true,
	"unknown": true,
	"comment": true,
	"import": true,
	"using": true,
}

const END_IDS := {
	"end": true,
	"end!": true,
}


static func from_resource(resource: DialogueResource) -> RouteGraph:
	var graph := RouteGraph.new()
	if resource == null:
		return graph
	graph.source_path = resource.resource_path
	_build(graph, resource.lines, resource.cues, resource.first_cue)
	return graph


static func from_text(text: String, path: String = ".") -> RouteGraph:
	var result: DMCompilerResult = DMCompiler.compile_string(text, path)
	var graph := RouteGraph.new()
	graph.source_path = path
	_build(graph, result.lines, result.cues, result.first_cue)
	return graph


static func make_stress(count: int, branching: int = 3) -> RouteGraph:
	## Synthetic layered DAG used to pin mesh-builder throughput.
	var graph := RouteGraph.new()
	graph.source_path = "stress"
	if count < 1:
		return graph
	for i: int in count:
		var n := RouteGraph.RouteNode.new()
		n.id = "n%d" % i
		n.kind = "choice" if (i % 7 == 0) else ("condition" if (i % 5 == 0) else "dialogue")
		n.title = "N%d" % (i % 12)
		n.body = "branch %d" % (i % 8)
		graph.add_port(n, false, "in", "in")
		var outs: int = 1 if n.kind != "choice" else mini(branching, 3)
		for o: int in outs:
			graph.add_port(n, true, "out%d" % o, "out%d" % o)
		graph.add_node(n)
	for i: int in count:
		var n: RouteGraph.RouteNode = graph.nodes[i]
		for o: int in n.outputs.size():
			var dest: int = i + 1 + o
			if dest >= count:
				continue
			graph.add_edge(n.id, "out%d" % o, "n%d" % dest, "in", "", "choice" if n.kind == "choice" else "flow")
	graph.first_id = "n0"
	return graph


static func _build(graph: RouteGraph, lines: Dictionary, cues: Dictionary, first_cue: String) -> void:
	if lines.is_empty():
		return
	for id: Variant in lines.keys():
		var data: Variant = lines[id]
		if data is not Dictionary:
			continue
		var type: String = str(data.get("type", ""))
		if SKIP_TYPES.has(type):
			continue
		var n := _make_node(str(id), data)
		graph.add_node(n)

	if not first_cue.is_empty() and graph.node_index.has(first_cue):
		graph.first_id = first_cue
	elif not cues.is_empty():
		var first_val: Variant = cues.values()[0]
		graph.first_id = str(first_val)

	for id: Variant in lines.keys():
		var data: Variant = lines[id]
		if data is not Dictionary:
			continue
		var sid := str(id)
		if not graph.node_index.has(sid):
			continue
		_connect_node(graph, sid, data)

	_drop_orphan_end(graph)


static func _make_node(id: String, data: Dictionary) -> RouteGraph.RouteNode:
	var n := RouteGraph.RouteNode.new()
	n.id = id
	var type: String = str(data.get("type", "dialogue"))
	n.kind = _kind_for(type, data)
	n.title = _title_for(n.kind, data)
	n.body = _body_for(n.kind, data)
	n.annotation = _annotation_for(data)
	var raw_tags: Variant = data.get("tags", PackedStringArray())
	if raw_tags is PackedStringArray:
		n.tags = raw_tags
	elif raw_tags is Array:
		n.tags = PackedStringArray(raw_tags)
	else:
		n.tags = PackedStringArray()
	_apply_stage_keys(n, n.tags)
	graph_add_ports(n, data)
	return n


static func graph_add_ports(n: RouteGraph.RouteNode, data: Dictionary) -> void:
	n.inputs.clear()
	n.outputs.clear()
	var in_port := RouteGraph.RoutePort.new()
	in_port.name = "in"
	in_port.label = "in"
	n.inputs.append(in_port)

	if n.kind == "end":
		return

	var responses: Array = _response_ids(data)
	if n.kind == "dialogue" and not responses.is_empty():
		var i := 0
		for rid: Variant in responses:
			var p := RouteGraph.RoutePort.new()
			p.name = "c%d" % i
			p.label = "c%d" % i
			n.outputs.append(p)
			i += 1
		return

	if n.kind == "condition":
		var t := RouteGraph.RoutePort.new()
		t.name = "true"
		t.label = "true"
		n.outputs.append(t)
		var f := RouteGraph.RoutePort.new()
		f.name = "false"
		f.label = "else"
		n.outputs.append(f)
		return

	var o := RouteGraph.RoutePort.new()
	o.name = "out"
	o.label = "out"
	n.outputs.append(o)


static func _connect_node(graph: RouteGraph, id: String, data: Dictionary) -> void:
	var type: String = str(data.get("type", ""))
	var n: RouteGraph.RouteNode = graph.get_node(id)
	if n == null:
		return

	var responses: Array = _response_ids(data)
	if n.kind == "dialogue" and not responses.is_empty():
		var i := 0
		for rid: Variant in responses:
			var choice_id := str(rid)
			_ensure_target(graph, choice_id)
			var label := ""
			if graph.node_index.has(choice_id):
				label = (graph.node_index[choice_id] as RouteGraph.RouteNode).body
			graph.add_edge(id, "c%d" % i, choice_id, "in", label, "choice")
			i += 1
		return

	if n.kind == "choice":
		_link(graph, id, "out", str(data.get("next_id", "")), "in", n.body, "choice")
		return

	if n.kind == "condition":
		_link(graph, id, "true", str(data.get("next_id", "")), "in", n.annotation, "condition")
		var sibling := str(data.get("next_sibling_id", ""))
		if sibling.is_empty():
			sibling = str(data.get("next_id_after", ""))
		_link(graph, id, "false", sibling, "in", "else", "condition")
		return

	_link(graph, id, "out", str(data.get("next_id", "")), "in", n.annotation, "flow")


static func _link(graph: RouteGraph, from_id: String, from_port: String, to_id: String, to_port: String, label: String, kind: String) -> void:
	to_id = _normalize_target(to_id)
	if to_id.is_empty():
		return
	_ensure_target(graph, to_id)
	graph.add_edge(from_id, from_port, to_id, to_port, label, kind)


static func _normalize_target(to_id: String) -> String:
	if to_id.is_empty() or to_id == "null":
		return ""
	if END_IDS.has(to_id):
		return "end"
	return to_id


static func _ensure_target(graph: RouteGraph, to_id: String) -> void:
	if to_id == "end":
		graph.ensure_end_node()


static func _drop_orphan_end(graph: RouteGraph) -> void:
	if not graph.node_index.has("end"):
		return
	for e: RouteGraph.RouteEdge in graph.edges:
		if e.to_id == "end":
			return
	graph.nodes = graph.nodes.filter(func(n: RouteGraph.RouteNode) -> bool: return n.id != "end")
	graph.node_index.erase("end")


static func _kind_for(type: String, data: Dictionary) -> String:
	match type:
		"cue":
			return "cue"
		"response":
			return "choice"
		"condition", "while", "match", "when":
			return "condition"
		"mutation":
			return "mutation"
		"goto":
			return "goto"
		"dialogue":
			return "dialogue"
		_:
			return type if not type.is_empty() else "dialogue"


static func _title_for(kind: String, data: Dictionary) -> String:
	match kind:
		"cue":
			return "~ %s" % str(data.get("text", "cue"))
		"choice":
			return "Choice"
		"condition":
			var expr := _expression_text(data)
			return "if %s" % expr if not expr.is_empty() else "else"
		"mutation":
			return "do"
		"goto":
			return "jump"
		"end":
			return "END"
		_:
			var character := str(data.get("character", ""))
			return character if not character.is_empty() else "Narration"


static func _body_for(kind: String, data: Dictionary) -> String:
	match kind:
		"cue":
			return str(data.get("text", ""))
		"mutation":
			return _expression_text(data.get("mutation", data))
		"condition":
			return _expression_text(data)
		"goto":
			return str(data.get("next_id", ""))
		_:
			return _strip_bbcode(str(data.get("text", "")))


static func _annotation_for(data: Dictionary) -> String:
	if data.has("condition_as_text") and str(data.condition_as_text) != "":
		return str(data.condition_as_text)
	if data.has("condition"):
		return _expression_text(data)
	if data.has("mutation"):
		return _expression_text(data.get("mutation", {}))
	return ""


static func _apply_stage_keys(n: RouteGraph.RouteNode, tags: PackedStringArray) -> void:
	for tag: String in tags:
		if tag.begins_with("bg=") and tag != "bg=none":
			n.bg_key = tag.substr(3)
		elif tag.begins_with("sprite=") and not tag.begins_with("sprite=none"):
			var spec := tag.substr(7)
			var parts := spec.split(":")
			if parts.size() > 0 and parts[0] != "none":
				n.sprite_key = parts[0]


static func _expression_text(data: Variant) -> String:
	if data is not Dictionary:
		return str(data)
	var d: Dictionary = data
	if d.has("condition_as_text") and str(d.condition_as_text) != "":
		return str(d.condition_as_text)
	var payload: Variant = d.get("condition", d.get("mutation", d.get("expression", data)))
	return _tokens_to_text(payload)


static func _tokens_to_text(value: Variant) -> String:
	if value is String:
		return value
	if value is bool or value is int or value is float:
		return str(value)
	if value is Dictionary:
		var d: Dictionary = value
		if d.has("expression"):
			return _tokens_to_text(d.expression)
		if d.has("function"):
			return "%s(%s)" % [str(d.function), _tokens_to_text(d.get("value", []))]
		if d.has("value") and d.has("type"):
			return _tokens_to_text(d.value)
		if d.has("value"):
			return _tokens_to_text(d.value)
		return ""
	if value is Array:
		var bits: PackedStringArray = PackedStringArray()
		for item: Variant in value:
			var piece := _tokens_to_text(item)
			if not piece.is_empty():
				bits.append(piece)
		return " ".join(bits)
	return ""


static func _response_ids(data: Dictionary) -> Array:
	var raw: Variant = data.get("responses", [])
	if raw is Array:
		return raw
	if raw is PackedStringArray:
		var out: Array = []
		for item: Variant in raw:
			out.append(item)
		return out
	return []


static func _strip_bbcode(source: String) -> String:
	var rx := RegEx.new()
	rx.compile("\\[[a-zA-Z/][^\\]]*\\]")
	return rx.sub(source, "", true).strip_edges()
