class_name SimWorld
extends RefCounted
## Simulation d'une partie, sans aucun nœud ni affichage.
## Le serveur fait autorité : il appelle step() à chaque pas. Le client réutilise
## step_hero_local() pour prédire le déplacement de son propre héros.
##
## Une partie : chaque équipe pousse deux voies avec ses sbires, détruit les temples
## adverses l'un après l'autre, puis le sanctuaire final. La relique et les camps de
## mercenaires donnent un avantage à l'équipe qui les prend. L'expérience est commune
## à toute l'équipe.

## Sert à distinguer les types de cible dans SimProjectile.hit_ids.
const TARGET_KEY := 100000

const BEAM_STRUCTURE := 0
const BEAM_ARCHER := 1
const BEAM_RELIC := 2

var arena: SimArena
var tick: int = 0
var heroes: Dictionary = {}  # id -> SimHero
var units: Array[SimUnit] = []
var structures: Array[SimStructure] = []
var projectiles: Array[SimProjectile] = []
## Attaques instantanées du dernier pas, pour l'affichage : [type, départ, arrivée].
var beams: Array = []
var team_kills: Array[int] = [0, 0]
var team_level: Array[int] = [1, 1]
## Expérience accumulée dans le niveau en cours.
var team_xp: Array[float] = [0.0, 0.0]
var relic_active: bool = false
## Temps avant la prochaine apparition de la relique.
var relic_timer: float = 0.0
## Progression de la canalisation de chaque équipe, de 0 à 1.
var relic_progress: Array[float] = [0.0, 0.0]
## État des camps : {alive: gardiens restants, timer: temps avant leur retour}.
var camps: Array[Dictionary] = []
var match_over: bool = false
var winner: int = -1
## Reliques prises depuis le début de la partie.
var relics_taken: int = 0
## Événements du dernier pas : [type, a, b].
##   kill(tueur ou 0, victime) · structure(rang, équipe attaquante) · relic_spawn
##   relic(équipe) · camp(équipe, rang) · level(équipe, niveau) · match_end(vainqueur)
var events: Array = []

var _next_hero_id: int = 1
var _next_unit_id: int = 1
var _next_projectile_id: int = 1
var _wave_timer: float = 0.0
var _units_by_id: Dictionary = {}
## Coups portés par les unités pendant le pas en cours : [type de cible, id, dégâts, équipe].
var _unit_hits: Array = []
var _match_start_tick: int = 0


func _init(p_arena: SimArena = null) -> void:
	arena = p_arena if p_arena != null else SimArena.make_default()
	_setup_match()


# ---------------------------------------------------------------------------
# Héros
# ---------------------------------------------------------------------------

func add_hero(team: int, def_id: String = HeroDefs.DEFAULT_HERO) -> SimHero:
	var h := SimHero.new()
	h.id = _next_hero_id
	_next_hero_id += 1
	h.team = team
	h.def_id = def_id
	h.max_hp = _hero_max_hp(h)
	h.spawn_slot = _free_spawn_slot(team)
	_place_at_spawn(h)
	heroes[h.id] = h
	return h


func remove_hero(id: int) -> void:
	heroes.erase(id)


## Temps écoulé depuis le début de la partie en cours, en secondes.
func match_time() -> float:
	return (tick - _match_start_tick) * SimConst.DT


func team_size(team: int) -> int:
	var count := 0
	for id in heroes:
		var h: SimHero = heroes[id]
		if h.team == team:
			count += 1
	return count


## Remet la partie à zéro en gardant les héros présents (nouvelle manche).
func reset_match() -> void:
	_setup_match()
	for id in heroes:
		var h: SimHero = heroes[id]
		h.kills = 0
		h.deaths = 0
		h.max_hp = _hero_max_hp(h)
		_place_at_spawn(h)


# ---------------------------------------------------------------------------
# Pas de simulation
# ---------------------------------------------------------------------------

## Avance la simulation d'un pas. inputs : id du héros -> SimInput.
func step(inputs: Dictionary) -> void:
	events.clear()
	beams.clear()
	tick += 1
	if match_over:
		return
	_step_heroes(inputs)
	_step_waves()
	_step_camps()
	_step_units()
	_step_structures()
	_step_projectiles()
	_step_relic()
	for team in 2:
		_grant_xp(team, SimConst.XP_PASSIVE_PER_SECOND * SimConst.DT)
	_remove_dead_units()


