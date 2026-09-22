extends RefCounted
## Compile a Dialogue Manager resource into routing nodes only.
## Named cues, choice groups and END stay. Linear lines, mutations and
## pass-through gotos collapse. Conditions become port badges, not nodes.
## Untyped on purpose: this script must not depend on DialogueResource or
## any route-graph class being present in the global class cache.


const MeshScript = preload("res://scenes/route_graph/route_graph_mesh_builder.gd")


## One resource, or every file under res://dialogue. The graph may contain cycles.
## The first cue of the first dialogue file is the entry (always leftmost).
## END is always rightmost. Back-edges do not move either anchor.
static func compile(resource, prefix: String = "", laid_out: bool = true) -> Dictionary:
	if resource == null or not ("lines" in resource) or not ("cues" in resource):
		return {"nodes": [], "edges": []}
	var lines: Dictionary = resource.lines
	var cues: Dictionary = resource.cues
	var line_key := {}
	for key in lines.keys():
		line_key[str(key)] = key
	var cue_at := {}
	for key in cues.keys():
		cue_at[str(key)] = str(cues[key])

	var cue_line_to_name := {}
	for lid in line_key.keys():
		var line: Dictionary = _line(lines, line_key, lid)
		if str(line.get("type", "")) != "cue":
			continue
		var nxt := str(line.get("next_id", ""))
		for cname in cue_at.keys():
			if cue_at[cname] == nxt or cue_at[cname] == lid:
				cue_line_to_name[lid] = cname

	var targeted := {}
	for lid in line_key.keys():
		var line: Dictionary = _line(lines, line_key, lid)
		if str(line.get("type", "")) != "goto":
			continue
		var nxt := str(line.get("next_id", ""))
		if nxt == "" or nxt == "end":
			continue
		if cue_line_to_name.has(nxt):
			targeted[cue_line_to_name[nxt]] = true
		for cname in cue_at.keys():
			if cue_at[cname] == nxt or cname == nxt:
				targeted[cname] = true

	var choice_groups := {}
	for lid in line_key.keys():
		var line: Dictionary = _line(lines, line_key, lid)
		if str(line.get("type", "")) != "response":
			continue
		var responses = line.get("responses", [])
		if typeof(responses) != TYPE_ARRAY and typeof(responses) != TYPE_PACKED_STRING_ARRAY:
			continue
		if responses.size() < 2:
			continue
		var gid := str(responses[0])
		if not choice_groups.has(gid):
			var ids: Array = []
			for rid in responses:
				ids.append(str(rid))
			choice_groups[gid] = ids

	var nodes: Array = []
	var by_id := {}
	var first_name := _first_cue_name(resource, cue_line_to_name, cue_at, line_key, lines)
	for cname in cue_at.keys():
		var is_start: bool = (not targeted.has(cname)) or cname == first_name
		var node := _make(
			cname,
			"START" if is_start else "ROUTE",
			cname.capitalize(),
			Color("#16A34A") if is_start else Color("#0F766E"),
			"cue"
		)
		# First cue of this file. compile_many keeps the flag only on the first file.
		node["entry"] = cname == first_name
		nodes.append(node)
		by_id[cname] = node

	for gid in choice_groups.keys():
		var source := _choice_source(lines, line_key, gid)
		var title := _choice_title_from(source, gid)
		var node := _make("choice_%s" % gid, "CHOICE", title, Color("#D97706"), "%d options" % choice_groups[gid].size())
		# Full dialogue msgid. Display translates it, then shortens.
		if source == "":
			node["title_source"] = "Choice %s"
			node["title_arg"] = gid
			node["title_dialogue"] = false
		else:
			node["title_source"] = source
			node["title_dialogue"] = true
		nodes.append(node)
		by_id[node.id] = node

	var end_node := _make("END", "ENDING", "END", Color("#9F1239"), "ending")
	nodes.append(end_node)
	by_id["END"] = end_node

	var sig := {}
	for cname in cue_at.keys():
		sig[cname] = cname
		sig[cue_at[cname]] = cname
		for lid in cue_line_to_name.keys():
			if cue_line_to_name[lid] == cname:
				sig[lid] = cname
	for gid in choice_groups.keys():
		sig[gid] = "choice_%s" % gid
	sig["end"] = "END"

	for cname in cue_at.keys():
		var fid: String = str(cue_at[cname])
		var targets: Array = []
		if choice_groups.has(fid):
			targets = [{"target": "choice_%s" % fid, "cond": ""}]
		else:
			targets = _collect(fid, lines, line_key, sig, by_id)
		_add_outputs(by_id[cname], targets, by_id, "FLOW")

	for gid in choice_groups.keys():
		var src: Dictionary = by_id["choice_%s" % gid]
		for rid in choice_groups[gid]:
			var response := _line(lines, line_key, rid)
			var tag_source := str(response.get("text", rid))
			var tag := _short(tag_source, 24)
			var response_cond_full := _cond_text(response)
			var next_id := str(response.get("next_id", ""))
			var targets: Array = _collect(next_id, lines, line_key, sig, by_id) if next_id != "" else []
			if targets.is_empty():
				targets = [{"target": "END", "cond": ""}]
			for item in _merge_targets(targets):
				var cond_full := response_cond_full
				var extra := str(item.get("cond", ""))
				if extra != "":
					cond_full = extra if cond_full == "" else "%s && %s" % [cond_full, extra]
				var target_id := str(item.get("target", ""))
				if not by_id.has(target_id) or target_id == src.id:
					continue
				src.outputs.append({
					"type": "CHOICE",
					"tag": tag,
					"tag_source": tag_source,
					"tag_dialogue": true,
					"tag_arg": "",
					"tag_kind": "line",
					"label": by_id[target_id].title,
					"target": target_id,
					"cond": _short(cond_full, 28),
					"cond_source": cond_full,
				})

	_mirror_inputs(nodes, by_id)
	var kept := _keep_routing(nodes)
	_bypass_removed(nodes, kept)
	by_id.clear()
	for node in kept:
		by_id[node.id] = node
	_mirror_inputs(kept, by_id)
	if prefix != "":
		_apply_prefix(kept, prefix)
	for node in kept:
		node.w = MeshScript.measure_width(node)
		node.h = MeshScript.measure_height(node.inputs.size(), node.outputs.size())
		node.subtitle = "%d in / %d out" % [node.inputs.size(), node.outputs.size()]
	if laid_out:
		_layout(kept)
	_annotate_lines(resource, kept, prefix)
	return {"nodes": kept, "edges": []}


