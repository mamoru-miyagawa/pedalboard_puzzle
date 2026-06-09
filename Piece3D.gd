extends Area3D
class_name Piece3D

## A 3D pedal token. Data only — movement/selection/wobble logic lives in Game3D.

var char_id: String = ""
var slot = null              # Slot3D it currently rests in (null while being dragged)

var body: Node3D = null      # pivot node that gets tilted for the wobble
var fitted_height := 0.5     # height of the scaled model

# Crisp 2D labels (drawn on the UI layer, not in the pixelated 3D viewport).
var name_label: Label = null
var cat_label: Label = null

# Damped-spring wobble state (x = tilt about X axis, y = tilt about Z axis).
var wobble := Vector2.ZERO
var wobble_vel := Vector2.ZERO
var prev_pos := Vector3.ZERO