## Partie de la mise à jour d'un héros qui ne dépend que de lui et de sa commande :
## recharges, orientation, ruée, déplacement. Le client la rejoue pour prédire.
static func step_hero_local(h: SimHero, cmd: SimInput, p_arena: SimArena, dt: float) -> void:
	if not h.alive:
		return
	var def: Dictionary = HeroDefs.get_def(h.def_id)
	var abilities: Array = def["abilities"]
	for i in h.cooldowns.size():
		h.cooldowns[i] = maxf(0.0, h.cooldowns[i] - dt)

	var to_aim := cmd.aim - h.pos
	if to_aim.length_squared() > 0.0001:
		h.facing = to_aim.normalized()

	var move := cmd.move.limit_length(1.0)
	for slot in abilities.size():
		var ability: Dictionary = abilities[slot]
		if ability["type"] != "dash":
			continue
		if (cmd.buttons & (1 << slot)) == 0 or h.cooldowns[slot] > 0.0 or h.dash_left > 0.0:
			continue
		var dir := move.normalized() if move.length_squared() > 0.01 else h.facing
		var duration: float = ability["duration"]
		var distance: float = ability["distance"]
		h.dash_vel = dir * (distance / duration)
		h.dash_left = duration
		h.cooldowns[slot] = ability["cooldown"]

	if h.dash_left > 0.0:
		h.pos += h.dash_vel * minf(dt, h.dash_left)
		h.dash_left = maxf(0.0, h.dash_left - dt)
	else:
		var speed: float = def["speed"]
		h.pos += move * speed * dt
	var radius: float = def["radius"]
	h.pos = p_arena.resolve_circle(h.pos, radius)


func _step_heroes(inputs: Dictionary) -> void:
	var ids: Array = heroes.keys()
	ids.sort()
	for id in ids:
		var h: SimHero = heroes[id]
		var cmd: SimInput = inputs.get(id)
		if cmd == null:
			cmd = SimInput.new()
			cmd.aim = h.pos + h.facing
		if cmd.seq > h.last_seq:
			h.last_seq = cmd.seq
		h.idle = cmd.buttons == 0 and cmd.move.length_squared() < 0.01
		if not h.alive:
			h.respawn_left -= SimConst.DT
			if h.respawn_left <= 0.0:
				_place_at_spawn(h)
			continue
		step_hero_local(h, cmd, arena, SimConst.DT)
		_step_hero_actions(h, cmd)
		_step_hero_regen(h)


func _step_hero_actions(h: SimHero, cmd: SimInput) -> void:
	var def: Dictionary = HeroDefs.get_def(h.def_id)
	var abilities: Array = def["abilities"]
	var hero_radius: float = def["radius"]
	for slot in abilities.size():
		var ability: Dictionary = abilities[slot]
		if ability["type"] != "projectile":
			continue
		if (cmd.buttons & (1 << slot)) == 0 or h.cooldowns[slot] > 0.0:
			continue
		h.cooldowns[slot] = ability["cooldown"]
		var p := SimProjectile.new()
		p.id = _next_projectile_id
		_next_projectile_id = _next_projectile_id % 0xFFFF + 1
		p.kind = slot
		p.team = h.team
		p.owner_id = h.id
		p.radius = ability["radius"]
		var base_damage: float = ability["damage"]
		p.damage = base_damage * SimConst.level_multiplier(team_level[h.team])
		p.range_left = ability["range"]
		p.pierce = ability["pierce"]
		var speed: float = ability["speed"]
		p.vel = h.facing * speed
		p.pos = h.pos + h.facing * (hero_radius + p.radius)
		projectiles.append(p)


func _step_hero_regen(h: SimHero) -> void:
	var gain := 0.0
	if (tick - h.last_hit_tick) * SimConst.DT >= SimConst.REGEN_DELAY:
		gain += SimConst.REGEN_RATE
	if not arena.fountains.is_empty() and h.pos.distance_to(arena.fountains[h.team]) <= SimConst.FOUNTAIN_RADIUS:
		gain += SimConst.FOUNTAIN_RATE
	if gain > 0.0:
		h.hp = minf(h.max_hp, h.hp + h.max_hp * gain * SimConst.DT)


# ---------------------------------------------------------------------------
# Sbires, mercenaires et gardiens de camp
# ---------------------------------------------------------------------------

