class_name StageTagParser extends RefCounted
## Pure parser for the short staging tags (#show #move #hide #focus #anim
## #video #stage). No nodes, no side effects - the balloon, StageActors and
## the route-map walker all share it, so a tag means the same thing live,
## on restore and while exploring branches.
##
## Contract (edit plan, appendix F):
## - The command name ends at the FIRST "="; the payload at its first "?".
## - Options are "&"-separated, each split at its first "=". Duplicates are
##   rejected. Spaces never terminate a tag.
## - For show/move/hide, "@" ends the actor[:look] part. The target runs to
##   "?" or the end: a named place (identifier) or a numeric vector of 2
##   (2D) or 3 (3D) finite, whitespace-separated components.
## - `by=` uses the same numeric-vector rule. A move names exactly one
##   target: @place/@coords OR ?by=vector.

## Commands this parser owns (legacy bg/sprite/focus=left|right are handled
## by the balloon; focus is shared).
const COMMANDS: PackedStringArray = ["show", "move", "hide", "focus", "anim", "video", "stage"]
## Options each command accepts. Anything else is rejected.
const ALLOWED_OPTS := {
	"show": ["t"],
	"move": ["t", "by", "trans", "ease"],
	"hide": ["t", "trans", "ease"],
	"focus": [],
	"anim": ["loop"],
	"video": ["loop", "on", "volume"],
	"stage": [],
}

static var _ident: RegEx


static func _ident_rx() -> RegEx:
	if _ident == null:
		_ident = RegEx.new()
		_ident.compile("^[A-Za-z_][A-Za-z0-9_]*$")
	return _ident


static func is_identifier(text: String) -> bool:
	return _ident_rx().search(text) != null


## True when [param tag] (without "#") is one of the short staging tags.
## `focus=` is included: it resolves legacy slots and actor IDs alike.
static func is_stage_tag(tag: String) -> bool:
	var eq := tag.find("=")
	if eq <= 0:
		return false
	return COMMANDS.has(tag.substr(0, eq))


## Parse a whitespace-separated numeric vector. Returns an Array of floats
## (2 or 3 finite components) or null.
static func parse_vector(text: String) -> Variant:
	var parts := text.strip_edges().split(" ", false)
	var clean: Array = []
	for part: String in parts:
		var p := part.strip_edges()
		if p == "":
			continue
		if not p.is_valid_float():
			return null
		var v := p.to_float()
		if is_nan(v) or is_inf(v):
			return null
		clean.append(v)
	if clean.size() < 2 or clean.size() > 3:
		return null
	return clean


static func _fail(tag: String, reason: String) -> Dictionary:
	return {"ok": false, "tag": tag, "error": reason}


