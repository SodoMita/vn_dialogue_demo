## Dev tool: drives the intro dialogue and saves viewport screenshots.
## Run under a virtual display, e.g.:
##   xvfb-run -a -s "-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --rendering-method gl_compatibility \
##     res://tools/capture_shots.tscn
extends Node


var balloon: VNBalloon


func _ready() -> void:
	await get_tree().process_frame
	run()


func press(action: StringName) -> void:
	var ev := InputEventKey.new()
	ev.pressed = true
	match action:
		&"ui_accept": ev.keycode = KEY_ENTER
		&"ui_cancel": ev.keycode = KEY_ESCAPE
		_: ev.keycode = KEY_ENTER
	Input.parse_input_event(ev)
	await get_tree().process_frame


func wait_until(cond: Callable, max_frames: int = 400) -> void:
	for i in max_frames:
		if cond.call():
			return
		await get_tree().process_frame


func settle() -> void:
	if is_instance_valid(balloon) and balloon.dialogue_label.is_typing:
		press(&"ui_cancel")
	await wait_until(func() -> bool:
		return not is_instance_valid(balloon) or not balloon.dialogue_label.is_typing
	)
	await get_tree().process_frame
	await get_tree().process_frame


func shot(name: String) -> void:
	await get_tree().process_frame
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("res://docs/%s.png" % name)
	print("SHOT %s" % name)


func new_line() -> void:
	var old: String = balloon.dialogue_line.id if balloon.dialogue_line else ""
	press(&"ui_accept")
	await wait_until(func() -> bool:
		return not is_instance_valid(balloon) or (balloon.dialogue_line != null and balloon.dialogue_line.id != old)
	)


func run() -> void:
	# Clean saves/settings so shots are deterministic.
	var saves_dir: DirAccess = DirAccess.open("user://saves")
	if saves_dir != null:
		saves_dir.list_dir_begin()
		var fname: String = saves_dir.get_next()
		while fname != "":
			saves_dir.remove(fname)
			fname = saves_dir.get_next()
	var user_dir: DirAccess = DirAccess.open("user://")
	if user_dir != null and user_dir.file_exists("settings.json"):
		user_dir.remove("settings.json")

	var res: DialogueResource = load("res://dialogue/intro.dialogue")
	balloon = DialogueManager.show_dialogue_balloon(res, "start")
	await get_tree().process_frame
	await get_tree().process_frame
	await wait_until(func() -> bool: return is_instance_valid(balloon) and balloon.dialogue_line != null)

	await settle()
	await shot("01_narration_classroom")

	await new_line()
	await settle()
	await shot("02_rook_right")

	await new_line()
	await settle()
	await shot("03_maya_left_focus")

	# walk to the first choice set
	for i in 3:
		if balloon.dialogue_line.responses.size() > 0:
			break
		await new_line()
		await settle()
	await wait_until(func() -> bool:
		return is_instance_valid(balloon) and balloon.dialogue_line.responses.size() > 0 and balloon.responses_menu.visible
	)
	await get_tree().process_frame
	await shot("04_choices")

	# History panel
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.physical_keycode = KEY_H
	Input.parse_input_event(ev)
	var rel := InputEventKey.new()
	rel.keycode = KEY_H
	Input.parse_input_event(rel)
	await wait_until(func() -> bool:
		return is_instance_valid(balloon) and balloon.history_panel.visible
	)
	await get_tree().process_frame
	await shot("05_history")

	# Close history, save, and capture the toast + system bar.
	var evh := InputEventKey.new()
	evh.pressed = true
	evh.physical_keycode = KEY_H
	Input.parse_input_event(evh)
	await wait_until(func() -> bool:
		return not is_instance_valid(balloon) or not balloon.history_panel.visible
	)
	var evs := InputEventKey.new()
	evs.pressed = true
	evs.keycode = KEY_F5
	Input.parse_input_event(evs)
	await wait_until(func() -> bool:
		return is_instance_valid(balloon) and balloon.toast_label.visible
	)
	await get_tree().process_frame
	await shot("06_saved_toast")

	# 07: plain line with the bottom system row (no toast)
	await wait_until(func() -> bool:
		return is_instance_valid(balloon) and not balloon.toast_label.visible
	, 600)
	await get_tree().process_frame
	await shot("07_system_row")

	# 08: save menu with slot list + New Slot
	balloon.open_save_menu("save")
	await wait_until(func() -> bool:
		return is_instance_valid(balloon) and balloon.save_menu_panel.visible
	)
	await get_tree().process_frame
	await get_tree().process_frame
	await shot("08_save_menu")

	# 09: settings panel
	balloon._close_overlay(balloon.save_menu_panel)
	balloon._on_settings_pressed()
	await wait_until(func() -> bool:
		return is_instance_valid(balloon) and balloon.settings_panel.visible
	)
	await get_tree().process_frame
	await get_tree().process_frame
	await shot("09_settings")

	# 10: pause menu
	balloon._close_overlay(balloon.settings_panel)
	balloon.open_pause()
	await wait_until(func() -> bool:
		return is_instance_valid(balloon) and balloon.pause_panel.visible
	)
	await get_tree().process_frame
	await get_tree().process_frame
	await shot("10_pause")

	# 11: panic screen (boss key)
	balloon.close_pause()
	balloon.toggle_panic()
	await wait_until(func() -> bool:
		return is_instance_valid(balloon) and balloon.panic_screen.visible
	)
	await get_tree().process_frame
	await get_tree().process_frame
	await shot("11_panic")

	await get_tree().process_frame
	get_tree().quit(0)
