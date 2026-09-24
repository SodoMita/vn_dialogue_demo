class_name VNBalloon extends CanvasLayer
const RouteTravel = preload("res://scenes/route_graph/route_graph_travel.gd")
const PanicScript = preload("res://scenes/panic_screen.gd")
## A classical visual-novel balloon for Dialogue Manager.
##
## The whole UI (background stage, sprite slots, name plate, dialogue box,
## next indicator, responses menu, history panel, save-slot menu, settings,
## pause menu and the bottom system row) is AUTHORED in `vn_balloon.tscn`.
## The panic screen is its own scene (`panic_screen.tscn`) so that page can be
## edited on its own. This script only adds behaviour: it never creates
## structural nodes - dynamic list entries
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
@export var next_action: StringName = &"dialogue_advance"

## The action that toggles fast-forward skip mode.
@export var skip_action: StringName = &"dialogue_skip"

## The action that closes the top-most overlay without changing modes.
@export var close_action: StringName = &"dialogue_close"

## The action that toggles the history (backlog) panel.
@export var history_action: StringName = &"dialogue_history"

## Quick-save / quick-load actions (slot 0).
@export var save_action: StringName = &"dialogue_save"
@export var load_action: StringName = &"dialogue_load"

## The action that toggles the pause menu (Esc / right click).
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
@onready var history_scroll: ScrollContainer = %HistoryScroll

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
@onready var prev_choice_button: Button = %PrevChoiceButton
@onready var next_choice_button: Button = %NextChoiceButton
@onready var toast_label: Label = %ToastLabel
@onready var hold_indicator: HoldIndicator = %HoldIndicator
@onready var toast_timer: Timer = %ToastTimer
@onready var auto_timer: Timer = %AutoTimer

## Save-slot menu
@onready var save_menu_panel: PanelContainer = %SaveMenuPanel
@onready var save_menu_title: Label = %SaveMenuTitle
@onready var slot_list: VBoxContainer = %SlotList
@onready var slot_template: Button = %SlotButton
@onready var new_slot_button: Button = %NewSlotButton
@onready var save_close_button: Button = %SaveCloseButton

## Settings
@onready var settings_panel: PanelContainer = %SettingsPanel
@onready var settings_scroll: ScrollContainer = %SettingsScroll
@onready var text_speed_slider: HSlider = %TextSpeedSlider
@onready var text_speed_value: Label = %TextSpeedValue
@onready var text_size_slider: HSlider = %TextSizeSlider
@onready var text_size_value: Label = %TextSizeValue
@onready var skip_speed_slider: HSlider = %SkipSpeedSlider
@onready var skip_speed_value: Label = %SkipSpeedValue
@onready var skip_mode_option: OptionButton = %SkipModeOption
@onready var advance_key_button: Button = %AdvanceKeyButton
@onready var skip_key_button: Button = %SkipKeyButton
@onready var close_key_button: Button = %CloseKeyButton
@onready var history_key_button: Button = %HistoryKeyButton
@onready var quick_save_key_button: Button = %QuickSaveKeyButton
@onready var quick_load_key_button: Button = %QuickLoadKeyButton
@onready var pause_key_button: Button = %PauseKeyButton
@onready var panic_key_button: Button = %PanicKeyButton
@onready var auto_delay_slider: HSlider = %AutoDelaySlider
@onready var auto_delay_value: Label = %AutoDelayValue
@onready var ui_scale_slider: HSlider = %UIScaleSlider
@onready var ui_scale_value: Label = %UIScaleValue
@onready var settings_margin: MarginContainer = %SettingsMargin
@onready var ui_root: Control = %UIRoot
@onready var sprite_scale_slider: HSlider = %SpriteScaleSlider
@onready var sprite_scale_value: Label = %SpriteScaleValue
@onready var sprite_y_slider: HSlider = %SpriteYSlider
@onready var sprite_y_value: Label = %SpriteYValue
@onready var sync_voice_check: CheckBox = %SyncVoiceCheck
@onready var settings_close_button: Button = %SettingsCloseButton
@onready var settings_vbox: VBoxContainer = %SettingsVBox
@onready var portrait_check: CheckBox = %PortraitCheck
@onready var language_option: OptionButton = %LanguageOption
@onready var responses_center: CenterContainer = %ResponsesCenter
@onready var fullscreen_check: CheckBox = %FullscreenCheck
@onready var vsync_check: CheckBox = %VsyncCheck
@onready var resolution_option: OptionButton = %ResolutionOption
@onready var res_width_spin: SpinBox = %ResWidthSpin
@onready var res_height_spin: SpinBox = %ResHeightSpin
@onready var glyph_scale_option: OptionButton = %GlyphScaleOption
@onready var game_filter_option: OptionButton = %GameFilterOption
@onready var map_filter_option: OptionButton = %MapFilterOption
@onready var master_vol_slider: HSlider = %MasterVolSlider
@onready var master_vol_value: Label = %MasterVolValue
@onready var music_vol_slider: HSlider = %MusicVolSlider
@onready var music_vol_value: Label = %MusicVolValue
@onready var voice_vol_slider: HSlider = %VoiceVolSlider
@onready var voice_vol_value: Label = %VoiceVolValue
@onready var sfx_vol_slider: HSlider = %SfxVolSlider
@onready var sfx_vol_value: Label = %SfxVolValue
@onready var procedural_music_check: CheckBox = %ProceduralMusicCheck
@onready var typewriter_sfx_check: CheckBox = %TypewriterSfxCheck
@onready var button_sfx_check: CheckBox = %ButtonSfxCheck

## Pause + panic
@onready var pause_panel: PanelContainer = %PausePanel
@onready var resume_button: Button = %ResumeButton
## Loaded from `panic_scene_path` when panic opens. Not authored in this scene.
var panic_screen: Control
var panic_close_button: Button
var _panic_place: Dictionary = {}
@export_file("*.tscn") var panic_scene_path: String = "res://scenes/panic_screen.tscn"

## Bottom system row (wraps on narrow aspects / big UI scales)
@onready var bottom_ui: Control = %BottomUI
@onready var system_row: GridContainer = %SystemRow
@onready var pause_button: Button = %PauseButton
@onready var route_button: Button = %RouteButton

## Route graph overlay (optional feature, single-pass renderer)
@onready var route_graph_panel: PanelContainer = %RouteGraphPanel

## Timers
@onready var skip_timer: Timer = %SkipTimer
@onready var voice_player: AudioStreamPlayer = %VoicePlayer

## Timer used to briefly hide the box while a mutation runs (authored in the scene).
@onready var mutation_cooldown: Timer = %MutationCooldown


## Temporary game states
var temporary_game_states: Array = []

## The AudioDirector autoload (music + SFX); null when a scene runs standalone.
var audio: Node = null

## See if we are waiting for the player
var is_waiting_for_input: bool = false

## See if we are running a long mutation and should hide the box
var will_hide_box: bool = false

## A dictionary to store any ephemeral variables dialogue can use via `locals.`
var locals: Dictionary = {}

## Backlog of every line shown this run; clicking an entry rolls back to it.
var history: Array[Dictionary] = []

## Ren'Py-style cursor into [member history]: the entry currently on screen.
## Entries past the cursor are the "forward" stack roll-forward can revisit;
## advancing from a rolled-back position discards them.
var history_cursor: int = -1

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
var _seeking_choice: bool = false
var auto_delay: float = 1.5
var skip_delay: float = 0.1
var skip_seen_only: bool = false
var ui_scale: float = 1.0
var sprite_scale: float = 1.0
var sprite_y: float = 0.0
var sync_voice: bool = false
## Whether music is generated at runtime (Settings "Generated music"); off
## falls back to the mood-matched OGG loops in assets/music.
var procedural_music: bool = true
## Whether the typewriter ticks per typed character (Settings "Typewriter sound").
var typewriter_sfx: bool = true
## Whether UI buttons/overlays/choices play feedback (Settings "Button sound").
var button_sfx: bool = true

## Distinct pitch per selected choice (wrap-around), so options sound different.
const CHOICE_PITCHES: Array[float] = [1.0, 1.12, 1.26, 1.33, 1.5]

## Hold-to-close on menu empty space: a long tap confirms, a quick tap is
## ignored (accidental-tap protection) and a swipe/move cancels so dragging to
## scroll still works. The ring appears after HOLD_APPEAR and closes the menu
## when released at/after HOLD_SECONDS.
const HOLD_SECONDS: float = 0.55
const HOLD_APPEAR: float = 0.12
const HOLD_CANCEL_DIST: float = 10.0

var _hold_active: bool = false
var _hold_elapsed: float = 0.0
var _hold_from: Vector2 = Vector2.ZERO
## Set while a map jump replays lines through Dialogue Manager. Mutations still
## run, but they must not hide the box or play the mutation beat.
var _silent_travel: bool = false
var _resize_queued: bool = false
var _laid_out_size := Vector2(-1, -1)

## Whether the current press turned into a drag/swipe. Row handlers (slots,
## history entries, rebind/rot buttons) check this so a scroll gesture ending
## on a button never activates it.
var _press_dragged: bool = false
var _press_from: Vector2 = Vector2.ZERO
var portrait_mode: bool = false
var force_portrait: bool = false
var rotation_deg: int = 0
var language: String = "en"
var glyph_scale: int = 2
var game_filter: int = 1
var map_filter: int = 1
const GLYPH_SCALE_LABELS: Array[String] = ["1× Low", "2× Medium", "3× High", "4× Ultra"]
const FILTER_LABELS: Array[String] = ["Nearest", "Linear", "Nearest mipmaps", "Linear mipmaps"]
## Authored offset_top/bottom per sprite, captured once so the Y-offset
## setting is applied as a delta instead of flattening the rect.
var _sprite_base_offsets: Dictionary = {}
var save_menu_mode: String = "save"
var _settings_path: String = "user://settings.json"

## Lines the player has already seen (persistent, for skip-seen-only).
var _seen_ids: Dictionary = {}
var _seen_path: String = "user://seen.json"
## Whether the line currently on screen was seen before it was shown.
var _current_was_seen: bool = false

const RES_PRESETS: Array = [
	[1280, 720], [1600, 900], [1920, 1080], [2560, 1440],
]
## UI and sprites are authored for this canvas. A larger layout would make
## those fixed pixel sizes a smaller fraction of the screen.
const DESIGN_SIZE := Vector2(1280, 720)

## Every keyboard-driven VN action is remappable. Mouse/touch bindings remain
## alongside the chosen key (for example, right click continues to pause).
const BINDABLE_ACTIONS: Array[StringName] = [
	&"dialogue_advance", &"dialogue_skip", &"dialogue_close", &"dialogue_history",
	&"dialogue_save", &"dialogue_load", &"dialogue_pause", &"dialogue_panic",
]
var _binding_buttons: Dictionary = {}
var _listening_for_action: StringName = &""

## Authored settings side/top margins; the logical margins shrink as the UI
## scale grows so the rendered settings column keeps a constant, usable width.
const SETTINGS_SIDE_MARGIN: float = 180.0
const SETTINGS_V_MARGIN: float = 40.0

## Voice clips per `#voice=` tag; per-locale Ogg Vorbis under assets/voices,
## falling back to English when the active locale lacks a clip.
func _voice_path(key: String) -> String:
	var loc: String = TranslationServer.get_locale().left(2)
	var localized := "res://assets/voices/%s/%s.ogg" % [loc, key]
	if ResourceLoader.exists(localized) or FileAccess.file_exists(localized):
		return localized
	return "res://assets/voices/en/%s.ogg" % key


