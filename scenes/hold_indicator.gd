extends Control
class_name HoldIndicator

## Animated hold-to-close ring: a big golden circle that fills toward the
## release as the gesture charges. Purely decorative — mouse_filter IGNORE.

signal completed

const RADIUS := 104.0          ## 4x the old 26 px ring
const BASE_WIDTH := 14.0
const GOLD := Color(1.0, 0.84, 0.0)

var progress: float = 0.0
var _point: Vector2 = Vector2.ZERO
var _age: float = 0.0
var _hold_time: float = 0.0
var _complete: bool = false
var _blink_t: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(2 * RADIUS + 64, 2 * RADIUS + 64)
	set_process(false)
	hide()


func show_at(pos: Vector2) -> void:
	_point = pos
	progress = 0.0
	_age = 0.0
	_hold_time = 0.0
	_complete = false
	_blink_t = 0.0
	visible = true
	set_process(true)
	queue_redraw()


func hide_ring() -> void:
	visible = false
	set_process(false)


func _process(delta: float) -> void:
	_age += delta
	if not _complete:
		_hold_time += delta
	else:
		_blink_t += delta * 30.0
		if _blink_t > TAU:
			completed.emit()
			hide_ring()
			return
	queue_redraw()


func _draw() -> void:
	if not visible:
		return
	var pop: float = clampf(_age / 0.14, 0.0, 1.0)
	var ease: float = 1.0 - pow(1.0 - pop, 3.0)
	var ring_scale: float = lerpf(0.5, 1.0, ease)
	var wob: float = 1.0 + 0.05 * sin(_age * 22.0) * (1.0 - pop)
	var r: float = RADIUS * ring_scale * wob
	var base_alpha: float = clampf(0.5 + _age * 4.0, 0.0, 1.0)
	var sweep: float = TAU * progress
	# fading golden trail arcs behind the fill
	for i: int in 3:
		var ph: float = fmod(_hold_time * 6.0 - float(i) * 0.7, 3.0) / 3.0
		var ta: float = (1.0 - ph) * 0.28 * base_alpha
		if ta > 0.01:
			var rr: float = r * (1.0 + ph * 0.35)
			draw_arc(_point, rr, -PI / 2, -PI / 2 + TAU * 0.8, 64,
					Color(GOLD, ta), BASE_WIDTH * 0.4, true)
	# dim golden base track (always visible)
	draw_arc(_point, r, -PI / 2, -PI / 2 + TAU * 0.999, 64,
			Color(GOLD, 0.45), BASE_WIDTH, true)
	# solid golden progress arc
	if sweep > 0.01:
		draw_arc(_point, r, -PI / 2, -PI / 2 + sweep, 48,
				Color(GOLD, 1.0), BASE_WIDTH, true)
	# golden center dot
	var blink: float = 0.0
	if _complete:
		blink = 1.0 - absf(sin(_blink_t))
	draw_circle(_point, BASE_WIDTH * 0.55, Color(GOLD, 0.95))
	# completion blink
	if blink > 0.0:
		draw_arc(_point, r + BASE_WIDTH, -PI / 2, -PI / 2 + TAU * 0.999, 64,
				Color(1.0, 0.95, 0.55, blink), BASE_WIDTH * 0.8, true)
