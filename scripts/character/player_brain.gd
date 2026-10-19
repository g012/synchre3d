class_name PlayerBrain
extends CharacterBrain
## Human control: movement, jump and the melee shove (RB) come from a PlayerInput. Spells
## are fed to the character's SpellCaster from the same PlayerInput's timestamped syllable
## events, so they never interfere with moving, jumping or shoving.

const JUMP_BUFFER := 0.12

var input: PlayerInput
var _jump_buffer := 0.0
var _push_buffer := 0.0


func _init(player_input: PlayerInput) -> void:
	input = player_input


func update(_character: ArenaCharacter, delta: float) -> void:
	_jump_buffer = maxf(_jump_buffer - delta, 0.0)
	_push_buffer = maxf(_push_buffer - delta, 0.0)
	if input.jump_just_pressed():
		_jump_buffer = JUMP_BUFFER
	if input.push_just_pressed():
		_push_buffer = JUMP_BUFFER


func get_move(_character: ArenaCharacter) -> Vector3:
	return input.move_vector()


func wants_jump(_character: ArenaCharacter) -> bool:
	if _jump_buffer > 0.0:
		_jump_buffer = 0.0
		return true
	return false


func wants_push(_character: ArenaCharacter) -> bool:
	if _push_buffer > 0.0:
		_push_buffer = 0.0
		return true
	return false