## Runtime-rendered slot thumbnails, keyed by the stored stage keys.
var _thumb_cache: Dictionary = {}

## Mobile swipe tracking: an upward swipe opens the history backlog.
var _touch_from: Vector2 = Vector2.INF
## Keyboard skip is momentary: the mode lasts only while the key is held.
var _skip_key_held: bool = false
## Set when a held keyboard skip reaches a choice; consumed by its next line.
var _resume_skip_after_choice: bool = false
## Invalidates delayed auto/time continuations when skip advances a line.
var _line_token: int = 0

## Frames left during which the emulated mouse click of a finished swipe is swallowed.
var _swipe_guard_frames: int = 0

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
	if is_instance_valid(panic_screen):
		panic_screen.hide()
	hold_indicator.hide()
	if is_instance_valid(route_graph_panel):
		route_graph_panel.hide()
		if route_graph_panel.has_signal("travel_requested") and not route_graph_panel.travel_requested.is_connected(_on_route_travel_requested):
			route_graph_panel.travel_requested.connect(_on_route_travel_requested)
	DirAccess.make_dir_recursive_absolute(saves_dir)
	_ensure_audio_buses()
	audio = get_node_or_null("/root/AudioDirector")
	if audio != null:
		dialogue_label.spoke.connect(_on_label_spoke)
		_connect_ui_sfx()
	_setup_key_bindings()
	_load_seen()
	_load_settings()
	_sync_quality_controls()
	_apply_display_quality()
	if audio != null:
		audio.set_procedural_enabled(procedural_music)
	# Apply slider defaults even on a fresh install (set_value-less first run).
	_on_text_size_changed(text_size_slider.value)
	_on_skip_speed_changed(skip_speed_slider.value)
	_on_ui_scale_changed(ui_scale_slider.value)
	_on_sprite_scale_changed(sprite_scale_slider.value)
	_on_sprite_y_changed(sprite_y_slider.value)
	# NOTIFICATION_WM_SIZE_CHANGED is delivered to the Window, not to this
	# CanvasLayer, so a drag, fullscreen or resolution change never reached
	# the reflow. The viewport signal does.
	var view := get_viewport()
	if not view.size_changed.is_connected(_on_viewport_size_changed):
		view.size_changed.connect(_on_viewport_size_changed)
	if DisplayServer.get_name() != "headless":
		# Keep letterboxes a 16:9 design, so a taller or wider window never
		# changes the layout. Expand lets the logical size follow the window.
		view.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	_reflow_settings()
	_update_slider_value_labels()
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


func _process(delta: float) -> void:
	if _swipe_guard_frames > 0:
		_swipe_guard_frames -= 1
	if _hold_active:
		if not _any_overlay_open():
			_cancel_hold()
		else:
			_hold_elapsed += delta
			if _hold_elapsed >= HOLD_APPEAR:
				if not hold_indicator.visible:
					hold_indicator.show_at(_hold_from)
					if button_sfx and audio != null:
						audio.hold_start()
					# inside _process, in the _hold_active branch:
				hold_indicator.progress = clampf(_hold_elapsed / HOLD_SECONDS, 0.0, 1.0)
				if button_sfx and audio != null:
					audio.hold_progress(hold_indicator.progress)
				if _hold_elapsed >= HOLD_SECONDS:
					_finish_hold()
	if is_instance_valid(dialogue_line):
		next_indicator.visible = not dialogue_label.is_typing \
			and dialogue_line.responses.size() == 0 \
			and is_waiting_for_input


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_SIZE_CHANGED:
		_on_viewport_size_changed()
	# Detect a change of locale and repaint the current dialogue line (text,
	# name plate and choices) plus every authored UI string.
	if what == NOTIFICATION_TRANSLATION_CHANGED and _locale != TranslationServer.get_locale() and is_instance_valid(dialogue_label):
		_locale = TranslationServer.get_locale()
		await _repaint_current_line()
		_retranslate_dynamic()


## Re-fetch the current line under the new locale and repaint it in place;
## the engine only translates at instantiation, so a live switch needs this.
func _repaint_current_line() -> void:
	if not is_instance_valid(dialogue_line) or not is_instance_valid(dialogue_resource):
		return
	var dm: Node = Engine.get_singleton("DialogueManager")
	# get_line() does not inject the resource's `using` autoloads the way
	# get_next_dialogue_line() does, so {{player_name}} etc. need them here.
	var states: Array = temporary_game_states.duplicate()
	for state_name: String in dialogue_resource.using_states:
		var autoload: Node = get_tree().root.get_node_or_null(state_name)
		if is_instance_valid(autoload):
			states = [autoload] + states
	var fresh: DialogueLine = await dm.get_line(dialogue_resource, dialogue_line.id, states)
	if not is_instance_valid(fresh):
		return
	dialogue_line.text = fresh.text
	dialogue_line.character = fresh.character
	dialogue_line.responses = fresh.responses
	character_label.text = tr(dialogue_line.character, "dialogue")
	character_label.visible = not dialogue_line.character.is_empty()
	name_plate.visible = character_label.visible
	dialogue_label.dialogue_line = dialogue_line
	if not dialogue_line.text.is_empty():
		dialogue_label.type_out()
		dialogue_label.skip_typing()
	if responses_menu.visible:
		responses_menu.responses = dialogue_line.responses
		call_deferred("_layout_responses")


## Start some dialogue
func start(with_dialogue_resource: DialogueResource = null, cue: String = "", extra_game_states: Array = []) -> void:
	temporary_game_states = [self] + extra_game_states
	is_waiting_for_input = false
	if PanicScript.has_ticket():
		var place: Dictionary = PanicScript.take_ticket()
		await _resume_from_panic(place)
		return
	if is_instance_valid(with_dialogue_resource):
		dialogue_resource = with_dialogue_resource
	if not cue.is_empty():
		start_from_cue = cue
	show()
	# Ambient music under the conversation; tagged #music= lines override this.
	if audio != null and audio.music_source == "":
		audio.play_theme(&"calm")
	dialogue_line = await dialogue_resource.get_next_dialogue_line(start_from_cue, temporary_game_states)


## Apply any changes to the balloon given a new [DialogueLine].
func apply_dialogue_line() -> void:
	_line_token += 1
	var this_line_token: int = _line_token
	mutation_cooldown.stop()
	auto_timer.stop()

	next_indicator.hide()
	is_waiting_for_input = false

	# Stage direction tags first, so the scene is dressed before the text types out.
	voice_player.stop()
	_apply_stage_tags(dialogue_line)
	_apply_voice_pacing()

	# Was this line already seen before being shown now? (skip-seen-only uses it)
	_current_was_seen = _seen_ids.has(dialogue_line.id)

	# Log this line in the backlog (skipped while rolling back to it), capturing
	# the story state and the dressed stage so rollback can restore both.
	if not _restoring and (not dialogue_line.text.is_empty() or not dialogue_line.character.is_empty()):
		var entry: Dictionary = {
			"id": dialogue_line.id,
			"character": dialogue_line.character,
			"text": _strip_bbcode(dialogue_line.text),
			"bg": _current_bg,
			"left": _current_left,
			"right": _current_right,
			"focus": _current_focus,
			"choices": dialogue_line.responses.size() > 0,
		}
		var game_state: Node = get_tree().root.get_node_or_null("GameState")
		if is_instance_valid(game_state) and game_state.has_method("snapshot"):
			entry.state = game_state.snapshot()
		# Advancing while rolled back starts a new branch: drop the forward stack.
		if history_cursor < history.size() - 1:
			history = history.slice(0, history_cursor + 1)
		history.append(entry)
		history_cursor = history.size() - 1
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
		if skip_mode or _seeking_choice:
			# skip_typing() fires finished_typing synchronously, so only await
			# when the label is still actually typing - otherwise the signal
			# races past the await and the line never completes.
			dialogue_label.skip_typing()
		if dialogue_label.is_typing:
			await dialogue_label.finished_typing

	# Wait for next line
	if dialogue_line.responses.size() > 0:
		balloon.focus_mode = Control.FOCUS_NONE
		# Keep the held-key intent while the choice menu is open. The choice
		# itself remains a stop, but the selected branch must resume skipping.
		_resume_skip_after_choice = _skip_key_held or Input.is_action_pressed(skip_action) or skip_mode
		# Choices pause progression, but Skip remains enabled. Once a response
		# is selected, the branch resumes skipping automatically.
		_seeking_choice = false
		responses_menu.show()
		call_deferred("_layout_responses")
	elif dialogue_line.time != "":
		# Timed/stage slides used to ignore skip entirely because their own
		# await bypassed SkipTimer. Skip them immediately when active.
		if skip_mode or _skip_key_held:
			next(dialogue_line.next_id)
		else:
			var time: float = dialogue_line.text.length() * 0.02 if dialogue_line.time == "auto" else dialogue_line.time.to_float()
			await get_tree().create_timer(time).timeout
			if this_line_token == _line_token:
				next(dialogue_line.next_id)
	else:
		is_waiting_for_input = true
		balloon.focus_mode = Control.FOCUS_ALL
		balloon.grab_focus()
		# A held skip key must carry across a choice. Choices deliberately stop
		# the current line, but the first line after the selection is skippable.
		if (_skip_key_held or _resume_skip_after_choice or Input.is_action_pressed(skip_action)) and not _any_overlay_open():
			skip_mode = true
			_resume_skip_after_choice = false
			skip_button.modulate = Color(1.0, 0.85, 0.5)
		if skip_mode and not _any_overlay_open():
			if skip_seen_only and not _current_was_seen:
				_toggle_skip_off_at_unseen()
			else:
				skip_timer.start(skip_delay)
		elif _seeking_choice and not _any_overlay_open():
			next(dialogue_line.next_id)
		elif auto_mode and not _any_overlay_open():
			auto_timer.start(auto_delay)
	_mark_seen(dialogue_line.id)


## Go to the next line
func next(next_id: String) -> void:
	dialogue_line = await dialogue_resource.get_next_dialogue_line(next_id, temporary_game_states)


#region Overlays


func _any_overlay_open() -> bool:
	return history_panel.visible or save_menu_panel.visible or settings_panel.visible \
		or pause_panel.visible or _panic_open() or route_graph_panel.visible


func _open_overlay(p: Control) -> void:
	auto_timer.stop()
	is_waiting_for_input = false
	p.show()
	_sfx("open")


func _close_overlay(p: Control) -> void:
	p.hide()
	_sfx("close")
	if p == settings_panel:
		_listening_for_action = &""
		_refresh_binding_labels()
		settings_close_button.hide()
	_restore_waiting()


func _close_top_overlay() -> void:
	if pause_panel.visible:
		close_pause()
	elif route_graph_panel.visible:
		_close_route_graph()
	elif settings_panel.visible:
		_close_overlay(settings_panel)
	elif save_menu_panel.visible:
		_close_overlay(save_menu_panel)
	elif history_panel.visible:
		close_history()


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
		elif tag.begins_with("voice="):
			_play_voice(tag.substr(6))
		elif tag.begins_with("music=") and audio != null:
			audio.request_music(tag.substr(6))
		elif tag.begins_with("sfx=") and audio != null:
			audio.play_sfx(tag.substr(4))


## Play the voiced clip for a line on the Voice bus; lines without a clip
## (or a still-missing file) simply stay silent.
func _play_voice(key: String) -> void:
	voice_player.stop()
	var path: String = _voice_path(key)
	if not (ResourceLoader.exists(path) or FileAccess.file_exists(path)):
		return
	voice_player.stream = load(path)
	voice_player.play()


