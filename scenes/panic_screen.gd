extends Control
## Boss screen. Edit this scene (layout, colors, text) without touching the
## balloon. Closing it loads the game scene back at the line that was showing.
## When this scene replaces the game it is not inside the scaled UI, so it
## reapplies the saved resolution, UI scale, and rotation itself.


signal dismissed

const DisplayScale = preload("res://scenes/display_scale.gd")

var _base_font_sizes: Dictionary = {}

## Place to resume after this scene replaces the game. Empty when the screen
## is only covering a game that is still loaded.
static var ticket: Dictionary = {}


static func has_ticket() -> bool:
	return not ticket.is_empty()


static func take_ticket() -> Dictionary:
	var place := ticket
	ticket = {}
	return place


static func load_into(parent: Node, path: String) -> Control:
	var packed: Resource = load(path)
	if packed == null:
		return null
	var screen: Control = packed.instantiate()
	screen.name = "PanicScreen"
	parent.add_child(screen)
	# Stay under the settings X so that button remains the last UIRoot child.
	# z_index keeps the lecture page above it while the page is open.
	var closer := parent.get_node_or_null("SettingsCloseButton")
	if closer != null:
		parent.move_child(screen, closer.get_index())
	return screen


static func return_to_game(tree: SceneTree) -> void:
	var back := str(ticket.get("scene_path", ""))
	if back == "" or not ResourceLoader.exists(back):
		back = "res://scenes/vn_scene.tscn"
	tree.change_scene_to_file(back)


func _ready() -> void:
	_apply_text()
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Overlay panic sits in the balloon's already-rotated canvas. Only the
	# standalone page (this scene replaced the game) applies scale and rotation.
	if get_tree().current_scene == self:
		_apply_standalone_scale()
		if not get_viewport().size_changed.is_connected(_apply_standalone_scale):
			get_viewport().size_changed.connect(_apply_standalone_scale)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_apply_text()


var _applying_view := false


func _apply_standalone_scale() -> void:
	if _applying_view:
		return
	_applying_view = true
	var data := DisplayScale.read_settings()
	var w := int(data.get("res_w", DisplayScale.DESIGN.x))
	var h := int(data.get("res_h", DisplayScale.DESIGN.y))
	DisplayScale.apply_window(get_tree(), w, h)
	# Same limits as the UI scale slider. Volume is unrelated.
	var ui := clampf(float(data.get("ui_scale", 1.0)), 0.5, 2.5)
	scale = Vector2(ui, ui)
	var deg := int(data.get("rotation", 0))
	_apply_saved_rotation(deg)
	var text_mul := clampf(float(data.get("text_size", 20.0)) / 20.0, 0.5, 2.0)
	for node in [get_node_or_null("PanicMargin/PanicScroll/PanicVBox/PanicTitle"),
			get_node_or_null("PanicMargin/PanicScroll/PanicVBox/PanicBody"),
			get_node_or_null("PanicCloseButton")]:
		if not node is Control:
			continue
		if not _base_font_sizes.has(node.get_instance_id()):
			_base_font_sizes[node.get_instance_id()] = node.get_theme_font_size("font_size")
		node.add_theme_font_size_override("font_size", roundi(float(_base_font_sizes[node.get_instance_id()]) * text_mul))
	_applying_view = false


## Same idea as the balloon CanvasLayer: at 90/270 the page lays out in the
## swapped logical size, then rotates around the window center so it fills the
## window. Overlay panic must not call this — it is already inside that layer.
func _apply_saved_rotation(deg: int) -> void:
	var d := posmod(deg, 360)
	if d != 90 and d != 180 and d != 270:
		d = 0
	var win := get_viewport().get_visible_rect().size
	if win.x < 2.0 or win.y < 2.0:
		return
	var swapped := d == 90 or d == 270
	var logical := Vector2(win.y, win.x) if swapped else win
	var ui := scale.x if scale.x > 0.01 else 1.0
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	anchor_right = 0.0
	anchor_bottom = 0.0
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	size = logical / ui
	pivot_offset = size * 0.5
	rotation = deg_to_rad(float(d))
	position = win * 0.5 - pivot_offset


func _apply_text() -> void:
	var title := get_node_or_null("PanicMargin/PanicScroll/PanicVBox/PanicTitle")
	var body := get_node_or_null("PanicMargin/PanicScroll/PanicVBox/PanicBody")
	if title != null and "text" in title:
		title.text = tr("PHYS 201 - Quantum Mechanics II")
	if body != null and "text" in body:
		body.text = tr("Lecture 12: The time-independent Schroedinger equation. H psi = E psi, where H is the Hamiltonian operator. For a particle in a 1-D infinite well of width L the energy eigenvalues are E_n = n^2 h^2 / (8 m L^2). Reminder: problem set 4 is due Friday - problems 3.7, 3.9 and the derivation of the uncertainty principle for position and momentum.")


func _unhandled_input(event: InputEvent) -> void:
	# Only when this scene replaced the game. An overlay lets the balloon own the key.
	if get_tree().current_scene != self:
		return
	if event.is_action_pressed(&"dialogue_panic"):
		get_viewport().set_input_as_handled()
		_request_close()


func _request_close() -> void:
	if get_tree().current_scene == self:
		return_to_game(get_tree())
		return
	dismissed.emit()