## Every *.dialogue under res://dialogue, sorted by path. Index 0 is the first file.
static func compile_project() -> Dictionary:
	return compile_many(_load_dialogue_files())


## resources[0] is the first dialogue file. Its first cue stays leftmost.
## Later files are prefixed so cue names can collide. END is one shared node.
static func compile_many(resources: Array) -> Dictionary:
	var combined: Array = []
	var end_node = null
	var entry_kept := false
	for i in resources.size():
		var prefix := ""
		if resources.size() > 1:
			prefix = _prefix_for(resources[i], i)
		var part: Dictionary = compile(resources[i], prefix, false)
		for node in part.get("nodes", []):
			if _is_ending(node):
				if end_node == null:
					end_node = node
				continue
			if i > 0 or entry_kept:
				node["entry"] = false
			elif bool(node.get("entry", false)):
				entry_kept = true
			combined.append(node)
	if end_node != null:
		combined.append(end_node)
	var by_id := {}
	for node in combined:
		by_id[str(node.id)] = node
	_mirror_inputs(combined, by_id)
	for node in combined:
		node.w = MeshScript.measure_width(node)
		node.h = MeshScript.measure_height(node.inputs.size(), node.outputs.size())
		node.subtitle = "%d in / %d out" % [node.inputs.size(), node.outputs.size()]
	_layout(combined)
	return {"nodes": combined, "edges": []}


static func _load_dialogue_files() -> Array:
	var paths: Array = []
	var dir := DirAccess.open("res://dialogue")
	if dir == null:
		return paths
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(".dialogue"):
			paths.append("res://dialogue/%s" % name)
		name = dir.get_next()
	dir.list_dir_end()
	paths.sort()
	var resources: Array = []
	for path in paths:
		var loaded = load(path)
		if loaded != null:
			resources.append(loaded)
	return resources


static func _prefix_for(resource, index: int) -> String:
	var path := ""
	if resource != null and "resource_path" in resource:
		path = str(resource.resource_path)
	if path == "":
		return "file%d" % index
	return path.get_file().get_basename()


static func _apply_prefix(nodes: Array, prefix: String) -> void:
	var remap := {}
	for node in nodes:
		var old_id := str(node.id)
		if _is_ending(node):
			remap[old_id] = old_id
			continue
		var new_id := "%s/%s" % [prefix, old_id]
		remap[old_id] = new_id
		node["raw_id"] = old_id
		node.id = new_id
	for node in nodes:
		for outp in node.outputs:
			var target := str(outp.get("target", ""))
			if remap.has(target):
				outp.target = remap[target]
		for inp in node.inputs:
			var source := str(inp.get("source", ""))
			if remap.has(source):
				inp.source = remap[source]


static func _is_ending(node) -> bool:
	return str(node.get("type", "")) == "ENDING" or str(node.get("id", "")) == "END"