## Optional: stretch the typewriter so the line finishes typing when its voice
## clip ends. Unvoiced lines (or sync off) keep the configured text speed.
func _apply_voice_pacing() -> void:
	if sync_voice and voice_player.stream != null and voice_player.playing:
		var chars: float = max(1.0, float(dialogue_line.text.length()))
		dialogue_label.seconds_per_step = clampf(voice_player.stream.get_length() / chars, 0.005, 0.5)
	else:
		dialogue_label.seconds_per_step = text_speed_slider.value


func _on_sync_voice_toggled(on: bool) -> void:
	sync_voice = on
	if is_instance_valid(dialogue_line):
		_apply_voice_pacing()
	_save_settings()


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
	# New texture => new size; keep the pivot at the bottom centre.
	_apply_sprite_transform()


func _set_focus(slot_name: String) -> void:
	_current_focus = slot_name
	var dim: float = 0.45
	sprite_left.modulate.a = 1.0
	sprite_right.modulate.a = 1.0
	if slot_name == "left" and sprite_right.texture != null:
		sprite_right.modulate.a = dim
	elif slot_name == "right" and sprite_left.texture != null:
		sprite_left.modulate.a = dim


## Remove BBCode markup for places that show plain text (the backlog rows).
func _strip_bbcode(source: String) -> String:
	var rx := RegEx.new()
	rx.compile("\\[[a-zA-Z/][^\\]]*\\]")
	return rx.sub(source, "", true)


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
## Non-destructive: entries after [param index] stay in the backlog so the
## wheel / roll-forward can revisit them (Ren'Py-style).
func rollback_to(index: int) -> void:
	if index < 0 or index >= history.size():
		return

	var entry: Dictionary = history[index]
	history_cursor = index
	auto_timer.stop()
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


## Roll forward to the newest kept line after a rollback.
func roll_forward() -> void:
	if history_cursor < history.size() - 1:
		rollback_to(history_cursor + 1)


func _on_history_entry_pressed(index: int) -> void:
	if _press_dragged:
		return
	rollback_to(index)


#endregion


#region Save / load (arbitrary slots)


func _slot_path(i: int) -> String:
	return "%s/slot_%d.json" % [saves_dir, i]


## Save the current position (backlog + story state) into slot [param i].
func save_to_slot(i: int) -> Error:
	if history.is_empty():
		_toast(tr("Nothing to save"))
		_sfx("error")
		return ERR_INVALID_DATA

	var current: Dictionary = history[history_cursor] if history_cursor >= 0 else history[history.size() - 1]
	var data: Dictionary = {
		"resource": dialogue_resource.resource_path,
		"history": history,
		"cursor": history_cursor,
		"meta": {
			"label": _strip_bbcode(("%s: %s" % [current.character, current.text]) if current.character != "" else current.text),
			"when": Time.get_datetime_string_from_system(),
			# Stage keys only - the slot menu re-renders a thumbnail from these
			# at runtime instead of storing image data in the save.
			"bg": current.get("bg", ""),
			"left": current.get("left", ""),
			"right": current.get("right", ""),
			"focus": current.get("focus", ""),
		},
	}
	_thumb_cache.clear()
	var file: FileAccess = FileAccess.open(_slot_path(i), FileAccess.WRITE)
	if file == null:
		_toast(tr("Save failed"))
		_sfx("error")
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data))
	file.close()
	_toast(tr("Saved to slot %d") % i)
	_sfx("save")
	return OK


## Load slot [param i]: backlog, story state, stage and current line all return.
func load_from_slot(i: int) -> void:
	var path: String = _slot_path(i)
	if not FileAccess.file_exists(path):
		_toast(tr("Empty slot"))
		_sfx("error")
		return

	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data is not Dictionary or not (data.get("history") is Array) or (data.history as Array).is_empty():
		_toast(tr("Save is broken"))
		_sfx("error")
		return

	var resource_path: String = data.get("resource", "")
	if ResourceLoader.exists(resource_path):
		dialogue_resource = load(resource_path)

	var loaded: Array[Dictionary] = []
	for entry: Variant in data.history:
		if entry is Dictionary:
			loaded.append(entry)
	history = loaded

	var cursor: int = clampi(int(data.get("cursor", history.size() - 1)), 0, history.size() - 1)
	rollback_to(cursor)
	_toast(tr("Loaded slot %d") % i)
	_sfx("save")


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
			out.append({
				"index": index,
				"label": str(meta.get("label", "")),
				"when": str(meta.get("when", "")),
				"bg": str(meta.get("bg", "")),
				"left": str(meta.get("left", "")),
				"right": str(meta.get("right", "")),
				"focus": str(meta.get("focus", "")),
			})
		file_name = dir.get_next()
	out.sort_custom(func(a: Variant, b: Variant) -> bool: return a.index < b.index)
	return out


func open_save_menu(mode: String) -> void:
	save_menu_mode = mode
	save_menu_title.text = tr("Save") if mode == "save" else tr("Load")
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
		b.text = tr("Slot %d - %s  (%s)") % [s.index, s.label, s.when]
		if s.bg != "" or s.left != "" or s.right != "":
			b.icon = _slot_thumb(s)
			b.expand_icon = true
			b.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.show()
		b.pressed.connect(_on_slot_pressed.bind(s.index))
		slot_list.add_child(b)


## Compose a small preview texture for a slot row from the stage keys stored
## in the save. Nothing image-like is persisted; the thumbnail is rendered in
## memory (once per unique stage) when the menu is built.
func _slot_thumb(meta: Dictionary) -> Texture2D:
	var key: String = "%s|%s|%s|%s" % [meta.get("bg", ""), meta.get("left", ""), meta.get("right", ""), meta.get("focus", "")]
	if _thumb_cache.has(key):
		return _thumb_cache[key]

	var img := Image.create(160, 90, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.06, 0.06, 0.1, 1))
	var bg_key: String = str(meta.get("bg", ""))
	if backgrounds.has(bg_key):
		var bi: Image = (backgrounds[bg_key] as Texture2D).get_image().duplicate()
		bi.convert(Image.FORMAT_RGBA8)
		bi.resize(160, 90, Image.INTERPOLATE_BILINEAR)
		img.blit_rect(bi, Rect2i(0, 0, 160, 90), Vector2i.ZERO)
	for slot_name: String in ["left", "right"]:
		var s_key: String = str(meta.get(slot_name, ""))
		if s_key != "" and sprites.has(s_key):
			var si: Image = (sprites[s_key] as Texture2D).get_image().duplicate()
			si.convert(Image.FORMAT_RGBA8)
			var w: int = maxi(1, roundi(float(si.get_width()) * 90.0 / float(si.get_height())))
			si.resize(w, 90, Image.INTERPOLATE_BILINEAR)
			var x: int = 4 if slot_name == "left" else 160 - w - 4
			img.blit_rect(si, Rect2i(0, 0, si.get_width(), si.get_height()), Vector2i(x, 0))

	var tex := ImageTexture.create_from_image(img)
	_thumb_cache[key] = tex
	return tex


func _focus_first_slot() -> void:
	for child: Node in slot_list.get_children():
		if child != slot_template:
			child.grab_focus()
			break


func _on_slot_pressed(i: int) -> void:
	if _press_dragged:
		return
	_close_overlay(save_menu_panel)
	if save_menu_mode == "save":
		save_to_slot(i)
	else:
		load_from_slot(i)


func _on_new_slot_pressed() -> void:
	if _press_dragged:
		return
	var max_i: int = 0
	for s: Dictionary in _scan_slots():
		max_i = max(max_i, s.index)
	save_to_slot(max_i + 1)
	_rebuild_slot_list()


#endregion


#region Settings


## Wire the authored binding buttons to one generic capture path.
func _setup_key_bindings() -> void:
	_binding_buttons = {
		&"dialogue_advance": advance_key_button,
		&"dialogue_skip": skip_key_button,
		&"dialogue_close": close_key_button,
		&"dialogue_history": history_key_button,
		&"dialogue_save": quick_save_key_button,
		&"dialogue_load": quick_load_key_button,
		&"dialogue_pause": pause_key_button,
		&"dialogue_panic": panic_key_button,
	}
	for action: StringName in BINDABLE_ACTIONS:
		(_binding_buttons[action] as Button).pressed.connect(_on_rebind_button_pressed.bind(action))
	_refresh_binding_labels()


func _begin_rebind(action: StringName) -> void:
	if not _listening_for_action.is_empty():
		_refresh_binding_labels()
	_listening_for_action = action
	(_binding_buttons[action] as Button).text = tr("Press any key...")


## Use InputMap directly for the two momentary/global controls. This is more
## reliable than InputEvent.is_action_* when a key is delivered by a focused
## Control or when a binding was restored at runtime.
func _action_pressed(event: InputEvent, action: StringName) -> bool:
	return event.is_pressed() and InputMap.event_is_action(event, action)


func _action_released(event: InputEvent, action: StringName) -> bool:
	return not event.is_pressed() and InputMap.event_is_action(event, action)


