extends Control
class_name DotLeader

## A row of evenly spaced dots that fills its width — the leader between a label
## and a value, e.g. "TYPE .......... Overdrive". Used in the pedal spec sheet.

@export var dot_color := Color("#9a9ab0")
@export var dot_radius := 1.6
@export var spacing := 7.0
@export var baseline := 0.7      # vertical position of the dots (0 top, 1 bottom)

func _ready() -> void:
	resized.connect(queue_redraw)

func _draw() -> void:
	var y := size.y * baseline
	var x := spacing
	while x <= size.x - dot_radius:
		draw_circle(Vector2(x, y), dot_radius, dot_color)
		x += spacing
