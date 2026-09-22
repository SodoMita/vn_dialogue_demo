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
		fails += 1
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
		&"dialogue_close": ev.keycode = KEY_BACKSPACE
		&"dialogue_skip": ev.keycode = KEY_CTRL
		&"ui_down": ev.keycode = KEY_DOWN
		&"ui_right": ev.keycode = KEY_RIGHT
		&"ui_left": ev.keycode = KEY_LEFT
		&"dialogue_history": ev.physical_keycode = KEY_H  # action is bound to physical H
		&"dialogue_save": ev.keycode = KEY_F5
		&"dialogue_load": ev.keycode = KEY_F9
		&"dialogue_pause": ev.keycode = KEY_ESCAPE
		&"dialogue_panic": ev.keycode = KEY_F12
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
		press(&"ui_accept")
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
	# Response placement is deferred until Control minimum sizes settle.
	await get_tree().process_frame
	return balloon.dialogue_line


## Choose the i-th (0-based) visible response via keyboard.
func choose(i: int) -> DialogueLine:
	for n in i:
		press(&"ui_down")
	press(&"ui_accept")
	return await await_line_change()


func run() -> void:
	gs = get_tree().root.get_node("GameState")
	# Wipe saves and settings so the run is deterministic.
	var saves_dir: DirAccess = DirAccess.open("user://saves")
	if saves_dir != null:
		saves_dir.list_dir_begin()
		var save_name: String = saves_dir.get_next()
		while save_name != "":
			saves_dir.remove(save_name)
			save_name = saves_dir.get_next()
	var user_dir: DirAccess = DirAccess.open("user://")
	if user_dir != null:
		if user_dir.file_exists("settings.json"):
			user_dir.remove("settings.json")
		if user_dir.file_exists("seen.json"):
			user_dir.remove("seen.json")
	var sf := FileAccess.open("user://settings.json", FileAccess.WRITE)
	sf.store_string('{ "language": "en" }')
	sf.close()
	# --- 0: the balloon is an authored, editable scene; the script builds nothing ---
	var tscn_text: String = FileAccess.get_file_as_string("res://scenes/vn_balloon.tscn")
	for n in ["Balloon", "Background", "SpriteLeft", "SpriteRight", "DialogueBox", "NamePlate", "CharacterLabel", "DialogueLabel", "NextIndicator", "ResponsesMenu", "MutationCooldown", "HistoryPanel", "HistoryList", "HistoryEntry", "SaveMenuPanel", "SlotList", "SlotButton", "SettingsPanel", "TextSpeedSlider", "AutoDelaySlider", "PausePanel", "PanicScreen", "SystemRow", "QSButton", "QLButton", "AutoButton", "SkipButton", "LogButton", "PanicButton", "AutoTimer", "FullscreenCheck", "QuitButton", "PrevChoiceButton", "NextChoiceButton", "HistoryScroll", "SettingsScroll", "SettingsMargin", "UIRoot", "TextSizeSlider", "SkipSpeedSlider", "SkipModeOption", "UIScaleSlider", "VsyncCheck", "ResolutionOption", "ResWidthSpin", "ResHeightSpin", "MasterVolSlider", "MusicVolSlider", "VoiceVolSlider", "SfxVolSlider", "ProceduralMusicCheck", "TypewriterSfxCheck", "ButtonSfxCheck", "SaveMenuTitleRow", "SaveCloseButton", "HoldIndicator", "SpriteScaleSlider", "SpriteYSlider", "SkipTimer", "VoicePlayer", "SyncVoiceCheck", "SettingsCloseButton", "PortraitCheck", "Rot0Button", "Rot90Button", "Rot180Button", "Rot270Button", "PauseButton", "PanicCloseButton", "LanguageOption", "AdvanceKeyButton", "SkipKeyButton", "CloseKeyButton", "HistoryKeyButton", "QuickSaveKeyButton", "QuickLoadKeyButton", "PauseKeyButton", "PanicKeyButton"]:
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
	press(&"ui_accept")
	await wait_ready()
	await get_tree().process_frame
	check(balloon.dialogue_label.visible_ratio == 1.0, "Advance completes typing")
	check(balloon.next_indicator.visible, "next indicator shows while waiting")

	# --- 5: Rook's first line and his sprite ---
	line = await step()
	check(line != null and line.character == "Rook", "line 2 is Rook")
	check(alive() and balloon.sprite_right.texture != null and balloon.sprite_right.modulate.a == 1.0, "#sprite=rook:right shows right sprite")
	check(alive() and balloon.sprite_right.size.y > 500, "portrait keeps its authored height")
	check(alive() and balloon.voice_player.playing and balloon.voice_player.bus == &"Voice",
		"Rook's voiced line plays a voice clip on the Voice bus")
	var missing_voices := 0
	for k: String in ["r1", "r2", "r3", "r4", "r5", "r6", "m1", "m2", "m3", "m4", "m5", "m6", "m7", "m8"]:
		var vp: String = balloon._voice_path(k)
		if not (ResourceLoader.exists(vp) or FileAccess.file_exists(vp)):
			missing_voices += 1
	check(alive() and missing_voices == 0, "every voiced line has a loadable clip")
	# Optional typewriter pacing follows the voiced clip.
	balloon.sync_voice_check.toggled.emit(true)
	balloon.rollback_to(balloon.history_cursor)  # re-apply Rook's voiced line
	await wait_ready()
	var paced: float = clampf(balloon.voice_player.stream.get_length() / max(1.0, float(balloon.dialogue_line.text.length())), 0.005, 0.5)
	check(alive() and is_equal_approx(balloon.dialogue_label.seconds_per_step, paced),
		"typewriter paces itself to the voice clip")
	balloon.sync_voice_check.toggled.emit(false)
	balloon.rollback_to(balloon.history_cursor)
	await wait_ready()
	check(alive() and is_equal_approx(balloon.dialogue_label.seconds_per_step, balloon.text_speed_slider.value),
		"pacing returns to the text speed when sync is off")

	# --- 5b: Enter/Space are as reliable as the left mouse button ---
	var kb_before: String = balloon.dialogue_line.id
	press(&"ui_accept")
	await wait_until(func() -> bool:
		return not alive() or (balloon.dialogue_line != null and balloon.dialogue_line.id != kb_before)
	)
	check(alive() and balloon.dialogue_line.id != kb_before, "Enter advances the dialogue when waiting")
	await wait_until(func() -> bool: return not alive() or balloon.dialogue_label.is_typing)
	press(&"ui_accept")
	await get_tree().process_frame
	check(alive() and not balloon.dialogue_label.is_typing, "Enter skips the typewriter exactly like a click")
	balloon.rollback_to(balloon.history_cursor - 1)
	await wait_ready()

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
	check(alive() and balloon.responses_menu.get_global_rect().position.y >= 0.0
		and balloon.responses_menu.get_global_rect().end.y <= balloon.dialogue_box.get_global_rect().position.y + 1.0,
		"choices sit above the dialogue box, fully on screen")
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
	check(alive() and not balloon.voice_player.playing, "unvoiced narration stops the voice")
	check(line != null and line.text.begins_with("The first bell"), "condition `if day == 1` branch taken")
	check(alive() and balloon.dialogue_label.bbcode_enabled, "dialogue label renders BBCode-styled text")
	check(alive() and not "[" in balloon.history[balloon.history_cursor].text,
		"backlog stores styled lines without raw BBCode markup")
	line = await step()  # rooftop narration
	check(line != null and line.text.begins_with("Wind over the chain-link"), "jumped to ~ rooftop cue")
	check(alive() and balloon.background.texture != null and balloon.background.texture.resource_path.ends_with("rooftop.webp"), "#bg=rooftop switched background")

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
	check(alive() and balloon.history_cursor == 1, "rollback moved the history cursor")
	check(alive() and balloon.history.size() >= 8, "forward entries kept for roll-forward")
	check(alive() and not balloon.history_panel.visible, "history panel closed after rollback")
	check(alive() and balloon.background.texture != null and balloon.background.texture.resource_path.ends_with("classroom.webp"), "stage re-dressed from rolled-back line's tags")

	# The panel can be closed without rolling back.
	press(&"dialogue_history")
	await get_tree().process_frame
	check(alive() and balloon.history_panel.visible, "history action toggles the panel open again")
	press(&"dialogue_close")
	await get_tree().process_frame
	check(alive() and not balloon.history_panel.visible, "Close action closes history without rollback")
	check(alive() and balloon.history_cursor == 1, "closing without rollback keeps the cursor")

	# --- 11: quick save / quick load (slot 0) ---
	press(&"dialogue_save")
	await get_tree().process_frame
	check(FileAccess.file_exists("user://saves/slot_0.json"), "quick save wrote user://saves/slot_0.json")
	check(alive() and balloon.toast_label.visible and balloon.toast_label.text == "Saved to slot 0", "toast confirms the quick save")
	var saved_size: int = balloon.history.size()
	var saved_cursor: int = balloon.history_cursor

	# Diverge: advance past the save point.
	line = await step()
	check(line != null and line.character == "Maya", "advanced past the save point")
	check(alive() and balloon.history.size() == 3, "backlog grew after advancing")

	# Load via the F9 quick-load action.
	press(&"dialogue_load")
	await wait_until(func() -> bool:
		return alive() and balloon.dialogue_line != null and balloon.dialogue_line.text.contains("transfer student")
	)
	check(alive() and balloon.dialogue_line.text.contains("transfer student"), "quick load returns to the saved line")
	check(alive() and balloon.history.size() == saved_size and balloon.history_cursor == saved_cursor, "quick load restores the saved backlog")
	check(alive() and balloon.toast_label.text == "Loaded slot 0", "toast confirms the quick load")

	# Play continues from the loaded point.
	if alive() and balloon.dialogue_label.is_typing:
		press(&"ui_accept")
	line = await step()
	check(line != null and line.character == "Maya", "dialogue continues after load")

	# --- 12: save menu with an arbitrary number of slots ---
	balloon.save_button.grab_focus()
	press(&"ui_accept")
	await get_tree().process_frame
	check(alive() and balloon.save_menu_panel.visible, "Save button opens the save menu")
	check(alive() and balloon.save_menu_title.text == "Save", "save menu is titled 'Save'")
	check(alive() and balloon.new_slot_button.visible, "save mode offers a New Slot button")
	check(alive() and not balloon.is_waiting_for_input, "waiting pauses while the menu is open")

	balloon.new_slot_button.grab_focus()
	press(&"ui_accept")
	await get_tree().process_frame
	await get_tree().process_frame
	check(FileAccess.file_exists("user://saves/slot_1.json"), "New Slot created user://saves/slot_1.json")
	check(alive() and balloon.toast_label.text == "Saved to slot 1", "toast confirms the new-slot save")
	var slot_rows: Array = []
	if alive():
		for child: Node in balloon.slot_list.get_children():
			if child != balloon.slot_template and child.visible:
				slot_rows.append(child)
	check(slot_rows.size() == 2, "slot list shows one row per save file")
	check(alive() and balloon.save_menu_panel.visible, "save menu stays open after saving")

	press(&"dialogue_close")
	await get_tree().process_frame
	check(alive() and not balloon.save_menu_panel.visible, "Close action closes the save menu")

	# Advance, then load the older snapshot through the Load menu.
	line = await step()
	check(line != null and line.text.contains("bell rang"), "advanced past the menu save point")

	balloon.load_button.grab_focus()
	press(&"ui_accept")
	await get_tree().process_frame
	check(alive() and balloon.save_menu_panel.visible and balloon.save_menu_title.text == "Load", "Load button opens the menu in load mode")
	check(alive() and not balloon.new_slot_button.visible, "load mode hides the New Slot button")
	var first_slot: Button = null
	if alive():
		for child: Node in balloon.slot_list.get_children():
			if child != balloon.slot_template and child.visible:
				first_slot = child
				break
	check(first_slot != null and first_slot.text.begins_with("Slot 0"), "first row is slot 0")
	if first_slot != null:
		first_slot.grab_focus()
		press(&"ui_accept")
		await wait_until(func() -> bool:
			return alive() and balloon.dialogue_line != null and balloon.dialogue_line.text.contains("transfer student")
		)
	check(alive() and balloon.dialogue_line.text.contains("transfer student"), "choosing a row loads that slot")
	check(alive() and not balloon.save_menu_panel.visible, "menu closes after loading")
	check(alive() and balloon.history.size() == saved_size and balloon.history_cursor == saved_cursor, "loaded slot restored its backlog")
	if alive() and balloon.dialogue_label.is_typing:
		press(&"ui_accept")
	await wait_ready()

	# --- 13: settings ---
	balloon.settings_button.grab_focus()
	press(&"ui_accept")
	await get_tree().process_frame
	check(alive() and balloon.settings_panel.visible, "Settings button opens the settings panel")

	var speed_before: float = balloon.dialogue_label.seconds_per_step
	balloon.text_speed_slider.grab_focus()
	press(&"ui_right")
	await get_tree().process_frame
	check(alive() and balloon.text_speed_slider.value > speed_before, "text speed slider moved right")
	check(alive() and is_equal_approx(balloon.dialogue_label.seconds_per_step, balloon.text_speed_slider.value), "text speed applied to the typewriter")
	check(FileAccess.file_exists("user://settings.json"), "settings persisted to user://settings.json")

	var delay_before: float = balloon.auto_delay
	balloon.auto_delay_slider.grab_focus()
	press(&"ui_left")
	await get_tree().process_frame
	check(alive() and balloon.auto_delay < delay_before, "auto delay slider changed the delay")

	press(&"dialogue_close")
	await get_tree().process_frame
	check(alive() and not balloon.settings_panel.visible, "Close action closes settings")
	await wait_ready()
	check(alive() and balloon.is_waiting_for_input, "balloon waits for input again after settings close")

	# --- 14: auto, skip, pause and the panic screen ---
	var auto_start_id: String = balloon.dialogue_line.id
	balloon.auto_button.grab_focus()
	press(&"ui_accept")
	await get_tree().process_frame
	check(alive() and balloon.auto_mode, "Auto button enables auto mode")
	check(alive() and balloon.toast_label.text == "Auto on", "toast confirms auto mode")
	var advanced_by_auto: bool = await wait_until(func() -> bool:
		return not alive() or balloon.dialogue_line.id != auto_start_id
	, 6000)
	check(advanced_by_auto, "auto mode advances the dialogue on its own")
	balloon.auto_button.grab_focus()
	press(&"ui_accept")
	await get_tree().process_frame
	check(alive() and not balloon.auto_mode, "Auto button toggles auto mode off")

	# The remappable Ctrl action controls the same mode as the system-row button.
	# Check synchronously: this particular line is about to expose choices, where
	# skip mode correctly stops itself on the following frame.
	var skip_key_event := InputEventKey.new()
	skip_key_event.pressed = true
	skip_key_event.keycode = KEY_CTRL
	balloon._input(skip_key_event)
	check(alive() and balloon.skip_mode, "Skip key enables skip mode")
	balloon._input(skip_key_event)
	check(alive() and not balloon.skip_mode, "Skip key toggles skip mode off")

	# Skip: runs the dialogue to the next choices without further input.
	balloon.skip_button.grab_focus()
	press(&"ui_accept")
	await get_tree().process_frame
	check(alive() and balloon.skip_mode, "Skip button enables skip mode")
	await wait_until(func() -> bool:
		return not alive() or balloon.dialogue_line.responses.size() > 0
	, 6000)
	check(alive() and balloon.dialogue_line.responses.size() > 0, "skip mode ran to the next choices")
	check(alive() and not balloon.skip_mode, "skip mode stops at choices")
	await choose(0)

	# Pause via the Esc action. Start a known clip so the regression check proves
	# Resume continues voice playback instead of merely unmuting the bus.
	balloon._play_voice("r1")
	await get_tree().process_frame
	check(alive() and balloon.voice_player.playing, "voice is playing before pause")
	press(&"dialogue_pause")
	await get_tree().process_frame
	check(alive() and balloon.pause_panel.visible, "pause action opens the pause menu")
	check(alive() and AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")), "pause silences all audio")
	check(alive() and balloon.voice_player.stream_paused, "pause suspends the current voice clip")
	check(alive() and not balloon.is_waiting_for_input, "input blocked while paused")
	press(&"ui_accept")  # Resume owns focus when the menu opens
	await get_tree().process_frame
	check(alive() and not balloon.pause_panel.visible, "Resume closes the pause menu")
	check(alive() and not AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")), "resume restores audio")
	check(alive() and balloon.voice_player.playing and not balloon.voice_player.stream_paused,
		"Resume continues the current voice clip")
	await wait_ready()
	check(alive() and balloon.is_waiting_for_input, "balloon waits for input again after resume")

	# Panic screen (boss key): everything is swallowed except the boss key.
	press(&"dialogue_panic")
	await get_tree().process_frame
	check(alive() and balloon.panic_screen.visible, "panic action shows the panic screen")
	check(alive() and AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")), "panic silences all audio")
	var frozen_id: String = balloon.dialogue_line.id
	press(&"ui_accept")
	press(&"dialogue_close")
	await get_tree().process_frame
	check(alive() and balloon.dialogue_line.id == frozen_id, "panic screen swallows dialogue input")
	check(alive() and balloon.panic_screen.visible, "other keys do not dismiss the panic screen")
	press(&"dialogue_panic")
	await get_tree().process_frame
	check(alive() and not balloon.panic_screen.visible, "panic action hides the panic screen again")
	check(alive() and not AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")), "leaving panic restores audio")

	# Panic raised from inside the pause menu: closing it must stay silent.
	press(&"dialogue_pause")
	await get_tree().process_frame
	press(&"dialogue_panic")
	await get_tree().process_frame
	press(&"dialogue_panic")
	await get_tree().process_frame
	check(alive() and balloon.pause_panel.visible
		and AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")),
		"leaving panic keeps audio silent while still paused")
	balloon.close_pause()
	await get_tree().process_frame
	check(alive() and not AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")),
		"audio returns once pause is closed too")
	await wait_ready()
	check(alive() and balloon.is_waiting_for_input, "dialogue resumes waiting after panic")

	# --- 15: fullscreen setting, swipe-up history, quit entry ---
	balloon.settings_button.grab_focus()
	press(&"ui_accept")
	await get_tree().process_frame
	check(alive() and balloon.settings_panel.visible, "settings reopen for the fullscreen toggle")
	balloon.fullscreen_check.grab_focus()
	press(&"ui_accept")
	await get_tree().process_frame
	check(alive() and balloon.fullscreen_check.button_pressed, "fullscreen checkbox toggles on")
	var settings_data: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://settings.json"))
	check(settings_data is Dictionary and settings_data.get("fullscreen") == true, "fullscreen preference persisted")
	balloon.fullscreen_check.grab_focus()
	press(&"ui_accept")
	await get_tree().process_frame
	check(alive() and not balloon.fullscreen_check.button_pressed, "fullscreen checkbox toggles back off")
	press(&"dialogue_close")
	await get_tree().process_frame
	check(alive() and not balloon.settings_panel.visible, "settings close again")
	await wait_ready()

	# Swipe up (mobile) opens the history without advancing the dialogue.
	var line_before: String = balloon.dialogue_line.id
	var t_down := InputEventScreenTouch.new()
	t_down.pressed = true
	t_down.position = Vector2(640, 520)
	Input.parse_input_event(t_down)
	var t_up := InputEventScreenTouch.new()
	t_up.pressed = false
	t_up.position = Vector2(640, 320)
	Input.parse_input_event(t_up)
	await get_tree().process_frame
	await get_tree().process_frame
	check(alive() and balloon.history_panel.visible, "swipe up opens the history (mobile)")
	check(alive() and balloon.dialogue_line.id == line_before, "the swipe does not advance the dialogue")
	press(&"dialogue_close")
	await get_tree().process_frame
	check(alive() and not balloon.history_panel.visible, "history closes after the swipe")

	# The pause menu offers a Quit entry (the suite never presses it).
	press(&"dialogue_pause")
	await get_tree().process_frame
	var quit_btn: Node = balloon.get_node("%QuitButton") if alive() else null
	check(quit_btn is Button and (quit_btn as Button).visible, "pause menu offers a Quit entry")
	press(&"dialogue_pause")
	await get_tree().process_frame
	check(alive() and not balloon.pause_panel.visible, "pause closes again")
	await wait_ready()

	# --- 16: history scrolling, choice jumps, slot thumbnails ---
	# Ren'Py-style wheel: roll back one line, then roll forward again.
	var fwd_id: String = balloon.dialogue_line.id
	var wu := InputEventMouseButton.new()
	wu.button_index = MOUSE_BUTTON_WHEEL_UP
	wu.pressed = true
	wu.position = Vector2(640, 360)
	Input.parse_input_event(wu)
	await wait_until(func() -> bool:
		return not alive() or (balloon.dialogue_line != null and balloon.dialogue_line.id != fwd_id)
	)
	check(alive() and balloon.dialogue_line.id != fwd_id, "wheel up rolls the game back one line")
	if alive() and balloon.dialogue_label.is_typing:
		press(&"ui_accept")
	var wd := InputEventMouseButton.new()
	wd.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wd.pressed = true
	wd.position = Vector2(640, 360)
	Input.parse_input_event(wd)
	await wait_until(func() -> bool:
		return not alive() or (balloon.dialogue_line != null and balloon.dialogue_line.id == fwd_id)
	)
	check(alive() and balloon.dialogue_line.id == fwd_id, "wheel down rolls forward to the newer line")
	if alive() and balloon.dialogue_label.is_typing:
		press(&"ui_accept")
	await wait_ready()

	# Kirikiri-style jumps: next choice ...
	balloon.next_choice_button.grab_focus()
	press(&"ui_accept")
	await wait_until(func() -> bool:
		return not alive() or (balloon.dialogue_line != null and balloon.dialogue_line.responses.size() > 0 and not balloon.dialogue_label.is_typing)
	, 3000)
	check(alive() and balloon.dialogue_line.responses.size() > 0, "Next Choice jumps to the following choice")
	var choice_text: String = balloon.dialogue_line.text if alive() else ""
	await choose(0)

	# ... and previous choice.
	balloon.prev_choice_button.grab_focus()
	press(&"ui_accept")
	await wait_until(func() -> bool:
		return not alive() or (balloon.dialogue_line != null and balloon.dialogue_line.responses.size() > 0 and not balloon.dialogue_label.is_typing)
	, 600)
	check(alive() and balloon.dialogue_line.responses.size() > 0, "Prev Choice returns to a choice line")
	check(alive() and balloon.dialogue_line.text == choice_text, "Prev Choice lands on the choice just passed")

	# Pass the rolled-back choice so the backlog overflows the panel.
	await choose(0)
	line = await step()

	# The backlog panel scrolls (focus-follow in its ScrollContainer); by now
	# enough lines are logged that the list overflows the panel.
	press(&"dialogue_history")
	await get_tree().process_frame
	await get_tree().process_frame
	var h_rows: Array = []
	if alive():
		for child: Node in balloon.history_list.get_children():
			if child != balloon.history_entry_template and child.visible:
				h_rows.append(child)
	check(h_rows.size() >= 14, "backlog holds every line incl. seeked-past ones")
	if h_rows.size() > 1:
		h_rows[h_rows.size() - 1].grab_focus()
		await get_tree().process_frame
		await get_tree().process_frame
	check(alive() and balloon.history_scroll.scroll_vertical > 0, "history panel scrolls down to the focused row")
	press(&"dialogue_close")
	await get_tree().process_frame

	# Slot rows show runtime-rendered thumbnails; no image data is persisted.
	balloon.open_save_menu("save")
	await get_tree().process_frame
	await get_tree().process_frame
	var with_icon := 0
	if alive():
		for child: Node in balloon.slot_list.get_children():
			if child != balloon.slot_template and child.visible and (child as Button).icon != null:
				with_icon += 1
	check(with_icon >= 2, "filled slot rows show rendered thumbnails")
	var slot_json: String = FileAccess.get_file_as_string("user://saves/slot_0.json")
	check(not "\"image\"" in slot_json and not "base64" in slot_json, "saves store stage keys, not image data")
	press(&"dialogue_close")
	await get_tree().process_frame

	# --- 17: the full settings surface (text, skip, video, audio) ---
	balloon.settings_button.grab_focus()
	press(&"ui_accept")
	await get_tree().process_frame
	check(alive() and balloon.settings_panel.visible, "settings reopened for the full surface")
	check(alive() and balloon.settings_scroll.size.y > 0 and balloon.settings_scroll.get_v_scroll_bar().size.y > 0,
		"settings live in a real scrolling container")
	check(alive() and balloon.text_size_slider.size.x > 350, "settings rows fill the column width")
	check(alive() and balloon.settings_close_button.visible, "a close button covers touch devices")
	balloon.settings_close_button.grab_focus()
	press(&"ui_accept")
	await get_tree().process_frame
	check(alive() and not balloon.settings_panel.visible and not balloon.settings_close_button.visible,
		"the close button exits settings")
	balloon.settings_button.grab_focus()
	press(&"ui_accept")
	await get_tree().process_frame
	check(alive() and balloon.settings_panel.visible, "settings reopened after close-button exit")
	check(alive() and balloon.skip_mode_option.item_count == 2 and balloon.resolution_option.item_count == 5,
		"the skip-mode and resolution dropdowns carry their authored items")

	# Every keyboard action has an authored button. Clicking one enters capture
	# mode; the next key replaces that action immediately and is persisted.
	check(alive() and balloon.BINDABLE_ACTIONS.size() == 8
		and balloon.advance_key_button is Button and balloon.skip_key_button is Button
		and balloon.close_key_button is Button and balloon.history_key_button is Button
		and balloon.quick_save_key_button is Button
		and balloon.quick_load_key_button is Button and balloon.pause_key_button is Button
		and balloon.panic_key_button is Button,
		"settings authors a binding button for every keyboard action")
	var old_skip_key := (InputMap.action_get_events(&"dialogue_skip")[0] as InputEventKey).duplicate() as InputEventKey
	balloon._begin_rebind(&"dialogue_skip")
	check(balloon.skip_key_button.text == "Press any key...", "binding button waits for the next key")
	var rebound := InputEventKey.new()
	rebound.pressed = true
	rebound.keycode = KEY_K
	Input.parse_input_event(rebound)
	await get_tree().process_frame
	var rebound_events := InputMap.action_get_events(&"dialogue_skip")
	var binding_data: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://settings.json"))
	check(rebound_events.size() == 1 and (rebound_events[0] as InputEventKey).keycode == KEY_K
		and balloon.skip_key_button.text == "K",
		"next key replaces the selected action binding")
	check(binding_data is Dictionary and int(binding_data.key_bindings.dialogue_skip.keycode) == KEY_K,
		"custom key binding persists in settings")
	balloon._replace_action_key(&"dialogue_skip", old_skip_key)
	balloon._load_key_bindings(binding_data.key_bindings)
	check((InputMap.action_get_events(&"dialogue_skip")[0] as InputEventKey).keycode == KEY_K,
		"saved key binding restores into InputMap")
	balloon._replace_action_key(&"dialogue_skip", old_skip_key)
	balloon._refresh_binding_labels()
	balloon._save_settings()

	# Text size
	balloon.text_size_slider.value += 4  # set_value() emits value_changed
	await get_tree().process_frame
	check(alive() and balloon.dialogue_label.get_theme_font_size("normal_font_size") == int(balloon.text_size_slider.value),
		"text size applied to the dialogue label")
	check(alive() and balloon.character_label.get_theme_font_size("normal_font_size") == int(balloon.text_size_slider.value),
		"text size applied to the name plate")

	# Skip speed
	balloon.skip_speed_slider.value += 0.05
	await get_tree().process_frame
	check(alive() and is_equal_approx(balloon.skip_delay,
			balloon.skip_speed_slider.min_value + balloon.skip_speed_slider.max_value - balloon.skip_speed_slider.value)
		and is_equal_approx(balloon.skip_timer.wait_time, balloon.skip_delay),
		"skip speed applied to the skip timer with faster-right slider semantics")

	# Skip mode
	balloon.skip_mode_option.item_selected.emit(1)
	check(alive() and balloon.skip_seen_only, "skip mode 'seen only' registered")
	balloon.skip_mode_option.item_selected.emit(0)
	check(alive() and not balloon.skip_seen_only, "skip mode 'everything' registered")

	# UI scaling: only the UI subtree scales, the stage keeps its authored
	# size, and the settings column keeps a constant rendered width.
	var stage_size_before: Vector2 = balloon.background.size
	balloon.ui_scale_slider.value = 1.25
	await get_tree().process_frame
	check(alive() and balloon.ui_root.scale == Vector2(1.25, 1.25), "UI scale applied to the UI root only")
	check(alive() and is_equal_approx(balloon.ui_root.size.x, 1280.0 / 1.25),
		"UI root logical size shrinks so edges stay on screen")
	check(alive() and is_equal_approx(balloon.settings_margin.get_theme_constant("margin_left") * 1.25, 180.0),
		"settings width responds to the UI scale")
	check(alive() and balloon.sprite_left.scale == Vector2(1.0, 1.0)
		and stage_size_before == balloon.background.size,
		"UI scale leaves the stage and sprites untouched")
	balloon.ui_scale_slider.value = 1.0
	await get_tree().process_frame
	check(alive() and balloon.settings_margin.get_theme_constant("margin_left") == 180,
		"settings margins restore at scale 1")
	# Portrait: sliders wrap below their labels and the panel goes wide.
	balloon.set_portrait_mode(true)
	await get_tree().process_frame
	check(alive() and (balloon.text_size_slider.get_parent() as BoxContainer).vertical
		and balloon.settings_margin.get_theme_constant("margin_left") == 16,
		"portrait wraps sliders under labels, near-fullscreen wide")
	balloon.set_portrait_mode(false)
	await get_tree().process_frame
	check(alive() and not (balloon.text_size_slider.get_parent() as BoxContainer).vertical
		and balloon.settings_margin.get_theme_constant("margin_left") == 180,
		"landscape restores side-by-side rows")
	balloon.portrait_check.toggled.emit(true)
	await get_tree().process_frame
	check(alive() and balloon.portrait_mode
		and (balloon.text_size_slider.get_parent() as BoxContainer).vertical,
		"portrait layout can be forced from settings (editor-friendly)")
	balloon.portrait_check.toggled.emit(false)
	await get_tree().process_frame

	# Rotation buttons: 90 degrees flips the effective orientation to portrait.
	balloon._set_rotation(90)
	await get_tree().process_frame
	check(alive() and is_equal_approx(balloon.rotation, PI / 2.0) and balloon.portrait_mode,
		"90 rotation fits the view and swaps to portrait")
	check(alive() and balloon.balloon.size == Vector2(720.0, 1280.0)
		and is_equal_approx(balloon.transform.x.length(), 1.0),
		"rotation flips the logical resolution X/Y so the view fills the window (no gaps)")
	balloon._set_rotation(0)
	await get_tree().process_frame
	check(alive() and balloon.rotation == 0.0 and not balloon.portrait_mode,
		"rotation back to 0 restores landscape")
	check(alive() and balloon.balloon.size == Vector2(1280.0, 720.0),
		"logical resolution unflips at rotation 0")

	# Mobile ergonomics: the bottom row wraps, pause is one tap away, and the
	# panic page has a touch exit.
	balloon._set_rotation(90)
	await get_tree().process_frame
	check(alive() and balloon.system_row.columns < balloon.system_row.get_child_count()
		and (balloon.system_row.offset_bottom - balloon.system_row.offset_top) > 44.0,
		"system row wraps to fit a narrow aspect")
	balloon._set_rotation(0)
	await get_tree().process_frame
	check(alive() and balloon.system_row.columns == balloon.system_row.get_child_count(),
		"system row restores a single row on wide aspects")
	balloon.pause_button.pressed.emit()
	await get_tree().process_frame
	check(alive() and balloon.pause_panel.visible, "the row's Pause button opens pause on touch devices")
	balloon.pause_button.pressed.emit()
	await get_tree().process_frame
	check(alive() and not balloon.pause_panel.visible, "the Pause button closes pause again")
	balloon.toggle_panic()
	await get_tree().process_frame
	check(alive() and balloon.panic_screen.visible, "panic screen opens")
	balloon.panic_close_button.pressed.emit()
	await get_tree().process_frame
	check(alive() and not balloon.panic_screen.visible, "panic screen has a touch exit for phones")

	# --- i18n: Russian locale, translated UI/dialogue, localized voices ---
	check(alive() and balloon.language_option.item_count == 2, "language option offers English and Russian")
	balloon.language_option.item_selected.emit(1)
	await get_tree().process_frame
	await get_tree().process_frame
	check(alive() and TranslationServer.get_locale() == "ru", "language option switches the locale to Russian")
	check(alive() and balloon.save_button.text == "Сохранить", "authored UI strings follow the locale")
	check(alive() and balloon.skip_mode_option.get_item_text(0) == "Всё", "runtime option items follow the locale")
	var cyr := false
	for ch: String in balloon.dialogue_label.text:
		if ch.unicode_at(0) >= 0x400:
			cyr = true
			break
	check(alive() and cyr, "the visible line repaints in Russian on locale switch")
	var ru_clip := FileAccess.file_exists("res://assets/voices/ru/m1.ogg")
	check(alive() and balloon._voice_path("m1") == ("res://assets/voices/ru/m1.ogg" if ru_clip else "res://assets/voices/en/m1.ogg"),
		"voices resolve per locale with English fallback")
	var missing_ru := 0
	for k: String in ["r1", "r2", "r3", "r4", "r5", "r6", "m1", "m2", "m3", "m4", "m5", "m6", "m7", "m8"]:
		if not FileAccess.file_exists("res://assets/voices/ru/%s.ogg" % k):
			missing_ru += 1
	check(missing_ru == 0, "every voiced line has a Russian clip")
	balloon._play_voice("r1")
	check(alive() and balloon.voice_player.stream != null
		and balloon.voice_player.stream.resource_path.contains("/ru/"),
		"voiced lines play the localized clip under Russian")
	balloon.voice_player.stop()
	balloon.language_option.item_selected.emit(0)
	await get_tree().process_frame
	await get_tree().process_frame
	check(alive() and TranslationServer.get_locale() == "en" and balloon.save_button.text == "Save",
		"switching back restores English")

	# Sprite scale & Y offset are settings of their own, separate from UI scale
	balloon.sprite_scale_slider.value = 1.25
	await get_tree().process_frame
	check(alive() and balloon.sprite_left.scale == Vector2(1.25, 1.25)
		and balloon.sprite_right.scale == Vector2(1.25, 1.25),
		"sprite scale applied to both character sprites")
	balloon.sprite_y_slider.value = -40
	check(alive() and balloon.sprite_left.offset_bottom == -40.0
		and balloon.sprite_right.offset_bottom == -40.0,
		"sprite Y offset applied to both character sprites")
	check(alive() and balloon.sprite_left.size.y > 500, "Y offset shifts without flattening the sprite")
	var sprite_data: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://settings.json"))
	check(sprite_data is Dictionary and is_equal_approx(float(sprite_data.sprite_scale), 1.25)
		and float(sprite_data.sprite_y) == -40.0,
		"sprite scale and offset persisted")
	balloon.sprite_scale_slider.value = 1.0
	balloon.sprite_y_slider.value = 0

	# Regression: the bottom UI (dialogue box + system row) must stay the
	# lowest UIRoot layer, otherwise it paints over the lower settings rows
	# and swallows their taps (the old "sliders don't slide" bug). Headless
	# GUIs ignore synthetic taps, so tools/capture_shots.gd proves the tap
	# for real under xvfb; here we pin the layering that makes it work.
	var uiroot: Control = balloon.get_node("%UIRoot")
	check(alive() and uiroot.get_node("BottomUI").get_index() == 0,
		"dialogue box layer is the lowest UIRoot layer (never covers overlays)")
	check(alive() and balloon.settings_close_button.get_index() == uiroot.get_child_count() - 1,
		"the touch close button stays above every panel")

	# Resolution presets and any custom positive size
	balloon.resolution_option.item_selected.emit(1)
	check(alive() and int(balloon.res_width_spin.value) == 1600 and int(balloon.res_height_spin.value) == 900,
		"resolution preset fills the custom size spinboxes")
	balloon.res_width_spin.value = 1366
	balloon.res_width_spin.value_changed.emit(1366.0)  # set_value() emits nothing; user edits do
	balloon.res_height_spin.value = 768
	balloon.res_height_spin.value_changed.emit(768.0)
	await get_tree().process_frame
	check(alive() and balloon.resolution_option.selected == 4, "custom size flips the preset menu to 'Custom'")
	var res_data: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://settings.json"))
	check(res_data is Dictionary and int(res_data.res_w) == 1366 and int(res_data.res_h) == 768,
		"custom resolution persisted")
	balloon.res_width_spin.value = 1280
	balloon.res_width_spin.value_changed.emit(1280.0)
	balloon.res_height_spin.value = 720
	balloon.res_height_spin.value_changed.emit(720.0)
	check(alive() and balloon.resolution_option.selected == 0, "a size matching a preset re-selects it")

	# Vsync persists (headless has no real display to flip)
	balloon.vsync_check.toggled.emit(false)
	var vsync_data: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://settings.json"))
	check(vsync_data is Dictionary and vsync_data.get("vsync") == false, "vsync preference persisted")
	balloon.vsync_check.toggled.emit(true)

	# Audio buses and volumes
	balloon.master_vol_slider.value = 50
	balloon.music_vol_slider.value = 0
	await get_tree().process_frame
	check(alive() and AudioServer.get_bus_index(&"Music") > 0 and AudioServer.get_bus_index(&"Voice") > 0
		and AudioServer.get_bus_index(&"SFX") > 0, "music/voice/sfx audio buses exist")
	check(alive() and is_equal_approx(AudioServer.get_bus_volume_db(0), linear_to_db(0.5)),
		"master volume converted to dB")
	check(alive() and AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Music")) <= -79.0,
		"zero volume mutes the bus")
	balloon.master_vol_slider.value = 80
	balloon.music_vol_slider.value = 80

	# Seen-only skip: fast-forwards through read lines, halts at the first unread one.
	# The suite has played the whole game by now, so reset the seen log to create
	# a genuine read/unread boundary right after the current line.
	DirAccess.remove_absolute(balloon._seen_path)
	balloon._seen_ids = {}
	press(&"dialogue_close")
	await get_tree().process_frame
	check(alive() and not balloon.settings_panel.visible, "settings closed again")
	await wait_ready()
	# Roll back to a line followed by a plain (non-choice) line, so the halt we
	# observe is the seen-only halt and not the stop-at-choices halt.
	var rb_index: int = -1
	for i in range(balloon.history_cursor - 1, 0, -1):
		if not bool(balloon.history[i + 1].get("choices", false)):
			rb_index = i
			break
	check(alive() and rb_index > 0, "found a rollback spot with a plain line after it")
	balloon.rollback_to(rb_index)
	await wait_ready()
	var rolled_back_id: String = balloon.dialogue_line.id
	# This line was read when first shown; the re-apply after clearing reset the flag.
	balloon._current_was_seen = true
	balloon.skip_seen_only = true
	balloon.skip_button.grab_focus()
	press(&"ui_accept")
	line = await await_line_change()
	check(alive() and line.id != rolled_back_id, "seen-only skip advanced off the current line")
	for i in 240:
		if alive() and not balloon.skip_mode:
			break
		await get_tree().process_frame
	check(alive() and not balloon.skip_mode, "seen-only skip stopped itself at unseen text")
	# Exactly two lines were re-marked: the rollback target and the line skip halted on.
	check(alive() and balloon._seen_ids.size() == 2 and balloon._seen_ids.has(balloon.dialogue_line.id),
		"skip halted on the first unread line")
	check(alive() and "unseen" in balloon.toast_label.text, "the halt is announced to the player")
	balloon.skip_seen_only = false

	# --- Audio: procedural music, OGG loops and SFX -------------------------
	var ad: Node = get_tree().root.get_node("AudioDirector")
	check(ad != null, "AudioDirector autoload is registered")
	# Every bundled audio asset must stay tiny (< 20 KB).
	var oversize: Array[String] = []
	var music_files: int = 0
	var sfx_files: int = 0
	for dir_path: String in ["res://assets/music", "res://assets/sfx"]:
		var assets: DirAccess = DirAccess.open(dir_path)
		check(assets != null, "%s exists" % dir_path)
		if assets != null:
			assets.list_dir_begin()
			var asset_name: String = assets.get_next()
			while asset_name != "":
				if not assets.current_is_dir() and asset_name.ends_with(".ogg"):
					if dir_path.ends_with("music"):
						music_files += 1
					else:
						sfx_files += 1
					if FileAccess.get_file_as_bytes(dir_path + "/" + asset_name).size() >= 20 * 1024:
						oversize.append(dir_path + "/" + asset_name)
				asset_name = assets.get_next()
	check(music_files >= 2, "two tiny OGG music loops ship with the project")
	check(sfx_files >= 6, "the OGG SFX set is complete (click/open/close/confirm/save/error)")
	check(oversize.is_empty(), "every generated audio file is under 20 KB %s" % [oversize])

	# Procedural engine: starting a theme schedules notes and renders frames.
	var notes0: int = ad.notes_scheduled
	var frames0: int = ad.frames_pushed
	ad.play_theme(&"tense")
	for i in 30:
		await get_tree().process_frame
	check(ad.music_source == "procedural" and ad.current_theme == &"tense",
		"procedural theme 'tense' runs the generator")
	check(ad.notes_scheduled > notes0, "the scheduler queued notes for the theme")
	check(ad.frames_pushed > frames0, "rendered audio frames reached the generator")

	# Theme switching, idempotence and stop.
	ad.play_theme(&"night")
	check(ad.current_theme == &"night", "switching themes re-targets the generator")
	ad.play_theme(&"night")
	ad.play_theme(&"stop")
	await get_tree().process_frame
	check(ad.music_source == "", "play_theme stop silences the music")

	# Bundled OGG loop playback.
	ad.play_music_loop("res://assets/music/day.ogg")
	check(ad.music_source == "loop", "play_music_loop() crossfades to a loop source")
	check(String(ad._loop_path).ends_with("day.ogg"), "the loop player tracks the active OGG")

	# SFX: OGG assets, then the synthesized fallback for unknown keys.
	var played0: int = ad.sfx_played
	ad.play_sfx("confirm")
	check(ad.sfx_played == played0 + 1 and ad.last_sfx == "confirm" and ad.last_sfx_source == "ogg",
		"play_sfx('confirm') uses the OGG asset")
	ad.play_sfx("no_such_blip")
	check(ad.last_sfx == "no_such_blip" and ad.last_sfx_source == "synth",
		"unknown SFX keys fall back to runtime synthesis")

	# Typewriter ticks arrive per character (whitespace still counts a request).
	var ticks0: int = ad.typing_ticks
	balloon._on_label_spoke("a", 1, 0.018)
	balloon._on_label_spoke(" ", 2, 0.018)
	balloon._on_label_spoke("b", 3, 0.018)
	check(ad.typing_ticks == ticks0 + 3, "the typewriter forwards a tick per typed character")

	# Stage tags route through the director.
	var tagged: DialogueLine = DialogueLine.new()
	tagged.tags = ["music=warm"]
	balloon._apply_stage_tags(tagged)
	check(ad.current_theme == &"warm" and ad.music_source == "procedural",
		"#music= tag switches the procedural theme")
	var sfx_tag: DialogueLine = DialogueLine.new()
	sfx_tag.tags = ["sfx=open"]
	var tagged0: int = ad.sfx_played
	balloon._apply_stage_tags(sfx_tag)
	check(ad.sfx_played == tagged0 + 1 and ad.last_sfx == "open", "#sfx= tag plays through the director")
	var loop_tag: DialogueLine = DialogueLine.new()
	loop_tag.tags = ["music=loop:night"]
	balloon._apply_stage_tags(loop_tag)
	check(ad.music_source == "loop", "#music=loop:<key> plays a bundled OGG loop")
	var stop_tag: DialogueLine = DialogueLine.new()
	stop_tag.tags = ["music=stop"]
	balloon._apply_stage_tags(stop_tag)
	check(ad.music_source == "", "#music=stop fades the music out")

	# The "Generated music" toggle: persistence and the loop fallback.
	ad.play_theme(&"calm")
	check(ad.music_source == "procedural", "generation on -> themes use the engine")
	balloon.procedural_music_check.button_pressed = false
	balloon.procedural_music_check.toggled.emit(false)
	var pm_data: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://settings.json"))
	check(ad.procedural_enabled == false, "the toggle reaches the AudioDirector")
	check(pm_data is Dictionary and pm_data.get("procedural_music") == false,
		"generated-music preference persists")
	ad.play_theme(&"calm")
	check(ad.music_source == "loop", "generation off -> themes fall back to OGG loops")
	balloon.procedural_music_check.button_pressed = true
	balloon.procedural_music_check.toggled.emit(true)
	check(ad.procedural_enabled == true and ad.music_source == "procedural",
		"re-enabling generation restores the procedural engine")

	# Pause ducks audio without dropping the music; resume keeps it playing.
	ad.play_theme(&"calm")
	var theme_kept: StringName = ad.current_theme
	balloon.open_pause()
	check(ad.current_theme == theme_kept and ad.music_source == "procedural",
		"pause keeps the music state (Master bus duck only)")
	balloon.close_pause()
	check(ad.music_source == "procedural" and ad.current_theme == theme_kept,
		"resume keeps the same music going")

	# --- Sound toggles, per-choice sounds, dismiss-on-empty, save close ---
	# "Typewriter sound" gates per-character tick forwarding.
	balloon.typewriter_sfx_check.button_pressed = false
	balloon.typewriter_sfx_check.toggled.emit(false)
	var ticks_off: int = ad.typing_ticks
	balloon._on_label_spoke("a", 1, 0.018)
	check(ad.typing_ticks == ticks_off, "typewriter sound off stops tick forwarding")
	balloon.typewriter_sfx_check.button_pressed = true
	balloon.typewriter_sfx_check.toggled.emit(true)
	balloon._on_label_spoke("a", 1, 0.018)
	check(ad.typing_ticks == ticks_off + 1, "typewriter sound on forwards ticks again")
	# "Button sound" gates UI feedback.
	balloon.button_sfx_check.button_pressed = false
	balloon.button_sfx_check.toggled.emit(false)
	var btn_off: int = ad.sfx_played
	balloon._on_ui_button_sfx()
	balloon._sfx("open")
	check(ad.sfx_played == btn_off, "button sound off silences UI feedback")
	balloon.button_sfx_check.button_pressed = true
	balloon.button_sfx_check.toggled.emit(true)
	balloon._on_ui_button_sfx()
	check(ad.sfx_played == btn_off + 1, "button sound on plays UI feedback again")
	# Story #sfx= tags ignore the button toggle (content, not UI).
	balloon.button_sfx_check.button_pressed = false
	balloon.button_sfx_check.toggled.emit(false)
	var tag_off: int = ad.sfx_played
	var story_tag: DialogueLine = DialogueLine.new()
	story_tag.tags = ["sfx=open"]
	balloon._apply_stage_tags(story_tag)
	check(ad.sfx_played == tag_off + 1, "#sfx= tags still play with button sound off")
	balloon.button_sfx_check.button_pressed = true
	balloon.button_sfx_check.toggled.emit(true)
	var snd_data: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://settings.json"))
	check(snd_data is Dictionary and snd_data.get("sfx_typewriter") == true and snd_data.get("sfx_buttons") == true,
		"both sound toggles persist in settings.json")

	# Different choices play different sounds; #sfx= tags pick the clip.
	var saved_responses: Array = balloon.dialogue_line.responses
	var r1: DialogueResponse = DialogueResponse.new()
	var r2: DialogueResponse = DialogueResponse.new()
	var r3: DialogueResponse = DialogueResponse.new()
	r3.tags = ["sfx=error"]
	var crafted: Array[DialogueResponse] = [r1, r2, r3]
	balloon.dialogue_line.responses = crafted
	balloon._on_response_selected_sfx(r1)
	var pitch1: float = ad.last_sfx_pitch
	var key1: String = ad.last_sfx
	balloon._on_response_selected_sfx(r2)
	var pitch2: float = ad.last_sfx_pitch
	check(key1 == "confirm" and ad.last_sfx == "confirm" and pitch1 != pitch2,
		"different choices play the choice sound at different pitches")
	check(is_equal_approx(pitch1, 1.0) and pitch2 > pitch1, "choice pitches ascend with the option index")
	balloon._on_response_selected_sfx(r3)
	check(ad.last_sfx == "error" and is_equal_approx(ad.last_sfx_pitch, 1.0),
		"a #sfx= tag on a response overrides the choice sound")
	balloon.dialogue_line.responses = saved_responses

	# --- Hold-to-close: long tap on empty space, quick taps ignored, swipes cancel ---
	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.pressed = true
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = Vector2(30, 30)
	var release: InputEventMouseButton = InputEventMouseButton.new()
	release.pressed = false
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = press.position
	# Quick tap: nothing happens (accidental-tap protection).
	balloon.open_save_menu("load")
	check(alive() and balloon.save_menu_panel.visible, "the load menu opens")
	balloon.save_menu_panel.gui_input.emit(press)
	await get_tree().process_frame
	await get_tree().process_frame
	balloon._input(release)
	check(alive() and balloon.save_menu_panel.visible and not balloon._hold_active,
		"a quick tap does not dismiss a menu")
	# Long hold: ring + sound announce it, release completes the close.
	var hold_sfx0: int = ad.sfx_played
	balloon.save_menu_panel.gui_input.emit(press)
	await wait_until(func() -> bool: return not balloon._hold_active or balloon.hold_indicator.visible, 200)
	check(alive() and balloon.hold_indicator.visible, "holding empty space shows the animated indicator")
	check(ad.sfx_played == hold_sfx0 + 1 and ad.last_sfx == "hold", "the hold gesture is announced with sound")
	check(ad._hold_player.playing, "the hold tone plays continuously while charging")
	var tone_p0: float = ad._hold_player.pitch_scale
	await get_tree().process_frame
	await get_tree().process_frame
	check(ad._hold_player.pitch_scale > tone_p0, "the hold tone rises with progress")
	check(alive() and balloon.hold_indicator.progress > 0.0, "the indicator fills toward the close")
	await wait_until(func() -> bool: return not balloon._hold_active or balloon._hold_elapsed >= balloon.HOLD_SECONDS, 300)
	balloon._input(release)
	check(alive() and not balloon.save_menu_panel.visible and not balloon._hold_active and not balloon.hold_indicator.visible,
		"a long tap closes the menu and clears the indicator")
	check(not ad._hold_player.playing, "the hold tone stops with the gesture")
	# A swipe cancels the hold so touch scrolling still works.
	balloon.open_history()
	check(alive() and balloon.history_panel.visible, "the history panel opens")
	balloon.history_panel.gui_input.emit(press)
	await wait_until(func() -> bool: return not balloon._hold_active or balloon.hold_indicator.visible, 200)
	var swipe: InputEventMouseMotion = InputEventMouseMotion.new()
	swipe.position = press.position + Vector2(40, 0)
	swipe.relative = Vector2(40, 0)
	balloon._input(swipe)
	check(not balloon._hold_active and not balloon.hold_indicator.visible, "a swipe cancels the hold")
	check(not ad._hold_player.playing, "a swipe silences the hold tone")
	for i: int in 80:
		await get_tree().process_frame
	balloon._input(release)
	check(alive() and balloon.history_panel.visible, "a swiping drag does not dismiss the menu")
	balloon._close_overlay(balloon.history_panel)
	# Long hold works on settings and pause too (top-overlay close path).
	balloon._on_settings_pressed()
	check(alive() and balloon.settings_panel.visible, "the settings panel opens")
	balloon.settings_panel.gui_input.emit(press)
	await wait_until(func() -> bool: return not balloon._hold_active or balloon._hold_elapsed >= balloon.HOLD_SECONDS, 300)
	balloon._input(release)
	check(alive() and not balloon.settings_panel.visible and not balloon.settings_close_button.visible,
		"a long tap closes the settings")
	balloon.open_pause()
	check(alive() and balloon.pause_panel.visible, "the pause menu opens")
	balloon.pause_panel.gui_input.emit(press)
	await wait_until(func() -> bool: return not balloon._hold_active or balloon._hold_elapsed >= balloon.HOLD_SECONDS, 300)
	balloon._input(release)
	check(alive() and not balloon.pause_panel.visible, "a long tap closes the pause menu")
	# The save menu keeps its own X; non-left presses never start a hold.
	balloon.open_save_menu("save")
	check(alive() and balloon.save_menu_panel.visible, "the save menu opens")
	balloon.save_close_button.pressed.emit()
	check(alive() and not balloon.save_menu_panel.visible, "the save menu close button closes it")
	balloon.open_save_menu("load")
	var rclick: InputEventMouseButton = InputEventMouseButton.new()
	rclick.pressed = true
	rclick.button_index = MOUSE_BUTTON_RIGHT
	balloon.save_menu_panel.gui_input.emit(rclick)
	check(alive() and balloon.save_menu_panel.visible and not balloon._hold_active,
		"non-left presses do not start the hold")
	balloon._close_overlay(balloon.save_menu_panel)

	# --- Touch scrolling: rows pass drags to their ScrollContainer ---
	check(alive() and balloon.slot_template.mouse_filter == Control.MOUSE_FILTER_PASS
		and balloon.history_entry_template.mouse_filter == Control.MOUSE_FILTER_PASS,
		"list row templates pass input up so drags scroll the menu")
	check(alive() and balloon.history_scroll.get("scroll_deadzone") > 0.0
		and balloon.settings_scroll.get("scroll_deadzone") > 0.0
		and (balloon.slot_list.get_parent() as ScrollContainer).get("scroll_deadzone") > 0.0,
		"menu scroll containers carry a drag deadzone")
	# A press that moves is a drag: row handlers must not activate on release.
	var dp: InputEventMouseButton = InputEventMouseButton.new()
	dp.pressed = true
	dp.button_index = MOUSE_BUTTON_LEFT
	dp.position = Vector2(400, 300)
	balloon._input(dp)
	var dm: InputEventMouseMotion = InputEventMouseMotion.new()
	dm.position = Vector2(400, 340)
	dm.relative = Vector2(0, 40)
	dm.button_mask = MOUSE_BUTTON_MASK_LEFT
	balloon._input(dm)
	var dr: InputEventMouseButton = InputEventMouseButton.new()
	dr.pressed = false
	dr.button_index = MOUSE_BUTTON_LEFT
	dr.position = dm.position
	balloon._input(dr)
	check(balloon._press_dragged, "a moved press is tracked as a drag gesture")
	balloon.open_save_menu("save")
	var slots_before: int = balloon._scan_slots().size()
	balloon._on_slot_pressed(9)
	check(balloon._scan_slots().size() == slots_before,
		"a drag gesture ending on a row does not activate it")
	balloon._close_overlay(balloon.save_menu_panel)
	balloon._press_dragged = false
	# Presses on interactive controls never start the hold.
	balloon.open_save_menu("load")
	var over_btn: InputEventMouseButton = InputEventMouseButton.new()
	over_btn.pressed = true
	over_btn.button_index = MOUSE_BUTTON_LEFT
	over_btn.position = balloon.save_close_button.get_global_rect().get_center()
	balloon.save_menu_panel.gui_input.emit(over_btn)
	check(not balloon._hold_active, "a press on a control does not start the hold")
	balloon._close_overlay(balloon.save_menu_panel)

	finish()


func finish() -> void:
	print("=====================================")
	print("VN balloon tests: %d passed, %d failed" % [passes, fails])
	print("=====================================")
	# Drop references so the forced quit doesn't report them as in-use.
	balloon = null
	resource = null
	get_tree().quit(1 if fails > 0 else 0)
