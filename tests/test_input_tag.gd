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
	# The prompt must wear the same gold VN chrome as every other widget.
	check(scene.contains("StyleBoxFlat_input_normal") and scene.contains("StyleBoxFlat_input_focus"),
		"the field has authored VN styleboxes")
	check(scene.contains("LineEdit/styles/focus = SubResource(\"StyleBoxFlat_input_focus\")"),
		"Theme_vn styles LineEdit")
	var row_block := scene.substr(scene.find("name=\"InputRow\""))
	row_block = row_block.substr(0, row_block.find("name=\"InputField\""))
	check(row_block.contains("theme = SubResource(\"Theme_vn\")"), "the row uses the shared VN theme")
	check(balloon.contains("entry.inputs = input_values.duplicate(true)")
		and balloon.contains("input_values = (entry.get(\"inputs\", {}) as Dictionary).duplicate(true)"),
		"input_values ride along with history (saves + rollback)")
	# Values live on GameState so dialogue (and the route-graph walker, which
	# runs without the balloon) can read {{input_value("key")}} anywhere.
	var gs: Node = get_tree().root.get_node_or_null("GameState")
	check(gs != null and gs.get("input_values") is Dictionary, "GameState owns input_values")
	if gs != null:
		gs.input_values["probe"] = "mochi"
		check(str(gs.input_value("probe")) == "mochi", "GameState.input_value reads it back")
		var snap: Dictionary = gs.snapshot()
		check((snap.get("input_values", {}) as Dictionary).get("probe") == "mochi",
			"snapshot carries typed answers (saves + rollback)")
		gs.input_values = {}
		gs.restore(snap)
		check(str(gs.input_value("probe")) == "mochi", "restore brings typed answers back")
		gs.reset()
		check((gs.input_values as Dictionary).is_empty(), "reset clears typed answers")

	var demo := FileAccess.get_file_as_string("res://examples/input_demo.dialogue")
	check(demo.contains("#input=player_name"), "the demo asks for a name")
	check(demo.contains("type=int") and demo.contains("secret=true"), "the demo covers typed and secret input")