func _step_waves() -> void:
	if arena.lanes.is_empty():
		return
	_wave_timer -= SimConst.DT
	if _wave_timer > 0.0:
		return
	_wave_timer = SimConst.WAVE_INTERVAL
	for lane in arena.lanes.size():
		for team in 2:
			if units.size() + UnitDefs.WAVE.size() > SimConst.MAX_UNITS:
				return
			var path := arena.lane_path(lane, team)
			var heading := (path[1] - path[0]).normalized()
			for entry: Array in UnitDefs.WAVE:
				var offset: Vector2 = entry[1]
				var u := _spawn_unit(entry[0], team, path[0] + offset - heading * absf(offset.y))
				u.path = path
				u.wp = 1
				u.offset = offset


func _step_camps() -> void:
	for index in camps.size():
		var camp: Dictionary = camps[index]
		if camp["alive"] > 0:
			continue
		camp["timer"] -= SimConst.DT
		if camp["timer"] > 0.0:
			continue
		var guards: Array = arena.camps[index]["guards"]
		for point: Vector2 in guards:
			var u := _spawn_unit(UnitDefs.GUARDIAN, SimConst.TEAM_NEUTRAL, point)
			if u == null:
				continue
			u.camp = index
			u.home = point
			camp["alive"] += 1


func _step_units() -> void:
	_unit_hits.clear()
	for u in units:
		u.attacked = false
		if not u.alive:
			continue
		u.attack_cd = maxf(0.0, u.attack_cd - SimConst.DT)
		var def: Dictionary = UnitDefs.get_def(u.kind)
		if u.team == SimConst.TEAM_NEUTRAL:
			_step_camp_guard(u, def)
		else:
			_step_lane_unit(u, def)
		var radius: float = def["radius"]
		u.pos = arena.resolve_unit(u.pos, radius)
	# Les coups d'un même pas s'appliquent ensemble, une fois que tout le monde a agi :
	# sinon l'équipe traitée en premier gagnerait tous les duels à égalité.
	for hit: Array in _unit_hits:
		var target_id: int = hit[1]
		match hit[0]:
			SimUnit.TARGET_HERO:
				var hero: SimHero = heroes.get(target_id)
				if hero != null:
					_damage_hero(hero, hit[2], hit[3], 0)
			SimUnit.TARGET_UNIT:
				var unit: SimUnit = _units_by_id.get(target_id)
				if unit != null:
					_damage_unit(unit, hit[2], hit[3], 0)
			SimUnit.TARGET_STRUCTURE:
				_damage_structure(structures[target_id], hit[2], hit[3])
	_separate_units()


func _step_lane_unit(u: SimUnit, def: Dictionary) -> void:
	if (tick + u.id) % 6 == 0 or _target_info(u.target_type, u.target_id, u.team).is_empty():
		_acquire_target(u, def)
	if u.target_type != SimUnit.TARGET_NONE and _engage(u, def):
		return
	if u.wp >= u.path.size():
		return
	var to_goal := u.path[u.wp] + u.offset - u.pos
	if to_goal.length() < 1.5:
		u.wp += 1
	else:
		var speed: float = def["speed"]
		u.pos += to_goal.normalized() * speed * SimConst.DT


## Gardien de camp : reste à son poste, attaque le héros qui s'approche ou le frappe,
## puis rentre et se soigne si ce héros s'éloigne.
func _step_camp_guard(u: SimUnit, def: Dictionary) -> void:
	var target: SimHero = null
	if u.target_type == SimUnit.TARGET_HERO:
		target = heroes.get(u.target_id)
	if target != null and (not target.alive or target.pos.distance_to(u.home) > SimConst.CAMP_LEASH):
		target = null
	if target == null:
		var aggro: float = def["aggro"]
		var best := aggro * aggro
		for id in heroes:
			var h: SimHero = heroes[id]
			if not h.alive or h.pos.distance_to(u.home) > SimConst.CAMP_LEASH:
				continue
			var d := h.pos.distance_squared_to(u.pos)
			if d < best:
				best = d
				target = h
	if target == null:
		u.target_type = SimUnit.TARGET_NONE
		var back := u.home - u.pos
		if back.length() > 0.2:
			var speed: float = def["speed"]
			u.pos += back.normalized() * minf(speed * 1.5 * SimConst.DT, back.length())
		u.hp = minf(u.max_hp, u.hp + u.max_hp * 0.25 * SimConst.DT)
		return
	u.target_type = SimUnit.TARGET_HERO
	u.target_id = target.id
	_engage(u, def)


