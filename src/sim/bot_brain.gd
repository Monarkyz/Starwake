class_name BotBrain
extends RefCounted
## Petit cerveau de bot : poursuit l'adversaire le plus proche, garde ses distances et tire.
## Sert côté serveur (bots d'entraînement) et côté client (pilote automatique des tests).

var _rng := RandomNumberGenerator.new()
var _strafe: float = 1.0
var _strafe_left: float = 0.0
var _aim_error: Vector2 = Vector2.ZERO


func _init(seed_value: int = 0) -> void:
	if seed_value != 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()


func think(me: SimHero, heroes: Array, _arena: SimArena) -> SimInput:
	var cmd := SimInput.new()
	cmd.aim = me.pos + me.facing
	if not me.alive:
		return cmd

	var target: SimHero = null
	var best := INF
	for h: SimHero in heroes:
		if h.team == me.team or not h.alive:
			continue
		var d := me.pos.distance_squared_to(h.pos)
		if d < best:
			best = d
			target = h
	if target == null:
		# Personne à combattre : revenir vers le milieu du terrain.
		cmd.move = (Vector2(0.0, 5.0) - me.pos).limit_length(1.0)
		return cmd

	var to_target := target.pos - me.pos
	var dist := to_target.length()
	var dir := to_target / maxf(dist, 0.001)

	_strafe_left -= SimConst.DT
	if _strafe_left <= 0.0:
		_strafe_left = _rng.randf_range(0.6, 1.8)
		_strafe = 1.0 if _rng.randf() < 0.5 else -1.0
		_aim_error = Vector2(_rng.randf_range(-0.9, 0.9), _rng.randf_range(-0.9, 0.9))

	var side := Vector2(-dir.y, dir.x) * _strafe
	if dist > 8.5:
		cmd.move = (dir + side * 0.35).normalized()
	elif dist < 5.0:
		cmd.move = (-dir + side * 0.6).normalized()
	else:
		cmd.move = side

	cmd.aim = target.pos + _aim_error
	if dist < 9.5:
		cmd.buttons |= SimConst.BTN_ATTACK
	if dist < 15.0:
		cmd.buttons |= SimConst.BTN_ABILITY_1
	if me.hp < me.max_hp * 0.3 and dist < 6.0:
		cmd.buttons |= SimConst.BTN_ABILITY_2
	return cmd
