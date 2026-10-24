class_name SwarmBrain
extends CharacterBrain
## Survival enemy: rushes straight at its target, sidesteps holes and props in its way,
## and shoves once in reach. Cheap on purpose (dozens run at once): the path ahead is only
## re-checked a few times per second, staggered between enemies.

## Seconds between path checks.
const THINK := 0.2
## How far ahead a hole is looked for.
const LOOKAHEAD := 0.9

var arena: Arena
var target: ArenaCharacter
var _move := Vector3.ZERO
var _dir := Vector2.ZERO
var _think := 0.0
var _want_push := false
var _push_delay := -1.0
var _rng := RandomNumberGenerator.new()


func _init(arena_ref: Arena, target_ref: ArenaCharacter, seed_value := 1) -> void:
	arena = arena_ref
	target = target_ref
	_rng.seed = seed_value
	_think = _rng.randf() * THINK


func update(c: ArenaCharacter, delta: float) -> void:
	_want_push = false
	if not target or not target.is_alive() or not c.is_controllable():
		_move = Vector3.ZERO
		_push_delay = -1.0
		return
	var my := Vector2(c.global_position.x, c.global_position.z)
	var to := Vector2(target.global_position.x, target.global_position.z) - my
	var dist := to.length()
	var to_n := to / maxf(dist, 0.001)
	_think -= delta
	if _think <= 0.0:
		_think = THINK
		_dir = to_n
		# Straight ahead unless that walks into a hole or a prop; then the smallest detour that
		# doesn't.
		var side := 1.0 if _rng.randf() < 0.5 else -1.0
		for a in [0.0, 0.6, -0.6, 1.2, -1.2, 1.9, -1.9]:
			var cand := to_n.rotated(a * side)
			var q := my + cand * LOOKAHEAD
			if arena.ground_sdf(q) < -0.25 and not _blocked(q):
				_dir = cand
				break
	var speed := 1.0 if dist > c.push_range * 0.8 else 0.35
	_move = Vector3(_dir.x, 0.0, _dir.y) * speed
	# Shove once in reach and roughly facing the target, after a short reaction.
	var angle := rad_to_deg(c.facing.angle_to(Vector3(to_n.x, 0.0, to_n.y)))
	if dist < c.push_range * 0.95 and angle < 45.0:
		if _push_delay < 0.0:
			_push_delay = _rng.randf_range(0.15, 0.45)
		_push_delay -= delta
		if _push_delay <= 0.0:
			_want_push = true
			_push_delay = -1.0
	else:
		_push_delay = -1.0


func _blocked(p: Vector2) -> bool:
	for o in arena.obstacles:
		if p.distance_squared_to(Vector2(o.x, o.y)) < (o.z + 0.45) * (o.z + 0.45):
			return true
	return false


func get_move(_c: ArenaCharacter) -> Vector3:
	return _move


func wants_push(_c: ArenaCharacter) -> bool:
	return _want_push
