extends RefCounted
## Silent story travel. The graph only names the target. Dialogue Manager walks
## the lines, so conditions and mutations stay the engine's, not a second copy.
## No class_name: a missing UID class cache must not break parsing.


const CompilerScript = preload("res://scenes/route_graph/route_graph_compiler.gd")
const DMConstants = preload("res://addons/dialogue_manager/constants.gd")

const STEP_LIMIT := 400


## Earliest history entry that already shows this header, including a future
## entry that has not been truncated. -1 if the player has never been there.
static func history_index(history: Array, target: Dictionary) -> int:
	var ids: Array = []
	for entry in history:
		if entry is Dictionary:
			ids.append(str(entry.get("id", "")))
	return CompilerScript.history_index_for(
		ids,
		target.get("line_ids", []),
		str(target.get("jump_key", "")),
		str(target.get("file_uid", ""))
	)


## Walk from [param start_key] until a target line. On failure, [param game_state]
## is restored to the snapshot taken at entry. [param include_start] is false when
## the player is already standing on [param start_key] and that line is in history.
static func replay(resource, start_key: String, target: Dictionary, history: Array, hist_pos: int, game_state: Node, extra_states: Array, allow_diverge: bool, include_start: bool, stage: Dictionary) -> Dictionary:
	var origin := _capture(game_state)
	if resource == null:
		return {"ok": false, "blocked": false, "diverged": false, "lines": [], "line": null}
	var wanted := _wanted(target)
	if wanted.is_empty():
		return {"ok": false, "blocked": false, "diverged": false, "lines": [], "line": null}
	var found: Dictionary = await _walk(resource, start_key, wanted, history, hist_pos, game_state, extra_states, allow_diverge, include_start, stage.duplicate(true), {}, 0)
	if not bool(found.get("ok", false)):
		_restore(game_state, origin)
	return found


static func _wanted(target: Dictionary) -> Dictionary:
	var wanted := {}
	for lid in target.get("line_ids", []):
		var text := str(lid)
		if text == "":
			continue
		wanted[text] = true
		wanted[CompilerScript._bare_id(text)] = true
	var jump := str(target.get("jump_key", ""))
	if jump != "" and jump != "END" and jump != "end":
		wanted[jump] = true
		wanted[CompilerScript._bare_id(jump)] = true
	return wanted


static func _matches(line_id: String, wanted: Dictionary) -> bool:
	return wanted.has(line_id) or wanted.has(CompilerScript._bare_id(line_id))


static func _capture(game_state: Node) -> Dictionary:
	if game_state != null and game_state.has_method("snapshot"):
		return game_state.snapshot()
	return {}


static func _restore(game_state: Node, data: Dictionary) -> void:
	if game_state != null and game_state.has_method("restore") and not data.is_empty():
		game_state.restore(data)


static func _walk(resource, key: String, wanted: Dictionary, history: Array, hist_pos: int, game_state: Node, extra_states: Array, allow_diverge: bool, include_start: bool, stage: Dictionary, seen: Dictionary, steps: int) -> Dictionary:
	# An empty key is the file's first cue only on the opening call. Later, it means the line has no next.
	if steps > STEP_LIMIT or _is_end(key) or (key == "" and steps > 0):
		return {"ok": false, "blocked": false, "diverged": false, "lines": [], "line": null}
	if key != "" and (seen.has(key) or seen.has(CompilerScript._bare_id(key))):
		return {"ok": false, "blocked": false, "diverged": false, "lines": [], "line": null}
	var line: DialogueLine = await resource.get_next_dialogue_line(key, extra_states, DMConstants.MutationBehaviour.Wait)
	if line == null:
		return {"ok": false, "blocked": false, "diverged": false, "lines": [], "line": null}
	var lid := str(line.id)
	if seen.has(lid):
		return {"ok": false, "blocked": false, "diverged": false, "lines": [], "line": null}
	var next_seen := seen.duplicate()
	next_seen[lid] = true
	next_seen[CompilerScript._bare_id(lid)] = true
	var here := _dress(stage, line)
	var at_target := _matches(lid, wanted)
	# Snapshot on arrival. Recording after the child walk would stamp the ending state onto earlier lines.
	var arrived := _record(line, here, game_state)
	if at_target and include_start:
		return {"ok": true, "blocked": false, "diverged": false, "lines": [arrived], "line": line}
	if at_target and not include_start:
		return {"ok": true, "blocked": false, "diverged": false, "lines": [], "line": line}
	var next_hist := _consume(history, hist_pos, lid)
	if line.responses.size() > 0:
		return await _walk_choices(resource, line, wanted, history, next_hist, game_state, extra_states, allow_diverge, here, next_seen, steps, include_start, arrived)
	var nxt := str(line.next_id)
	if nxt == "" or _is_end(nxt):
		return {"ok": false, "blocked": false, "diverged": false, "lines": [], "line": null}
	var child: Dictionary = await _walk(resource, nxt, wanted, history, next_hist, game_state, extra_states, allow_diverge, true, here, next_seen, steps + 1)
	if not bool(child.get("ok", false)):
		return child
	if include_start:
		var lines: Array = [arrived]
		lines.append_array(child.get("lines", []))
		child["lines"] = lines
	return child