static func _make(id: String, type: String, title: String, color: Color, subtitle: String) -> Dictionary:
	return {
		"id": id,
		"type": type,
		"title": title,
		"title_source": title,
		"title_dialogue": false,
		"color": color,
		"subtitle": subtitle,
		"x": 0.0,
		"y": 0.0,
		"w": 240.0,
		"h": 140.0,
		"inputs": [],
		"outputs": [],
		"line_ids": [],
		"response_ids": [],
		"jump_key": id,
		"file_path": "",
		"file_uid": "",
		"raw_id": id,
	}


static func _line(lines: Dictionary, line_key: Dictionary, id: String) -> Dictionary:
	if not line_key.has(id):
		return {}
	var line = lines[line_key[id]]
	return line if line is Dictionary else {}


static func _first_cue_name(resource, cue_line_to_name: Dictionary, cue_at: Dictionary, line_key: Dictionary, lines: Dictionary) -> String:
	var first_id := str(resource.first_cue) if "first_cue" in resource else ""
	if cue_line_to_name.has(first_id):
		return cue_line_to_name[first_id]
	var first_line := _line(lines, line_key, first_id)
	var nxt := str(first_line.get("next_id", ""))
	for cname in cue_at.keys():
		if cue_at[cname] == nxt or cname == first_id:
			return cname
	if cue_at.size() > 0:
		return str(cue_at.keys()[0])
	return ""


static func _choice_source(lines: Dictionary, line_key: Dictionary, gid: String) -> String:
	for lid in line_key.keys():
		var line := _line(lines, line_key, lid)
		if str(line.get("next_id", "")) != gid:
			continue
		if str(line.get("type", "")) == "response":
			continue
		var text := str(line.get("text", "")).strip_edges()
		if text != "":
			return text
	return ""


static func _choice_title(lines: Dictionary, line_key: Dictionary, gid: String) -> String:
	return _choice_title_from(_choice_source(lines, line_key, gid), gid)


static func _choice_title_from(source: String, gid: String) -> String:
	if source == "":
		return "Choice %s" % gid
	var text := source
	var sentence := text.find(". ")
	if sentence > 8:
		text = text.substr(0, sentence + 1)
	return _short(text, 42)


static func _collect(start_id: String, lines: Dictionary, line_key: Dictionary, sig: Dictionary, by_id: Dictionary) -> Array:
	var results: Array = []
	if start_id == "":
		return results
	var stack: Array = [{"id": start_id, "cond": ""}]
	var visited := {}
	var guard := 0
	while not stack.is_empty() and guard < 600:
		guard += 1
		var item: Dictionary = stack.pop_back()
		var cur_id := str(item.get("id", ""))
		var cur_cond := str(item.get("cond", ""))
		var seen_key := "%s|%s" % [cur_id, cur_cond]
		if visited.has(seen_key):
			continue
		visited[seen_key] = true
		if cur_id == "end":
			results.append({"target": "END", "cond": cur_cond})
			continue
		if cur_id != start_id and sig.has(cur_id):
			results.append({"target": sig[cur_id], "cond": cur_cond})
			continue
		if cur_id != start_id and by_id.has(cur_id) and not line_key.has(cur_id):
			results.append({"target": cur_id, "cond": cur_cond})
			continue
		var line := _line(lines, line_key, cur_id)
		if line.is_empty():
			continue
		if str(line.get("type", "")) == "condition":
			var cond_txt := _cond_text(line)
			if cond_txt == "":
				cond_txt = "else"
			var true_next := str(line.get("next_id", ""))
			var false_next := str(line.get("next_sibling_id", ""))
			if false_next == "":
				false_next = str(line.get("next_id_after", ""))
			if true_next != "":
				stack.append({"id": true_next, "cond": _and(cur_cond, "" if cond_txt == "else" else cond_txt)})
			if false_next != "":
				var negated := cur_cond if cond_txt == "else" else _and(cur_cond, _negate(cond_txt))
				stack.append({"id": false_next, "cond": negated})
			continue
		var nxt := str(line.get("next_id", ""))
		if nxt == "":
			nxt = str(line.get("next_id_after", ""))
		if nxt == "" or nxt == cur_id:
			continue
		stack.append({"id": nxt, "cond": cur_cond})
	return results


static func _add_outputs(src: Dictionary, targets: Array, by_id: Dictionary, type: String) -> void:
	for item in _merge_targets(targets):
		var target_id := str(item.get("target", ""))
		if not by_id.has(target_id) or target_id == src.id:
			continue
		var cond_full := str(item.get("cond", ""))
		src.outputs.append({
			"type": type,
			"tag": _short(str(by_id[target_id].title), 18),
			"tag_source": str(by_id[target_id].get("title_source", by_id[target_id].title)),
			"tag_dialogue": bool(by_id[target_id].get("title_dialogue", false)),
			"tag_arg": str(by_id[target_id].get("title_arg", "")),
			"tag_kind": "title",
			"label": by_id[target_id].title,
			"target": target_id,
			"cond": _short(cond_full, 28),
			"cond_source": cond_full,
		})


