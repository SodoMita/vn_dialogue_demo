class_name VNBalloon extends CanvasLayer
## A classical visual-novel balloon for Dialogue Manager.
##
## The whole UI (background stage, sprite slots, name plate, dialogue box,
## next indicator, responses menu, history panel, save-slot menu, settings,
## pause menu, panic screen and the bottom system row) is AUTHORED in
## `vn_balloon.tscn` and freely editable in the Godot editor. This script only
## adds behaviour: it never creates structural nodes - dynamic list entries
## (history, slots) duplicate authored template buttons, the standard DM pattern.
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

## Quick-save / quick-load actions (slot 0).
@export var save_action: StringName = &"dialogue_save"
@export var load_action: StringName = &"dialogue_load"

## The action that toggles the pause menu (P / right click).
@export var pause_action: StringName = &"dialogue_pause"

## The boss-key action that swaps to the panic screen.
@export var panic_action: StringName = &"dialogue_panic"

## Directory holding the arbitrary number of save slots.
@export var saves_dir: String = "user://saves"

## How many seconds each typed character takes (overridden by saved settings).
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

## History (backlog)
@onready var history_panel: PanelContainer = %HistoryPanel
@onready var history_list: VBoxContainer = %HistoryList
@onready var history_entry_template: Button = %HistoryEntry

## System row + chrome
@onready var qs_button: Button = %QSButton
@onready var ql_button: Button = %QLButton
@onready var save_button: Button = %SaveButton
@onready var load_button: Button = %LoadButton
@onready var auto_button: Button = %AutoButton
@onready var skip_button: Button = %SkipButton
@onready var log_button: Button = %LogButton
@onready var settings_button: Button = %SettingsButton
@onready var panic_button: Button = %PanicButton
@onready var toast_label: Label = %ToastLabel
@onready var toast_timer: Timer = %ToastTimer
@onready var auto_timer: Timer = %AutoTimer

## Save-slot menu
@onready var save_menu_panel: PanelContainer = %SaveMenuPanel
@onready var save_menu_title: Label = %SaveMenuTitle
@onready var slot_list: VBoxContainer = %SlotList
@onready var slot_template: Button = %SlotButton
@onready var new_slot_button: Button = %NewSlotButton

## Settings
@onready var settings_panel: PanelContainer = %SettingsPanel
@onready var text_speed_slider: HSlider = %TextSpeedSlider
@onready var auto_delay_slider: HSlider = %AutoDelaySlider

## Pause + panic
@onready var pause_panel: PanelContainer = %PausePanel
@onready var resume_button: Button = %ResumeButton
@onready var panic_screen: Control = %PanicScreen

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

## Modes
var auto_mode: bool = false
var skip_mode: bool = false
var auto_delay: float = 1.5
var save_menu_mode: String = "save"
var _settings_path: String = "user://settings.json"

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
	save_menu_panel.hide()
	slot_template.hide()
	settings_panel.hide()
	pause_panel.hide()
	panic_screen.hide()
	DirAccess.make_dir_recursive_absolute(saves_dir)
	_load_settings()
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
	auto_timer.stop()

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
		if skip_mode:
			# skip_typing() fires finished_typing synchronously, so only await
			# when the label is still actually typing - otherwise the signal
			# races past the await and the line never completes.
			dialogue_label.skip_typing()
		if dialogue_label.is_typing:
			await dialogue_label.finished_typing

	# Wait for next line
	if dialogue_line.responses.size() > 0:
		balloon.focus_mode = Control.FOCUS_NONE
		skip_mode = false
		skip_button.modulate = Color.WHITE
		responses_menu.show()
	elif dialogue_line.time != "":
		var time: float = dialogue_line.text.length() * 0.02 if dialogue_line.time == "auto" else dialogue_line.time.to_float()
		await get_tree().create_timer(time).timeout
		next(dialogue_line.next_id)
	else:
		is_waiting_for_input = true
		balloon.focus_mode = Control.FOCUS_ALL
		balloon.grab_focus()
		if skip_mode and not _any_overlay_open():
			next(dialogue_line.next_id)
		elif auto_mode and not _any_overlay_open():
			auto_timer.start(auto_delay)


## Go to the next line
func next(next_id: String) -> void:
	dialogue_line = await dialogue_resource.get_next_dialogue_line(next_id, temporary_game_states)


