extends Control
## Boss screen. Edit this scene (layout, colors, text) without touching the
## balloon. Closing it loads the game scene back at the line that was showing.


signal dismissed

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


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_apply_text()


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