static func _merge_targets(targets: Array) -> Array:
	var grouped := {}
	var order: Array = []
	for item in targets:
		var target_id := str(item.get("target", ""))
		if target_id == "":
			continue
		if not grouped.has(target_id):
			grouped[target_id] = []
			order.append(target_id)
		grouped[target_id].append(str(item.get("cond", "")))
	var merged: Array = []
	for target_id in order:
		var conds: Array = grouped[target_id]
		var cond := ""
		if conds.size() == 1:
			cond = str(conds[0])
		merged.append({"target": target_id, "cond": cond})
	return merged


static func _mirror_inputs(nodes: Array, by_id: Dictionary) -> void:
	for node in nodes:
		node.inputs = []
	for node in nodes:
		for outp in node.outputs:
			var target_id := str(outp.get("target", ""))
			if not by_id.has(target_id):
				continue
			var tag := str(outp.get("tag", ""))
			var tag_source := str(outp.get("tag_source", tag))
			var tag_dialogue := bool(outp.get("tag_dialogue", false))
			var tag_arg := str(outp.get("tag_arg", ""))
			var tag_kind := str(outp.get("tag_kind", "ui"))
			if str(node.get("type", "")) != "CHOICE":
				tag = _short(str(node.title), 18)
				tag_source = str(node.get("title_source", node.title))
				tag_dialogue = bool(node.get("title_dialogue", false))
				tag_arg = str(node.get("title_arg", ""))
				tag_kind = "title"
			by_id[target_id].inputs.append({
				"type": outp.get("type", "FLOW"),
				"tag": tag,
				"tag_source": tag_source,
				"tag_dialogue": tag_dialogue,
				"tag_arg": tag_arg,
				"tag_kind": tag_kind,
				"label": node.title,
				"source": node.id,
				"cond": outp.get("cond", ""),
				"cond_source": outp.get("cond_source", outp.get("cond", "")),
			})


static func _keep_routing(nodes: Array) -> Array:
	var kept: Array = []
	for node in nodes:
		var keep := false
		if node.type == "START" or node.type == "CHOICE":
			keep = true
		elif node.type == "ENDING":
			keep = node.inputs.size() > 0
		elif node.type == "ROUTE":
			keep = node.inputs.size() > 0 or node.outputs.size() > 0
		elif node.inputs.size() >= 2 or node.outputs.size() >= 2:
			keep = true
		if keep:
			kept.append(node)
	return kept


static func _bypass_removed(all_nodes: Array, kept: Array) -> void:
	var alive := {}
	for node in kept:
		alive[node.id] = node
	var removed := {}
	for node in all_nodes:
		if not alive.has(node.id):
			removed[node.id] = node
	if removed.is_empty():
		return
	for node in kept:
		for outp in node.outputs:
			var guard := 0
			while removed.has(str(outp.get("target", ""))) and guard < 8:
				guard += 1
				var hop: Dictionary = removed[str(outp.target)]
				if hop.outputs.is_empty():
					outp.target = "END"
					break
				var nxt: Dictionary = hop.outputs[0]
				outp.target = nxt.get("target", "END")
				if str(outp.get("cond", "")) == "" and str(nxt.get("cond", "")) != "":
					outp.cond = nxt.cond
					outp["cond_source"] = nxt.get("cond_source", nxt.cond)


## Cycle-safe ranks. A back-edge (a return to a node already on the DFS stack)
## is drawn, but it does not pull the entry right or push a node past END.
static func _layout(nodes: Array) -> void:
	var by_id := {}
	for node in nodes:
		by_id[str(node.id)] = node
		node["layer"] = -1
	var entry = _find_entry(nodes)
	var back := {}
	var color := {}
	if entry != null:
		_mark_back_edges(str(entry.id), by_id, color, back)
	for node in nodes:
		_mark_back_edges(str(node.id), by_id, color, back)
	var queue: Array = []
	if entry != null:
		entry.layer = 0
		queue.append(entry)
	for node in nodes:
		if node == entry or _is_ending(node):
			continue
		if str(node.get("type", "")) == "START" or node.get("inputs", []).is_empty():
			if int(node.layer) < 0:
				node.layer = 1
				queue.append(node)
	if queue.is_empty() and not nodes.is_empty():
		nodes[0].layer = 0
		queue.append(nodes[0])
	var guard := 0
	var limit := maxi(8, nodes.size() * nodes.size())
	while not queue.is_empty() and guard < limit:
		guard += 1
		var cur: Dictionary = queue.pop_front()
		if _is_ending(cur):
			continue
		for outp in cur.outputs:
			var target_id := str(outp.get("target", ""))
			var target = by_id.get(target_id, null)
			if target == null or _is_ending(target):
				continue
			if back.has("%s->%s" % [str(cur.id), target_id]):
				continue
			var next_layer := int(cur.layer) + 1
			if next_layer >= nodes.size():
				continue
			if int(target.layer) < next_layer:
				target.layer = next_layer
				queue.append(target)
	var max_other := 0
	for node in nodes:
		if node == entry or _is_ending(node):
			continue
		if int(node.layer) < 0:
			node.layer = 1
		max_other = maxi(max_other, int(node.layer))
	if entry != null:
		entry.layer = 0
	for node in nodes:
		if _is_ending(node):
			node.layer = max_other + 1
	var layers := {}
	var max_layer := 0
	for node in nodes:
		if int(node.layer) < 0:
			node.layer = 1
		max_layer = maxi(max_layer, int(node.layer))
		if not layers.has(node.layer):
			layers[node.layer] = []
		layers[node.layer].append(node)
	var x := 40.0
	for layer in range(max_layer + 1):
		if not layers.has(layer):
			continue
		var column: Array = layers[layer]
		column.sort_custom(func(a, b): return str(a.id) < str(b.id))
		var y := 36.0
		var column_w := 0.0
		for node in column:
			node.x = x
			node.y = y
			y += float(node.h) + 48.0
			column_w = maxf(column_w, float(node.w))
		x += column_w + 90.0
	_pin_anchors(nodes)