## Capture before GUI/unhandled input so even Escape, Enter and the boss key can
## become a binding without also closing the panel or triggering their action.
func _input(event: InputEvent) -> void:
	# Track press -> drag so list-row handlers can tell a swipe from a tap.
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if (event as InputEventMouseButton).pressed:
			_press_from = (event as InputEventMouseButton).position
			_press_dragged = false
	elif event is InputEventMouseMotion and not _press_dragged \
			and ((event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT) != 0 \
			and ((event as InputEventMouseMotion).position - _press_from).length() > HOLD_CANCEL_DIST:
		_press_dragged = true
	elif event is InputEventScreenDrag and not _press_dragged \
			and ((event as InputEventScreenDrag).position - _press_from).length() > HOLD_CANCEL_DIST:
		_press_dragged = true
	# Hold-to-close bookkeeping runs first so scrolling drags that the GUI
	# consumes later still cancel the gesture (and the release can be swallowed).
	if _hold_active:
		if event is InputEventMouseMotion and ((event as InputEventMouseMotion).position - _hold_from).length() > HOLD_CANCEL_DIST:
			_cancel_hold()
		elif event is InputEventScreenDrag and ((event as InputEventScreenDrag).position - _hold_from).length() > HOLD_CANCEL_DIST:
			_cancel_hold()
		elif event is InputEventMouseButton:
			var mb_hold: InputEventMouseButton = event
			if not mb_hold.pressed and mb_hold.button_index == MOUSE_BUTTON_LEFT:
				if _hold_elapsed >= HOLD_SECONDS:
					get_viewport().set_input_as_handled()
					_finish_hold()
				else:
					_cancel_hold()
	if not _listening_for_action.is_empty() and settings_panel.visible:
		if event is InputEventKey and event.pressed and not event.echo:
			var action := _listening_for_action
			_listening_for_action = &""
			_replace_action_key(action, event as InputEventKey)
			_refresh_binding_labels()
			_save_settings()
			(_binding_buttons[action] as Button).grab_focus()
			get_viewport().set_input_as_handled()
		return
	if not is_instance_valid(balloon) or not balloon.is_visible_in_tree() or _panic_open():
		return
	# Pause and Close must win before focused GUI controls consume Esc or
	# Backspace (notably OptionButton and SpinBox/LineEdit).
	if event.is_action_pressed(pause_action):
		if pause_panel.visible:
			close_pause()
		elif is_instance_valid(route_graph_panel) and route_graph_panel.visible:
			_close_route_graph()
		else:
			open_pause()
		get_viewport().set_input_as_handled()
		return
	if _any_overlay_open() and _action_pressed(event, close_action):
		_close_top_overlay()
		get_viewport().set_input_as_handled()
		return
	# Keyboard skip is a hold gesture, not a latch. The toolbar button remains
	# a conventional toggle for mouse/touch users.
	if _action_pressed(event, skip_action) and not (event is InputEventKey and (event as InputEventKey).echo):
		_skip_key_held = true
		if not _any_overlay_open():
			_set_skip_active(true)
		get_viewport().set_input_as_handled()
	elif _action_released(event, skip_action):
		_skip_key_held = false
		_set_skip_active(false)
		get_viewport().set_input_as_handled()


## Replace only keyboard events; mouse/touch affordances stay active.
func _replace_action_key(action: StringName, source: InputEventKey) -> void:
	var non_key_events: Array[InputEvent] = []
	for old_event: InputEvent in InputMap.action_get_events(action):
		if not old_event is InputEventKey:
			non_key_events.append(old_event)
	InputMap.action_erase_events(action)
	var key := source.duplicate() as InputEventKey
	key.pressed = false
	key.echo = false
	key.unicode = 0
	InputMap.action_add_event(action, key)
	for old_event: InputEvent in non_key_events:
		InputMap.action_add_event(action, old_event)


func _binding_label(action: StringName) -> String:
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey:
			var key_event := event as InputEventKey
			var code: Key = key_event.keycode if key_event.keycode != 0 else key_event.physical_keycode
			return OS.get_keycode_string(code)
	return tr("Unbound")


func _refresh_binding_labels() -> void:
	for action: StringName in BINDABLE_ACTIONS:
		(_binding_buttons[action] as Button).text = _binding_label(action)


func _serialize_key_bindings() -> Dictionary:
	var result: Dictionary = {}
	for action: StringName in BINDABLE_ACTIONS:
		for event: InputEvent in InputMap.action_get_events(action):
			if event is InputEventKey:
				var key := event as InputEventKey
				result[String(action)] = {
					"keycode": int(key.keycode),
					"physical_keycode": int(key.physical_keycode),
					"alt": key.alt_pressed, "shift": key.shift_pressed,
					"ctrl": key.ctrl_pressed, "meta": key.meta_pressed,
				}
				break
	return result


func _load_key_bindings(saved: Variant) -> void:
	if saved is Dictionary:
		for action: StringName in BINDABLE_ACTIONS:
			var item: Variant = saved.get(String(action))
			if item is Dictionary and (int(item.get("keycode", 0)) != 0 or int(item.get("physical_keycode", 0)) != 0):
				var key := InputEventKey.new()
				key.keycode = int(item.get("keycode", 0)) as Key
				key.physical_keycode = int(item.get("physical_keycode", 0)) as Key
				key.alt_pressed = bool(item.get("alt", false))
				key.shift_pressed = bool(item.get("shift", false))
				key.ctrl_pressed = bool(item.get("ctrl", false))
				key.meta_pressed = bool(item.get("meta", false))
				_replace_action_key(action, key)
	_refresh_binding_labels()


func _load_settings() -> void:
	var data: Dictionary = {}
	if FileAccess.file_exists(_settings_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_settings_path))
		if parsed is Dictionary:
			data = parsed
	# Language applies even on first run: the saved choice wins, otherwise the
	# OS locale when we ship it.
	if data.has("language"):
		language = "ru" if String(data.language) == "ru" else "en"
	else:
		language = "ru" if TranslationServer.get_locale().left(2) == "ru" else "en"
	language_option.selected = 1 if language == "ru" else 0
	TranslationServer.set_locale(language)
	_load_key_bindings(data.get("key_bindings", {}))
	if data.is_empty():
		return
	if data.has("text_speed"):
		text_speed_slider.value = float(data.text_speed)
		_on_text_speed_changed(float(data.text_speed))
	if data.has("text_size"):
		text_size_slider.value = float(data.text_size)
		_on_text_size_changed(float(data.text_size))
	if data.has("skip_speed"):
		skip_speed_slider.value = float(data.skip_speed)
		_on_skip_speed_changed(float(data.skip_speed))
	if data.has("skip_seen_only"):
		skip_seen_only = bool(data.skip_seen_only)
		skip_mode_option.selected = 1 if skip_seen_only else 0
	if data.has("auto_delay"):
		auto_delay_slider.value = float(data.auto_delay)
		_on_auto_delay_changed(float(data.auto_delay))
	if data.has("ui_scale"):
		ui_scale_slider.value = float(data.ui_scale)
		_on_ui_scale_changed(float(data.ui_scale))
	if data.has("sprite_scale"):
		sprite_scale_slider.value = float(data.sprite_scale)
		_on_sprite_scale_changed(float(data.sprite_scale))
	if data.has("sprite_y"):
		sprite_y_slider.value = float(data.sprite_y)
		_on_sprite_y_changed(float(data.sprite_y))
	if data.has("sync_voice"):
		sync_voice = bool(data.sync_voice)
		sync_voice_check.button_pressed = sync_voice
	if data.has("force_portrait"):
		force_portrait = bool(data.force_portrait)
		portrait_check.button_pressed = force_portrait
		_reflow_settings()
	if data.has("rotation"):
		_set_rotation(int(data.rotation))
	if data.has("language"):
		language = "ru" if String(data.language) == "ru" else "en"
	language_option.selected = 1 if language == "ru" else 0
	TranslationServer.set_locale(language)
	if data.has("fullscreen"):
		# Programmatic set_pressed() emits no signal, so apply it by hand.
		fullscreen_check.button_pressed = bool(data.fullscreen)
		_apply_fullscreen(bool(data.fullscreen))
	if data.has("vsync"):
		vsync_check.button_pressed = bool(data.vsync)
		_apply_vsync(bool(data.vsync))
	if data.has("res_w") and data.has("res_h"):
		res_width_spin.value = float(data.res_w)
		res_height_spin.value = float(data.res_h)
		_sync_resolution_option()
		_apply_resolution(int(data.res_w), int(data.res_h))
	if data.has("glyph_scale"):
		glyph_scale = clampi(int(data.glyph_scale), 1, 4)
	if data.has("game_filter"):
		game_filter = clampi(int(data.game_filter), 0, FILTER_LABELS.size() - 1)
	if data.has("map_filter"):
		map_filter = clampi(int(data.map_filter), 0, FILTER_LABELS.size() - 1)
	_sync_quality_controls()
	for key: String in ["vol_master", "vol_music", "vol_voice", "vol_sfx"]:
		if data.has(key):
			var slider: HSlider = {"vol_master": master_vol_slider, "vol_music": music_vol_slider,
				"vol_voice": voice_vol_slider, "vol_sfx": sfx_vol_slider}[key]
			slider.value = float(data[key])
	_set_bus_volume("Master", master_vol_slider.value)
	_set_bus_volume("Music", music_vol_slider.value)
	_set_bus_volume("Voice", voice_vol_slider.value)
	_set_bus_volume("SFX", sfx_vol_slider.value)
	if data.has("procedural_music"):
		procedural_music = bool(data.procedural_music)
		procedural_music_check.button_pressed = procedural_music
	if data.has("sfx_typewriter"):
		typewriter_sfx = bool(data.sfx_typewriter)
		typewriter_sfx_check.button_pressed = typewriter_sfx
	if data.has("sfx_buttons"):
		button_sfx = bool(data.sfx_buttons)
		button_sfx_check.button_pressed = button_sfx


func _save_settings() -> void:
	var file: FileAccess = FileAccess.open(_settings_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"key_bindings": _serialize_key_bindings(),
		"text_speed": text_speed_slider.value,
		"text_size": text_size_slider.value,
		"skip_speed": skip_speed_slider.value,
		"skip_seen_only": skip_seen_only,
		"auto_delay": auto_delay_slider.value,
		"ui_scale": ui_scale_slider.value,
		"sprite_scale": sprite_scale_slider.value,
		"sprite_y": sprite_y_slider.value,
		"sync_voice": sync_voice_check.button_pressed,
		"force_portrait": portrait_check.button_pressed,
		"rotation": rotation_deg,
		"language": language,
		"fullscreen": fullscreen_check.button_pressed,
		"vsync": vsync_check.button_pressed,
		"res_w": int(res_width_spin.value),
		"res_h": int(res_height_spin.value),
		"glyph_scale": glyph_scale,
		"game_filter": game_filter,
		"map_filter": map_filter,
		"vol_master": master_vol_slider.value,
		"vol_music": music_vol_slider.value,
		"vol_voice": voice_vol_slider.value,
		"vol_sfx": sfx_vol_slider.value,
		"procedural_music": procedural_music_check.button_pressed,
		"sfx_typewriter": typewriter_sfx_check.button_pressed,
		"sfx_buttons": button_sfx_check.button_pressed,
	}))
	file.close()


func _on_text_speed_changed(v: float) -> void:
	dialogue_label.seconds_per_step = v
	_update_slider_value_labels()
	_save_settings()


func _on_auto_delay_changed(v: float) -> void:
	auto_delay = v
	_update_slider_value_labels()
	_save_settings()


func _on_fullscreen_toggled(on: bool) -> void:
	_apply_fullscreen(on)
	_save_settings()


func _apply_fullscreen(on: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return  # no window to switch; the preference is still persisted
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED
	)


func _on_text_size_changed(v: float) -> void:
	dialogue_label.add_theme_font_size_override("normal_font_size", int(v))
	character_label.add_theme_font_size_override("normal_font_size", int(v))
	_save_settings()


func _on_skip_speed_changed(v: float) -> void:
	# The control reads as speed: moving right is faster. Internally the timer
	# needs the inverse quantity, seconds between lines.
	skip_delay = skip_speed_slider.min_value + skip_speed_slider.max_value - v
	skip_timer.wait_time = skip_delay
	_update_slider_value_labels()
	_save_settings()


func _on_skip_mode_selected(index: int) -> void:
	skip_seen_only = index == 1
	_save_settings()


func _on_ui_scale_changed(v: float) -> void:
	_apply_ui_scale(v)
	_update_slider_value_labels()
	_save_settings()


## How much to enlarge authored UI and sprites so a larger layout does not
## make them a smaller fraction of the screen. Below the design size, leave
## them alone — a narrow window should reflow, not shrink the chrome.
func _resolution_keep_scale() -> float:
	var logical := get_viewport().get_visible_rect().size
	if logical.x < 1.0 or logical.y < 1.0:
		return 1.0
	var fit := minf(logical.x / DESIGN_SIZE.x, logical.y / DESIGN_SIZE.y)
	return fit if fit > 1.0 else 1.0


func _shown_scale(user_scale: float) -> float:
	return user_scale * _resolution_keep_scale()


## UI scale touches only the UI subtree (UIRoot): the stage, background and
## sprites live outside it and keep their authored size at any UI-scale setting.
## A higher resolution enlarges this same subtree so the UI does not shrink.
func _apply_ui_scale(s: float) -> void:
	ui_scale = s
	var shown := _shown_scale(s)
	ui_root.scale = Vector2(shown, shown)
	# Fractional anchors keep UIRoot at window/shown logical pixels (the anchors
	# track window resizes on their own); the render scale then maps it back
	# to exactly the window size, edge-anchored UI included.
	ui_root.anchor_right = 1.0 / shown
	ui_root.anchor_bottom = 1.0 / shown
	# Shrink the logical margins so the rendered settings column stays a
	# constant, usable width no matter how big the UI gets; in portrait the
	# panel goes (nearly) fullscreen-wide instead.
	var side: float = 16.0 if portrait_mode else SETTINGS_SIDE_MARGIN
	var m: int = roundi(side / shown)
	var mv: int = roundi(SETTINGS_V_MARGIN / shown)
	settings_margin.add_theme_constant_override("margin_left", m)
	settings_margin.add_theme_constant_override("margin_right", m)
	settings_margin.add_theme_constant_override("margin_top", mv)
	settings_margin.add_theme_constant_override("margin_bottom", mv)


