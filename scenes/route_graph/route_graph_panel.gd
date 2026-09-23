extends PanelContainer
## Optional overlay. The rest of the VN does not require this panel.
## Never touch view.node_by_id here: if the view script failed to attach,
## view is a bare Control and that lookup is the second error in the log.


signal travel_requested(target: Dictionary)

@onready var view: Control = %RouteGraphView
@onready var close_btn: Button = %CloseButton
@onready var here_label: Label = %HereLabel
@onready var hint_label: Label = %HintLabel
@onready var title_label: Label = %TitleLabel
@onready var visited_toggle: Button = %VisitedToggle
@onready var spoiler_panel: Control = %SpoilerPanel
@onready var spoiler_title: Label = %SpoilerTitle
@onready var spoiler_body: Label = %SpoilerBody
@onready var spoiler_confirm: Button = %SpoilerConfirm
@onready var spoiler_cancel: Button = %SpoilerCancel

var visited_only := true


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	if view == null:
		view = get_node_or_null("Margin/VBox/GraphContainer/RouteGraphView")
	if close_btn:
		close_btn.pressed.connect(_on_close)
	if visited_toggle:
		visited_toggle.toggled.connect(_on_visited_toggled)
		visited_toggle.set_pressed_no_signal(true)
	if spoiler_confirm:
		spoiler_confirm.pressed.connect(_on_spoiler_confirmed)
	if spoiler_cancel:
		spoiler_cancel.pressed.connect(_on_spoiler_cancelled)
	if spoiler_panel:
		spoiler_panel.hide()
	if view != null and view.has_signal("travel_requested") and not view.travel_requested.is_connected(_on_view_travel):
		view.travel_requested.connect(_on_view_travel)
	_apply_texts()
	_sync_toggle_look()


func set_glyph_scale(scale: int, rebuild: bool = true) -> void:
	if view != null and is_instance_valid(view) and view.has_method("set_glyph_scale"):
		view.set_glyph_scale(scale, rebuild)


func set_map_filter(index: int, rebuild: bool = true) -> void:
	if view != null and is_instance_valid(view) and view.has_method("set_map_filter"):
		view.set_map_filter(index, rebuild)


func show_graph(resource = null, player: Dictionary = {}, glyph_scale: int = -1) -> void:
	visible = true
	_apply_texts()
	if glyph_scale >= 1:
		set_glyph_scale(glyph_scale, false)
	if view != null and is_instance_valid(view) and view.has_method("open_resource"):
		view.open_resource(resource, player)
		if view.has_method("set_visited_only"):
			view.set_visited_only(visited_only)
	_refresh_here()


func refresh_locale() -> void:
	_apply_texts()
	if view != null and is_instance_valid(view) and view.has_method("refresh_locale"):
		view.refresh_locale()
	_refresh_here()


## Returns true when a spoiler prompt was open and this call dismissed it.
## The map itself stays up so a stray Esc does not also close it.
func dismiss_spoiler() -> bool:
	if spoiler_panel != null and spoiler_panel.visible:
		_on_spoiler_cancelled()
		return true
	return false


func _on_close() -> void:
	if dismiss_spoiler():
		return
	visible = false


func _on_view_travel(target: Dictionary) -> void:
	var payload := target.duplicate()
	# Visited only is the spoiler gate. A path that rewrites earlier choices
	# waits for the same approval as showing unread routes.
	payload["spoilers_ok"] = not visited_only
	travel_requested.emit(payload)


func _on_visited_toggled(on: bool) -> void:
	if on:
		_set_visited_only(true)
		return
	# Turning the filter off reveals unread routes. Keep it on until approved.
	if visited_toggle:
		visited_toggle.set_pressed_no_signal(true)
	_sync_toggle_look()
	if spoiler_panel:
		spoiler_panel.show()
		if spoiler_cancel:
			spoiler_cancel.grab_focus()


func _on_spoiler_confirmed() -> void:
	if spoiler_panel:
		spoiler_panel.hide()
	_set_visited_only(false)
	if visited_toggle:
		visited_toggle.set_pressed_no_signal(false)
	_sync_toggle_look()


func _on_spoiler_cancelled() -> void:
	if spoiler_panel:
		spoiler_panel.hide()
	if visited_toggle:
		visited_toggle.set_pressed_no_signal(true)
	_sync_toggle_look()


func _set_visited_only(on: bool) -> void:
	visited_only = on
	if view != null and is_instance_valid(view) and view.has_method("set_visited_only"):
		view.set_visited_only(on)
	_refresh_here()
	_sync_toggle_look()


func _sync_toggle_look() -> void:
	if visited_toggle == null:
		return
	visited_toggle.text = tr("Visited only") if visited_only else tr("Full map")
	visited_toggle.modulate = Color(1.0, 0.85, 0.5) if visited_only else Color(1.0, 0.72, 0.45)


func _refresh_here() -> void:
	if here_label == null:
		return
	var title := ""
	if view != null and is_instance_valid(view) and view.has_method("here_title"):
		title = str(view.here_title())
	if title == "":
		here_label.text = tr("Here: —")
	else:
		here_label.text = tr("Here: %s") % title


func _apply_texts() -> void:
	if title_label:
		title_label.text = tr("Story map")
	if hint_label:
		hint_label.text = tr("Drag to pan  ·  Pinch or wheel to zoom  ·  Port → other side  ·  Edge → furthest of its two nodes  ·  Header → play there")
	if close_btn:
		close_btn.text = tr("Close")
	if spoiler_title:
		spoiler_title.text = tr("Spoilers ahead")
	if spoiler_body:
		spoiler_body.text = tr("Turning this off shows the whole story map, including paths you have not visited.")
	if spoiler_confirm:
		spoiler_confirm.text = tr("Show spoilers")
	if spoiler_cancel:
		spoiler_cancel.text = tr("Keep hidden")
	_sync_toggle_look()
	_refresh_here()
