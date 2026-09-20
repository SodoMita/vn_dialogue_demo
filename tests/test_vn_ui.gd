## Headless test-suite for the custom VN balloon.
## Run with: godot --headless res://tests/test_vn_ui.tscn
extends Node


var fails: int = 0
var passes: int = 0
var balloon: VNBalloon
var resource: DialogueResource
var ended: bool = false
var gs: Node


func _ready() -> void:
	var watchdog := Timer.new()
	watchdog.one_shot = true
	watchdog.wait_time = 120
	watchdog.timeout.connect(func() -> void:
		printerr("[FAIL] watchdog timeout")
		finish()
	)
	add_child(watchdog)
	watchdog.start()
	await get_tree().process_frame
	run()


func check(cond: bool, what: String) -> void:
	if cond:
		passes += 1
		print("[PASS] %s" % what)
	else:
		fails += 1
		printerr("[FAIL] %s" % what)


func press(action: StringName) -> void:
	var ev := InputEventKey.new()
	ev.pressed = true
	match action:
		&"ui_accept": ev.keycode = KEY_ENTER
		&"ui_cancel": ev.keycode = KEY_ESCAPE
		&"ui_down": ev.keycode = KEY_DOWN
		&"dialogue_history": ev.physical_keycode = KEY_H  # action is bound to physical H
		_: ev.keycode = KEY_ENTER
	Input.parse_input_event(ev)
	# Native Controls (Buttons) activate on key release, so send the pair.
	var rel := InputEventKey.new()
	rel.pressed = false
	rel.keycode = ev.keycode
	rel.physical_keycode = ev.physical_keycode
	Input.parse_input_event(rel)
	await get_tree().process_frame


func alive() -> bool:
	return is_instance_valid(balloon)


func wait_until(cond: Callable, max_frames: int = 400) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		if not alive():
			return cond.call()
		await get_tree().process_frame
	return cond.call()


## Wait until the current line finished typing and is actionable.
func wait_ready() -> void:
	await wait_until(func() -> bool:
		return not alive() or (not balloon.dialogue_label.is_typing and (balloon.is_waiting_for_input or balloon.dialogue_line != null and balloon.dialogue_line.responses.size() > 0))
	)


## Wait until the current line id changes, skip its typing, and wait until actionable.
func await_line_change() -> DialogueLine:
	var start_id: String = balloon.dialogue_line.id if alive() and balloon.dialogue_line != null else ""
	await wait_until(func() -> bool:
		return not alive() or (balloon.dialogue_line != null and balloon.dialogue_line.id != start_id)
	)
	if not alive():
		return null
	if balloon.dialogue_label.is_typing:
		press(&"ui_cancel")
	await wait_ready()
	return balloon.dialogue_line


## Advance from a line that has no responses.
func step() -> DialogueLine:
	press(&"ui_accept")
	return await await_line_change()


## Advance until the current line offers responses, then return it.
func run_to_responses() -> DialogueLine:
	await wait_ready()
	var guard := 0
	while alive() and balloon.dialogue_line != null and balloon.dialogue_line.responses.size() == 0 and guard < 40:
		press(&"ui_accept")
		await await_line_change()
		guard += 1
	if not alive():
		return null
	return balloon.dialogue_line


## Choose the i-th (0-based) visible response via keyboard.
func choose(i: int) -> DialogueLine:
	for n in i:
		press(&"ui_down")
	press(&"ui_accept")
	return await await_line_change()


