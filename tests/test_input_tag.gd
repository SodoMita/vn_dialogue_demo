## Headless checks for the Dialogic-style `#input=` tag.
## Run with: godot --headless res://tests/test_input_tag.tscn
extends Node

const InputTagScript = preload("res://scenes/input_tag.gd")

var fails := 0
var passes := 0


func _ready() -> void:
	run()
	print("input-tag %d passed, %d failed" % [passes, fails])
	get_tree().quit(1 if fails else 0)


func check(cond: bool, what: String) -> void:
	if cond:
		passes += 1
		print("[PASS] %s" % what)
	else:
		fails += 1
		printerr("[FAIL] %s" % what)


func run() -> void:
	check(InputTagScript.is_input_tag("input=player_name"), "recognises the tag")
	check(not InputTagScript.is_input_tag("show=maya@left"), "ignores staging tags")

	var bare: Dictionary = InputTagScript.parse("input=player_name")
	check(bare.ok and bare.variable == "player_name", "bare tag names the variable")
	check(bare.type == "text" and bare.max_length == 0 and not bare.allow_empty, "defaults")

	var full: Dictionary = InputTagScript.parse(
		"input=GameState.player_name?placeholder=Your name&default=Alex&max=16&ok=Write")
	check(full.ok and full.variable == "player_name", "GameState. prefix is stripped")
	check(full.placeholder == "Your name", "spaces do not end the tag")
	check(full.default == "Alex" and full.max_length == 16 and full.ok_text == "Write", "options")

	check(not InputTagScript.parse("input=2name").ok, "rejects a bad identifier")
	check(not InputTagScript.parse("input=a?nope=1").ok, "rejects unknown options")
	check(not InputTagScript.parse("input=a?max=1&max=2").ok, "rejects duplicates")
	check(not InputTagScript.parse("input=a?max=x").ok, "rejects a non-numeric max")
	check(not InputTagScript.parse("input=a?type=date").ok, "rejects an unknown type")

	var spec: Dictionary = InputTagScript.parse("input=a")
	check(not InputTagScript.is_valid_value(spec, "  "), "empty is refused by default")
	check(InputTagScript.is_valid_value(spec, "Mia"), "text passes")
	var opt: Dictionary = InputTagScript.parse("input=a?allow_empty=true")
	check(InputTagScript.is_valid_value(opt, ""), "allow_empty lets blanks through")
	var num: Dictionary = InputTagScript.parse("input=age?type=int")
	check(not InputTagScript.is_valid_value(num, "old"), "int refuses words")
	check(InputTagScript.is_valid_value(num, " 17 "), "int accepts digits")
	check(InputTagScript.coerce(num, " 17 ") == 17, "int is coerced")
	check(InputTagScript.coerce(InputTagScript.parse("input=f?type=float"), "1.5") == 1.5, "float is coerced")
	check(InputTagScript.coerce(spec, "Mia") == "Mia", "text is kept verbatim")

	# The balloon and the demo must stay wired to the tag.
	var balloon := FileAccess.get_file_as_string("res://scenes/vn_balloon.gd")
	check(balloon.contains("InputTag.is_input_tag"), "balloon parses input tags")
	check(balloon.contains("func _open_input_prompt"), "balloon opens a prompt")
	var scene := FileAccess.get_file_as_string("res://scenes/vn_balloon.tscn")
	check(scene.contains("name=\"InputField\""), "the field is authored in the scene")
	var demo := FileAccess.get_file_as_string("res://examples/input_demo.dialogue")
	check(demo.contains("#input=player_name"), "the demo asks for a name")
	check(demo.contains("type=int") and demo.contains("secret=true"), "the demo covers typed and secret input")