## Cherche la cible la plus proche : d'abord une unité adverse, puis un bâtiment
## attaquable, puis un héros.
func _acquire_target(u: SimUnit, def: Dictionary) -> void:
	u.target_type = SimUnit.TARGET_NONE
	var enemy := 1 - u.team
	var aggro: float = def["aggro"]
	var best := aggro * aggro
	for other in units:
		if not other.alive or other.team != enemy:
			continue
		var d := other.pos.distance_squared_to(u.pos)
		if d < best:
			best = d
			u.target_type = SimUnit.TARGET_UNIT
			u.target_id = other.id
	if u.target_type != SimUnit.TARGET_NONE:
		return
	var best_edge := aggro
	for s in structures:
		if not s.alive or not s.vulnerable or s.team != enemy:
			continue
		var edge := s.pos.distance_to(u.pos) - s.radius
		if edge < best_edge:
			best_edge = edge
			u.target_type = SimUnit.TARGET_STRUCTURE
			u.target_id = s.index
	if u.target_type != SimUnit.TARGET_NONE:
		return
	best = aggro * aggro * 0.64
	for id in heroes:
		var h: SimHero = heroes[id]
		if not h.alive or h.team != enemy:
			continue
		var d := h.pos.distance_squared_to(u.pos)
		if d < best:
			best = d
			u.target_type = SimUnit.TARGET_HERO
			u.target_id = h.id


## Position et rayon d'une cible, ou tableau vide si elle n'est plus valable pour
## une unité de l'équipe donnée.
func _target_info(target_type: int, target_id: int, team: int) -> Array:
	match target_type:
		SimUnit.TARGET_HERO:
			var h: SimHero = heroes.get(target_id)
			if h != null and h.alive and h.team != team:
				var hero_radius: float = HeroDefs.get_def(h.def_id)["radius"]
				return [h.pos, hero_radius]
		SimUnit.TARGET_UNIT:
			var other: SimUnit = _units_by_id.get(target_id)
			if other != null and other.alive and other.team != team:
				var unit_radius: float = UnitDefs.get_def(other.kind)["radius"]
				return [other.pos, unit_radius]
		SimUnit.TARGET_STRUCTURE:
			if target_id >= 0 and target_id < structures.size():
				var s := structures[target_id]
				if s.alive and s.vulnerable and s.team != team:
					return [s.pos, s.radius]
	return []


## Avance vers la cible de l'unité ou la frappe. Renvoie faux si la cible n'est plus valable.
func _engage(u: SimUnit, def: Dictionary) -> bool:
	var info := _target_info(u.target_type, u.target_id, u.team)
	if info.is_empty():
		u.target_type = SimUnit.TARGET_NONE
		return false
	var target_pos: Vector2 = info[0]
	var target_radius: float = info[1]
	var to_target := target_pos - u.pos
	var reach: float = def["range"]
	var own_radius: float = def["radius"]
	if to_target.length() - target_radius - own_radius > reach:
		var speed: float = def["speed"]
		u.pos += to_target.normalized() * speed * SimConst.DT
		return true
	if u.attack_cd > 0.0:
		return true
	u.attack_cd = def["cooldown"]
	u.attacked = true
	var amount: float = def["damage"]
	if def["ranged"]:
		beams.append([BEAM_ARCHER, u.pos, target_pos])
	if u.target_type == SimUnit.TARGET_STRUCTURE:
		var mult: float = def["structure_mult"]
		amount *= mult * (1.0 + SimConst.SIEGE_GROWTH_PER_MINUTE * match_time() / 60.0)
	_unit_hits.append([u.target_type, u.target_id, amount, u.team])
	return true


## Écarte les unités qui se chevauchent, pour qu'elles ne s'empilent pas.
func _separate_units() -> void:
	var count := units.size()
	for i in count:
		var a := units[i]
		if not a.alive:
			continue
		var radius_a: float = UnitDefs.get_def(a.kind)["radius"]
		for j in range(i + 1, count):
			var b := units[j]
			if not b.alive:
				continue
			var radius_b: float = UnitDefs.get_def(b.kind)["radius"]
			var min_dist := radius_a + radius_b
			var delta := b.pos - a.pos
			var dist_sq := delta.length_squared()
			if dist_sq >= min_dist * min_dist:
				continue
			var dist := sqrt(dist_sq)
			var dir := delta / dist if dist > 0.001 else Vector2.from_angle(float(a.id * 7 + b.id))
			var push := dir * (min_dist - dist) * 0.25
			a.pos -= push
			b.pos += push


