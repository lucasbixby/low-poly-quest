extends Node3D
class_name CylinderTrack

## Attach this to the root node of your cylinder (e.g. a StaticBody3D
## with a MeshInstance3D + CollisionShape3D, or a CSGCylinder3D, as
## children).
##
## Godot's cylinder primitives default to having their long axis along
## local Y. For this "rolling log" effect the cylinder should lie on
## its side with its axis along X, so rotate the mesh/collision children
## 90 degrees around Z in the editor before running.
##
## This script only handles rolling and shifting now. Standing height
## is figured out entirely by player.gd via a downward raycast against
## whatever collision shapes actually exist -- so this track doesn't
## need to know its own radius, or track any "zones," at all.

@export var roll_speed: float = 0.25
@export var shift_speed: float = 5.0
@export var shift_limit: float = 30.0

var _start_x: float = 0.0
var _base_roll_speed: float = 0.0
var _base_shift_speed: float = 0.0

func _ready() -> void:
	_start_x = position.x
	_base_roll_speed = roll_speed
	_base_shift_speed = shift_speed

## Call with true while sprint is held, false otherwise. Adds a flat
## +1.0 to both roll_speed and shift_speed while active, reverting to
## their normal values as soon as it's called with false again.
func set_sprinting(active: bool) -> void:
	var roll_bonus := 0.15 if active else 0.0
	var shift_bonus := 5.0 if active else 0.0
	roll_speed = _base_roll_speed + roll_bonus
	shift_speed = _base_shift_speed + shift_bonus

## Positive = player moving forward. Rotates the track about its own
## X axis, simulating the player running along the top.
func roll(input: float, delta: float) -> void:
	rotate_x(-input * roll_speed * delta)

## Positive = player moving right. Translates the whole track sideways
## under the (world-stationary) player.
func shift(input: float, delta: float) -> void:
	var new_x := position.x - input * shift_speed * delta
	if shift_limit > 0.0:
		new_x = clamp(new_x, _start_x - shift_limit, _start_x + shift_limit)
	position.x = new_x