#region Overlays


func _any_overlay_open() -> bool:
	return history_panel.visible or save_menu_panel.visible or settings_panel.visible \
		or pause_panel.visible or panic_screen.visible


func _open_overlay(p: Control) -> void:
	auto_timer.stop()
	is_waiting_for_input = false
	p.show()


func _close_overlay(p: Control) -> void:
	p.hide()
	_restore_waiting()


## Hand the balloon back its waiting state (and focus) once every overlay is gone.
func _restore_waiting() -> void:
	if _any_overlay_open():
		return
	if is_instance_valid(dialogue_line) and not dialogue_label.is_typing and dialogue_line.responses.size() == 0:
		is_waiting_for_input = true
		balloon.focus_mode = Control.FOCUS_ALL
		balloon.grab_focus()
		if skip_mode:
			next(dialogue_line.next_id)
		elif auto_mode:
			auto_timer.start(auto_delay)


#endregion


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
	_set_background(str(entry.get("bg", "")))
	var left_key: String = str(entry.get("left", ""))
	_set_sprite(("%s:left" % left_key) if left_key != "" else "none:left")
	var right_key: String = str(entry.get("right", ""))
	_set_sprite(("%s:right" % right_key) if right_key != "" else "none:right")
	var focus_key: String = str(entry.get("focus", ""))
	if focus_key != "":
		_set_focus(focus_key)


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

	_open_overlay(history_panel)
	# Focus the first entry so keyboard navigation works immediately.
	for child: Node in history_list.get_children():
		if child != history_entry_template:
			child.grab_focus()
			break


func close_history() -> void:
	_close_overlay(history_panel)


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


#region Save / load (arbitrary slots)


func _slot_path(i: int) -> String:
	return "%s/slot_%d.json" % [saves_dir, i]


## Save the current position (backlog + story state) into slot [param i].
func save_to_slot(i: int) -> Error:
	if history.is_empty():
		_toast("Nothing to save")
		return ERR_INVALID_DATA

	var current: Dictionary = history[history.size() - 1]
	var data: Dictionary = {
		"resource": dialogue_resource.resource_path,
		"history": history,
		"meta": {
			"label": ("%s: %s" % [current.character, current.text]) if current.character != "" else current.text,
			"when": Time.get_datetime_string_from_system(),
		},
	}
	var file: FileAccess = FileAccess.open(_slot_path(i), FileAccess.WRITE)
	if file == null:
		_toast("Save failed")
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data))
	file.close()
	_toast("Saved to slot %d" % i)
	return OK


## Load slot [param i]: backlog, story state, stage and current line all return.
func load_from_slot(i: int) -> void:
	var path: String = _slot_path(i)
	if not FileAccess.file_exists(path):
		_toast("Empty slot")
		return

	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data is not Dictionary or not (data.get("history") is Array) or (data.history as Array).is_empty():
		_toast("Save is broken")
		return

	var resource_path: String = data.get("resource", "")
	if ResourceLoader.exists(resource_path):
		dialogue_resource = load(resource_path)

	var loaded: Array[Dictionary] = []
	for entry: Variant in data.history:
		if entry is Dictionary:
			loaded.append(entry)
	history = loaded

	rollback_to(history.size() - 1)
	_toast("Loaded slot %d" % i)


func quick_save() -> void:
	save_to_slot(0)


func quick_load() -> void:
	load_from_slot(0)


func _scan_slots() -> Array:
	var out: Array = []
	var dir: DirAccess = DirAccess.open(saves_dir)
	if dir == null:
		return out
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if file_name.begins_with("slot_") and file_name.ends_with(".json"):
			var index: int = file_name.substr(5, file_name.length() - 10).to_int()
			var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("%s/%s" % [saves_dir, file_name]))
			var meta: Dictionary = data.get("meta", {}) if data is Dictionary else {}
			out.append({"index": index, "label": str(meta.get("label", "")), "when": str(meta.get("when", ""))})
		file_name = dir.get_next()
	out.sort_custom(func(a: Variant, b: Variant) -> bool: return a.index < b.index)
	return out


func open_save_menu(mode: String) -> void:
	save_menu_mode = mode
	save_menu_title.text = "Save" if mode == "save" else "Load"
	new_slot_button.visible = mode == "save"
	_rebuild_slot_list()
	_open_overlay(save_menu_panel)
	if mode == "save":
		new_slot_button.grab_focus()
	else:
		_focus_first_slot()