func _spawn_unit(kind: int, team: int, pos: Vector2) -> SimUnit:
	if units.size() >= SimConst.MAX_UNITS_HARD:
		return null
	var u := SimUnit.new()
	while _units_by_id.has(_next_unit_id):
		_next_unit_id = _next_unit_id % 0xFFFF + 1
	u.id = _next_unit_id
	_next_unit_id = _next_unit_id % 0xFFFF + 1
	u.kind = kind
	u.team = team
	u.pos = pos
	u.max_hp = UnitDefs.get_def(kind)["max_hp"]
	u.hp = u.max_hp
	units.append(u)
	_units_by_id[u.id] = u
	return u


func _remove_dead_units() -> void:
	var kept: Array[SimUnit] = []
	for u in units:
		if u.alive:
			kept.append(u)
		else:
			_units_by_id.erase(u.id)
	units = kept


# ---------------------------------------------------------------------------
# Bâtiments
# ---------------------------------------------------------------------------

func _step_structures() -> void:
	for s in structures:
		if not s.alive or s.damage <= 0.0:
			continue
		s.attack_cd = maxf(0.0, s.attack_cd - SimConst.DT)
		if s.attack_cd > 0.0:
			continue
		var enemy := 1 - s.team
		var best := s.attack_range * s.attack_range
		var target_unit: SimUnit = null
		for u in units:
			if not u.alive or u.team != enemy:
				continue
			var d := u.pos.distance_squared_to(s.pos)
			if d < best:
				best = d
				target_unit = u
		if target_unit != null:
			s.attack_cd = s.cooldown
			beams.append([BEAM_STRUCTURE, s.pos, target_unit.pos])
			_damage_unit(target_unit, s.damage, s.team, 0)
			continue
		var target_hero: SimHero = null
		for id in heroes:
			var h: SimHero = heroes[id]
			if not h.alive or h.team != enemy:
				continue
			var d := h.pos.distance_squared_to(s.pos)
			if d < best:
				best = d
				target_hero = h
		if target_hero != null:
			s.attack_cd = s.cooldown
			beams.append([BEAM_STRUCTURE, s.pos, target_hero.pos])
			_damage_hero(target_hero, s.damage, s.team, 0)


## Un temple intérieur n'est attaquable qu'après la chute du temple extérieur de sa voie ;
## le sanctuaire, qu'après la chute d'un temple intérieur.
func _update_vulnerability() -> void:
	var alive: Array[bool] = []
	for s in structures:
		alive.append(s.alive)
		match s.tier:
			0:
				s.vulnerable = true
			1:
				s.vulnerable = not _has_structure(s.team, s.lane, 0)
			_:
				s.vulnerable = false
				for lane in arena.lanes.size():
					if not _has_structure(s.team, lane, 1):
						s.vulnerable = true
				if arena.lanes.is_empty():
					s.vulnerable = true
	arena.set_structures_alive(alive)


func _has_structure(team: int, lane: int, tier: int) -> bool:
	for s in structures:
		if s.alive and s.team == team and s.lane == lane and s.tier == tier:
			return true
	return false


## Bâtiment d'une équipe le plus avancé sur une voie, ou null s'il n'en reste pas.
func _front_structure(team: int, lane: int) -> SimStructure:
	var front: SimStructure = null
	for s in structures:
		if s.alive and s.team == team and s.lane == lane and (front == null or s.tier < front.tier):
			front = s
	return front


func _core_of(team: int) -> SimStructure:
	for s in structures:
		if s.alive and s.team == team and s.kind == SimStructure.KIND_CORE:
			return s
	return null


# ---------------------------------------------------------------------------
# Projectiles
# ---------------------------------------------------------------------------

