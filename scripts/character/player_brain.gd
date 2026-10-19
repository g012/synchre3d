class_name PlayerBrain
extends CharacterBrain
## Keyboard control. Movement is relative to the screen (camera), not to the character.
## A push pressed slightly early (during cooldown) is buffered so mashing feels fair.

const PUSH_BUFFER := 0.15

## Action name prefixes this player listens to, e.g. ["p1_"] or ["p1_", "p2_"].
var prefixes: Array[String] = ["p1_"]
var camera: PixelCamera

var _push_buffer := 0.0


func _init(action_prefixes: Array[String], cam: PixelCamera) -> void:
	prefixes = action_prefixes
	camera = cam


func update(_character: ArenaCharacter, delta: float) -> void:
	_push_buffer = maxf(_push_buffer - delta, 0.0)
	for p in prefixes:
		if Input.is_action_just_pressed(p + "push"):
			_push_buffer = PUSH_BUFFER


func get_move(_character: ArenaCharacter) -> Vector3:
	var v := Vector2.ZERO
	for p in prefixes:
		v += Input.get_vector(p + "left", p + "right", p + "up", p + "down")
	v = v.limit_length(1.0)
	var axes := camera.ground_axes()
	return axes[0] * v.x + axes[1] * v.y


func wants_push(_character: ArenaCharacter) -> bool:
	if _push_buffer > 0.0:
		_push_buffer = 0.0
		return true
	return false