func _rebuild_slot_list() -> void:
	for child: Node in slot_list.get_children():
		if child == slot_template:
			continue
		slot_list.remove_child(child)
		child.queue_free()
	for s: Dictionary in _scan_slots():
		var b: Button = slot_template.duplicate()
		b.text = "Slot %d - %s  (%s)" % [s.index, s.label, s.when]
		b.show()
		b.pressed.connect(_on_slot_pressed.bind(s.index))
		slot_list.add_child(b)


func _focus_first_slot() -> void:
	for child: Node in slot_list.get_children():
		if child != slot_template:
			child.grab_focus()
			break


func _on_slot_pressed(i: int) -> void:
	_close_overlay(save_menu_panel)
	if save_menu_mode == "save":
		save_to_slot(i)
	else:
		load_from_slot(i)


func _on_new_slot_pressed() -> void:
	var max_i: int = 0
	for s: Dictionary in _scan_slots():
		max_i = max(max_i, s.index)
	save_to_slot(max_i + 1)
	_rebuild_slot_list()


#endregion


#region Settings


func _load_settings() -> void:
	if not FileAccess.file_exists(_settings_path):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(_settings_path))
	if data is not Dictionary:
		return
	if data.has("text_speed"):
		text_speed_slider.value = float(data.text_speed)
		_on_text_speed_changed(float(data.text_speed))
	if data.has("auto_delay"):
		auto_delay_slider.value = float(data.auto_delay)
		_on_auto_delay_changed(float(data.auto_delay))


func _save_settings() -> void:
	var file: FileAccess = FileAccess.open(_settings_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({"text_speed": text_speed_slider.value, "auto_delay": auto_delay_slider.value}))
	file.close()


func _on_text_speed_changed(v: float) -> void:
	dialogue_label.seconds_per_step = v
	_save_settings()


func _on_auto_delay_changed(v: float) -> void:
	auto_delay = v
	_save_settings()


#endregion


#region Pause / panic / modes


func open_pause() -> void:
	_open_overlay(pause_panel)
	dialogue_label.set_process(false)
	resume_button.grab_focus()


func close_pause() -> void:
	pause_panel.hide()
	dialogue_label.set_process(true)
	_restore_waiting()


func toggle_panic() -> void:
	panic_screen.visible = not panic_screen.visible
	if panic_screen.visible:
		auto_timer.stop()
		is_waiting_for_input = false
		dialogue_label.set_process(false)
	else:
		dialogue_label.set_process(true)
		_restore_waiting()


func _toggle_auto() -> void:
	auto_mode = not auto_mode
	auto_button.modulate = Color(1.0, 0.85, 0.5) if auto_mode else Color.WHITE
	_toast("Auto on" if auto_mode else "Auto off")
	if auto_mode and is_waiting_for_input and not _any_overlay_open():
		auto_timer.start(auto_delay)
	else:
		auto_timer.stop()


func _toggle_skip() -> void:
	skip_mode = not skip_mode
	skip_button.modulate = Color(1.0, 0.85, 0.5) if skip_mode else Color.WHITE
	_toast("Skip on" if skip_mode else "Skip off")
	auto_timer.stop()
	if skip_mode and is_waiting_for_input and not _any_overlay_open() \
		and is_instance_valid(dialogue_line) and dialogue_line.responses.size() == 0:
		next(dialogue_line.next_id)


func _on_auto_timeout() -> void:
	if is_waiting_for_input and is_instance_valid(dialogue_line) \
		and dialogue_line.responses.size() == 0 and not _any_overlay_open():
		next(dialogue_line.next_id)


#endregion


#region Input