func _step_projectiles() -> void:
	var kept: Array[SimProjectile] = []
	for p in projectiles:
		var travel := minf(p.vel.length() * SimConst.DT, p.range_left)
		var from := p.pos
		var to := from + p.vel.normalized() * travel
		var wall := arena.segment_block_fraction(from, to, p.radius)
		var spent := false

		# Cibles croisées pendant ce pas : [fraction, type, identifiant].
		var hits: Array = []
		for id in heroes:
			var h: SimHero = heroes[id]
			if h.alive and h.team != p.team:
				var hero_radius: float = HeroDefs.get_def(h.def_id)["radius"]
				_collect_hit(hits, p, from, to, wall, SimUnit.TARGET_HERO, h.id, h.pos, hero_radius)
		for u in units:
			if u.alive and u.team != p.team:
				var unit_radius: float = UnitDefs.get_def(u.kind)["radius"]
				_collect_hit(hits, p, from, to, wall, SimUnit.TARGET_UNIT, u.id, u.pos, unit_radius)
		for s in structures:
			if s.alive and s.team != p.team:
				_collect_hit(hits, p, from, to, wall, SimUnit.TARGET_STRUCTURE, s.index, s.pos, s.radius)
		hits.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])

		for hit: Array in hits:
			var target_id: int = hit[2]
			p.hit_ids.append(hit[1] * TARGET_KEY + target_id)
			match hit[1]:
				SimUnit.TARGET_HERO:
					_damage_hero(heroes[target_id], p.damage, p.team, p.owner_id)
				SimUnit.TARGET_UNIT:
					_damage_unit(_units_by_id[target_id], p.damage, p.team, p.owner_id)
				SimUnit.TARGET_STRUCTURE:
					# Un bâtiment arrête tous les projectiles, même perforants.
					_damage_structure(structures[target_id], p.damage, p.team)
					spent = true
			if spent or not p.pierce:
				spent = true
				break

		p.pos = to
		p.range_left -= travel
		if wall <= 1.0 or p.range_left <= 0.001 or not arena.is_inside(p.pos):
			spent = true
		if not spent:
			kept.append(p)
	projectiles = kept


func _collect_hit(hits: Array, p: SimProjectile, from: Vector2, to: Vector2, wall: float,
		target_type: int, target_id: int, target_pos: Vector2, target_radius: float) -> void:
	if p.hit_ids.has(target_type * TARGET_KEY + target_id):
		return
	var t := SimArena.segment_circle_fraction(from, to, target_pos, target_radius + p.radius)
	if t <= 1.0 and t <= wall:
		hits.append([t, target_type, target_id])


# ---------------------------------------------------------------------------
# Relique
# ---------------------------------------------------------------------------

func _step_relic() -> void:
	if not arena.has_altar:
		return
	if not relic_active:
		for id in heroes:
			var h: SimHero = heroes[id]
			h.channeling = false
		relic_timer -= SimConst.DT
		if relic_timer <= 0.0:
			relic_active = true
			relic_progress = [0.0, 0.0]
			events.append(["relic_spawn", 0, 0])
		return

	var channeling: Array[bool] = [false, false]
	for id in heroes:
		var h: SimHero = heroes[id]
		h.channeling = (h.alive and h.idle
				and h.pos.distance_to(arena.altar) <= arena.altar_radius
				and (tick - h.last_hit_tick) * SimConst.DT >= SimConst.RELIC_INTERRUPT)
		if h.channeling:
			channeling[h.team] = true
	for team in 2:
		if channeling[team]:
			relic_progress[team] += SimConst.DT / SimConst.RELIC_CHANNEL_TIME
		else:
			relic_progress[team] = maxf(0.0, relic_progress[team] - SimConst.DT / SimConst.RELIC_DECAY_TIME)
	for team in 2:
		if relic_progress[team] >= 1.0:
			_capture_relic(team)
			return


## L'onde de la relique frappe, sur chaque voie, le bâtiment adverse le plus avancé.
func _capture_relic(team: int) -> void:
	relic_active = false
	relic_timer = SimConst.RELIC_INTERVAL
	relic_progress = [0.0, 0.0]
	events.append(["relic", team, 0])
	var growth := 1.0 + SimConst.RELIC_GROWTH * relics_taken
	relics_taken += 1
	var enemy := 1 - team
	for lane in arena.lanes.size():
		var target := _front_structure(enemy, lane)
		var amount := SimConst.RELIC_TEMPLE_DAMAGE
		if target == null:
			target = _core_of(enemy)
			amount = SimConst.RELIC_CORE_DAMAGE
		if target == null:
			continue
		beams.append([BEAM_RELIC, arena.altar, target.pos])
		_damage_structure(target, amount * growth, team)
		if match_over:
			return


# ---------------------------------------------------------------------------
# Dégâts, éliminations, expérience
# ---------------------------------------------------------------------------

