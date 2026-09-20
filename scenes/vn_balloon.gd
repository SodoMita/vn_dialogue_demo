class_name VNBalloon extends CanvasLayer
## A classical visual-novel balloon for Dialogue Manager.
##
## The whole UI (background stage, sprite slots, name plate, dialogue box,
## next indicator and responses menu) is AUTHORED in `vn_balloon.tscn` and is
## freely editable in the Godot editor. This script only adds behaviour: it
## never creates, adds or rebuilds scene nodes.
##
## Stage direction tags supported on any dialogue line:
##   #bg=name              switch the background (key of `backgrounds`)
##   #bg=none              clear the background
##   #sprite=name:slot     show a portrait in slot "left" or "right" (key of `sprites`)
##   #sprite=none:slot     clear a slot
##   #focus=slot           spotlight one slot, dim the other
##   #box=hide / #box=show hide or show the dialogue box (pure stage directions)


## The dialogue resource (only needed when dropping the balloon into a scene manually).
@export var dialogue_resource: DialogueResource

## Start from a given cue when used as a [Node] in a scene.
@export var start_from_cue: String = ""

## If placed in a scene manually, start the dialogue on ready.
@export var auto_start: bool = false

## If all other input is blocked as long as dialogue is shown.
@export var will_block_other_input: bool = true

## The action to use for advancing the dialogue.
@export var next_action: StringName = &"ui_accept"

## The action to use to skip typing the dialogue.
@export var skip_action: StringName = &"ui_cancel"

## The action that toggles the history (backlog) panel.
@export var history_action: StringName = &"dialogue_history"

## How many seconds each typed character takes.
@export var seconds_per_step: float = 0.018

## Background textures, referenced from dialogue with `#bg=<key>`.
@export var backgrounds: Dictionary[String, Texture2D] = {}

## Portrait textures, referenced from dialogue with `#sprite=<key>:<slot>`.
@export var sprites: Dictionary[String, Texture2D] = {}


## The base balloon anchor
@onready var balloon: Control = %Balloon

## Stage
@onready var background: TextureRect = %Background
@onready var sprite_left: TextureRect = %SpriteLeft
@onready var sprite_right: TextureRect = %SpriteRight

## Dialogue box
@onready var dialogue_box: PanelContainer = %DialogueBox
@onready var name_plate: PanelContainer = %NamePlate
@onready var character_label: RichTextLabel = %CharacterLabel
@onready var dialogue_label: DialogueLabel = %DialogueLabel
@onready var next_indicator: Polygon2D = %NextIndicator

## Choices
@onready var responses_menu: DialogueResponsesMenu = %ResponsesMenu

## History (backlog) panel - authored in the scene, entries duplicate %HistoryEntry.
@onready var history_panel: PanelContainer = %HistoryPanel
@onready var history_list: VBoxContainer = %HistoryList
@onready var history_entry_template: Button = %HistoryEntry

## Timer used to briefly hide the box while a mutation runs (authored in the scene).
@onready var mutation_cooldown: Timer = %MutationCooldown


## Temporary game states
var temporary_game_states: Array = []

## See if we are waiting for the player
var is_waiting_for_input: bool = false

## See if we are running a long mutation and should hide the box
var will_hide_box: bool = false

## A dictionary to store any ephemeral variables dialogue can use via `locals.`
var locals: Dictionary = {}

## Backlog of every line shown this run; clicking an entry rolls back to it.
var history: Array[Dictionary] = []

## True while a rollback line is being (re)applied, so it isn't logged twice.
var _restoring: bool = false

## The stage as currently dressed (tag keys), snapshotted into history entries.
var _current_bg: String = ""
var _current_left: String = ""
var _current_right: String = ""
var _current_focus: String = ""

var _locale: String = TranslationServer.get_locale()


## The current line
var dialogue_line: DialogueLine:
	set(value):
		if value:
			dialogue_line = value
			apply_dialogue_line()
		else:
			# The dialogue has finished so close the balloon
			if owner == null:
				queue_free()
			else:
				hide()
	get:
		return dialogue_line


func _ready() -> void:
	balloon.hide()
	history_panel.hide()
	history_entry_template.hide()
	Engine.get_singleton("DialogueManager").mutated.connect(_on_mutated)

	# If the responses menu doesn't have a next action set, use this one
	if responses_menu.next_action.is_empty():
		responses_menu.next_action = next_action

	dialogue_label.seconds_per_step = seconds_per_step
	mutation_cooldown.timeout.connect(_on_mutation_cooldown_timeout)

	if auto_start:
		if not is_instance_valid(dialogue_resource):
			assert(false, DMConstants.get_error_message(DMConstants.ERR_MISSING_RESOURCE_FOR_AUTOSTART))
		start()


func _process(_delta: float) -> void:
	if is_instance_valid(dialogue_line):
		next_indicator.visible = not dialogue_label.is_typing \
			and dialogue_line.responses.size() == 0 \
			and is_waiting_for_input