## Portrait/narrow layout: rows flip vertical (slider wraps below its label,
## fullscreen-wide) and the panel margins collapse. Landscape restores the
## authored side-by-side rows.
func _reflow_settings() -> void:
	_apply_rotation()
	# The logical space is what the UI lays out in, so its shape (not the
	# window's) decides portrait vs landscape rows.
	portrait_mode = force_portrait or (balloon.size.y > balloon.size.x)
	_apply_settings_layout()


## Test/override entry point for the portrait layout.
func set_portrait_mode(on: bool) -> void:
	force_portrait = on
	portrait_mode = on or balloon.size.y > balloon.size.x
	_apply_settings_layout()


func _apply_settings_layout() -> void:
	for child: Node in settings_vbox.get_children():
		if child is BoxContainer:
			(child as BoxContainer).vertical = portrait_mode
			var first: Node = child.get_child(0)
			if first is Label:
				(first as Label).custom_minimum_size.x = 0.0 if portrait_mode else 170.0
	_apply_ui_scale(ui_scale)
	_layout_system_row()


## The bottom button row wraps into as many rows as the logical width needs
## (narrow aspects, big UI scales): the GridContainer's column count drops
## until every button fits, and the dialogue box grows upward to make room.
func _layout_system_row() -> void:
	var btns := system_row.get_children()
	var count := btns.size()
	if count == 0:
		return
	var sep := 6.0
	var avail: float = balloon.size.x / ui_scale - 28.0
	var mins := PackedFloat64Array()
	for b: Node in btns:
		mins.push_back((b as Control).custom_minimum_size.x)
	var cols: int = 1
	for c: int in range(count, 0, -1):
		var colw := PackedFloat64Array()
		colw.resize(c)
		for i: int in count:
			var col: int = i % c
			colw[col] = maxf(colw[col], mins[i])
		var total := sep * float(c - 1)
		for w: float in colw:
			total += w
		if total <= avail:
			cols = c
			break
	system_row.columns = cols
	var rows := ceili(float(count) / float(cols))
	var h := float(rows) * 44.0 + float(rows - 1) * sep
	system_row.offset_top = system_row.offset_bottom - h
	bottom_ui.offset_top = -216.0 - (h - 44.0)


func _update_slider_value_labels() -> void:
	if not is_instance_valid(text_speed_value):
		return
	text_speed_value.text = "%.3f s" % text_speed_slider.value
	text_size_value.text = "%d px" % roundi(text_size_slider.value)
	skip_speed_value.text = "%.2f s" % skip_delay
	auto_delay_value.text = "%.2f s" % auto_delay_slider.value
	ui_scale_value.text = "%.2fx" % ui_scale_slider.value
	sprite_scale_value.text = "%.2fx" % sprite_scale_slider.value
	sprite_y_value.text = "%d px" % roundi(sprite_y_slider.value)
	master_vol_value.text = "%d%%" % roundi(master_vol_slider.value)
	music_vol_value.text = "%d%%" % roundi(music_vol_slider.value)
	voice_vol_value.text = "%d%%" % roundi(voice_vol_slider.value)
	sfx_vol_value.text = "%d%%" % roundi(sfx_vol_slider.value)


func _on_settings_close_pressed() -> void:
	_close_overlay(settings_panel)


func _on_portrait_toggled(on: bool) -> void:
	force_portrait = on
	_reflow_settings()
	_save_settings()


## Language switch: the engine translates authored strings and the dialogue,
## and the voice picker follows the locale on the next line.
func _on_language_changed(idx: int) -> void:
	language = "ru" if idx == 1 else "en"
	TranslationServer.set_locale(language)
	_save_settings()


## Authored control texts: Godot translates them once at instantiation but
## does not repaint them on a live locale switch, so they are re-applied
## from the catalog here (node name -> English catalog key).
const UI_TEXT_KEYS: Array = [
	["SaveButton", "Save"], ["LoadButton", "Load"], ["AutoButton", "Auto"],
	["SkipButton", "Skip"], ["PrevChoiceButton", "< Choice"], ["NextChoiceButton", "Choice >"],
	["LogButton", "Log"], ["SettingsButton", "Set"], ["PanicButton", "Panic"], ["PauseButton", "Pause"], ["RouteButton", "Map"],
	["NewSlotButton", "+ New slot"], ["SettingsTitle", "Settings"],
	["LanguageRowLabel", "Language"], ["TextSpeedRowLabel", "Text speed"],
	["TextSizeRowLabel", "Text size"], ["SyncVoiceRowLabel", "Sync text to voice"],
	["SyncVoiceCheck", "on"], ["SkipSpeedRowLabel", "Skip speed"],
	["SkipModeRowLabel", "Skip texts"], ["ControlsHeader", "Controls"],
	["AdvanceKeyRowLabel", "Advance"], ["SkipKeyRowLabel", "Skip mode"],
	["CloseKeyRowLabel", "Close"], ["HistoryKeyRowLabel", "History"], ["QuickSaveKeyRowLabel", "Quick save"],
	["QuickLoadKeyRowLabel", "Quick load"], ["PauseKeyRowLabel", "Pause"],
	["PanicKeyRowLabel", "Panic"], ["AutoDelayRowLabel", "Auto delay"], ["UIScaleRowLabel", "UI scale"], ["DisplayHeader", "Display"],
	["PortraitRowLabel", "Portrait layout"], ["PortraitCheck", "on"], ["RotationRowLabel", "Rotation"],
	["FullscreenRowLabel", "Fullscreen"], ["FullscreenCheck", "on"], ["VsyncRowLabel", "V-Sync"],
	["VsyncCheck", "on"], ["ResolutionRowLabel", "Resolution"], ["ResCustomLabel", "Custom size"],
	["GlyphScaleRowLabel", "Glyph scale"],
	["GameFilterRowLabel", "Game filter"], ["MapFilterRowLabel", "Map filter"],
	["AudioHeader", "Audio"], ["MasterVolRowLabel", "Master volume"],
	["MusicVolRowLabel", "Music volume"], ["VoiceVolRowLabel", "Voice volume"],
	["SfxVolRowLabel", "SFX volume"], ["ProceduralMusicRowLabel", "Generated music"],
	["ProceduralMusicCheck", "on"], ["TypewriterSfxRowLabel", "Typewriter sound"],
	["TypewriterSfxCheck", "on"], ["ButtonSfxRowLabel", "Button sound"],
	["ButtonSfxCheck", "on"], ["SpritesHeader", "Sprites"],
	["SpriteScaleRowLabel", "Sprite scale"], ["SpriteYRowLabel", "Sprite Y offset"],
	["SettingsHint", "Settings are saved automatically. Use Close or X to exit."],
	["PauseTitle", "Paused"], ["ResumeButton", "Resume"], ["PauseHistoryButton", "History"],
	["PauseSaveButton", "Save"], ["PauseLoadButton", "Load"], ["PauseSettingsButton", "Settings"],
	["QuitButton", "Quit"], ["PanicTitle", "PHYS 201 - Quantum Mechanics II"],
	["PanicBody", "Lecture 12: The time-independent Schroedinger equation. H psi = E psi, where H is the Hamiltonian operator. For a particle in a 1-D infinite well of width L the energy eigenvalues are E_n = n^2 h^2 / (8 m L^2). Reminder: problem set 4 is due Friday - problems 3.7, 3.9 and the derivation of the uncertainty principle for position and momentum."],
	["HistoryTitle", "History"],
	["HistoryHint", "Click a line to roll back to it - H or Esc closes"],
]


## Strings the engine can't auto-translate (option items, runtime titles)
## are re-set from the .po whenever the locale changes.
func _retranslate_dynamic() -> void:
	for entry: Array in UI_TEXT_KEYS:
		var n: Node = find_child(String(entry[0]), true, false)
		if n != null and "text" in n:
			(n as Object).set("text", tr(String(entry[1])))
	if is_instance_valid(skip_mode_option):
		skip_mode_option.set_item_text(0, tr("Everything"))
		skip_mode_option.set_item_text(1, tr("Seen only"))
	if is_instance_valid(resolution_option):
		resolution_option.set_item_text(RES_PRESETS.size(), tr("Custom"))
	if is_instance_valid(glyph_scale_option):
		for i in GLYPH_SCALE_LABELS.size():
			glyph_scale_option.set_item_text(i, tr(GLYPH_SCALE_LABELS[i]))
	for option in [game_filter_option, map_filter_option]:
		if is_instance_valid(option):
			for i in FILTER_LABELS.size():
				option.set_item_text(i, tr(FILTER_LABELS[i]))
	if is_instance_valid(save_menu_title) and save_menu_panel.visible:
		save_menu_title.text = tr("Save") if save_menu_mode == "save" else tr("Load")
	if is_instance_valid(route_graph_panel) and route_graph_panel.has_method("refresh_locale"):
		route_graph_panel.refresh_locale()
	if is_instance_valid(advance_key_button):
		_refresh_binding_labels()
		if not _listening_for_action.is_empty():
			(_binding_buttons[_listening_for_action] as Button).text = tr("Press any key...")


## Four settings buttons rotate the whole game view (the engine itself never
## rotates the window): 0/90/180/270 degrees. Rotation flips the logical
## resolution's X/Y, so the turned view fills the window with no letterbox
## gaps, and flips the effective orientation for a real portrait preview.
func _on_rebind_button_pressed(action: StringName) -> void:
	if _press_dragged:
		return
	_begin_rebind(action)


func _on_rot_0_pressed() -> void:
	if _press_dragged:
		return
	_set_rotation(0)


func _on_rot_90_pressed() -> void:
	if _press_dragged:
		return
	_set_rotation(90)


func _on_rot_180_pressed() -> void:
	if _press_dragged:
		return
	_set_rotation(180)


func _on_rot_270_pressed() -> void:
	if _press_dragged:
		return
	_set_rotation(270)


func _set_rotation(d: int) -> void:
	rotation_deg = d
	_apply_rotation()
	_reflow_settings()
	_save_settings()


## Window, fullscreen and resolution changes. Deferred so Control layout has
## the new visible rect before choices and sprite pivots are measured.
func _on_viewport_size_changed() -> void:
	if _resize_queued:
		return
	_resize_queued = true
	call_deferred("_apply_viewport_resize")


func _apply_viewport_resize() -> void:
	_resize_queued = false
	var vis := get_viewport().get_visible_rect().size
	if vis == _laid_out_size:
		return
	_laid_out_size = vis
	_reflow_settings()
	_layout_responses()
	_apply_sprite_transform()


func _apply_rotation() -> void:
	var win: Vector2 = get_viewport().get_visible_rect().size
	var r: float = deg_to_rad(float(rotation_deg))
	var swapped: bool = rotation_deg == 90 or rotation_deg == 270
	# Rotation also flips the logical resolution's X and Y: the stage and UI
	# lay out in the flipped space and the layer transform turns it on screen,
	# so the rotated view fills the window exactly -- no letterbox gaps.
	var logical: Vector2 = Vector2(win.y, win.x) if swapped else win
	balloon.anchor_right = 0.0
	balloon.anchor_bottom = 0.0
	balloon.size = logical
	var t := Transform2D().rotated(r)
	t.origin = (win * 0.5) - (t * (logical * 0.5))
	transform = t


