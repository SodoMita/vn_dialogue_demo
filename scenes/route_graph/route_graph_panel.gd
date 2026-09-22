extends PanelContainer
## Optional overlay. The rest of the VN does not require this panel.
## Never touch view.node_by_id here: if the view script failed to attach,
## view is a bare Control and that lookup is the second error in the log.


@onready var view: Control = %RouteGraphView
@onready var close_btn: Button = %CloseButton


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	if view == null:
		view = get_node_or_null("Margin/VBox/GraphContainer/RouteGraphView")
	if close_btn:
		close_btn.pressed.connect(_on_close)


func show_graph(resource = null) -> void:
	visible = true
	if view != null and is_instance_valid(view) and view.has_method("open_resource"):
		view.open_resource(resource)


func _on_close() -> void:
	visible = false