func _unhandled_input(event: InputEvent) -> void:
	if not (will_block_other_input and is_instance_valid(balloon) and balloon.is_visible_in_tree()):
		return

	# Toggle the history panel.
	if event.is_action_pressed(history_action):
		get_viewport().set_input_as_handled()
		if history_panel.visible:
			close_history()
		else:
			open_history()
		return

	# While the history is open, swallow anything the entry buttons didn't take;
	# the skip action closes the panel without rolling back.
	if history_panel.visible:
		get_viewport().set_input_as_handled()
		if event.is_action_pressed(skip_action):
			close_history()
		return

	# Advance via keyboard even when no control currently holds focus
	# (the gui_input handler already covers the focused-balloon and mouse cases).
	if is_waiting_for_input \
		and is_instance_valid(dialogue_line) \
		and dialogue_line.responses.size() == 0 \
		and not dialogue_label.is_typing \
		and event.is_action_pressed(next_action):
		get_viewport().set_input_as_handled()
		next(dialogue_line.next_id)
		return

	# Only the balloon is allowed to handle input while it's showing
	get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	# Detect a change of locale and update the current dialogue line to show the new language
	if what == NOTIFICATION_TRANSLATION_CHANGED and _locale != TranslationServer.get_locale() and is_instance_valid(dialogue_label):
		_locale = TranslationServer.get_locale()
		var visible_ratio: float = dialogue_label.visible_ratio
		await dialogue_line.refresh()
		if visible_ratio < 1:
			dialogue_label.skip_typing()


## Start some dialogue
func start(with_dialogue_resource: DialogueResource = null, cue: String = "", extra_game_states: Array = []) -> void:
	temporary_game_states = [self] + extra_game_states
	is_waiting_for_input = false
	if is_instance_valid(with_dialogue_resource):
		dialogue_resource = with_dialogue_resource
	if not cue.is_empty():
		start_from_cue = cue
	show()
	dialogue_line = await dialogue_resource.get_next_dialogue_line(start_from_cue, temporary_game_states)


## Apply any changes to the balloon given a new [DialogueLine].
func apply_dialogue_line() -> void:
	mutation_cooldown.stop()

	next_indicator.hide()
	is_waiting_for_input = false

	# Stage direction tags first, so the scene is dressed before the text types out.
	_apply_stage_tags(dialogue_line)

	# Log this line in the backlog (skipped while rolling back to it), capturing
	# the story state and the dressed stage so rollback can restore both.
	if not _restoring and (not dialogue_line.text.is_empty() or not dialogue_line.character.is_empty()):
		var entry: Dictionary = {
			"id": dialogue_line.id,
			"character": dialogue_line.character,
			"text": dialogue_line.text,
			"bg": _current_bg,
			"left": _current_left,
			"right": _current_right,
			"focus": _current_focus,
		}
		var game_state: Node = get_tree().root.get_node_or_null("GameState")
		if is_instance_valid(game_state) and game_state.has_method("snapshot"):
			entry.state = game_state.snapshot()
		history.append(entry)
	_restoring = false

	character_label.visible = not dialogue_line.character.is_empty()
	name_plate.visible = character_label.visible
	character_label.text = tr(dialogue_line.character, "dialogue")

	dialogue_label.hide()
	dialogue_label.dialogue_line = dialogue_line

	responses_menu.hide()
	responses_menu.responses = dialogue_line.responses

	# Show our balloon (a line may hide the box again via #box=hide)
	balloon.show()
	will_hide_box = false
	if dialogue_line.get_tag_value("box") != "hide":
		dialogue_box.show()
		name_plate.visible = character_label.visible

	dialogue_label.show()
	if not dialogue_line.text.is_empty():
		dialogue_label.type_out()
		await dialogue_label.finished_typing

	# Wait for next line
	if dialogue_line.responses.size() > 0:
		balloon.focus_mode = Control.FOCUS_NONE
		responses_menu.show()
	elif dialogue_line.time != "":
		var time: float = dialogue_line.text.length() * 0.02 if dialogue_line.time == "auto" else dialogue_line.time.to_float()
		await get_tree().create_timer(time).timeout
		next(dialogue_line.next_id)
	else:
		is_waiting_for_input = true
		balloon.focus_mode = Control.FOCUS_ALL
		balloon.grab_focus()


## Go to the next line
func next(next_id: String) -> void:
	dialogue_line = await dialogue_resource.get_next_dialogue_line(next_id, temporary_game_states)


#region Stage direction tags


func _apply_stage_tags(line: DialogueLine) -> void:
	for tag: String in line.tags:
		if tag.begins_with("bg="):
			_set_background(tag.substr(3))
		elif tag.begins_with("sprite="):
			_set_sprite(tag.substr(7))
		elif tag.begins_with("focus="):
			_set_focus(tag.substr(6))
		elif tag == "box=hide":
			dialogue_box.hide()
			name_plate.hide()
			next_indicator.hide()
		elif tag == "box=show":
			dialogue_box.show()


func _set_background(key: String) -> void:
	_current_bg = key
	if key == "none":
		background.texture = null
	elif backgrounds.has(key):
		background.texture = backgrounds[key]


