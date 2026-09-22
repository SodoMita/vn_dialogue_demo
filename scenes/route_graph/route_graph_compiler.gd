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
		var title := _choice_title(lines, line_key, gid)
		var node := _make("choice_%s" % gid, "CHOICE", title, Color("#D97706"), "%d options" % choice_groups[gid].size())
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
			var tag := _short(str(response.get("text", rid)), 24)
			var response_cond := _short(_cond_text(response), 28)
			var next_id := str(response.get("next_id", ""))
			var targets: Array = _collect(next_id, lines, line_key, sig, by_id) if next_id != "" else []
			if targets.is_empty():
				targets = [{"target": "END", "cond": ""}]
			for item in _merge_targets(targets):
				var cond := response_cond
				var extra := str(item.get("cond", ""))
				if extra != "":
					cond = extra if cond == "" else "%s && %s" % [cond, extra]
				var target_id := str(item.get("target", ""))
				if not by_id.has(target_id) or target_id == src.id:
					continue
				src.outputs.append({
					"type": "CHOICE",
					"tag": tag,
					"label": by_id[target_id].title,
					"target": target_id,
					"cond": _short(cond, 28),
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
		"color": color,
		"subtitle": subtitle,
		"x": 0.0,
		"y": 0.0,
		"w": 240.0,
		"h": 140.0,
		"inputs": [],
		"outputs": [],
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


static func _choice_title(lines: Dictionary, line_key: Dictionary, gid: String) -> String:
	for lid in line_key.keys():
		var line := _line(lines, line_key, lid)
		if str(line.get("next_id", "")) != gid:
			continue
		if str(line.get("type", "")) == "response":
			continue
		var text := str(line.get("text", "")).strip_edges()
		if text != "":
			var sentence := text.find(". ")
			if sentence > 8:
				text = text.substr(0, sentence + 1)
			return _short(text, 42)
	return "Choice %s" % gid


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
		src.outputs.append({
			"type": type,
			"tag": _short(str(by_id[target_id].title), 18),
			"label": by_id[target_id].title,
			"target": target_id,
			"cond": _short(str(item.get("cond", "")), 28),
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
			if str(node.get("type", "")) != "CHOICE":
				tag = _short(str(node.title), 18)
			by_id[target_id].inputs.append({
				"type": outp.get("type", "FLOW"),
				"tag": tag,
				"label": node.title,
				"source": node.id,
				"cond": outp.get("cond", ""),
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
