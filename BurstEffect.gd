extends Node2D
class_name BurstEffect

## A quick "pop" played when a pedal lands on the board: a ring of short lines
## bursting outward, fading as they fly out. Sized to reach a little past the
## pedal. Add it at the landing position; it animates once and frees itself.

const DURATION := 0.34          # seconds
const LINE_COUNT := 10
const COLOR := Color(1, 1, 1)   # tint of the burst

# Line travel / sizing (design-space pixels). Pedals are ~104 x ~137, so the
# lines reaching ~90 from centre sit just outside the pedal edges.
const START_RADIUS := 20.0      # how far from centre the lines begin
const END_RADIUS := 90.0        # how far they reach
const START_LEN := 30.0         # line length at the start
const END_LEN := 6.0            # line length at the end (they shrink as they fly)
const START_WIDTH := 6.0
const END_WIDTH := 1.5

var _t := 0.0                   # 0 → 1 over DURATION

func _process(delta: float) -> void:
	_t += delta / DURATION
	if _t >= 1.0:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var e := 1.0 - pow(1.0 - _t, 3.0)   # ease-out cubic for the outward travel
	var alpha := 1.0 - _t               # linear fade

	# Burst lines, evenly spaced around the circle.
	var inner: float = lerp(START_RADIUS, END_RADIUS, e)
	var length: float = lerp(START_LEN, END_LEN, e)
	var width: float = lerp(START_WIDTH, END_WIDTH, _t)
	var col := COLOR
	col.a = alpha
	for i in range(LINE_COUNT):
		var a := TAU * float(i) / float(LINE_COUNT)
		var dir := Vector2(cos(a), sin(a))
		draw_line(dir * inner, dir * (inner + length), col, width, true)
