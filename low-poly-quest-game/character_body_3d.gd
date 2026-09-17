extends CharacterBody3D

## Character controller for a "rolling log" style level.
##
## Horizontal movement is still an illusion: the player stays pinned
## to its starting world X/Z while CylinderTrack rolls and shifts
## underneath it. Standing height, jumping, and falling are all real,
## but driven by simple direct kinematics (position += velocity * delta)
## rather than move_and_slide() -- there's no collision response we
## actually need yet (no wall obstacles exist), and move_and_slide()'s
## built-in floor snapping/depenetration was causing intermittent
## missed jumps when landing exactly at a surface's height. Every frame
## a ray is cast straight down from above the player to find whatever
## collision surface actually exists there (road, sidewalk, anything
## else), and the player's Y is measured directly against that hit.
## There's no hand-tracked "zone" data to keep in sync with the real
## geometry. If you add real wall obstacles later that need the player
## to physically collide/slide against them, that's the point to bring
## move_and_slide() back for horizontal motion specifically.
##
## Requires these Input Map actions: forward, backward, left, right, jump

@export var cylinder_track: CylinderTrack
@export var stand_height_offset: float = 1.0

## How high (in meters) a jump should reach at its peak, and roughly
## how long the whole jump should take (seconds) if nothing gets in
## the way. Gravity and jump velocity are both derived from these two
## numbers so they can be tuned independently.
@export var jump_height: float = 2.0
@export var jump_air_time: float = 1.0

## How far above/below the track to search for ground. Should
## comfortably cover the tallest and lowest points your track geometry
## can ever reach (curbs included).
@export var ground_search_up: float = 60.0
@export var ground_search_down: float = 100.0

## How long (seconds) a jump press is remembered if it doesn't land on
## a frame where the ground is confirmed underneath -- prevents a
## press from being silently dropped by a one-frame raycast hiccup.
@export var jump_buffer_time: float = 0.15

## Mouse-look settings.
@export var mouse_sensitivity: float = 0.003
@export var min_pitch_deg: float = -80.0
@export var max_pitch_deg: float = 80.0

@onready var camera: Camera3D = $Camera3D

var _origin_x: float = 0.0
var _origin_z: float = 0.0
var _pitch: float = 0.0

var _gravity: float = 0.0
var _jump_velocity: float = 0.0
var _vertical_speed: float = 0.0
var _is_airborne: bool = false
var _jump_buffer_timer: float = 0.0

func _ready() -> void:
	# height = gravity * air_time^2 / 8, velocity = 4 * height / air_time
	_gravity = 8.0 * jump_height / (jump_air_time * jump_air_time)
	_jump_velocity = 4.0 * jump_height / jump_air_time

	_origin_x = global_position.x
	_origin_z = global_position.z
	if cylinder_track == null:
		push_warning("Player: no CylinderTrack assigned in the inspector.")
	else:
		var ground := _raycast_ground()
		if ground.hit:
			global_position.y = ground.y
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	# Press Escape to free the mouse (handy while testing in the editor).
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = (
			Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			else Input.MOUSE_MODE_CAPTURED
		)

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		_pitch = clamp(_pitch - event.relative.y * mouse_sensitivity,
			deg_to_rad(min_pitch_deg), deg_to_rad(max_pitch_deg))
		camera.rotation.x = _pitch

func _physics_process(delta: float) -> void:
	if cylinder_track == null:
		return

	var forward_input := Input.get_axis("backward", "forward")
	var strafe_input := Input.get_axis("left", "right")

	# Rotate the input by the body's current facing so "forward" always
	# means "wherever you're looking," not a fixed world axis.
	var input_vec := Vector2(strafe_input, forward_input)
	if input_vec.length() > 1.0:
		input_vec = input_vec.normalized()
	var local_dir := Vector3(input_vec.x, 0.0, -input_vec.y)
	var world_dir: Vector3 = global_transform.basis * local_dir

	var sprinting := Input.is_key_pressed(KEY_SHIFT) and Input.is_action_pressed("forward")
	cylinder_track.set_sprinting(sprinting)

	cylinder_track.roll(world_dir.z, delta)
	cylinder_track.shift(world_dir.x, delta)

	# Captured here, unconditionally, so a press is never lost just
	# because this exact frame's raycast happened to miss the ground.
	if Input.is_action_just_pressed("jump"):
		_jump_buffer_timer = jump_buffer_time
	elif _jump_buffer_timer > 0.0:
		_jump_buffer_timer -= delta

	var ground := _raycast_ground()

	if not _is_airborne:
		if ground.hit:
			global_position.y = ground.y
			if _jump_buffer_timer > 0.0:
				_is_airborne = true
				_vertical_speed = _jump_velocity
				_jump_buffer_timer = 0.0
		else:
			# Nothing under us -- start falling for real instead of
			# snapping to some fallback height.
			_is_airborne = true
			_vertical_speed = 0.0
	else:
		_vertical_speed -= _gravity * delta
		global_position.y += _vertical_speed * delta

		# Land the moment real Y falls back down to (or past) whatever
		# the ray currently reports as ground.
		if ground.hit and global_position.y <= ground.y:
			global_position.y = ground.y
			_is_airborne = false
			_vertical_speed = 0.0

	global_position.x = _origin_x
	global_position.z = _origin_z

func _raycast_ground() -> Dictionary:
	# Anchored to the track's own (never-moving) Y rather than the
	# player's current Y, so this stays reliable even mid-fall.
	var anchor_y := cylinder_track.global_position.y
	var from := Vector3(_origin_x, anchor_y + ground_search_up, _origin_z)
	var to := Vector3(_origin_x, anchor_y - ground_search_down, _origin_z)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [self]
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return {"hit": false, "y": 0.0}
	return {"hit": true, "y": result.position.y + stand_height_offset}
