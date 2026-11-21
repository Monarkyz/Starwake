class_name BotBrain
extends RefCounted
## Cerveau de bot. Par ordre de priorité : se replier quand il est blessé, combattre
## le héros adverse le plus proche, canaliser la relique, pousser sa voie.
## Sert côté serveur (bots d'entraînement) et côté client (pilote automatique des tests).
##
## "view" est un SimWorld (serveur) ou un SimSnapshot (client) : les deux exposent
## heroes, units, structures, relic_active et arena.

## Voie suivie par ce bot.
var lane: int = 0
## Un bot itinérant va chercher la relique d'où qu'il soit.
var roamer: bool = false

var _rng := RandomNumberGenerator.new()
var _strafe: float = 1.0
var _strafe_left: float = 0.0
var _aim_error: Vector2 = Vector2.ZERO
var _retreating: bool = false
# Détection de blocage contre un obstacle.
var _check_pos: Vector2 = Vector2.ZERO
var _check_left: int = 0
var _sidestep_left: int = 0
var _wanted_move: bool = false


func _init(seed_value: int = 0) -> void:
	if seed_value != 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()


func think(me: SimHero, view: Variant) -> SimInput:
	var cmd := SimInput.new()
	cmd.aim = me.pos + me.facing
	if not me.alive:
		_retreating = false
		_check_left = 0
		return cmd
	var arena: SimArena = view.arena
	_update_strafe()

	if me.hp < me.max_hp * 0.3:
		_retreating = true
	elif me.hp > me.max_hp * 0.85:
		_retreating = false

	var enemy_hero := _nearest_enemy_hero(me, view, 12.0)
	if _retreating and not arena.fountains.is_empty():
		cmd.move = (arena.fountains[me.team] - me.pos).limit_length(1.0)
		if enemy_hero != null:
			cmd.aim = enemy_hero.pos
			cmd.buttons |= SimConst.BTN_ATTACK
			if me.pos.distance_to(enemy_hero.pos) < 6.0:
				cmd.buttons |= SimConst.BTN_ABILITY_2
		return _finish(me, cmd)

	if enemy_hero != null:
		_fight_hero(me, enemy_hero, cmd)
	elif not _go_for_relic(me, view, arena, cmd):
		_push_lane(me, view, arena, cmd)
	_avoid_structures(me, view, cmd)
	return _finish(me, cmd)


func _fight_hero(me: SimHero, target: SimHero, cmd: SimInput) -> void:
	var to_target := target.pos - me.pos
	var dist := to_target.length()
	var dir := to_target / maxf(dist, 0.001)
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


## Va sur l'autel et y reste immobile pour canaliser. Renvoie faux si ce n'est pas le moment.
func _go_for_relic(me: SimHero, view: Variant, arena: SimArena, cmd: SimInput) -> bool:
	if not view.relic_active or not arena.has_altar:
		return false
	var dist := me.pos.distance_to(arena.altar)
	if not roamer and dist > 30.0:
		return false
	# Depuis la base, suivre d'abord la voie pour contourner le sanctuaire.
	if absf(me.pos.x) > 36.0:
		return false
	if dist > arena.altar_radius - 1.0:
		cmd.move = (arena.altar - me.pos).limit_length(1.0)
	return true


