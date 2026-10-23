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
## * Chants spells (when given a SpellCaster) like a player: it presses the syllables on the
##   shared beat with a little timing wobble. Easy for now: a spell every few seconds, picked
##   from the situation, and now and then a wrong syllable that makes it fizzle.

## Seconds between "target is pushable" and actually pushing.
var reaction_time := 0.22
## Extra random delay added to each reaction.
var reaction_jitter := 0.15
## How strongly edges repel the AI's own movement.
var edge_fear := 2.6
var arena: Arena
## Chanting (null = melee only, e.g. minions).
var caster: SpellCaster
## Seconds of rest between two incantations.
var cast_interval := Vector2(3.5, 7.0)
## Timing wobble of each syllable, as a fraction of its note's duration (the rhythm
## tolerance is 0.2).
var timing_jitter := 0.05
## Chance that an incantation contains a wrong syllable.
var flub_chance := 0.15

var _move := Vector3.ZERO
var _push_countdown := -1.0
var _want_push := false
var _rng := RandomNumberGenerator.new()
var _orbit_sign := 1.0
var _orbit_timer := 0.0
var _cast_wait := 2.5
# Syllables still to press: [{beat, button}], earliest first.
var _plan: Array[Dictionary] = []
var _plan_spell: SpellDefinition


func _init(arena_ref: Arena, seed_value := 1) -> void:
	arena = arena_ref
	_rng.seed = seed_value


func update(c: ArenaCharacter, delta: float) -> void:
	_want_push = false
	_update_chant(c, delta)
	var target := c.opponent
	if not target or not target.is_alive():
		target = _nearest_enemy(c)
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
	# Circle a little while approaching instead of walking in a straight line (not while
	# chanting an aimed spell: it fires where we face).
	if dist > 2.2 and _plan_spell and _aimed(_plan_spell):
		desired = to_n
	elif dist > 2.2:
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


# ---------------------------------------------------------------- chanting

func _update_chant(c: ArenaCharacter, delta: float) -> void:
	var clock := BeatClock.instance
	if not caster or not caster.listening or not c.is_alive() or c.state == ArenaCharacter.State.SPAWNING \
			or not clock or not clock.running:
		_plan.clear()
		_plan_spell = null
		return
	var b := clock.beats_now()
	if not _plan.is_empty():
		while not _plan.is_empty() and b >= _plan[0].beat:
			caster.syllable(_plan.pop_front().button, PlayerInput.now_seconds())
		if _plan.is_empty():
			_plan_spell = null
			_cast_wait = _rng.randf_range(cast_interval.x, cast_interval.y)
		return
	_cast_wait -= delta
	if _cast_wait > 0.0 or not c.is_controllable():
		return
	var spell := _choose_spell(c)
	if not spell:
		_cast_wait = 0.4
		return
	var p := _choose_chant(spell)
	# First syllable on the next half beat, then the chant's rhythm.
	var start := ceilf(b * 2.0 + 0.5) * 0.5
	var flub := _rng.randi_range(1, p.size() - 1) if _rng.randf() < flub_chance else -1
	for k in p.size():
		var button := p.syllables[k]
		if k == flub:
			button = (button + _rng.randi_range(1, 3)) % 4
		var wobble := _rng.randfn(0.0, timing_jitter * p.beats[k]) if k > 0 else 0.0
		_plan.append({"beat": start + p.onset(k) - p.onset(0) + wobble, "button": button})
	_plan_spell = spell


## Which level to chant `spell` at: mostly the short ones (easy CPU).
func _choose_chant(spell: SpellDefinition) -> RhythmPattern:
	var options: Array[RhythmPattern] = []
	var weights := PackedFloat32Array()
	for p in caster.engine.patterns:
		if p.payload == spell:
			options.append(p)
			weights.append([0.0, 0.45, 0.4, 0.15][clampi(p.level, 0, 3)])
	return options[_rng.rand_weighted(weights)]


## A spell that suits the situation (weighted at random among the enabled ones), or null.
func _choose_spell(c: ArenaCharacter) -> SpellDefinition:
	var target := c.opponent
	if not target or not target.is_alive():
		return null
	var my := Vector2(c.global_position.x, c.global_position.z)
	var their := Vector2(target.global_position.x, target.global_position.z)
	var dist := my.distance_to(their)
	var options: Array[SpellDefinition] = []
	var weights := PackedFloat32Array()
	for s in caster.book.active():
		var w := 0.0
		match s.effect:
			SpellDefinition.Effect.PUSH:
				w = 3.0 if dist > 2.0 and dist < 8.0 else 0.0
			SpellDefinition.Effect.CREATE_HOLE:
				w = 2.0 if dist > 1.6 and dist < 3.4 else 0.0
			SpellDefinition.Effect.CLOSE_HOLE:
				w = 1.0 if dist > 1.4 and dist < 3.0 else 0.0
				if not arena.nearest_hole(my, 1.5).is_empty():
					w = 2.0
			SpellDefinition.Effect.SHOCKWAVE:
				w = 2.0 if dist < 2.6 else 0.0
			SpellDefinition.Effect.KNOCKOUT, SpellDefinition.Effect.SWAP_BALL, SpellDefinition.Effect.SNARE_BALL:
				w = 0.8 if dist > 2.0 and dist < 7.0 else 0.0
			SpellDefinition.Effect.QUICKEN:
				w = 0.6 if dist > 3.0 else 0.0
			SpellDefinition.Effect.RAISE_MINION:
				w = 0.8
			SpellDefinition.Effect.TEMPO_UP, SpellDefinition.Effect.TEMPO_DOWN:
				w = 0.3
		if w > 0.0:
			options.append(s)
			weights.append(w)
	if options.is_empty():
		return null
	return options[_rng.rand_weighted(weights)]


static func _aimed(s: SpellDefinition) -> bool:
	return s.effect in [SpellDefinition.Effect.PUSH, SpellDefinition.Effect.CREATE_HOLE,
		SpellDefinition.Effect.CLOSE_HOLE, SpellDefinition.Effect.SWAP_BALL, SpellDefinition.Effect.KNOCKOUT,
		SpellDefinition.Effect.SNARE_BALL]


## The closest enemy (survival: minions have no single opponent), or null.
func _nearest_enemy(c: ArenaCharacter) -> ArenaCharacter:
	var best: ArenaCharacter = null
	var best_d := INF
	for e in c.enemies():
		var d := e.global_position.distance_squared_to(c.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best


## 0 when well inside the ground, rising to 1 at the edge and beyond.
func _danger(p: Vector2) -> float:
	return smoothstep(-0.95, 0.05, arena.ground_sdf(p))


func _obstacle_penalty(p: Vector2) -> float:
	var pen := 0.0
	# Slopes too steep to climb (mountain flanks) block like props.
	if not arena.mounds.is_empty() and arena.height_gradient(p).length() > 0.9:
		pen += 1.5
	for o in arena.obstacles:
		var d := p.distance_to(Vector2(o.x, o.y)) - o.z - 0.35
		if d < 0.0:
			pen += 1.5
	return pen


func get_move(_c: ArenaCharacter) -> Vector3:
	return _move


func wants_push(_c: ArenaCharacter) -> bool:
	return _want_push
