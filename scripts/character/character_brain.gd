class_name CharacterBrain
extends RefCounted
## Decides what a character wants to do. Subclassed by PlayerBrain and AIBrain.


## Called once per physics tick before the queries below.
func update(_character: ArenaCharacter, _delta: float) -> void:
	pass


## Desired move direction on the ground plane (length <= 1).
func get_move(_character: ArenaCharacter) -> Vector3:
	return Vector3.ZERO


## True when the character should start a melee push now (only asked when possible).
func wants_push(_character: ArenaCharacter) -> bool:
	return false


## True when the character should jump now (only asked when a jump is possible).
func wants_jump(_character: ArenaCharacter) -> bool:
	return false
