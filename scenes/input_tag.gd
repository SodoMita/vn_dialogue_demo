class_name InputTag extends RefCounted
## Pure parser for the `#input=` tag (Dialogic's "text input" event).
##
## Syntax (spaces never end a tag):
##   #input=player_name
##   #input=player_name?placeholder=Your name&default=Alex&max=16
##   #input=age?type=int&allow_empty=false
##
## - The variable name ends at the first "?" and must be an identifier
##   (an optional "GameState." prefix is stripped). The typed text is stored
##   on the GameState autoload when it has such a property, otherwise in the
##   balloon's `input_values` dictionary (readable from dialogue as
##   `input_value("name")`).
## - Options are "&"-separated, each split at its first "=". Unknown or
##   duplicated options are rejected, exactly like StageTagParser.

const ALLOWED_OPTS: PackedStringArray = [
	"placeholder", "default", "max", "type", "allow_empty", "secret", "ok",
]
const TYPES: PackedStringArray = ["text", "int", "float"]

static var _ident: RegEx


static func _ident_rx() -> RegEx:
	if _ident == null:
		_ident = RegEx.new()
		_ident.compile("^[A-Za-z_][A-Za-z0-9_]*$")
	return _ident


## True when [param tag] (without "#") is an input tag.
static func is_input_tag(tag: String) -> bool:
	return tag.begins_with("input=")


static func _fail(tag: String, reason: String) -> Dictionary:
	return {"ok": false, "tag": tag, "error": reason}


## Parse one tag (without the leading "#"). On success returns
## {ok, variable, placeholder, default, max_length, type, allow_empty,
##  secret, ok_text}.
static func parse(tag: String) -> Dictionary:
	if not is_input_tag(tag):
		return _fail(tag, "not an input tag")
	var payload: String = tag.substr(6)
	var name_part: String = payload
	var opt_part: String = ""
	var q: int = payload.find("?")
	if q >= 0:
		name_part = payload.substr(0, q)
		opt_part = payload.substr(q + 1)
	name_part = name_part.strip_edges()
	if name_part.begins_with("GameState."):
		name_part = name_part.substr(10)
	if _ident_rx().search(name_part) == null:
		return _fail(tag, "invalid variable name \"%s\"" % name_part)

	var opts: Dictionary = {}
	if opt_part.strip_edges() != "":
		for raw: String in opt_part.split("&", false):
			var eq: int = raw.find("=")
			if eq <= 0:
				return _fail(tag, "option \"%s\" needs a value" % raw)
			var key: String = raw.substr(0, eq).strip_edges()
			var value: String = raw.substr(eq + 1)
			if not ALLOWED_OPTS.has(key):
				return _fail(tag, "unknown option \"%s\"" % key)
			if opts.has(key):
				return _fail(tag, "duplicated option \"%s\"" % key)
			opts[key] = value

	var max_length: int = 0
	if opts.has("max"):
		var m: String = String(opts["max"]).strip_edges()
		if not m.is_valid_int() or m.to_int() < 0:
			return _fail(tag, "max must be a non-negative integer")
		max_length = m.to_int()

	var type_name: String = String(opts.get("type", "text")).strip_edges()
	if not TYPES.has(type_name):
		return _fail(tag, "unknown type \"%s\"" % type_name)

	return {
		"ok": true,
		"tag": tag,
		"variable": name_part,
		"placeholder": String(opts.get("placeholder", "")),
		"default": String(opts.get("default", "")),
		"max_length": max_length,
		"type": type_name,
		"allow_empty": _flag(opts, "allow_empty", false),
		"secret": _flag(opts, "secret", false),
		"ok_text": String(opts.get("ok", "OK")),
	}


static func _flag(opts: Dictionary, key: String, fallback: bool) -> bool:
	if not opts.has(key):
		return fallback
	var v: String = String(opts[key]).strip_edges().to_lower()
	return v == "" or v == "true" or v == "1" or v == "yes"


## Convert the typed text to the declared type.
static func coerce(spec: Dictionary, text: String) -> Variant:
	match String(spec.get("type", "text")):
		"int":
			return text.strip_edges().to_int()
		"float":
			return text.strip_edges().to_float()
		_:
			return text


## True when [param text] may be submitted for [param spec].
static func is_valid_value(spec: Dictionary, text: String) -> bool:
	var trimmed: String = text.strip_edges()
	if trimmed == "":
		return bool(spec.get("allow_empty", false))
	match String(spec.get("type", "text")):
		"int":
			return trimmed.is_valid_int()
		"float":
			return trimmed.is_valid_float()
	return true