static func _find_entry(nodes: Array):
	for node in nodes:
		if bool(node.get("entry", false)):
			return node
	for node in nodes:
		if str(node.get("type", "")) == "START":
			return node
	return null


static func _mark_back_edges(id: String, by_id: Dictionary, color: Dictionary, back: Dictionary) -> void:
	if int(color.get(id, 0)) != 0:
		return
	color[id] = 1
	var node = by_id.get(id, {})
	for outp in node.get("outputs", []):
		var target_id := str(outp.get("target", ""))
		if not by_id.has(target_id):
			continue
		if int(color.get(target_id, 0)) == 1:
			back["%s->%s" % [id, target_id]] = true
			continue
		_mark_back_edges(target_id, by_id, color, back)
	color[id] = 2


static func _pin_anchors(nodes: Array) -> void:
	var entry = _find_entry(nodes)
	var gap := 90.0
	if entry != null:
		var min_other := 1.0e9
		var others := false
		for node in nodes:
			if node == entry:
				continue
			others = true
			min_other = minf(min_other, float(node.x))
		if others and float(entry.x) >= min_other - 0.5:
			entry.x = min_other - float(entry.w) - gap
	var max_right := -1.0e9
	var non_end := false
	var endings: Array = []
	for node in nodes:
		if _is_ending(node):
			endings.append(node)
		else:
			non_end = true
			max_right = maxf(max_right, float(node.x) + float(node.w))
	if non_end:
		var place := max_right + gap
		for ending in endings:
			if float(ending.x) < place - 0.5:
				ending.x = place


static func _cond_text(line: Dictionary) -> String:
	var parsed := _expr_to_text(line.get("condition", {}))
	if parsed != "":
		return parsed
	return str(line.get("condition_as_text", "")).strip_edges()


static func _expr_to_text(expr) -> String:
	if typeof(expr) != TYPE_DICTIONARY or expr.is_empty():
		return ""
	var parts: Array = []
	for item in expr.get("expression", []):
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var kind := str(item.get("type", ""))
		var value = item.get("value", "")
		if kind == "string":
			parts.append("\"%s\"" % str(value))
		elif str(value) != "":
			parts.append(str(value))
	return " ".join(parts).strip_edges()


static func _and(a: String, b: String) -> String:
	if a == "":
		return b
	if b == "":
		return a
	return "%s && %s" % [a, b]


static func _negate(cond: String) -> String:
	if cond.begins_with("!"):
		return cond.substr(1)
	return "!(%s)" % cond


static func _short(text: String, limit: int) -> String:
	var trimmed := text.strip_edges()
	if trimmed.length() <= limit:
		return trimmed
	return trimmed.substr(0, limit - 3) + "..."