## Size the choices band to the menu and park it just above the dialogue box,
## clamped so it can never escape past the top of the screen.
func _layout_responses() -> void:
	if not is_instance_valid(responses_menu) or not responses_menu.visible:
		return
	var parent_top: float = responses_center.get_parent().get_global_rect().position.y
	var box_top: float = dialogue_box.get_global_rect().position.y
	var h: float = responses_menu.get_combined_minimum_size().y
	var gap: float = 8.0
	var top: float = maxf(8.0, box_top - gap - h)
	responses_center.offset_top = top - parent_top
	responses_center.offset_bottom = (box_top - gap) - parent_top


func _on_sprite_scale_changed(v: float) -> void:
	sprite_scale = v
	_apply_sprite_transform()
	_update_slider_value_labels()
	_save_settings()


func _on_sprite_y_changed(v: float) -> void:
	sprite_y = v
	_apply_sprite_transform()
	_update_slider_value_labels()
	_save_settings()


## Sprite scale pivots at each sprite's bottom centre; the Y offset is a delta
## on top of the authored offsets so the anchored rect keeps its height.
func _apply_sprite_transform() -> void:
	for spr: TextureRect in [sprite_left, sprite_right]:
		if not _sprite_base_offsets.has(spr.get_instance_id()):
			_sprite_base_offsets[spr.get_instance_id()] = Vector2(spr.offset_top, spr.offset_bottom)
		var base: Vector2 = _sprite_base_offsets[spr.get_instance_id()]
		spr.offset_top = base.x + sprite_y
		spr.offset_bottom = base.y + sprite_y
		spr.pivot_offset = Vector2(spr.size.x * 0.5, spr.size.y)
		var shown := _shown_scale(sprite_scale)
		spr.scale = Vector2(shown, shown)


func _on_vsync_toggled(on: bool) -> void:
	_apply_vsync(on)
	_save_settings()


func _apply_vsync(on: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if on else DisplayServer.VSYNC_DISABLED
	)


func _sync_resolution_option() -> void:
	var w: int = int(res_width_spin.value)
	var h: int = int(res_height_spin.value)
	for i: int in RES_PRESETS.size():
		if RES_PRESETS[i][0] == w and RES_PRESETS[i][1] == h:
			resolution_option.selected = i
			return
	resolution_option.selected = RES_PRESETS.size()  # "Custom"


func _on_resolution_selected(index: int) -> void:
	if index < RES_PRESETS.size():
		# set_value() emits no signal, so this won't recurse into the spin handlers
		res_width_spin.value = RES_PRESETS[index][0]
		res_height_spin.value = RES_PRESETS[index][1]
		_apply_resolution(RES_PRESETS[index][0], RES_PRESETS[index][1])
	_save_settings()


func _on_res_width_changed(_v: float) -> void:
	_sync_resolution_option()
	_apply_resolution(int(res_width_spin.value), int(res_height_spin.value))
	_save_settings()


func _on_res_height_changed(_v: float) -> void:
	_sync_resolution_option()
	_apply_resolution(int(res_width_spin.value), int(res_height_spin.value))
	_save_settings()


func _sync_quality_controls() -> void:
	if is_instance_valid(glyph_scale_option):
		glyph_scale_option.set_block_signals(true)
		glyph_scale_option.selected = clampi(glyph_scale - 1, 0, GLYPH_SCALE_LABELS.size() - 1)
		glyph_scale_option.set_block_signals(false)
	if is_instance_valid(game_filter_option):
		game_filter_option.set_block_signals(true)
		game_filter_option.selected = game_filter
		game_filter_option.set_block_signals(false)
	if is_instance_valid(map_filter_option):
		map_filter_option.set_block_signals(true)
		map_filter_option.selected = map_filter
		map_filter_option.set_block_signals(false)


func _apply_display_quality() -> void:
	_apply_game_filter()
	if is_instance_valid(route_graph_panel):
		if route_graph_panel.has_method("set_glyph_scale"):
			route_graph_panel.set_glyph_scale(glyph_scale, false)
		if route_graph_panel.has_method("set_map_filter"):
			route_graph_panel.set_map_filter(map_filter, false)


func _apply_game_filter() -> void:
	var mode := _canvas_filter(game_filter)
	for node in [background, sprite_left, sprite_right]:
		if is_instance_valid(node):
			node.texture_filter = mode


func _canvas_filter(index: int) -> CanvasItem.TextureFilter:
	match clampi(index, 0, 3):
		0:
			return CanvasItem.TEXTURE_FILTER_NEAREST
		2:
			return CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		3:
			return CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_:
			return CanvasItem.TEXTURE_FILTER_LINEAR


func _on_glyph_scale_selected(idx: int) -> void:
	glyph_scale = clampi(idx, 0, 3) + 1
	_save_settings()
	if is_instance_valid(route_graph_panel) and route_graph_panel.has_method("set_glyph_scale"):
		route_graph_panel.set_glyph_scale(glyph_scale)


func _on_game_filter_selected(idx: int) -> void:
	game_filter = clampi(idx, 0, FILTER_LABELS.size() - 1)
	_apply_game_filter()
	_save_settings()


func _on_map_filter_selected(idx: int) -> void:
	map_filter = clampi(idx, 0, FILTER_LABELS.size() - 1)
	_save_settings()
	if is_instance_valid(route_graph_panel) and route_graph_panel.has_method("set_map_filter"):
		route_graph_panel.set_map_filter(map_filter)


func _apply_resolution(w: int, h: int) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if w < 1 or h < 1:
		return
	var view := get_viewport()
	view.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	# The chosen resolution is the layout size, not a scaled copy of 1280x720.
	# UI and sprites then scale by that same ratio so they do not shrink.
	view.content_scale_size = Vector2i(w, h)
	DisplayServer.window_set_size(Vector2i(w, h))
	_on_viewport_size_changed()


func _ensure_audio_buses() -> void:
	for bus_name: String in ["Music", "Voice", "SFX"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, &"Master")


func _set_bus_volume(bus_name: String, volume: float) -> void:
	var index: int = AudioServer.get_bus_index(bus_name)
	if index == -1:
		return
	var linear: float = clampf(volume, 0.0, 100.0) / 100.0
	AudioServer.set_bus_volume_db(index, linear_to_db(linear) if linear > 0.0 else -80.0)


func _on_master_vol_changed(v: float) -> void:
	_set_bus_volume("Master", v)
	_update_slider_value_labels()
	_save_settings()


func _on_music_vol_changed(v: float) -> void:
	_set_bus_volume("Music", v)
	_update_slider_value_labels()
	_save_settings()


func _on_voice_vol_changed(v: float) -> void:
	_set_bus_volume("Voice", v)
	_update_slider_value_labels()
	_save_settings()


func _on_sfx_vol_changed(v: float) -> void:
	_set_bus_volume("SFX", v)
	_update_slider_value_labels()
	_save_settings()


func _on_procedural_music_toggled(on: bool) -> void:
	procedural_music = on
	if audio != null:
		audio.set_procedural_enabled(on)
	_save_settings()


#endregion


#region Audio director (music + SFX)


## Play UI feedback through the AudioDirector (gated by "Button sound";
## story `#sfx=` tags call the director directly and ignore the toggle).
func _sfx(key: String, pitch: float = 1.0) -> void:
	if button_sfx and audio != null:
		audio.play_sfx(key, pitch)


## Typewriter blips: one request per typed character; the director throttles
## density and pitch, and skip mode types too fast to sound good.
func _on_label_spoke(letter: String, _letter_index: int, _speed: float) -> void:
	if not typewriter_sfx:
		return
	if skip_mode or _seeking_choice:
		return
	if audio != null:
		audio.typing_tick(letter)


## Every static chrome button gets a UI tick alongside its own handler.
func _connect_ui_sfx() -> void:
	for btn: Button in [qs_button, ql_button, save_button, load_button, auto_button,
			skip_button, log_button, settings_button, panic_button, pause_button,
			prev_choice_button, next_choice_button, settings_close_button,
			resume_button, new_slot_button, save_close_button]:
		if btn == null:
			continue
		btn.pressed.connect(_on_ui_button_sfx)
	responses_menu.response_selected.connect(_on_response_selected_sfx)


func _on_ui_button_sfx() -> void:
	if _press_dragged:
		return
	_sfx("click")


func _on_response_selected_sfx(response: DialogueResponse) -> void:
	# Each option plays its own pitch; a #sfx= tag on the response picks the clip.
	var key: String = "confirm"
	var pitch: float = CHOICE_PITCHES[0]
	if is_instance_valid(dialogue_line):
		pitch = CHOICE_PITCHES[maxi(0, dialogue_line.responses.find(response)) % CHOICE_PITCHES.size()]
	for tag: String in response.tags:
		if tag.begins_with("sfx="):
			key = tag.substr(4)
			pitch = 1.0
	_sfx(key, pitch)


