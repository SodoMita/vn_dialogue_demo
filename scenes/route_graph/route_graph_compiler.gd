class_name RouteGraphCompiler
# Runtime compiler: dialogue/*.dialogue -> route graph nodes
# Design: only routing + starts/ends, no 1-in/1-out filler, conditions as badges on ports

static func compile(resource: DialogueResource) -> Dictionary:
	if resource == null:
		return {"nodes": [], "edges": []}

	var lines: Dictionary = resource.lines
	var cues: Dictionary = resource.cues

	# Maps
	var cue_line_to_name: Dictionary = {}
	var first_dialogue_to_cue: Dictionary = {}
	for lid in lines.keys():
		var l: Dictionary = lines[lid]
		if l.get("type","") == "cue":
			var nid: String = l.get("next_id","")
			for cname in cues.keys():
				if cues[cname] == nid:
					cue_line_to_name[lid] = cname
					first_dialogue_to_cue[nid] = cname
	# Also direct mapping from cues dict
	for cname in cues.keys():
		first_dialogue_to_cue[cues[cname]] = cname

	# Targeted cues
	var targeted: Dictionary = {}
	for lid in lines.keys():
		var l: Dictionary = lines[lid]
		if l.get("type","") == "goto":
			var nid: String = l.get("next_id","")
			if nid == "end":
				continue
			if first_dialogue_to_cue.has(nid):
				targeted[first_dialogue_to_cue[nid]] = true
			if cue_line_to_name.has(nid):
				targeted[cue_line_to_name[nid]] = true
			for cname in cues.keys():
				if cues[cname] == nid:
					targeted[cname] = true

	var create_node = func(id: String, type: String, title: String, full: String, color: Color, subtitle: String) -> Dictionary:
		return {
			"id": id,
			"type": type,
			"color": color,
			"title": title,
			"full": full,
			"x": 0, "y": 0, "w": 260, "h": 150,
			"inputs": [],
			"outputs": [],
			"subtitle": subtitle,
			"has_conds": false
		}

	var nodes: Array = []
	var by_id: Dictionary = {}

	# Cue nodes (starts + routes)
	var first_cue_name: String = _first_cue_name(resource, cue_line_to_name, first_dialogue_to_cue)
	for cname in cues.keys():
		var is_start: bool = not targeted.has(cname) or cname == first_cue_name
		var type: String = "START" if is_start else "ROUTE"
		var color: Color = Color("#16A34A") if is_start else Color("#0F766E")
		var node: Dictionary = create_node.call(cname, type, cname.capitalize(), cname, color, "cue • %s" % ("entry" if is_start else "route"))
		node.w = 230
		node.h = 135
		nodes.append(node)
		by_id[cname] = node

	# Choice groups
	var choice_groups: Dictionary = {}
	for lid in lines.keys():
		var l: Dictionary = lines[lid]
		if l.get("type","") == "response" and l.has("responses"):
			var arr: Array = l.responses
			if arr.size() > 1:
				var is_sub: bool = false
				for g in choice_groups.keys():
					if lid in choice_groups[g].responses and lid != g:
						is_sub = true
						break
				if not is_sub:
					choice_groups[lid] = {"responses": arr}

	for gid in choice_groups.keys():
		var resp_ids: Array = choice_groups[gid].responses
		var prev_text: String = ""
		for lid in lines.keys():
			var l: Dictionary = lines[lid]
			if l.get("next_id","") == gid:
				if l.has("text"):
					prev_text = l.text
					break
		var title: String = "Choice"
		if prev_text != "":
			title = prev_text.left(24)
			if prev_text.length() > 24:
				title += "..."
		else:
			title = "Choice %s" % gid

		var node_id: String = "choice_%s" % gid
		var node: Dictionary = create_node.call(node_id, "CHOICE", title, title, Color("#D97706"), "%d options" % resp_ids.size())
		node.w = 300
		node.h = 100 + resp_ids.size()*46
		node.has_conds = true
		nodes.append(node)
		by_id[node_id] = node

	# END node
	var end_node: Dictionary = create_node.call("END", "ENDING", "END", "END", Color("#475569"), "ending")
	end_node.w = 180
	end_node.h = 100
	nodes.append(end_node)
	by_id["END"] = end_node

	# Significant mapping (only cues, choices, END) — no condition nodes
	var sig: Dictionary = {}
	for cname in cues.keys():
		sig[cues[cname]] = cname
		for lid in cue_line_to_name.keys():
			if cue_line_to_name[lid] == cname:
				sig[lid] = cname
	for gid in choice_groups.keys():
		sig[gid] = "choice_%s" % gid
	sig["end"] = "END"

	# Helper: collect targets from a line id, with condition accumulation, no condition nodes
	var collect_targets = func(start_id: String) -> Array:
		# Returns Array of {target: String, cond: String}
		var results: Array = []
		var stack: Array = [{"id": start_id, "cond": ""}]
		var visited: Dictionary = {}
		var iterations: int = 0
		while stack.size() > 0 and iterations < 500:
			iterations += 1
			var cur_item: Dictionary = stack.pop_back()
			var cur_id: String = cur_item.id
			var cur_cond: String = cur_item.cond

			if visited.has(cur_id + "|" + cur_cond):
				continue
			visited[cur_id + "|" + cur_cond] = true

			if cur_id == "end":
				results.append({"target": "END", "cond": cur_cond})
				continue

			# If cur is significant and not the start, return it
			if sig.has(cur_id) and cur_id != start_id:
				results.append({"target": sig[cur_id], "cond": cur_cond})
				continue

			var l: Dictionary = lines.get(cur_id, {})
			if l.is_empty():
				# Maybe cur is cue name?
				if by_id.has(cur_id) and cur_id != start_id:
					results.append({"target": cur_id, "cond": cur_cond})
				continue

			var ltype: String = l.get("type","")
			if ltype == "condition":
				var cond_txt: String = _expr_to_text(l.get("condition", {}))
				if cond_txt == "":
					cond_txt = l.get("condition_as_text", "")
					if cond_txt == "":
						cond_txt = "else"
				var true_next: String = l.get("next_id","")
				var false_next: String = l.get("next_sibling_id","")
				if false_next == "":
					false_next = l.get("next_id_after","")

				# True branch
				if true_next != "":
					var new_cond: String = cur_cond
					if cond_txt != "else":
						if new_cond != "":
							new_cond += " && " + cond_txt
						else:
							new_cond = cond_txt
					stack.append({"id": true_next, "cond": new_cond})

				# False branch
				if false_next != "":
					var new_cond_f: String = cur_cond
					if cond_txt == "else":
						# else has no condition, keep cur_cond
						pass
					else:
						var neg: String = "!" + cond_txt if not cond_txt.begins_with("!") else cond_txt.substr(1)
						if new_cond_f != "":
							new_cond_f += " && " + neg
						else:
							new_cond_f = neg
					stack.append({"id": false_next, "cond": new_cond_f})
				continue

			# Normal line: follow next_id
			var nxt: String = l.get("next_id","")
			if nxt == "":
				nxt = l.get("next_id_after","")
			if nxt == "":
				continue
			if nxt == "end":
				results.append({"target": "END", "cond": cur_cond})
				continue
			# If nxt is significant, return it
			if sig.has(nxt):
				results.append({"target": sig[nxt], "cond": cur_cond})
				continue
			if first_dialogue_to_cue.has(nxt):
				results.append({"target": first_dialogue_to_cue[nxt], "cond": cur_cond})
				continue
			if cue_line_to_name.has(nxt):
				results.append({"target": cue_line_to_name[nxt], "cond": cur_cond})
				continue
			stack.append({"id": nxt, "cond": cur_cond})
		return results

	# Build outputs

	# Cues -> next significant
	for cname in cues.keys():
		var fid: String = cues[cname]
		var targets: Array = collect_targets.call(fid)
		# Group by target, if multiple conds lead to same target, merge to no cond (both branches)
		var grouped: Dictionary = {}
		for t in targets:
			var tgt: String = t.target
			if tgt == cname:
				continue
			if not grouped.has(tgt):
				grouped[tgt] = []
			grouped[tgt].append(t.cond)
		for tgt in grouped.keys():
			var conds: Array = grouped[tgt]
			var final_cond: String = ""
			if conds.size() == 1:
				final_cond = conds[0]
			else:
				# multiple paths to same target -> if they are negations of each other, treat as no cond (both lead there)
				# Check if conds contain both X and !X -> merge to ""
				var has_both: bool = false
				# Simple heuristic: if we have 2 conds and one is negation of other, or one contains "&&" etc, just clear
				if conds.size() >= 2:
					final_cond = ""
				else:
					final_cond = conds[0]
			var src: Dictionary = by_id[cname]
			var full_dest: String = by_id[tgt].full if by_id.has(tgt) else tgt
			var label: String = RouteGraphData.display_label(full_dest, tgt, by_id[tgt].title if by_id.has(tgt) else tgt)
			src.outputs.append({
				"type": "FLOW",
				"tag": "OUT",
				"label": label,
				"target": tgt,
				"full_dest": full_dest,
				"cond": final_cond
			})

	# Choices -> each response option collects targets
	for gid in choice_groups.keys():
		var node_id: String = "choice_%s" % gid
		if not by_id.has(node_id):
			continue
		var src: Dictionary = by_id[node_id]
		var resp_ids: Array = choice_groups[gid].responses
		for rid in resp_ids:
			var rline: Dictionary = lines.get(rid, {})
			var rtext: String = rline.get("text","")
			if rtext == "":
				rtext = rid
			var rcond: String = ""
			if rline.has("condition"):
				rcond = _expr_to_text(rline.condition)
				if rcond == "":
					rcond = rline.get("condition_as_text","")

			var next_id: String = rline.get("next_id","")
			var targets: Array = collect_targets.call(next_id)
			if targets.is_empty():
				targets = [{"target": "END", "cond": ""}]

			# Group targets by destination to merge conds that lead to same place
			var grouped: Dictionary = {}
			for t in targets:
				var tgt: String = t.target
				if not grouped.has(tgt):
					grouped[tgt] = []
				grouped[tgt].append(t.cond)

			for tgt in grouped.keys():
				var cond_list: Array = grouped[tgt]
				var combined_cond: String = rcond
				# If multiple conds lead to same tgt, treat as no extra cond (both branches)
				var extra_cond: String = ""
				if cond_list.size() == 1:
					extra_cond = cond_list[0]
				else:
					extra_cond = "" # both branches lead to same target

				if extra_cond != "":
					if combined_cond != "":
						combined_cond += " && " + extra_cond
					else:
						combined_cond = extra_cond

				var full_dest: String = by_id[tgt].full if by_id.has(tgt) else tgt
				var label: String = RouteGraphData.display_label(full_dest, tgt, by_id[tgt].title if by_id.has(tgt) else tgt)
				src.outputs.append({
					"type": "CHOICE",
					"tag": rtext.left(12),
					"label": label,
					"target": tgt,
					"full_dest": full_dest,
					"cond": combined_cond
				})

	# Rebuild inputs
	for n in nodes:
		n.inputs.clear()
	for n in nodes:
		for outp in n.outputs:
			var tgt_id: String = outp.target
			if by_id.has(tgt_id):
				var tgt: Dictionary = by_id[tgt_id]
				var full_src: String = n.full
				var in_label: String = RouteGraphData.display_label(full_src, n.id, n.title)
				tgt.inputs.append({
					"type": outp.type,
					"tag": outp.tag,
					"label": in_label,
					"source": n.id,
					"full_src": full_src,
					"cond": outp.get("cond","")
				})

	# Filter: keep only routing + starts/ends, no 1-in/1-out
	var filtered: Array = []
	var final_by_id: Dictionary = {}
	for n in nodes:
		var ni: int = n.inputs.size()
		var no: int = n.outputs.size()
		var is_start: bool = n.type == "START"
		var is_end: bool = n.type == "ENDING"
		var is_routing: bool = ni >= 2 or no >= 2
		# Choice nodes are routing even if dedup leads to 1 out? Keep them if they have multiple response options originally
		if n.type == "CHOICE":
			is_routing = true
		if is_start or is_end or is_routing:
			filtered.append(n)
			final_by_id[n.id] = n

	# Bypass removed nodes
	var removed: Dictionary = {}
	for n in nodes:
		if not final_by_id.has(n.id):
			removed[n.id] = n

	# For each removed node, retarget its inputs' outputs to its outputs
	for rem_id in removed.keys():
		var rem: Dictionary = removed[rem_id]
		for src_id in final_by_id.keys():
			var src: Dictionary = final_by_id[src_id]
			for outp in src.outputs:
				if outp.target == rem_id:
					if rem.outputs.size() > 0:
						# Pick first output of removed
						outp.target = rem.outputs[0].target
						outp.full_dest = rem.outputs[0].full_dest
						outp.label = rem.outputs[0].label
						# Merge conds
						var rc: String = rem.outputs[0].get("cond","")
						if rc != "" and outp.get("cond","") == "":
							outp.cond = rc
					else:
						outp.target = "END"

	# Rebuild inputs again
	for n in filtered:
		n.inputs.clear()
	for n in filtered:
		for outp in n.outputs:
			var tgt_id: String = outp.target
			if final_by_id.has(tgt_id):
				var tgt: Dictionary = final_by_id[tgt_id]
				var full_src: String = n.full
				var in_label: String = RouteGraphData.display_label(full_src, n.id, n.title)
				tgt.inputs.append({
					"type": outp.type,
					"tag": outp.tag,
					"label": in_label,
					"source": n.id,
					"full_src": full_src,
					"cond": outp.get("cond","")
				})

	_layout_nodes(filtered)

	return {"nodes": filtered, "edges": []}