func _push_lane(me: SimHero, view: Variant, arena: SimArena, cmd: SimInput) -> void:
	# Sbires et mercenaires adverses à portée.
	var enemy := 1 - me.team
	var target_pos := Vector2.ZERO
	var best := 9.5 * 9.5
	var found := false
	for u: SimUnit in view.units:
		if u.team != enemy or not u.alive:
			continue
		var d := u.pos.distance_squared_to(me.pos)
		if d < best:
			best = d
			target_pos = u.pos
			found = true
	if found:
		cmd.aim = target_pos + _aim_error * 0.3
		cmd.buttons |= SimConst.BTN_ATTACK | SimConst.BTN_ABILITY_1
		if best < 16.0:
			# Garder ses distances, en reculant vers sa propre base.
			var back := -1.0 if me.team == SimConst.TEAM_DAWN else 1.0
			cmd.move = ((me.pos - target_pos).normalized() + Vector2(back, 0.0)).normalized()
		return

	# Bâtiment adverse attaquable à portée de tir.
	for s: SimStructure in view.structures:
		if s.team != enemy or not s.alive or not s.vulnerable:
			continue
		var edge := s.pos.distance_to(me.pos) - s.radius
		if edge < 9.0:
			cmd.aim = s.pos
			cmd.buttons |= SimConst.BTN_ATTACK | SimConst.BTN_ABILITY_1
			return
		if edge < 14.0:
			# À portée de vue : s'approcher jusqu'à pouvoir tirer (le repli est géré plus bas).
			cmd.move = (s.pos - me.pos).normalized()
			return

	if arena.lanes.is_empty():
		cmd.move = (Vector2.ZERO - me.pos).limit_length(1.0)
		return
	# Avancer le long de la voie : viser le premier point situé devant soi.
	var forward := 1.0 if me.team == SimConst.TEAM_DAWN else -1.0
	var path := arena.lane_path(lane % arena.lanes.size(), me.team)
	var goal: Vector2 = path[path.size() - 1]
	for point in path:
		if point.x * forward > me.pos.x * forward + 1.0:
			goal = point
			break
	# Marcher côté intérieur de la voie, pour passer à côté des temples alliés.
	goal.y *= 0.84
	cmd.move = (goal - me.pos).limit_length(1.0)


## Ne pas entrer dans la portée d'un bâtiment adverse sans sbires alliés pour l'occuper :
## le bot attend à la limite, et recule s'il s'y retrouve à découvert.
func _avoid_structures(me: SimHero, view: Variant, cmd: SimInput) -> void:
	for s: SimStructure in view.structures:
		if s.team == me.team or not s.alive:
			continue
		var dist := s.pos.distance_to(me.pos)
		var hold := s.attack_range + 2.0
		if dist > hold:
			continue
		var covered := false
		for u: SimUnit in view.units:
			if u.team == me.team and u.alive and u.pos.distance_to(s.pos) <= s.attack_range - 2.0:
				covered = true
				break
		if covered:
			continue
		if dist < hold - 1.5:
			cmd.move = (me.pos - s.pos).normalized()
		elif cmd.move.dot(s.pos - me.pos) > 0.0:
			cmd.move = Vector2.ZERO
		return


func _nearest_enemy_hero(me: SimHero, view: Variant, max_dist: float) -> SimHero:
	var target: SimHero = null
	var best := max_dist * max_dist
	for id: int in view.heroes:
		var h: SimHero = view.heroes[id]
		if h.team == me.team or not h.alive:
			continue
		var d := me.pos.distance_squared_to(h.pos)
		if d < best:
			best = d
			target = h
	return target


func _update_strafe() -> void:
	_strafe_left -= SimConst.DT
	if _strafe_left <= 0.0:
		_strafe_left = _rng.randf_range(0.6, 1.8)
		_strafe = 1.0 if _rng.randf() < 0.5 else -1.0
		_aim_error = Vector2(_rng.randf_range(-0.9, 0.9), _rng.randf_range(-0.9, 0.9))


## Dernière étape : si le bot veut avancer mais n'avance pas (obstacle pile en face),
## il fait quelques pas de côté.
func _finish(me: SimHero, cmd: SimInput) -> SimInput:
	if _sidestep_left > 0:
		_sidestep_left -= 1
		if cmd.move.length_squared() > 0.01:
			cmd.move = Vector2(-cmd.move.y, cmd.move.x) * _strafe
		return cmd
	if _check_left <= 0:
		if _wanted_move and me.pos.distance_to(_check_pos) < 0.5:
			_sidestep_left = 18
		_check_pos = me.pos
		_check_left = 30
		_wanted_move = true
	_check_left -= 1
	if cmd.move.length_squared() < 0.25:
		_wanted_move = false
	return cmd