## Line ownership for "you are here", visited filtering and header travel.
## Cue spans stop at the next routing node. Choice nodes own their prompt,
## their responses and the lines until the next cue. END is a sink, not a
## span, so seeing the last line does not reveal the ending node.
static func _annotate_lines(resource, nodes: Array, prefix: String = "") -> void:
	var file_uid := _file_uid(resource)
	var file_path := ""
	if resource != null and "resource_path" in resource:
		file_path = str(resource.resource_path)
	for node in nodes:
		node["file_uid"] = file_uid
		node["file_path"] = file_path
		node["line_ids"] = []
		node["response_ids"] = []
		node["jump_key"] = _raw_node_id(node, prefix)
	if resource == null or not ("lines" in resource) or not ("cues" in resource):
		return
	var lines: Dictionary = resource.lines
	var cues: Dictionary = resource.cues
	var line_key := {}
	for key in lines.keys():
		line_key[str(key)] = key
	var sig := {}
	for node in nodes:
		var raw := _raw_node_id(node, prefix)
		var id := str(node.get("id", ""))
		var typ := str(node.get("type", ""))
		if typ == "ENDING" or raw == "END":
			sig["end"] = id
			sig["END"] = id
			node["jump_key"] = ""
		elif typ == "CHOICE" or raw.begins_with("choice_"):
			var gid := raw.trim_prefix("choice_")
			sig[gid] = id
			node["jump_key"] = gid
		else:
			sig[raw] = id
			if cues.has(raw):
				sig[str(cues[raw])] = id
			node["jump_key"] = raw
	for node in nodes:
		var raw := _raw_node_id(node, prefix)
		var id := str(node.get("id", ""))
		var typ := str(node.get("type", ""))
		if typ == "ENDING" or raw == "END":
			continue
		if typ == "CHOICE" or raw.begins_with("choice_"):
			var gid := raw.trim_prefix("choice_")
			var responses: Array = []
			if line_key.has(gid):
				var listed = _line(lines, line_key, gid).get("responses", [])
				if typeof(listed) == TYPE_ARRAY or typeof(listed) == TYPE_PACKED_STRING_ARRAY:
					for rid in listed:
						responses.append(str(rid))
			if responses.is_empty():
				responses.append(gid)
			node["response_ids"] = responses
			var claimed: Array = []
			for rid in responses:
				for lid in _claim_span(str(rid), lines, line_key, sig, id):
					if not claimed.has(lid):
						claimed.append(lid)
			var prompt := _prompt_id(lines, line_key, gid)
			if prompt != "":
				node["jump_key"] = prompt
				if not claimed.has(prompt):
					claimed.append(prompt)
			node["line_ids"] = claimed
			continue
		var anchor := ""
		if cues.has(raw):
			anchor = str(cues[raw])
		elif line_key.has(raw):
			anchor = raw
		if anchor == "":
			continue
		node["line_ids"] = _claim_span(anchor, lines, line_key, sig, id)
		node["jump_key"] = raw
	# The prompt is the choice, not the previous scene.
	for node in nodes:
		var raw := _raw_node_id(node, prefix)
		if str(node.get("type", "")) != "CHOICE" and not raw.begins_with("choice_"):
			continue
		var prompt := str(node.get("jump_key", ""))
		if not _looks_like_line_id(prompt):
			continue
		for other in nodes:
			if other == node:
				continue
			other["line_ids"].erase(prompt)
		if not node["line_ids"].has(prompt):
			node["line_ids"].append(prompt)
	var end_line := ""
	for lid in line_key.keys():
		var line := _line(lines, line_key, lid)
		if str(line.get("type", "")) == "dialogue" and str(line.get("next_id", "")) == "end":
			end_line = str(lid)
	if end_line != "":
		for node in nodes:
			if str(node.get("type", "")) == "ENDING" or _raw_node_id(node, prefix) == "END":
				node["jump_key"] = end_line


static func _raw_node_id(node: Dictionary, prefix: String) -> String:
	var raw := str(node.get("raw_id", ""))
	if raw == "":
		raw = str(node.get("id", ""))
	if prefix != "" and raw.begins_with(prefix + "/"):
		return raw.substr(prefix.length() + 1)
	return raw


static func _file_uid(resource) -> String:
	# Dialogue line ids are "<uid-without-scheme>@<line>", from
	# ResourceUID.path_to_uid. ResourceLoader.get_resource_uid is a numeric
	# id and must not be used here or visited/current matching fails.
	var path := ""
	if resource != null and "resource_path" in resource:
		path = str(resource.resource_path)
	if path == "" or not path.begins_with("res://"):
		return ""
	if not ResourceLoader.exists(path):
		return ""
	var uid := str(ResourceUID.path_to_uid(path))
	if uid == "" or uid == "uid://" or uid == "-1" or uid.begins_with("uid://<"):
		return ""
	return uid.replace("uid://", "")


static func _claim_span(start_id: String, lines: Dictionary, line_key: Dictionary, sig: Dictionary, owner_id: String) -> Array:
	var claimed: Array = []
	var stack: Array = [start_id]
	var visited := {}
	var guard := 0
	while not stack.is_empty() and guard < 800:
		guard += 1
		var cur_id := str(stack.pop_back())
		if cur_id == "" or cur_id == "end" or visited.has(cur_id):
			continue
		visited[cur_id] = true
		if sig.has(cur_id) and str(sig[cur_id]) != owner_id:
			continue
		claimed.append(cur_id)
		var line := _line(lines, line_key, cur_id)
		if line.is_empty():
			continue
		if str(line.get("type", "")) == "condition":
			var true_next := str(line.get("next_id", ""))
			var false_next := str(line.get("next_sibling_id", ""))
			if false_next == "":
				false_next = str(line.get("next_id_after", ""))
			if true_next != "":
				stack.append(true_next)
			if false_next != "":
				stack.append(false_next)
			continue
		var nxt := str(line.get("next_id", ""))
		if nxt == "":
			nxt = str(line.get("next_id_after", ""))
		if nxt != "" and nxt != cur_id:
			stack.append(nxt)
	return claimed


