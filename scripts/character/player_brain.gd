class_name PlayerBrain
extends CharacterBrain
## Human control: movement and jump come from a PlayerInput. Attacks are spells, fed to the
## character's SpellCaster from the same PlayerInput's timestamped syllable events, so they
## never interfere with moving or jumping.

const JUMP_BUFFER := 0.12

var input: PlayerInput
var _jump_buffer := 0.0


func _init(player_input: PlayerInput) -> void:
	input = player_input


func update(_character: ArenaCharacter, delta: float) -> void:
	_jump_buffer = maxf(_jump_buffer - delta, 0.0)
	if input.jump_just_pressed():
		_jump_buffer = JUMP_BUFFER


func get_move(_character: ArenaCharacter) -> Vector3:
	return input.move_vector()


func wants_jump(_character: ArenaCharacter) -> bool:
	if _jump_buffer > 0.0:
		_jump_buffer = 0.0
		return true
	return false
