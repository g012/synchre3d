class_name CharacterBrain
extends RefCounted
## Decides what a character wants to do. Subclassed by PlayerBrain and AIBrain.


## Called once per physics tick before the queries below.
func update(_character: ArenaCharacter, _delta: float) -> void:
	pass


## Desired move direction on the ground plane (length <= 1).
func get_move(_character: ArenaCharacter) -> Vector3:
	return Vector3.ZERO


## True when the character should start a push now (only asked when a push is possible).
func wants_push(_character: ArenaCharacter) -> bool:
	return false
