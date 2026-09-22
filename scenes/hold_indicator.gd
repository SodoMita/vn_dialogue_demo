extends Control
class_name HoldIndicator

const RADIUS := 104.0
const BASE_WIDTH := 14.0
const GOLD := Color(1.0, 0.84, 0.0)

var progress: float = 0.0
var _point: Vector2 = Vector2.ZERO
var _age: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(2 * RADIUS + 64, 2 * RADIUS + 64)
	set_process(false)
	hide()


func show_at(pos: Vector2) -> void:
	_point = pos
	progress = 0.0
	_age = 0.0
	visible = true
	set_process(true)
	queue_redraw()


func hide_ring() -> void:
	visible = false
	set_process(false)


func _process(delta: float) -> void:
	_age += delta
	queue_redraw()


func _draw() -> void:
	var pop: float = clampf(_age / 0.14, 0.0, 1.0)
	var e: float = 1.0 - pow(1.0 - pop, 3.0)
	var r: float = RADIUS * lerpf(0.5, 1.0, e)
	var sweep: float = TAU * clampf(progress, 0.0, 1.0)

	# base track
	draw_circle(_point, r, Color(GOLD, 0.45), false, BASE_WIDTH, true)
	# progress
	if sweep > 0.01:
		draw_arc(_point, r, -PI / 2, -PI / 2 + sweep, 48, GOLD, BASE_WIDTH, true)
	# center dot
	draw_circle(_point, BASE_WIDTH * 0.55, Color(GOLD, 0.95))