static func _first_cue_name(resource: DialogueResource, cue_line_map: Dictionary, first_dialogue_map: Dictionary) -> String:
	var first_id: String = resource.first_cue
	if cue_line_map.has(first_id):
		return cue_line_map[first_id]
	var first_line: Dictionary = resource.lines.get(first_id, {})
	var nid: String = first_line.get("next_id","")
	if first_dialogue_map.has(nid):
		return first_dialogue_map[nid]
	if resource.cues.size() > 0:
		return resource.cues.keys()[0]
	return ""

static func _expr_to_text(expr: Dictionary) -> String:
	if expr.is_empty():
		return ""
	var arr: Array = expr.get("expression", [])
	var parts: Array = []
	for item in arr:
		var t: String = item.get("type","")
		var v: Variant = item.get("value","")
		if t == "variable":
			parts.append(str(v))
		elif t == "number":
			parts.append(str(v))
		elif t == "string":
			parts.append("\"%s\"" % str(v))
		elif t == "comparison" or t == "operator" or t == "assignment" or t == "and_or" or t == "negation":
			parts.append(str(v))
		elif t == "function":
			parts.append(str(v))
		else:
			parts.append(str(v))
	return " ".join(parts).strip_edges()

static func _layout_nodes(nodes: Array) -> void:
	var by_id: Dictionary = {}
	for n in nodes:
		by_id[n.id] = n
		n["layer"] = -1

	var starts: Array = []
	for n in nodes:
		if n.type == "START":
			starts.append(n)
			n.layer = 0

	if starts.is_empty() and nodes.size() > 0:
		nodes[0].layer = 0
		starts.append(nodes[0])

	var queue: Array = starts.duplicate()
	var visited: Dictionary = {}
	while queue.size() > 0:
		var cur: Dictionary = queue.pop_front()
		if visited.has(cur.id):
			continue
		visited[cur.id] = true
		for outp in cur.outputs:
			var tgt_id: String = outp.target
			if by_id.has(tgt_id):
				var tgt: Dictionary = by_id[tgt_id]
				if tgt.layer < cur.layer + 1:
					tgt.layer = cur.layer + 1
				queue.append(tgt)

	var layers: Dictionary = {}
	var max_layer: int = 0
	for n in nodes:
		if n.layer == -1:
			n.layer = 0
		max_layer = max(max_layer, n.layer)
		if not layers.has(n.layer):
			layers[n.layer] = []
		layers[n.layer].append(n)

	var gap: int = 360
	for l in range(max_layer+1):
		if not layers.has(l):
			continue
		var arr: Array = layers[l]
		arr.sort_custom(func(a,b): return a.id < b.id)
		var y: int = 80
		for n in arr:
			n.x = 30 + l*gap
			n.y = y
			y += n.h + 200
			var rows: int = max(n.inputs.size(), n.outputs.size())
			if rows == 0:
				rows = 1
			var row_h: int = 46 if n.get("has_conds", false) else 34
			var needed: int = 90 + rows*row_h + 30
			if n.h < needed:
				n.h = needed