func _set_sprite(spec: String) -> void:
	var parts: PackedStringArray = spec.split(":")
	var key: String = parts[0]
	var is_left: bool = parts.size() == 1 or parts[1] == "left"
	var slot: TextureRect = sprite_left if is_left else sprite_right
	if is_left:
		_current_left = key
	else:
		_current_right = key
	if key == "none":
		slot.texture = null
		slot.modulate.a = 0.0
	elif sprites.has(key):
		slot.texture = sprites[key]
		slot.modulate.a = 1.0


func _set_focus(slot_name: String) -> void:
	_current_focus = slot_name
	var dim: float = 0.45
	sprite_left.modulate.a = 1.0
	sprite_right.modulate.a = 1.0
	if slot_name == "left" and sprite_right.texture != null:
		sprite_right.modulate.a = dim
	elif slot_name == "right" and sprite_left.texture != null:
		sprite_left.modulate.a = dim


## Re-dress the stage exactly as it was when a history entry was shown.
func _restore_stage(entry: Dictionary) -> void:
	_set_background(entry.get("bg", ""))
	_set_sprite("%s:left" % entry.get("left", "none") if entry.get("left", "") != "" else "none:left")
	_set_sprite("%s:right" % entry.get("right", "none") if entry.get("right", "") != "" else "none:right")
	if entry.get("focus", "") != "":
		_set_focus(entry.focus)


#endregion


#region History / rollback


## Rebuild the backlog list from [member history] and show the panel.
func open_history() -> void:
	if history.is_empty():
		return

	for child: Node in history_list.get_children():
		if child == history_entry_template:
			continue
		history_list.remove_child(child)
		child.queue_free()

	for i: int in history.size():
		var entry: Dictionary = history[i]
		var item: Button = history_entry_template.duplicate()
		item.text = entry.text if entry.character.is_empty() else "%s: %s" % [entry.character, entry.text]
		item.show()
		item.pressed.connect(_on_history_entry_pressed.bind(i))
		history_list.add_child(item)

	is_waiting_for_input = false
	history_panel.show()
	# Focus the first entry so keyboard navigation works immediately.
	for child: Node in history_list.get_children():
		if child != history_entry_template:
			child.grab_focus()
			break


func close_history() -> void:
	history_panel.hide()
	# If the current line was already waiting for input, let it wait again.
	if is_instance_valid(dialogue_line) and not dialogue_label.is_typing and dialogue_line.responses.size() == 0:
		is_waiting_for_input = true
		balloon.focus_mode = Control.FOCUS_ALL
		balloon.grab_focus()


## Jump back to a previously shown line, restoring the story state snapshot.
func rollback_to(index: int) -> void:
	if index < 0 or index >= history.size():
		return

	var entry: Dictionary = history[index]
	history = history.slice(0, index + 1)
	close_history()

	var game_state: Node = get_tree().root.get_node_or_null("GameState")
	if is_instance_valid(game_state) and game_state.has_method("restore") and entry.has("state"):
		game_state.restore(entry.state)
	_restore_stage(entry)

	_restoring = true
	var line: DialogueLine = await dialogue_resource.get_next_dialogue_line(entry.id, temporary_game_states)
	if line != null:
		dialogue_line = line
	_restoring = false


func _on_history_entry_pressed(index: int) -> void:
	rollback_to(index)


#endregion


#region Signals


func _on_mutation_cooldown_timeout() -> void:
	if will_hide_box:
		will_hide_box = false
		dialogue_box.hide()
		name_plate.hide()


func _on_mutated(mutation: Dictionary) -> void:
	if not mutation.is_inline:
		is_waiting_for_input = false
		will_hide_box = true
		mutation_cooldown.start(0.1)


func _on_balloon_gui_input(event: InputEvent) -> void:
	if history_panel.visible:
		return

	# The balloon swallows input while waiting, so the history toggle has to be
	# honoured here as well as in _unhandled_input.
	if event.is_action_pressed(history_action):
		get_viewport().set_input_as_handled()
		open_history()
		return

	# See if we need to skip typing of the dialogue
	if dialogue_label.is_typing:
		var mouse_was_clicked: bool = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed()
		var skip_button_was_pressed: bool = event.is_action_pressed(skip_action)
		if mouse_was_clicked or skip_button_was_pressed:
			get_viewport().set_input_as_handled()
			dialogue_label.skip_typing()
			return

	if not is_waiting_for_input: return
	if dialogue_line.responses.size() > 0: return

	# When there are no response options the balloon itself is the clickable thing
	get_viewport().set_input_as_handled()

	if event is InputEventMouseButton and event.is_pressed() and event.button_index == MOUSE_BUTTON_LEFT:
		next(dialogue_line.next_id)
	elif event.is_action_pressed(next_action) and get_viewport().gui_get_focus_owner() == balloon:
		next(dialogue_line.next_id)


func _on_responses_menu_response_selected(response: DialogueResponse) -> void:
	next(response.next_id)


#endregion