## Parse one tag (no leading "#"). Returns a Dictionary with "ok"; on
## success: cmd, actor, look, place (String or ""), coords (Array or null),
## by (Array or null), opts (Dictionary of String -> String|true), plus
## "stop" for video and "clip" for anim.
static func parse(tag: String) -> Dictionary:
	var eq := tag.find("=")
	if eq <= 0:
		return _fail(tag, "expected command=payload")
	var cmd := tag.substr(0, eq).strip_edges()
	if not COMMANDS.has(cmd):
		return _fail(tag, "unknown staging command '%s'" % cmd)
	var payload := tag.substr(eq + 1)
	var head := payload
	var opts: Dictionary = {}
	var q := payload.find("?")
	if q >= 0:
		head = payload.substr(0, q)
		for item: String in payload.substr(q + 1).split("&"):
			if item.strip_edges() == "":
				return _fail(tag, "empty option")
			var ieq := item.find("=")
			var k := (item.substr(0, ieq) if ieq >= 0 else item).strip_edges()
			var v: Variant = item.substr(ieq + 1).strip_edges() if ieq >= 0 else true
			if k == "":
				return _fail(tag, "option without a name")
			if opts.has(k):
				return _fail(tag, "duplicate option '%s'" % k)
			if not (ALLOWED_OPTS[cmd] as Array).has(k):
				return _fail(tag, "option '%s' is not valid for #%s" % [k, cmd])
			opts[k] = v
	var out := {"ok": true, "tag": tag, "cmd": cmd, "actor": "", "look": "", "place": "", "coords": null, "by": null, "opts": opts}
	if opts.has("t"):
		var t := str(opts.t)
		if not t.is_valid_float() or t.to_float() < 0.0 or is_inf(t.to_float()):
			return _fail(tag, "t must be a non-negative number of seconds")
	if opts.has("by"):
		if opts.by is bool:
			return _fail(tag, "by needs a vector")
		var by: Variant = parse_vector(str(opts.by))
		if by == null:
			return _fail(tag, "by must be 2 or 3 numbers separated by spaces")
		out.by = by
	match cmd:
		"show", "move", "hide":
			var at := head.find("@")
			var who := head if at < 0 else head.substr(0, at)
			var target := "" if at < 0 else head.substr(at + 1).strip_edges()
			if at >= 0 and target == "":
				return _fail(tag, "@ needs a place or coordinates")
			var colon := who.find(":")
			var actor := (who if colon < 0 else who.substr(0, colon)).strip_edges()
			var look := "" if colon < 0 else who.substr(colon + 1).strip_edges()
			if not is_identifier(actor):
				return _fail(tag, "actor must be an ID like maya")
			if colon >= 0 and not is_identifier(look):
				return _fail(tag, "look must be a name like smile")
			if cmd != "show" and look != "":
				return _fail(tag, "only #show changes the look")
			out.actor = actor
			out.look = look
			if target != "":
				if is_identifier(target):
					out.place = target
				else:
					var v: Variant = parse_vector(target)
					if v == null:
						return _fail(tag, "@ needs a place name or 2/3 numbers")
					out.coords = v
			if cmd == "move":
				var has_target: bool = out.place != "" or out.coords != null
				if has_target and out.by != null:
					return _fail(tag, "a move names @place OR ?by=, not both")
				if not has_target and out.by == null:
					return _fail(tag, "a move needs @place, @x y or ?by=x y")
			elif out.by != null:
				return _fail(tag, "?by= is only valid for #move")
		"focus":
			var id := head.strip_edges()
			if not is_identifier(id):
				return _fail(tag, "focus needs an actor ID")
			out.actor = id
		"anim":
			var parts := head.split(":", true, 1)
			if parts.size() != 2 or not is_identifier(parts[0].strip_edges()) or parts[1].strip_edges() == "":
				return _fail(tag, "expected #anim=actor:clip")
			out.actor = parts[0].strip_edges()
			out.clip = parts[1].strip_edges()
		"video":
			var parts := head.split(":", true, 1)
			var name := parts[0].strip_edges()
			if not is_identifier(name):
				return _fail(tag, "expected #video=name or #video=name:stop")
			out.name = name
			out.stop = parts.size() == 2 and parts[1].strip_edges() == "stop"
			if parts.size() == 2 and not out.stop:
				return _fail(tag, "the only video action is :stop")
			if opts.has("on") and not is_identifier(str(opts.on)):
				return _fail(tag, "on= needs an actor ID")
		"stage":
			var name := head.strip_edges()
			if name != "2d" and not is_identifier(name):
				return _fail(tag, "expected #stage=name or #stage=2d")
			out.name = name
	return out


## Presentation commands of one line, in story order, with the implicit
## speaker focus appended (a speaker's own #sprite= brings them forward
## unless the line names a focus). Shared by the balloon and the route-map
## walker so both record the same list. Returns an Array of tag Strings.
static func line_commands(tags: Array, speaker: String) -> Array:
	var out: Array = []
	var speaker_slot := ""
	var had_focus := false
	for raw: Variant in tags:
		var tag := str(raw)
		if tag.begins_with("bg=") or tag.begins_with("sprite="):
			out.append(tag)
			if tag.begins_with("sprite="):
				var slot := speaker_slot_for_sprite(tag.substr(7), speaker)
				if slot != "":
					speaker_slot = slot
		elif tag.begins_with("focus="):
			had_focus = true
			out.append(tag)
		elif is_stage_tag(tag) or is_motion_tag(tag):
			out.append(tag)
	if not had_focus and speaker_slot != "":
		out.append("focus=" + speaker_slot)
	return out


## Klima's advanced motion tags (StageDirector).
static func is_motion_tag(tag: String) -> bool:
	for prefix: String in ["tween=", "tween_stop=", "set=", "shake=", "nla=", "nla_stop=", "nla_track=", "target=", "sprite3d=", "place3d="]:
		if tag.begins_with(prefix):
			return true
	return false


## Slot of a portrait tag that belongs to the speaking character, or "".
static func speaker_slot_for_sprite(spec: String, speaker: String) -> String:
	var parts: PackedStringArray = spec.split(":")
	var key := parts[0].strip_edges().to_lower()
	var who := speaker.strip_edges().to_lower()
	if who == "" or key == "" or key == "none":
		return ""
	if key != who and not key.begins_with(who + "_"):
		return ""
	if parts.size() == 1 or parts[1] == "left":
		return "left"
	return "right"