func _damage_hero(target: SimHero, amount: float, source_team: int, source_hero_id: int) -> void:
	if not target.alive:
		return
	target.hp = maxf(0.0, target.hp - amount)
	target.last_hit_tick = tick
	if target.hp > 0.0:
		return
	target.alive = false
	target.respawn_left = SimConst.respawn_time(team_level[target.team])
	target.dash_left = 0.0
	target.channeling = false
	target.deaths += 1
	var killer: SimHero = heroes.get(source_hero_id)
	if killer != null:
		killer.kills += 1
	if source_team == 1 - target.team:
		team_kills[source_team] += 1
		_grant_xp(source_team, SimConst.XP_HERO_KILL + SimConst.XP_HERO_KILL_PER_LEVEL * team_level[target.team])
	events.append(["kill", source_hero_id, target.id])


func _damage_unit(u: SimUnit, amount: float, source_team: int, source_hero_id: int) -> void:
	if not u.alive:
		return
	u.hp -= amount
	if u.team == SimConst.TEAM_NEUTRAL and source_hero_id != 0 and u.target_type == SimUnit.TARGET_NONE:
		# Un gardien frappé de loin se retourne contre son agresseur.
		u.target_type = SimUnit.TARGET_HERO
		u.target_id = source_hero_id
	if u.hp > 0.0:
		return
	u.hp = 0.0
	u.alive = false
	var xp: float = UnitDefs.get_def(u.kind)["xp"]
	if u.team == SimConst.TEAM_NEUTRAL:
		_grant_xp(source_team, xp)
		var camp: Dictionary = camps[u.camp]
		camp["alive"] -= 1
		if camp["alive"] <= 0:
			_capture_camp(u.camp, source_team)
	elif _hero_near(1 - u.team, u.pos, SimConst.XP_SOAK_RANGE):
		_grant_xp(1 - u.team, xp)


func _damage_structure(s: SimStructure, amount: float, source_team: int) -> void:
	if not s.alive or not s.vulnerable:
		return
	s.hp = maxf(0.0, s.hp - amount)
	if s.hp > 0.0:
		return
	s.alive = false
	_update_vulnerability()
	_grant_xp(1 - s.team, SimConst.XP_STRUCTURE)
	events.append(["structure", s.index, source_team])
	if s.kind == SimStructure.KIND_CORE:
		match_over = true
		winner = 1 - s.team
		events.append(["match_end", winner, 0])


## Le camp vaincu rejoint l'équipe qui a porté le dernier coup : ses mercenaires
## partent pousser la voie voisine.
func _capture_camp(index: int, team: int) -> void:
	var camp: Dictionary = camps[index]
	camp["alive"] = 0
	camp["timer"] = SimConst.CAMP_RESPAWN
	if team != SimConst.TEAM_DAWN and team != SimConst.TEAM_DUSK:
		return
	events.append(["camp", team, index])
	var def: Dictionary = arena.camps[index]
	var lane: int = def["lane"]
	var forward := 1.0 if team == SimConst.TEAM_DAWN else -1.0
	var full := arena.lane_path(lane, team)
	# Rejoindre la voie un peu en avant du camp, puis la suivre jusqu'au bout.
	var join := Vector2(forward * 10.0, full[1].y)
	var path: Array[Vector2] = [join]
	for point in full:
		if point.x * forward > join.x * forward:
			path.append(point)
	var guards: Array = def["guards"]
	for point: Vector2 in guards:
		var u := _spawn_unit(UnitDefs.GUARDIAN, team, point)
		if u != null:
			u.path = path


func _grant_xp(team: int, amount: float) -> void:
	if team != SimConst.TEAM_DAWN and team != SimConst.TEAM_DUSK:
		return
	if team_level[team] >= SimConst.MAX_LEVEL:
		return
	team_xp[team] += amount
	while team_level[team] < SimConst.MAX_LEVEL and team_xp[team] >= SimConst.xp_needed(team_level[team]):
		team_xp[team] -= SimConst.xp_needed(team_level[team])
		team_level[team] += 1
		events.append(["level", team, team_level[team]])
		for id in heroes:
			var h: SimHero = heroes[id]
			if h.team != team:
				continue
			var ratio := h.hp / maxf(h.max_hp, 1.0)
			h.max_hp = _hero_max_hp(h)
			h.hp = h.max_hp * ratio


func _hero_near(team: int, pos: Vector2, distance: float) -> bool:
	for id in heroes:
		var h: SimHero = heroes[id]
		if h.alive and h.team == team and h.pos.distance_to(pos) <= distance:
			return true
	return false


func _hero_max_hp(h: SimHero) -> float:
	var base: float = HeroDefs.get_def(h.def_id)["max_hp"]
	return base * SimConst.level_multiplier(team_level[h.team])


