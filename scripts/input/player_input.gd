class_name PlayerInput
extends Node
## Captures one human player's controls.
##
## * Syllables (A/B/X/Y): every press is emitted immediately from `_input` as a timestamped
##   event (`Time.get_ticks_usec`, like the original Synchre RhythmInput), so rhythm timing
##   never depends on the render or physics rate. Events are plain data (player, button,
##   time): exactly what a network layer would forward later.
## * Movement (left stick / keys), jump (RT / key) and the melee shove (RB / key) are
##   sampled by the character's brain during physics, independently of the incantation.

## Emitted for every face-button press; `time` is in seconds on the monotonic clock.
signal syllable_pressed(button: int, time: float)
signal syllable_released(button: int, time: float)

const BUTTON_ACTIONS := ["syl_a", "syl_b", "syl_x", "syl_y"]

## Action name prefixes this player listens to, e.g. ["p1_"] or ["p1_", "p2_"].
var prefixes: Array[String] = ["p1_"]
var camera: PixelCamera


static func now_seconds() -> float:
	return Time.get_ticks_usec() * 0.000001


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadMotion or event is InputEventMouseMotion:
		return
	for p in prefixes:
		for b in BUTTON_ACTIONS.size():
			var action := StringName(p + BUTTON_ACTIONS[b])
			if event.is_action_pressed(action, false, true):
				syllable_pressed.emit(b, now_seconds())
				return
			if event.is_action_released(action, true):
				syllable_released.emit(b, now_seconds())
				return


## Desired movement on the ground plane, relative to the screen (length <= 1).
func move_vector() -> Vector3:
	var v := Vector2.ZERO
	for p in prefixes:
		v += Input.get_vector(p + "left", p + "right", p + "up", p + "down")
	v = v.limit_length(1.0)
	if not camera:
		return Vector3(v.x, 0.0, v.y)
	var axes := camera.ground_axes()
	return axes[0] * v.x + axes[1] * v.y


## True on the physics tick the jump control goes down. For the analog RT the InputMap
## deadzone (0.5) is the activation threshold and Input's action state gives the edge, so
## one trigger pull = one jump.
func jump_just_pressed() -> bool:
	for p in prefixes:
		if Input.is_action_just_pressed(p + "jump"):
			return true
	return false


## True on the physics tick the shove button (RB, digital) goes down.
func push_just_pressed() -> bool:
	for p in prefixes:
		if Input.is_action_just_pressed(p + "push"):
			return true
	return false