static func _prompt_id(lines: Dictionary, line_key: Dictionary, gid: String) -> String:
	for lid in line_key.keys():
		var line := _line(lines, line_key, lid)
		if str(line.get("next_id", "")) != gid:
			continue
		if str(line.get("type", "")) == "response":
			continue
		return str(lid)
	return ""


static func locate_player(nodes: Array, player: Dictionary) -> String:
	if bool(player.get("ended", false)):
		for node in nodes:
			if str(node.get("type", "")) == "ENDING" or str(node.get("id", "")) == "END":
				return str(node.get("id", ""))
	var response_ids: Array = player.get("response_ids", [])
	if not response_ids.is_empty():
		var wanted := {}
		for rid in response_ids:
			wanted[_bare_id(str(rid))] = true
		for node in nodes:
			for rid in node.get("response_ids", []):
				if wanted.has(_bare_id(str(rid))):
					return str(node.get("id", ""))
	var current := _id_pair(str(player.get("line_id", "")))
	var best := ""
	var best_rank := -1
	if str(current.get("line", "")) != "":
		for node in nodes:
			if str(node.get("type", "")) == "ENDING":
				continue
			if not _node_owns_line(node, current):
				continue
			var rank := int(node.get("layer", 0))
			if rank >= best_rank:
				best = str(node.get("id", ""))
				best_rank = rank
	if best != "":
		return best
	if str(player.get("line_id", "")) == "":
		for node in nodes:
			if bool(node.get("entry", false)):
				return str(node.get("id", ""))
	return ""


static func visited_node_ids(nodes: Array, player: Dictionary) -> Dictionary:
	var result := {}
	var current := locate_player(nodes, player)
	var seen_lines: Array = player.get("visited_ids", [])
	for node in nodes:
		var id := str(node.get("id", ""))
		if id != "" and id == current:
			result[id] = true
			continue
		if bool(player.get("ended", false)) and (str(node.get("type", "")) == "ENDING" or id == "END"):
			result[id] = true
			continue
		if str(node.get("type", "")) == "ENDING":
			continue
		for raw in seen_lines:
			if _node_owns_line(node, _id_pair(str(raw))):
				result[id] = true
				break
	return result


static func history_index_for(history_ids: Array, line_ids: Array, jump_key: String, file_uid: String = "") -> int:
	var wanted := {}
	for lid in line_ids:
		var bare := _bare_id(str(lid))
		if bare != "":
			wanted[bare] = true
	var jump_bare := _bare_id(jump_key)
	if _looks_like_line_id(jump_bare):
		wanted[jump_bare] = true
	if wanted.is_empty():
		return -1
	for i in history_ids.size():
		var parts := _id_pair(str(history_ids[i]))
		if file_uid != "" and str(parts.get("uid", "")) != "" and str(parts.get("uid", "")) != file_uid:
			continue
		if wanted.has(str(parts.get("line", ""))):
			return i
	return -1


## shown nodes only. relayout packs the visited subset so empty future columns
## do not sketch the rest of the story.
static func prepare_display(nodes: Array, shown: Dictionary, relayout: bool) -> Array:
	var picked: Array = []
	for node in nodes:
		if not shown.has(str(node.get("id", ""))):
			continue
		var copy: Dictionary = (node as Dictionary).duplicate(true)
		if relayout:
			var outputs: Array = []
			for outp in copy.get("outputs", []):
				if shown.has(str(outp.get("target", ""))):
					outputs.append(outp)
			copy["outputs"] = outputs
			copy["inputs"] = []
		picked.append(copy)
	if not relayout:
		return picked
	var by_id := {}
	for node in picked:
		by_id[str(node.get("id", ""))] = node
	_mirror_inputs(picked, by_id)
	for node in picked:
		node["w"] = MeshScript.measure_width(node)
		node["h"] = MeshScript.measure_height(node.get("inputs", []).size(), node.get("outputs", []).size())
		node["subtitle"] = "%d in / %d out" % [node.get("inputs", []).size(), node.get("outputs", []).size()]
	if not picked.is_empty():
		_layout(picked)
	return picked


## Display copies. Compile keeps English source strings so a locale switch can
## rebake without rebuilding the graph. Dialogue text uses the dialogue catalog;
## cue names, END, subtitles and condition badges use the UI catalog.
static func localized_title(node: Dictionary) -> String:
	var copy: Dictionary = node.duplicate(true)
	_localize_title(copy)
	return str(copy.get("title", ""))