## Press-and-hold on empty menu space runs the hold-to-close gesture
## (containers and labels pass the press up to the full-rect panel). The panic
## screen deliberately has no hold-to-close: it must swallow everything.
func _on_menu_empty_press(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and not _press_on_interactive(mb.position):
			_begin_hold(mb.position)


## True when the press landed on an interactive control (buttons pass drags up
## to their ScrollContainer, so their presses also reach the panel).
func _press_on_interactive(pos: Vector2) -> bool:
	for menu: Control in [save_menu_panel, settings_panel, pause_panel, history_panel]:
		if menu.visible and _hits_interactive(menu, pos):
			return true
	return false


func _hits_interactive(c: Control, pos: Vector2) -> bool:
	for child: Node in c.get_children():
		if not child is Control or not (child as Control).visible:
			continue
		var ch: Control = child
		if ch.mouse_filter != Control.MOUSE_FILTER_IGNORE \
				and (ch is BaseButton or ch is Range or ch is LineEdit or ch is TextEdit \
				or ch is ItemList or ch is Tree) \
				and ch.get_global_rect().has_point(pos):
			return true
		if _hits_interactive(ch, pos):
			return true
	return false


func _begin_hold(pos: Vector2) -> void:
	_hold_active = true
	_hold_elapsed = 0.0
	_hold_from = pos


func _cancel_hold() -> void:
	_hold_active = false
	hold_indicator.hide_ring()
	if audio != null:
		audio.hold_stop()


func _finish_hold() -> void:
	if not _hold_active:
		return
	_hold_active = false
	hold_indicator.hide_ring()
	if audio != null:
		audio.hold_stop()
	_close_top_overlay()


func _on_save_close_pressed() -> void:
	_close_overlay(save_menu_panel)


func _on_typewriter_sfx_toggled(on: bool) -> void:
	typewriter_sfx = on
	_save_settings()


func _on_button_sfx_toggled(on: bool) -> void:
	button_sfx = on
	_save_settings()


#endregion


#region Pause / panic / modes


func open_pause() -> void:
	_open_overlay(pause_panel)
	dialogue_label.set_process(false)
	_silence_audio(true)
	resume_button.grab_focus()


func close_pause() -> void:
	pause_panel.hide()
	dialogue_label.set_process(true)
	_silence_audio(false)
	_sfx("close")
	_restore_waiting()


func toggle_panic() -> void:
	if _panic_open():
		_close_panic()
	else:
		_open_panic()


func _panic_open() -> bool:
	return is_instance_valid(panic_screen) and panic_screen.visible


func _panic_can_swap() -> bool:
	var current := get_tree().current_scene
	return current != null and current.scene_file_path == "res://scenes/vn_scene.tscn"


func _capture_panic_place() -> Dictionary:
	var place := {
		"scene_path": "",
		"resource": "",
		"line_id": "",
		"history": history.duplicate(true),
		"cursor": history_cursor,
		"bg": _current_bg,
		"left": _current_left,
		"right": _current_right,
		"focus": _current_focus,
		"paused": pause_panel.visible,
	}
	var current := get_tree().current_scene
	if current != null:
		place.scene_path = current.scene_file_path
	if is_instance_valid(dialogue_resource):
		place.resource = dialogue_resource.resource_path
	if is_instance_valid(dialogue_line):
		place.line_id = dialogue_line.id
	var game_state := get_tree().root.get_node_or_null("GameState")
	if is_instance_valid(game_state) and game_state.has_method("snapshot"):
		place.state = game_state.snapshot()
	return place


func _ensure_panic_loaded() -> bool:
	if is_instance_valid(panic_screen):
		return true
	if panic_scene_path == "" or not ResourceLoader.exists(panic_scene_path):
		_toast(tr("Nothing to show there"))
		return false
	panic_screen = PanicScript.load_into(ui_root, panic_scene_path)
	if not is_instance_valid(panic_screen):
		_toast(tr("Nothing to show there"))
		return false
	panic_close_button = panic_screen.find_child("PanicCloseButton", true, false) as Button
	# The scene's own button already emits `dismissed`. Connecting pressed too
	# would close twice and skip a line when skip mode is on.
	if panic_screen.has_signal("dismissed") and not panic_screen.dismissed.is_connected(_close_panic):
		panic_screen.dismissed.connect(_close_panic)
	elif panic_close_button != null and not panic_close_button.pressed.is_connected(_on_panic_close_pressed):
		panic_close_button.pressed.connect(_on_panic_close_pressed)
	if panic_close_button != null and not panic_close_button.pressed.is_connected(_on_ui_button_sfx):
		panic_close_button.pressed.connect(_on_ui_button_sfx)
	return true


func _open_panic() -> void:
	var place := _capture_panic_place()
	# The game scene can be replaced by the panic scene, then loaded back.
	# Any other host (the UI tests, a custom parent) keeps the game loaded
	# and covers it, because changing scene would free that host.
	if _panic_can_swap():
		PanicScript.ticket = place
		_silence_audio(true)
		_sfx("open")
		get_tree().change_scene_to_file(panic_scene_path)
		return
	_panic_place = place
	if not _ensure_panic_loaded():
		return
	panic_screen.show()
	auto_timer.stop()
	is_waiting_for_input = false
	dialogue_label.set_process(false)
	_silence_audio(true)
	_sfx("open")


func _close_panic() -> void:
	if is_instance_valid(panic_screen):
		panic_screen.hide()
	_restore_panic_place(_panic_place)
	if is_instance_valid(dialogue_label):
		dialogue_label.set_process(true)
	_silence_audio(false)
	_sfx("close")
	_restore_waiting()


func _restore_panic_place(place: Dictionary) -> void:
	if place.is_empty():
		return
	var game_state := get_tree().root.get_node_or_null("GameState")
	if is_instance_valid(game_state) and game_state.has_method("restore") and place.get("state") is Dictionary:
		game_state.restore(place.state)
	if place.get("history") is Array:
		history = place.history
		history_cursor = int(place.get("cursor", history_cursor))
	var saved_id := str(place.get("line_id", ""))
	if saved_id != "" and (not is_instance_valid(dialogue_line) or str(dialogue_line.id) != saved_id):
		var found := int(place.get("cursor", -1))
		if found < 0 or found >= history.size() or str(history[found].get("id", "")) != saved_id:
			found = -1
			for i in history.size():
				if str(history[i].get("id", "")) == saved_id:
					found = i
					break
		if found >= 0:
			rollback_to(found)
	_restore_stage({
		"bg": str(place.get("bg", "")),
		"left": str(place.get("left", "")),
		"right": str(place.get("right", "")),
		"focus": str(place.get("focus", "")),
	})


func _resume_from_panic(place: Dictionary) -> void:
	var resource_path := str(place.get("resource", ""))
	if resource_path != "" and ResourceLoader.exists(resource_path):
		dialogue_resource = load(resource_path)
	show()
	var game_state := get_tree().root.get_node_or_null("GameState")
	if is_instance_valid(game_state) and game_state.has_method("restore") and place.get("state") is Dictionary:
		game_state.restore(place.state)
	if place.get("history") is Array:
		history = place.history
		history_cursor = int(place.get("cursor", -1))
	var line_id := str(place.get("line_id", ""))
	if line_id != "" and is_instance_valid(dialogue_resource):
		# get_next injects the file's `using` autoloads. get_line does not, so
		# {{player_name}} would fail here and a direct game_states write would
		# wipe Dialogue Manager's autoload map.
		_restoring = true
		var line: DialogueLine = await dialogue_resource.get_next_dialogue_line(line_id, temporary_game_states)
		if line != null:
			dialogue_line = line
		if place.get("history") is Array:
			history = place.history
			history_cursor = int(place.get("cursor", history_cursor))
	_restore_stage({
		"bg": str(place.get("bg", "")),
		"left": str(place.get("left", "")),
		"right": str(place.get("right", "")),
		"focus": str(place.get("focus", "")),
	})
	if bool(place.get("paused", false)):
		open_pause()
	else:
		_silence_audio(false)
		_restore_waiting()


## Pause and the boss screen silence everything.  Pause the current voice in
## place instead of stopping it, so Resume continues the line from the same
## playback position.  The Master bus remains muted while either overlay is up.
func _silence_audio(on: bool) -> void:
	# Leaving one overlay while the other is still up must keep both the bus and
	# the current voice paused.
	var silent: bool = on or pause_panel.visible or _panic_open()
	voice_player.stream_paused = silent
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), silent)


## Touch pause: keyboards have the pause action, phones only get this button.
func _on_pause_button_pressed() -> void:
	if pause_panel.visible:
		close_pause()
	else:
		open_pause()


## Touch exit for the panic page (the boss key alone is no help on phones).
func _on_panic_close_pressed() -> void:
	_close_panic()


func _toggle_auto() -> void:
	auto_mode = not auto_mode
	auto_button.modulate = Color(1.0, 0.85, 0.5) if auto_mode else Color.WHITE
	_toast(tr("Auto on") if auto_mode else tr("Auto off"))
	if auto_mode and is_waiting_for_input and not _any_overlay_open():
		auto_timer.start(auto_delay)
	else:
		auto_timer.stop()


func _set_skip_active(on: bool) -> void:
	skip_mode = on
	skip_button.modulate = Color(1.0, 0.85, 0.5) if on else Color.WHITE
	auto_timer.stop()
	skip_timer.stop()
	if on and not _any_overlay_open() and is_instance_valid(dialogue_line):
		# Holding skip should finish the current typewriter immediately, not
		# wait for the slide to finish at normal text speed.
		if dialogue_label.is_typing:
			dialogue_label.skip_typing()
		elif dialogue_line.time != "" and not is_waiting_for_input:
			# A timed line may already be in its delay; invalidate its continuation
			# and advance now instead of waiting for the delay to expire.
			_line_token += 1
			next(dialogue_line.next_id)
	if on and is_waiting_for_input and not _any_overlay_open() \
		and is_instance_valid(dialogue_line) and dialogue_line.responses.size() == 0:
		if skip_seen_only and not _current_was_seen:
			_toggle_skip_off_at_unseen()
		else:
			skip_timer.start(skip_delay)


func _toggle_skip() -> void:
	_set_skip_active(not skip_mode)
	_toast(tr("Skip on") if skip_mode else tr("Skip off"))


func _toggle_skip_off_at_unseen() -> void:
	skip_mode = false
	skip_button.modulate = Color.WHITE
	skip_timer.stop()
	_toast(tr("Skip stopped at unseen text"))


func _on_skip_timeout() -> void:
	if not skip_mode:
		return
	if is_waiting_for_input and is_instance_valid(dialogue_line) \
		and dialogue_line.responses.size() == 0 and not _any_overlay_open():
		if skip_seen_only and not _current_was_seen:
			_toggle_skip_off_at_unseen()
		else:
			next(dialogue_line.next_id)


func _mark_seen(id: String) -> void:
	if not _seen_ids.has(id):
		_seen_ids[id] = true
		var f: FileAccess = FileAccess.open(_seen_path, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(_seen_ids.keys()))
			f.close()


