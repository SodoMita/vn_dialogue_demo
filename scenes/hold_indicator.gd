class_name HoldIndicator extends Control
## Animated hold-to-close ring drawn at the press point while the player keeps
## holding empty menu space. The balloon drives it: show_at() pops it in,
## `progress` (0..1) fills the ring, hide_ring() cancels. mouse_filter stays
## IGNORE so it never steals the touch/mouse from the menu underneath.

const RADIUS: float = 26.0

var progress: float = 0.0
var point: Vector2 = Vector2.ZERO
var _pop: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_at(pos: Vector2) -> void:
	point = pos
	progress = 0.0
	_pop = 0.0
	show()
	set_process(true)
	queue_redraw()


func hide_ring() -> void:
	hide()
	set_process(false)
	queue_redraw()


func _process(delta: float) -> void:
	_pop = minf(1.0, _pop + delta / 0.14)
	queue_redraw()


func _draw() -> void:
	if not visible:
		return
	var r: float = RADIUS * (0.6 + 0.4 * _pop)
	var a: float = 0.35 + 0.55 * _pop
	var gold := Color(0.93, 0.78, 0.42, a)
	draw_circle(point, r, Color(0.04, 0.05, 0.08, 0.45 * a))
	draw_arc(point, r, 0.0, TAU, 32, Color(0.85, 0.85, 0.9, 0.3 * a), 3.0)
	draw_arc(point, r, -PI / 2, -PI / 2 + TAU * clampf(progress, 0.0, 1.0), 48, gold, 5.0)
	draw_circle(point, 3.5 + 1.5 * _pop, gold)
