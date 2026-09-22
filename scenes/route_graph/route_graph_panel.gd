extends PanelContainer
# Optional overlay panel hosting the route graph
# No grid, no editing - just view + pan/zoom + click navigation

@onready var view: Control = %RouteGraphView
@onready var close_btn: Button = %CloseButton
@onready var hint_label: Label = %HintLabel

func _ready() -> void:
	visible = false
	# close button
	if close_btn:
		close_btn.pressed.connect(_on_close)
	# hide on Esc
	mouse_filter = Control.MOUSE_FILTER_STOP

func show_graph() -> void:
	visible = true
	# center on first start (runtime data)
	if view:
		var first_start: String = "start"
		if view.node_by_id.size() > 0:
			for nid in view.node_by_id.keys():
				var n: Dictionary = view.node_by_id[nid]
				if n.type == "START":
					first_start = nid
					break
		if view.has_method("_pan_to_node"):
			view.call_deferred("_pan_to_node", first_start)

func _on_close() -> void:
	visible = false

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		visible = false
		get_viewport().set_input_as_handled()