static func _walk_choices(resource, line: DialogueLine, wanted: Dictionary, history: Array, hist_pos: int, game_state: Node, extra_states: Array, allow_diverge: bool, stage: Dictionary, seen: Dictionary, steps: int, include_start: bool, prompt_record: Dictionary) -> Dictionary:
	var recorded := _recorded_next(history, hist_pos)
	var snap := _capture(game_state)
	var ordered: Array = await _order_responses(resource, line, recorded, game_state, extra_states)
	_restore(game_state, snap)
	var tried_hist := false
	var blocked := false
	for item in ordered:
		var historical: bool = bool(item.get("historical", false))
		if recorded != "" and not historical and not allow_diverge:
			blocked = true
			continue
		if historical:
			tried_hist = true
		_restore(game_state, snap)
		var child: Dictionary = await _walk(resource, str(item.get("next_id", "")), wanted, history, hist_pos, game_state, extra_states, allow_diverge, true, stage, seen.duplicate(), steps + 1)
		if bool(child.get("ok", false)):
			var diverged: bool = (recorded != "" and not historical) or bool(child.get("diverged", false))
			if diverged and not allow_diverge:
				_restore(game_state, snap)
				return {"ok": false, "blocked": true, "diverged": true, "lines": [], "line": null}
			var lines: Array = []
			if include_start:
				lines.append(prompt_record)
			lines.append_array(child.get("lines", []))
			return {"ok": true, "blocked": false, "diverged": diverged, "lines": lines, "line": child.get("line")}
		if bool(child.get("blocked", false)):
			blocked = true
	_restore(game_state, snap)
	var refused := recorded != "" and not allow_diverge and not tried_hist
	return {"ok": false, "blocked": blocked or refused, "diverged": false, "lines": [], "line": null}


## Historical response first, so a replay keeps the longest prefix of the played branch.
static func _order_responses(resource, line: DialogueLine, recorded: String, game_state: Node, extra_states: Array) -> Array:
	var snap := _capture(game_state)
	var ranked: Array = []
	var rest: Array = []
	for response in line.responses:
		_restore(game_state, snap)
		var next_id := str(response.next_id)
		var landed := ""
		if next_id != "" and not _is_end(next_id):
			var peeked: DialogueLine = await resource.get_next_dialogue_line(next_id, extra_states, DMConstants.MutationBehaviour.Wait)
			if peeked != null:
				landed = str(peeked.id)
		var historical: bool = recorded != "" and (landed == recorded or CompilerScript._bare_id(landed) == CompilerScript._bare_id(recorded) or next_id == recorded or CompilerScript._bare_id(next_id) == CompilerScript._bare_id(recorded))
		var item := {"next_id": next_id, "historical": historical}
		if historical:
			ranked.append(item)
		else:
			rest.append(item)
	_restore(game_state, snap)
	ranked.append_array(rest)
	return ranked


static func _consume(history: Array, hist_pos: int, line_id: String) -> int:
	if hist_pos >= 0 and hist_pos < history.size():
		var entry = history[hist_pos]
		if entry is Dictionary and _same_line(str(entry.get("id", "")), line_id):
			return hist_pos + 1
	return hist_pos


static func _recorded_next(history: Array, hist_pos: int) -> String:
	if hist_pos >= 0 and hist_pos < history.size():
		var entry = history[hist_pos]
		if entry is Dictionary:
			return str(entry.get("id", ""))
	return ""


static func _same_line(a: String, b: String) -> bool:
	return a == b or CompilerScript._bare_id(a) == CompilerScript._bare_id(b)


static func _is_end(key: String) -> bool:
	return key == "end" or key == "end!" or key == "END"


static func _dress(stage: Dictionary, line: DialogueLine) -> Dictionary:
	var next := stage.duplicate(true)
	for tag in line.tags:
		var text := str(tag)
		if text.begins_with("bg="):
			next["bg"] = text.substr(3)
		elif text.begins_with("sprite="):
			var spec := text.substr(7)
			var parts := spec.split(":")
			var sprite_key := parts[0]
			var slot := "left" if parts.size() == 1 or parts[1] == "left" else "right"
			next[slot] = sprite_key
		elif text.begins_with("focus="):
			next["focus"] = text.substr(6)
	return next


static func _record(line: DialogueLine, stage: Dictionary, game_state: Node) -> Dictionary:
	var entry := {
		"id": str(line.id),
		"character": line.character,
		"text": _plain(line.text),
		"bg": str(stage.get("bg", "")),
		"left": str(stage.get("left", "")),
		"right": str(stage.get("right", "")),
		"focus": str(stage.get("focus", "")),
		"choices": line.responses.size() > 0,
	}
	if game_state != null and game_state.has_method("snapshot"):
		entry["state"] = game_state.snapshot()
	return entry


static func _plain(source: String) -> String:
	var out := ""
	var i := 0
	while i < source.length():
		if source[i] == "[":
			var close := source.find("]", i)
			if close < 0:
				out += source.substr(i)
				break
			i = close + 1
		else:
			out += source[i]
			i += 1
	return out
