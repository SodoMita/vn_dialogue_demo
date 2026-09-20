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

	await get_tree().process_frame
	get_tree().quit(0)