func _unhandled_input(event: InputEvent) -> void:
	if not (will_block_other_input and is_instance_valid(balloon) and balloon.is_visible_in_tree()):
		return

	# The panic screen overrides absolutely; only the boss key closes it.
	if panic_screen.visible:
		get_viewport().set_input_as_handled()
		if event.is_action_pressed(panic_action):
			toggle_panic()
		return

	if event.is_action_pressed(panic_action):
		get_viewport().set_input_as_handled()
		toggle_panic()
		return

	if _try_system_actions(event):
		return

	if event.is_action_pressed(pause_action):
		get_viewport().set_input_as_handled()
		if pause_panel.visible:
			close_pause()
		else:
			open_pause()
		return

	if event.is_action_pressed(history_action):
		get_viewport().set_input_as_handled()
		if history_panel.visible:
			close_history()
		else:
			open_history()
		return

	# While any overlay is open, swallow anything its controls didn't take;
	# the skip action closes the top-most overlay without side effects.
	if _any_overlay_open():
		get_viewport().set_input_as_handled()
		if event.is_action_pressed(skip_action):
			if settings_panel.visible:
				_close_overlay(settings_panel)
			elif save_menu_panel.visible:
				_close_overlay(save_menu_panel)
			elif pause_panel.visible:
				close_pause()
			elif history_panel.visible:
				close_history()
		return

	# Advance via keyboard even when no control currently holds focus
	# (the gui_input handler already covers the focused-balloon and mouse cases).
	# Only when the balloon (or nothing) owns focus - a focused Button handles
	# its own activation on key release and must not advance the dialogue.
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	if is_waiting_for_input \
		and is_instance_valid(dialogue_line) \
		and dialogue_line.responses.size() == 0 \
		and not dialogue_label.is_typing \
		and (focus_owner == balloon or focus_owner == null) \
		and event.is_action_pressed(next_action):
		get_viewport().set_input_as_handled()
		next(dialogue_line.next_id)
		return

	# Only the balloon is allowed to handle input while it's showing
	get_viewport().set_input_as_handled()


func _on_balloon_gui_input(event: InputEvent) -> void:
	# The boss key is global: honour it before anything can swallow the event.
	if event.is_action_pressed(panic_action):
		get_viewport().set_input_as_handled()
		toggle_panic()
		return
	if panic_screen.visible:
		get_viewport().set_input_as_handled()
		return
	if _try_system_actions(event):
		return
	if _any_overlay_open():
		return

	if event.is_action_pressed(pause_action):
		get_viewport().set_input_as_handled()
		open_pause()
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


## Quick save/load work from anywhere - return true when the event was one of them.
func _try_system_actions(event: InputEvent) -> bool:
	if event.is_action_pressed(save_action):
		get_viewport().set_input_as_handled()
		quick_save()
		return true
	if event.is_action_pressed(load_action):
		get_viewport().set_input_as_handled()
		quick_load()
		return true
	return false


#endregion


#region System row + menu signals


func _refocus_balloon() -> void:
	if _any_overlay_open():
		return
	if is_instance_valid(dialogue_line) and dialogue_line.responses.size() == 0:
		balloon.focus_mode = Control.FOCUS_ALL
		balloon.grab_focus()


func _on_quick_save_pressed() -> void:
	quick_save()
	_refocus_balloon()


func _on_quick_load_pressed() -> void:
	quick_load()
	_refocus_balloon()


func _on_save_menu_pressed() -> void:
	open_save_menu("save")


func _on_load_menu_pressed() -> void:
	open_save_menu("load")


func _on_auto_pressed() -> void:
	_toggle_auto()
	_refocus_balloon()


func _on_skip_pressed() -> void:
	_toggle_skip()
	_refocus_balloon()


func _on_log_pressed() -> void:
	open_history()


func _on_settings_pressed() -> void:
	_open_overlay(settings_panel)
	text_speed_slider.grab_focus()


func _on_panic_pressed() -> void:
	toggle_panic()


func _on_resume_pressed() -> void:
	close_pause()


func _on_pause_history_pressed() -> void:
	pause_panel.hide()
	dialogue_label.set_process(true)
	open_history()


func _on_pause_save_pressed() -> void:
	pause_panel.hide()
	dialogue_label.set_process(true)
	open_save_menu("save")


func _on_pause_load_pressed() -> void:
	pause_panel.hide()
	dialogue_label.set_process(true)
	open_save_menu("load")


func _on_pause_settings_pressed() -> void:
	pause_panel.hide()
	dialogue_label.set_process(true)
	_open_overlay(settings_panel)
	text_speed_slider.grab_focus()


func _toast(message: String) -> void:
	toast_label.text = message
	toast_label.show()
	toast_timer.start()


func _on_toast_timeout() -> void:
	toast_label.hide()


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


func _on_responses_menu_response_selected(response: DialogueResponse) -> void:
	next(response.next_id)


#endregion