func run() -> void:
	gs = get_tree().root.get_node("GameState")
	# --- 0: the balloon is an authored, editable scene; the script builds nothing ---
	var tscn_text: String = FileAccess.get_file_as_string("res://scenes/vn_balloon.tscn")
	for n in ["Balloon", "Background", "SpriteLeft", "SpriteRight", "DialogueBox", "NamePlate", "CharacterLabel", "DialogueLabel", "NextIndicator", "ResponsesMenu", "MutationCooldown", "HistoryPanel", "HistoryList", "HistoryEntry"]:
		check(tscn_text.contains("[node name=\"%s\"" % n), "vn_balloon.tscn authors node '%s'" % n)
	var gd_text: String = FileAccess.get_file_as_string("res://scenes/vn_balloon.gd")
	check(not "Button.new(" in gd_text and not "PanelContainer.new(" in gd_text and not "Control.new(" in gd_text and not "RichTextLabel.new(" in gd_text and not "TextureRect.new(" in gd_text and not "Label.new(" in gd_text, "vn_balloon.gd builds no structural UI in code")
	check(not "instantiate(" in gd_text, "vn_balloon.gd never instantiates a scene")

	# --- 1: dialogue resource imports ---
	resource = load("res://dialogue/intro.dialogue")
	check(resource is DialogueResource, "intro.dialogue imports as DialogueResource")
	check("start" in resource.get_cues(), "cue 'start' exists")
	check(resource.first_cue != "", "first cue resolved")
	check("rooftop" in resource.get_cues(), "cue 'rooftop' exists")

	# --- 2: project setting routes to our custom balloon ---
	Engine.get_singleton("DialogueManager").dialogue_ended.connect(func(_r: DialogueResource) -> void: ended = true)
	balloon = Engine.get_singleton("DialogueManager").show_dialogue_balloon(resource, "start")
	check(balloon != null, "show_dialogue_balloon() returned a balloon")
	await get_tree().process_frame
	await get_tree().process_frame
	check(balloon is VNBalloon, "balloon from project setting is the custom VNBalloon")
	check(balloon.get_parent() == self, "balloon was added to the running scene")

	# --- 3: first narration line + background tag ---
	await wait_until(func() -> bool: return alive() and balloon.dialogue_line != null)
	var line: DialogueLine = balloon.dialogue_line
	check(line.character == "", "line 1 is narration (empty character)")
	check(line.text.begins_with("The afternoon light"), "line 1 text matches")
	check(balloon.background.texture != null, "#bg=classroom applied to Background")
	check(balloon.sprite_left.modulate.a == 0.0 and balloon.sprite_right.modulate.a == 0.0, "sprite slots empty at start")

	# --- 4: typewriter types and can be skipped ---
	check(balloon.dialogue_label.is_typing, "typewriter is typing line 1")
	press(&"ui_cancel")
	await wait_ready()
	await get_tree().process_frame
	check(balloon.dialogue_label.visible_ratio == 1.0, "skip action completes typing")
	check(balloon.next_indicator.visible, "next indicator shows while waiting")

	# --- 5: Rook's first line and his sprite ---
	line = await step()
	check(line != null and line.character == "Rook", "line 2 is Rook")
	check(alive() and balloon.sprite_right.texture != null and balloon.sprite_right.modulate.a == 1.0, "#sprite=rook:right shows right sprite")

	# --- 6: Maya appears on the left, Rook dimmed by #focus=left ---
	line = await step()
	check(line != null and line.character == "Maya", "line 3 is Maya")
	check(alive() and balloon.sprite_left.texture != null and balloon.sprite_left.modulate.a == 1.0, "#sprite=maya:left shows left sprite")
	check(alive() and balloon.sprite_right.modulate.a < 1.0, "#focus=left dims the right slot")

	# Rook bell, Maya "..." then the question with responses
	await step()
	await step()
	line = await run_to_responses()
	check(line != null and line.text.contains("I'm Alex."), "{{player_name}} interpolation resolved")
	check(line != null and line.responses.size() == 3, "three responses offered")
	check(alive() and balloon.responses_menu.visible, "responses menu is visible")
	var items: Array = balloon.responses_menu.get_menu_items()
	check(items.size() == 3, "responses menu shows three buttons")
	if items.size() > 0:
		check(items[0].text.begins_with("I'm Alex"), "first choice text correct")
	else:
		check(false, "first choice text correct")

	# --- 7: pick the SECOND choice via real keyboard input ---
	line = await choose(1)
	check(line != null and line.text.contains("mysterious type"), "second choice leads to 'mysterious type' line")

	# --- 8: continue to the rooftop and check stage switch ---
	line = await step()  # mutation met_maya runs on the way here
	check(gs.met_maya == true, "mutation `do met_maya = true` ran")
	check(line != null and line.character == "Rook", "Rook rooftop line")
	line = await step()  # mutation met_rook runs on the way here
	check(gs.met_rook == true, "mutation `do met_rook = true` ran")
	check(line != null and line.text.begins_with("The first bell"), "condition `if day == 1` branch taken")
	line = await step()  # rooftop narration
	check(line != null and line.text.begins_with("Wind over the chain-link"), "jumped to ~ rooftop cue")
	check(alive() and balloon.background.texture != null and balloon.background.texture.resource_path.ends_with("rooftop.png"), "#bg=rooftop switched background")

	# --- rooftop choices: take the third one ---
	await step()  # Maya: see?
	await step()  # Rook: witness
	line = await run_to_responses()
	check(line != null and line.responses.size() == 3, "rooftop offers three choices")
	line = await choose(2)
	check(line != null and line.text.contains("sun goes down"), "third rooftop choice line reached")

	# --- 9: run to the end ---
	var guard := 0
	while alive() and not ended and guard < 40:
		if balloon.dialogue_line != null and balloon.dialogue_line.responses.size() > 0:
			await choose(0)
		else:
			await step()
		guard += 1
	await wait_until(func() -> bool: return ended, 200)
	check(ended, "dialogue_ended signal emitted")
	await wait_until(func() -> bool: return not alive(), 120)
	check(not alive(), "balloon freed itself at END")

	# --- 10: history & rollback (second balloon run) ---
	gs.reset()
	balloon = Engine.get_singleton("DialogueManager").show_dialogue_balloon(resource, "start")
	await get_tree().process_frame
	await get_tree().process_frame
	check(alive() and balloon is VNBalloon, "second balloon run started")

	# Fast-forward to the first choices, pick one, step once (runs met_maya).
	var qline: DialogueLine = await run_to_responses()
	check(qline != null and qline.responses.size() == 3, "run 2 reached the first choices")
	await choose(0)
	line = await step()
	check(gs.met_maya == true, "run 2: met_maya mutation ran")

	# Open the history with the H action.
	press(&"dialogue_history")
	await get_tree().process_frame
	await get_tree().process_frame
	check(alive() and balloon.history_panel.visible, "history action opens the history panel")
	var h_items: Array = []
	for child: Node in balloon.history_list.get_children():
		if child != balloon.history_entry_template and child.visible:
			h_items.append(child)
	check(h_items.size() == balloon.history.size(), "history list shows one entry per shown line")
	check(balloon.history.size() >= 8, "history recorded all shown lines")

	# Entry 1 is Rook's first line, before any mutation ran. Jump to it.
	var target_text: String = balloon.history[1].text
	h_items[1].grab_focus()
	press(&"ui_accept")
	line = await await_line_change()
	check(line != null and line.text == target_text, "clicking a history line jumps back to it")
	check(line != null and line.character == "Rook", "rolled back to Rook's first line")
	check(gs.met_maya == false and gs.met_rook == false, "story state restored to the rollback point")
	check(alive() and balloon.history.size() == 2, "history truncated after the rollback point")
	check(alive() and not balloon.history_panel.visible, "history panel closed after rollback")
	check(alive() and balloon.background.texture != null and balloon.background.texture.resource_path.ends_with("classroom.png"), "stage re-dressed from rolled-back line's tags")

	# The panel can be closed without rolling back.
	press(&"dialogue_history")
	await get_tree().process_frame
	check(alive() and balloon.history_panel.visible, "history action toggles the panel open again")
	press(&"ui_cancel")
	await get_tree().process_frame
	check(alive() and not balloon.history_panel.visible, "skip action closes history without rollback")
	check(alive() and balloon.history.size() == 2, "history unchanged when closing without rollback")

	finish()


func finish() -> void:
	print("=====================================")
	print("VN balloon tests: %d passed, %d failed" % [passes, fails])
	print("=====================================")
	# Drop references so the forced quit doesn't report them as in-use.
	balloon = null
	resource = null
	get_tree().quit(1 if fails > 0 else 0)