static func localize_nodes(nodes: Array) -> Array:
	var out: Array = []
	for node in nodes:
		if typeof(node) != TYPE_DICTIONARY:
			continue
		var copy: Dictionary = (node as Dictionary).duplicate(true)
		_localize_node(copy)
		out.append(copy)
	return out


## Translate, then remeasure and lay out so longer translations still fit.
static func fit_localized(nodes: Array) -> Array:
	var localized := localize_nodes(nodes)
	for node in localized:
		node["w"] = MeshScript.measure_width(node)
		node["h"] = MeshScript.measure_height(node.get("inputs", []).size(), node.get("outputs", []).size())
	if not localized.is_empty():
		_layout(localized)
	return localized


static func _localize_node(node: Dictionary) -> void:
	_localize_title(node)
	var ins: int = node.get("inputs", []).size()
	var outs: int = node.get("outputs", []).size()
	node["subtitle"] = _tr_text("%d in / %d out", false) % [ins, outs]
	for side in ["inputs", "outputs"]:
		for port in node.get(side, []):
			if typeof(port) != TYPE_DICTIONARY:
				continue
			_localize_port(port)


static func _localize_title(node: Dictionary) -> void:
	var source := str(node.get("title_source", node.get("title", "")))
	var dialogue := bool(node.get("title_dialogue", false))
	var translated := _tr_text(source, dialogue)
	var arg := str(node.get("title_arg", ""))
	if arg != "" and (translated.find("%s") >= 0 or translated.find("%d") >= 0):
		translated = translated % arg
	if dialogue:
		translated = _display_sentence(translated)
		node["title"] = _short(translated, 42)
	else:
		node["title"] = translated


static func _localize_port(port: Dictionary) -> void:
	var kind := str(port.get("tag_kind", ""))
	var source := str(port.get("tag_source", port.get("tag", "")))
	var dialogue := bool(port.get("tag_dialogue", false))
	var limit := 24 if str(port.get("type", "")) == "CHOICE" or kind == "line" else 18
	if kind == "line" or (kind != "title" and dialogue):
		port["tag"] = _short(_tr_text(source, true), limit)
	elif kind == "title" or kind == "":
		var fake := {
			"title_source": source,
			"title_dialogue": dialogue,
			"title_arg": str(port.get("tag_arg", "")),
			"title": source,
		}
		_localize_title(fake)
		port["tag"] = _short(str(fake.get("title", "")), limit)
	else:
		port["tag"] = _short(_tr_text(source, false), limit)
	var cond_src := str(port.get("cond_source", port.get("cond", "")))
	if cond_src != "":
		port["cond"] = _short(_tr_text(cond_src, false), 28)


static func _tr_text(text: String, dialogue: bool) -> String:
	if text == "":
		return ""
	# tr() is illegal in a static function. The translation server is not.
	var translated := str(TranslationServer.translate(text, "dialogue" if dialogue else ""))
	if dialogue:
		translated = _strip_bbcode(translated)
	return translated


static func _display_sentence(text: String) -> String:
	var sentence := text.find(". ")
	if sentence > 8:
		return text.substr(0, sentence + 1)
	return text


static func _strip_bbcode(source: String) -> String:
	var out := ""
	var i := 0
	while i < source.length():
		if source[i] == "[":
			var close := source.find("]", i)
			if close < 0:
				out += source.substr(i)
				break
			i = close + 1
			continue
		out += source[i]
		i += 1
	return out


static func _node_owns_line(node: Dictionary, parts: Dictionary) -> bool:
	var line := str(parts.get("line", ""))
	if line == "":
		return false
	var node_uid := str(node.get("file_uid", ""))
	var uid := str(parts.get("uid", ""))
	if uid != "" and node_uid != "" and uid != node_uid:
		return false
	for lid in node.get("line_ids", []):
		if str(lid) == line:
			return true
	for lid in node.get("response_ids", []):
		if str(lid) == line:
			return true
	return false


static func _id_pair(id: String) -> Dictionary:
	var s := id.strip_edges()
	if "|" in s:
		s = s.split("|")[0]
	var uid := ""
	var line := s
	if "@" in s:
		var bits := s.split("@")
		uid = str(bits[0])
		line = str(bits[bits.size() - 1])
	return {"uid": uid, "line": line}


static func _bare_id(id: String) -> String:
	return str(_id_pair(id).get("line", ""))


static func _looks_like_line_id(id: String) -> bool:
	if id == "" or id == "END" or id == "end":
		return false
	var digits := false
	for i in id.length():
		var c := id.unicode_at(i)
		var ok := (c >= 48 and c <= 57) or c == 46
		if not ok:
			return false
		if c >= 48 and c <= 57:
			digits = true
	return digits
