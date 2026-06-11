extends Node2D
class_name Piece2D

## A 2D pedal token. Data only — movement/selection/wobble logic lives in Game2D.

var char_id: String = ""
var slot = null              # Slot2D it currently rests in (null while being dragged)

var body: Node2D = null      # pivot node that gets rotated for the wobble
var display_size := Vector2(104, 137)   # on-screen size of the sprite (for hit-testing)

# Drop shadow — a child of the piece (tracks its position as it's dragged). On
# pickup the pedal lifts up and the shadow sinks down, to suggest height.
# Sprite2D (art) or Panel (fallback).
var shadow = null
var shadow_base_pos := Vector2.ZERO
var shadow_base_scale := Vector2.ONE

# Crisp labels (drawn on their own layer so the wobble doesn't tilt them).
var name_label: Label = null
var cat_label: Label = null

# Damped-spring wobble state — a single pendulum sway angle (radians).
var wobble := 0.0
var wobble_vel := 0.0
var prev_pos := Vector2.ZERO

# Active position tween (used when a displaced pedal glides to its new slot).
var move_tween: Tween = null