func _load_seen() -> void:
	_seen_ids = {}
	if not FileAccess.file_exists(_seen_path):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(_seen_path))
	if data is Array:
		for id: Variant in data:
			_seen_ids[str(id)] = true


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
	if _panic_open():
		get_viewport().set_input_as_handled()
		if event.is_action_pressed(panic_action):
			toggle_panic()
		return

	if event.is_action_pressed(panic_action):
		get_viewport().set_input_as_handled()
		toggle_panic()
		return

	# Handle these here as a fallback as well as in _input. Some embedded
	# platforms route key events straight to unhandled_input after a focused
	# control has seen them, which previously made Close and held Skip vanish.
	if _action_pressed(event, skip_action) and not (event is InputEventKey and (event as InputEventKey).echo):
		_skip_key_held = true
		if not _any_overlay_open():
			_set_skip_active(true)
		get_viewport().set_input_as_handled()
		return
	if _action_released(event, skip_action):
		_skip_key_held = false
		_set_skip_active(false)
		get_viewport().set_input_as_handled()
		return

	if _try_system_actions(event):
		return

	if event.is_action_pressed(pause_action):
		get_viewport().set_input_as_handled()
		if pause_panel.visible:
			close_pause()
		elif is_instance_valid(route_graph_panel) and route_graph_panel.visible:
			_close_route_graph()
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

	# Mobile: an upward swipe opens the history backlog (the emulated mouse
	# click the swipe produces is swallowed by the guard in the gui handler).
	if event is InputEventScreenTouch:
		if _any_overlay_open():
			get_viewport().set_input_as_handled()
			return
		if event.pressed:
			_touch_from = event.position
		else:
			var delta: Vector2 = event.position - _touch_from
			_touch_from = Vector2.INF
			if delta.y < -120.0 and absf(delta.x) < 90.0:
				_swipe_guard_frames = 2
				get_viewport().set_input_as_handled()
				open_history()
		return

	# Close dismisses the top-most overlay without toggling skip mode. Keep
	# this outside the overlay's own GUI path so focused controls cannot eat it.
	if _any_overlay_open() and _action_pressed(event, close_action):
		get_viewport().set_input_as_handled()
		_close_top_overlay()
		return

	# While any overlay is open, swallow anything its controls didn't take.
	if _any_overlay_open():
		get_viewport().set_input_as_handled()
		if _action_pressed(event, close_action):
			_close_top_overlay()
		return

	# Wheel roll-back/forward. The balloon's gui handler does this when it
	# receives the wheel; this is the fallback for builds where mouse events
	# bypass the GUI (e.g. headless). Overlays keep the wheel for scrolling.
	if event is InputEventMouseButton and event.pressed \
		and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		get_viewport().set_input_as_handled()
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and history_cursor > 0:
			rollback_to(history_cursor - 1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			roll_forward()
		return

	# Enter/Space mirror the left mouse button: skip the typewriter first, then
	# advance. Only when the balloon (or nothing) owns focus - a focused Button
	# activates on key *release*, so acting here would steal its focus first and
	# swallow the click.
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	if event.is_action_pressed(next_action) \
		and (focus_owner == balloon or focus_owner == null):
		get_viewport().set_input_as_handled()
		if dialogue_label.is_typing:
			dialogue_label.skip_typing()
		elif is_waiting_for_input \
			and is_instance_valid(dialogue_line) \
			and dialogue_line.responses.size() == 0:
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
	if _panic_open():
		get_viewport().set_input_as_handled()
		return
	if _try_system_actions(event):
		return
	if _any_overlay_open():
		return

	# A swipe gesture just ended; swallow its emulated mouse click so the
	# swipe doesn't also skip typing or advance the dialogue.
	if _swipe_guard_frames > 0 and event is InputEventMouseButton:
		get_viewport().set_input_as_handled()
		return

	# Ren'Py-style: the mouse wheel rolls the game back / forward through
	# the backlog instead of scrolling the page.
	if event is InputEventMouseButton and event.pressed \
		and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		get_viewport().set_input_as_handled()
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and history_cursor > 0:
			rollback_to(history_cursor - 1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			roll_forward()
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
		var advance_key_was_pressed: bool = event.is_action_pressed(next_action)
		if mouse_was_clicked or advance_key_was_pressed:
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


## Kirikiri-style jump: fast-forward to the next line that offers choices.
func _on_next_choice_pressed() -> void:
	if is_instance_valid(dialogue_line) and dialogue_line.responses.size() > 0:
		_toast(tr("Already at a choice"))
		_refocus_balloon()
		return
	_seeking_choice = true
	if is_instance_valid(dialogue_line):
		if dialogue_label.is_typing:
			dialogue_label.skip_typing()
		next(dialogue_line.next_id)
	_refocus_balloon()


## Kirikiri-style jump: return to the most recent line that offered choices.
func _on_prev_choice_pressed() -> void:
	for i in range(history_cursor - 1, -1, -1):
		if bool(history[i].get("choices", false)):
			rollback_to(i)
			return
	_toast(tr("No earlier choice"))
	_refocus_balloon()


func _on_settings_pressed() -> void:
	_open_overlay(settings_panel)
	settings_close_button.show()
	text_speed_slider.grab_focus()


func _on_route_button_pressed() -> void:
	# Optional route graph overlay - single-pass renderer
	if is_instance_valid(route_graph_panel):
		_open_overlay(route_graph_panel)
		if route_graph_panel.has_method("show_graph"):
			if route_graph_panel.has_method("set_map_filter"):
				route_graph_panel.set_map_filter(map_filter, false)
			route_graph_panel.show_graph(dialogue_resource, _route_player_state(), glyph_scale)
	else:
		_toast("Route graph not available")


func _close_route_graph() -> void:
	if not is_instance_valid(route_graph_panel):
		return
	if route_graph_panel.has_method("dismiss_spoiler") and route_graph_panel.dismiss_spoiler():
		return
	_close_overlay(route_graph_panel)


func _route_player_state() -> Dictionary:
	var history_ids: Array = []
	var visited_ids: Array = []
	for entry in history:
		var lid := str(entry.get("id", ""))
		history_ids.append(lid)
		visited_ids.append(lid)
	var line_id := ""
	var response_ids: Array = []
	var ended := not is_instance_valid(dialogue_line)
	if not ended:
		line_id = str(dialogue_line.id)
		visited_ids.append(line_id)
		for response in dialogue_line.responses:
			if response is Object and "id" in response:
				response_ids.append(str(response.id))
	return {
		"line_id": line_id,
		"visited_ids": visited_ids,
		"history_ids": history_ids,
		"response_ids": response_ids,
		"ended": ended,
	}


func _on_route_travel_requested(target: Dictionary) -> void:
	_close_route_graph()
	_halt_modes_for_travel()
	_travel_to_target(target)


func _halt_modes_for_travel() -> void:
	auto_mode = false
	_seeking_choice = false
	auto_timer.stop()
	if is_instance_valid(auto_button):
		auto_button.modulate = Color.WHITE
	_set_skip_active(false)


## Rollback if this place is already in the backlog. Otherwise replay the engine
## from the current line, then from the start, and only then jump raw.
func _travel_to_target(target: Dictionary) -> void:
	var title := str(target.get("title", ""))
	var index := RouteTravel.history_index(history, target)
	if index < 0:
		index = int(target.get("history_index", -1))
	if index >= 0 and index < history.size():
		rollback_to(index)
		_toast(tr("Moved to %s") % title)
		return
	var jump_key := str(target.get("jump_key", ""))
	var line_ids: Array = target.get("line_ids", [])
	if (jump_key == "" or jump_key == "END" or jump_key == "end") and line_ids.is_empty():
		_toast(tr("Nothing to show there"))
		return
	var snap := _capture_travel()
	var game_state: Node = get_tree().root.get_node_or_null("GameState")
	var spoilers_ok := bool(target.get("spoilers_ok", false))
	var current_id := ""
	if is_instance_valid(dialogue_line):
		current_id = str(dialogue_line.id)
	elif history_cursor >= 0 and history_cursor < history.size():
		current_id = str(history[history_cursor].get("id", ""))
	var stage := {
		"bg": _current_bg,
		"left": _current_left,
		"right": _current_right,
		"focus": _current_focus,
	}
	_silent_travel = true
	if current_id != "":
		var from_here: Dictionary = await RouteTravel.replay(dialogue_resource, current_id, target, history, history_cursor, game_state, temporary_game_states, true, false, stage)
		if bool(from_here.get("ok", false)):
			_silent_travel = false
			_commit_replay(from_here, history_cursor)
			_toast(tr("Moved to %s") % title)
			return
		_restore_travel(snap)
	if game_state != null and game_state.has_method("reset"):
		game_state.reset()
	var from_start: Dictionary = await RouteTravel.replay(dialogue_resource, "", target, history, 0, game_state, temporary_game_states, spoilers_ok, true, {})
	if bool(from_start.get("ok", false)):
		_silent_travel = false
		_commit_replay(from_start, -1)
		_toast(tr("Moved to %s") % title)
		return
	_restore_travel(snap)
	if bool(from_start.get("blocked", false)) and not spoilers_ok and not _travel_file_differs(target):
		var reachable := await _rewrite_would_reach(target, game_state)
		_restore_travel(snap)
		_silent_travel = false
		if reachable:
			_toast(tr("That path rewrites earlier choices."))
			return
	var file_path := str(target.get("file_path", ""))
	if file_path != "" and (not is_instance_valid(dialogue_resource) or str(dialogue_resource.resource_path) != file_path):
		var other = load(file_path)
		if other != null and game_state != null and game_state.has_method("reset"):
			game_state.reset()
			_silent_travel = true
			var from_file: Dictionary = await RouteTravel.replay(other, "", target, history, 0, game_state, temporary_game_states, spoilers_ok, true, {})
			if bool(from_file.get("ok", false)):
				dialogue_resource = other
				_silent_travel = false
				_commit_replay(from_file, -1)
				_toast(tr("Moved to %s") % title)
				return
			_restore_travel(snap)
			if bool(from_file.get("blocked", false)) and not spoilers_ok:
				var reachable := await _rewrite_would_reach_resource(other, target, game_state)
				_restore_travel(snap)
				_silent_travel = false
				if reachable:
					_toast(tr("That path rewrites earlier choices."))
					return
	_silent_travel = false
	_jump_to_route_key(jump_key, file_path, title, line_ids)


func _travel_file_differs(target: Dictionary) -> bool:
	var file_path := str(target.get("file_path", ""))
	return file_path != "" and (not is_instance_valid(dialogue_resource) or str(dialogue_resource.resource_path) != file_path)


## True when some choice sequence reaches the target, so the failure was a rewrite rather than a dead scene.
func _rewrite_would_reach(target: Dictionary, game_state: Node) -> bool:
	return await _rewrite_would_reach_resource(dialogue_resource, target, game_state)


func _rewrite_would_reach_resource(resource, target: Dictionary, game_state: Node) -> bool:
	if resource == null:
		return false
	if game_state != null and game_state.has_method("reset"):
		game_state.reset()
	_silent_travel = true
	var probe: Dictionary = await RouteTravel.replay(resource, "", target, [], 0, game_state, temporary_game_states, true, true, {})
	_silent_travel = false
	return bool(probe.get("ok", false))


func _capture_travel() -> Dictionary:
	var game_state: Node = get_tree().root.get_node_or_null("GameState")
	var state: Dictionary = {}
	if game_state != null and game_state.has_method("snapshot"):
		state = game_state.snapshot()
	return {
		"history": history.duplicate(true),
		"cursor": history_cursor,
		"state": state,
		"resource_path": str(dialogue_resource.resource_path) if is_instance_valid(dialogue_resource) else "",
		"bg": _current_bg,
		"left": _current_left,
		"right": _current_right,
		"focus": _current_focus,
	}


func _restore_travel(snap: Dictionary) -> void:
	history = snap.get("history", []).duplicate(true)
	history_cursor = int(snap.get("cursor", -1))
	var game_state: Node = get_tree().root.get_node_or_null("GameState")
	if game_state != null and game_state.has_method("restore"):
		game_state.restore(snap.get("state", {}))
	var path := str(snap.get("resource_path", ""))
	if path != "" and (not is_instance_valid(dialogue_resource) or str(dialogue_resource.resource_path) != path):
		var loaded = load(path)
		if loaded != null:
			dialogue_resource = loaded
	_restore_stage({
		"bg": str(snap.get("bg", "")),
		"left": str(snap.get("left", "")),
		"right": str(snap.get("right", "")),
		"focus": str(snap.get("focus", "")),
	})


## [param keep_through] is the last history index that stays. -1 replaces the backlog.
func _commit_replay(found: Dictionary, keep_through: int) -> void:
	var walked: Array = found.get("lines", [])
	if keep_through < 0:
		history = []
	elif keep_through < history.size() - 1:
		history = history.slice(0, keep_through + 1)
	for entry in walked:
		if entry is not Dictionary:
			continue
		if not history.is_empty() and str(entry.get("id", "")) == str(history[history.size() - 1].get("id", "")):
			continue
		history.append(entry)
	if history.is_empty():
		return
	history_cursor = history.size() - 1
	_restoring = true
	_restore_stage(history[history_cursor])
	var landed = found.get("line")
	if landed != null:
		dialogue_line = landed
	_restoring = false


func _jump_to_route_key(jump_key: String, file_path: String, title: String, line_ids: Array = []) -> void:
	if file_path != "" and (not is_instance_valid(dialogue_resource) or str(dialogue_resource.resource_path) != file_path):
		var loaded = load(file_path)
		if loaded != null:
			dialogue_resource = loaded
	if not is_instance_valid(dialogue_resource):
		_toast(tr("Nothing to show there"))
		return
	var key := jump_key
	if key == "" or key == "END" or key == "end":
		key = str(line_ids[0]) if not line_ids.is_empty() else ""
	if key == "" or key == "END" or key == "end" or not _resource_has_key(dialogue_resource, key):
		_toast(tr("Nothing to show there"))
		return
	if history_cursor < history.size() - 1:
		history = history.slice(0, history_cursor + 1)
	var line: DialogueLine = await dialogue_resource.get_next_dialogue_line(key, temporary_game_states)
	if line == null:
		_toast(tr("Nothing to show there"))
		return
	dialogue_line = line
	_toast(tr("Moved to %s, but the story state was not established.") % title)


func _resource_has_key(resource, key: String) -> bool:
	if resource == null or key == "":
		return false
	if resource.cues.has(key) or resource.lines.has(key):
		return true
	if "@" in key:
		var bare := key.split("@")[-1]
		return resource.lines.has(bare) or resource.cues.has(bare)
	return false


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


func _on_quit_pressed() -> void:
	get_tree().quit()


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
	if _silent_travel:
		return
	if not mutation.is_inline:
		is_waiting_for_input = false
		will_hide_box = true
		mutation_cooldown.start(0.1)


func _on_responses_menu_response_selected(response: DialogueResponse) -> void:
	next(response.next_id)


#endregion
