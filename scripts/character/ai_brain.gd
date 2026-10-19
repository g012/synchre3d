class_name AIBrain
extends CharacterBrain
## Simple but competent opponent.
##
## * Approaches the player, preferring the side opposite the player's nearest edge so a push
##   sends them toward a hole.
## * Steers among 16 candidate directions, penalising ones whose lookahead points are close to
##   an edge (from the arena distance field) or inside an obstacle.
## * Pushes when the target is in range and roughly in front, after a short human-like
##   reaction delay, so a quick sidestep can bait it into whiffing (and lunging toward a hole).

## Seconds between "target is pushable" and actually pushing.
var reaction_time := 0.22
## Extra random delay added to each reaction.
var reaction_jitter := 0.15
## How strongly edges repel the AI's own movement.
var edge_fear := 2.6
var arena: Arena

var _move := Vector3.ZERO
var _push_countdown := -1.0
var _want_push := false
var _rng := RandomNumberGenerator.new()
var _orbit_sign := 1.0
var _orbit_timer := 0.0


func _init(arena_ref: Arena, seed_value := 1) -> void:
	arena = arena_ref
	_rng.seed = seed_value


func update(c: ArenaCharacter, delta: float) -> void:
	_want_push = false
	var target := c.opponent
	if not target or not target.is_alive() or not c.is_controllable():
		_move = Vector3.ZERO
		_push_countdown = -1.0
		return
	var my := Vector2(c.global_position.x, c.global_position.z)
	var their := Vector2(target.global_position.x, target.global_position.z)
	var to := their - my
	var dist := to.length()
	var to_n := to / maxf(dist, 0.001)

	_orbit_timer -= delta
	if _orbit_timer <= 0.0:
		_orbit_timer = _rng.randf_range(1.2, 2.6)
		_orbit_sign = -_orbit_sign if _rng.randf() < 0.5 else _orbit_sign

	# Ideal attack spot: behind the target, opposite its nearest edge.
	var target_edge_dist := -arena.ground_sdf(their)
	var edge_dir := arena.ground_gradient(their)
	var ideal := their - to_n * 0.85
	if target_edge_dist < 3.0:
		ideal = their - edge_dir * 0.85
	var to_ideal := ideal - my
	var desired := to_ideal.normalized() if to_ideal.length() > 0.15 else to_n
	# When already close, face the target so a push can land.
	if dist < c.push_range * 1.05 and to_ideal.length() < 0.6:
		desired = to_n
	# Circle a little while approaching instead of walking in a straight line.
	if dist > 2.2:
		desired = (desired + Vector2(-desired.y, desired.x) * 0.35 * _orbit_sign).normalized()

	var best := Vector2.ZERO
	var best_score := -INF
	for i in 16:
		var a := TAU * i / 16.0
		var cand := Vector2(cos(a), sin(a))
		var score := cand.dot(desired)
		score -= _danger(my + cand * 0.55) * edge_fear
		score -= _danger(my + cand * 1.1) * edge_fear * 0.6
		score -= _obstacle_penalty(my + cand * 0.6)
		if score > best_score:
			best_score = score
			best = cand
	# Standing still is fine if every direction is worse than staying put near an edge.
	var stay := -_danger(my) * edge_fear * 0.8
	var speed := clampf(to_ideal.length() * 1.5, 0.35, 1.0)
	if best_score < stay - 0.2:
		best = Vector2.ZERO
	_move = Vector3(best.x, 0.0, best.y) * speed
	# In striking range: creep toward the target so we turn to face it (facing follows
	# movement), as long as our own footing is safe.
	if dist < c.push_range * 1.1 and arena.ground_sdf(my + to_n * 0.4) < -0.25:
		_move = Vector3(to_n.x, 0.0, to_n.y) * 0.3

	# Push decision with reaction delay.
	var angle := rad_to_deg(c.facing.angle_to(Vector3(to_n.x, 0.0, to_n.y)))
	var in_range := dist < c.push_range * 0.95 and angle < 38.0
	# A target already reeling gets punished faster.
	var stunned := target.state == ArenaCharacter.State.HITSTUN
	if in_range:
		if _push_countdown < 0.0:
			_push_countdown = (reaction_time * (0.5 if stunned else 1.0)) + _rng.randf() * reaction_jitter
		_push_countdown -= delta
		if _push_countdown <= 0.0:
			_want_push = true
			_push_countdown = -1.0
	else:
		_push_countdown = -1.0


## 0 when well inside the ground, rising to 1 at the edge and beyond.
func _danger(p: Vector2) -> float:
	return smoothstep(-0.95, 0.05, arena.ground_sdf(p))


func _obstacle_penalty(p: Vector2) -> float:
	var pen := 0.0
	for o in arena.obstacles:
		var d := p.distance_to(Vector2(o.x, o.y)) - o.z - 0.35
		if d < 0.0:
			pen += 1.5
	return pen


func get_move(_c: ArenaCharacter) -> Vector3:
	return _move


func wants_push(_c: ArenaCharacter) -> bool:
	return _want_push
