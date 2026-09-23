extends Node
## Survives scene changes. Confirms panic replaces the game scene, then close
## loads the game back on the same line.


func _ready() -> void:
	await get_tree().process_frame
	get_tree().change_scene_to_file("res://scenes/vn_scene.tscn")
	var balloon: Node = await _wait_balloon()
	if balloon == null:
		_fail("game did not start")
		return
	balloon.auto_mode = false
	balloon.skip_mode = false
	if balloon.auto_timer:
		balloon.auto_timer.stop()
	var line_id := ""
	if balloon.dialogue_line != null:
		line_id = str(balloon.dialogue_line.id)
	var cursor: int = balloon.history_cursor
	var resource_path := ""
	if balloon.dialogue_resource != null:
		resource_path = str(balloon.dialogue_resource.resource_path)
	balloon.toggle_panic()
	var panic: Node = await _wait_scene("panic_screen.tscn")
	if panic == null:
		_fail("panic did not load its scene")
		return
	if not panic.has_method("_request_close"):
		_fail("panic scene has no close")
		return
	panic._request_close()
	var game: Node = await _wait_scene("vn_scene.tscn")
	if game == null:
		_fail("close did not load the game scene")
		return
	balloon = await _wait_balloon()
	if balloon == null or balloon.dialogue_line == null:
		_fail("game loaded without a line")
		return
	if str(balloon.dialogue_line.id) != line_id:
		_fail("returned to line %s, expected %s" % [balloon.dialogue_line.id, line_id])
		return
	if balloon.history_cursor != cursor:
		_fail("history cursor is %s, expected %s" % [balloon.history_cursor, cursor])
		return
	if resource_path != "" and balloon.dialogue_resource != null and str(balloon.dialogue_resource.resource_path) != resource_path:
		_fail("returned in a different dialogue resource")
		return
	if AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")):
		_fail("audio stayed muted after returning")
		return
	print("PANIC RETURN OK line=%s cursor=%s" % [line_id, cursor])
	get_tree().quit(0)


func _wait_scene(suffix: String) -> Node:
	for _i in 240:
		var scene := get_tree().current_scene
		if scene != null and str(scene.scene_file_path).ends_with(suffix):
			return scene
		await get_tree().process_frame
	return null


func _wait_balloon() -> Node:
	for _i in 240:
		var scene := get_tree().current_scene
		if scene != null:
			for child in scene.get_children():
				if child != null and child.has_method("toggle_panic") and child.dialogue_line != null:
					return child
		await get_tree().process_frame
	return null


func _fail(message: String) -> void:
	push_error(message)
	print("PANIC RETURN FAIL: %s" % message)
	get_tree().quit(1)
