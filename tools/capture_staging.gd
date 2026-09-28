## Dev tool: plays examples/staging_demo.dialogue and saves screenshots.
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 \
##     --rendering-method gl_compatibility res://tools/capture_staging.tscn
extends Node

var balloon: VNBalloon


func _ready() -> void:
	await get_tree().process_frame
	var packed: PackedScene = load("res://scenes/vn_balloon.tscn")
	balloon = packed.instantiate()
	add_child(balloon)
	await get_tree().process_frame
	var res: Resource = load("res://examples/staging_demo.dialogue")
	balloon.start(res, "start")
	var shots := [[0, "s1_3d_door"], [1, "s2_3d_desk"], [4, "s3_3d_focus"], [9, "s4_2d_anchors"], [11, "s5_2d_moves"]]
	var step := 0
	for shot: Array in shots:
		while step < int(shot[0]):
			await _settle()
			balloon.next(balloon.dialogue_line.next_id)
			await _line_change()
			step += 1
		await _settle()
		await get_tree().create_timer(1.1).timeout
		var img := get_viewport().get_texture().get_image()
		img.save_png("user://%s.png" % shot[1])
		print("saved ", ProjectSettings.globalize_path("user://%s.png" % shot[1]))
	get_tree().quit()


func _settle() -> void:
	for i in 300:
		if is_instance_valid(balloon.dialogue_line) and not balloon.dialogue_label.is_typing:
			return
		if balloon.dialogue_label.is_typing:
			balloon.dialogue_label.skip_typing()
		await get_tree().process_frame


func _line_change() -> void:
	var before := str(balloon.dialogue_line.id)
	for i in 300:
		if is_instance_valid(balloon.dialogue_line) and str(balloon.dialogue_line.id) != before:
			return
		await get_tree().process_frame