# ---------------------------------------------------------------------------
# Mise en place
# ---------------------------------------------------------------------------

func _setup_match() -> void:
	structures.clear()
	for i in arena.structures.size():
		structures.append(SimStructure.from_def(i, arena.structures[i]))
	_update_vulnerability()
	units.clear()
	_units_by_id.clear()
	projectiles.clear()
	beams.clear()
	team_kills = [0, 0]
	team_level = [1, 1]
	team_xp = [0.0, 0.0]
	relic_active = false
	relic_timer = SimConst.RELIC_FIRST
	relic_progress = [0.0, 0.0]
	camps.clear()
	for i in arena.camps.size():
		camps.append({"alive": 0, "timer": SimConst.CAMP_FIRST})
	_wave_timer = SimConst.FIRST_WAVE
	match_over = false
	winner = -1
	relics_taken = 0
	_match_start_tick = tick


func _place_at_spawn(h: SimHero) -> void:
	var points: Array = arena.spawns[h.team]
	h.pos = points[h.spawn_slot % points.size()]
	h.facing = Vector2.RIGHT if h.team == SimConst.TEAM_DAWN else Vector2.LEFT
	h.hp = h.max_hp
	h.alive = true
	h.respawn_left = 0.0
	h.dash_left = 0.0
	h.dash_vel = Vector2.ZERO
	h.channeling = false
	h.last_hit_tick = -100000
	for i in h.cooldowns.size():
		h.cooldowns[i] = 0.0


func _free_spawn_slot(team: int) -> int:
	var used: Array[int] = []
	for id in heroes:
		var h: SimHero = heroes[id]
		if h.team == team:
			used.append(h.spawn_slot)
	var slot := 0
	while used.has(slot):
		slot += 1
	return slot


# ---------------------------------------------------------------------------
# Photographie pour le réseau
# ---------------------------------------------------------------------------

## Photographie binaire du monde, envoyée aux clients à chaque pas. Elle doit tenir dans
## un seul paquet (moins de 1392 octets) : d'où les plafonds sur chaque liste.
## Le format est décodé par SimSnapshot.from_bytes().
func to_snapshot() -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_u32(tick)
	buf.put_u8((1 if match_over else 0) | ((winner & 1) << 1 if winner >= 0 else 0))
	buf.put_u8(team_level[0])
	buf.put_u8(team_level[1])
	buf.put_u16(clampi(int(team_xp[0]), 0, 0xFFFF))
	buf.put_u16(clampi(int(team_xp[1]), 0, 0xFFFF))
	buf.put_u16(mini(team_kills[0], 0xFFFF))
	buf.put_u16(mini(team_kills[1], 0xFFFF))
	buf.put_u8(1 if relic_active else 0)
	buf.put_u16(clampi(ceili(relic_timer * 10.0), 0, 0xFFFF))
	buf.put_u8(clampi(roundi(relic_progress[0] * 255.0), 0, 255))
	buf.put_u8(clampi(roundi(relic_progress[1] * 255.0), 0, 255))

	buf.put_u8(camps.size())
	for camp in camps:
		buf.put_u8(mini(camp["alive"], 255))
		buf.put_u16(clampi(ceili(camp["timer"] * 10.0), 0, 0xFFFF))

	buf.put_u8(structures.size())
	for s in structures:
		s.write_state(buf)

	buf.put_u8(heroes.size())
	for id in heroes:
		var h: SimHero = heroes[id]
		h.write(buf)

	var unit_count := mini(units.size(), SimConst.MAX_UNITS_HARD)
	buf.put_u8(unit_count)
	for i in unit_count:
		units[i].write(buf)

	var projectile_count := mini(projectiles.size(), SimSnapshot.MAX_PROJECTILES)
	buf.put_u8(projectile_count)
	for i in projectile_count:
		projectiles[i].write(buf)

	var beam_count := mini(beams.size(), SimSnapshot.MAX_BEAMS)
	buf.put_u8(beam_count)
	for i in beam_count:
		var beam: Array = beams[i]
		var from: Vector2 = beam[1]
		var to: Vector2 = beam[2]
		buf.put_u8(beam[0])
		buf.put_16(SimConst.quantize(from.x))
		buf.put_16(SimConst.quantize(from.y))
		buf.put_16(SimConst.quantize(to.x))
		buf.put_16(SimConst.quantize(to.y))
	return buf.data_array
