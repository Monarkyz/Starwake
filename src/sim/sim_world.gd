class_name SimWorld
extends RefCounted
## Simulation du combat, sans aucun nœud ni affichage.
## Le serveur fait autorité : il appelle step() à chaque pas. Le client réutilise
## step_hero_local() pour prédire le déplacement de son propre héros.

var arena: SimArena
var tick: int = 0
var heroes: Dictionary = {}  # id -> SimHero
var projectiles: Array[SimProjectile] = []
var team_kills: Array[int] = [0, 0]
## Événements du dernier pas : {"type": "kill", "killer": id, "victim": id}.
var events: Array = []

var _next_id: int = 1


func _init(p_arena: SimArena = null) -> void:
	arena = p_arena if p_arena != null else SimArena.make_default()


func add_hero(team: int, def_id: String = HeroDefs.DEFAULT_HERO) -> SimHero:
	var def: Dictionary = HeroDefs.get_def(def_id)
	var h := SimHero.new()
	h.id = _next_id
	_next_id += 1
	h.team = team
	h.def_id = def_id
	h.max_hp = def["max_hp"]
	h.spawn_slot = _free_spawn_slot(team)
	_place_at_spawn(h)
	heroes[h.id] = h
	return h


func remove_hero(id: int) -> void:
	heroes.erase(id)


func team_size(team: int) -> int:
	var count := 0
	for id in heroes:
		var h: SimHero = heroes[id]
		if h.team == team:
			count += 1
	return count


## Avance la simulation d'un pas. inputs : id du héros -> SimInput.
func step(inputs: Dictionary) -> void:
	events.clear()
	tick += 1
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
		if not h.alive:
			h.respawn_left -= SimConst.DT
			if h.respawn_left <= 0.0:
				_place_at_spawn(h)
			continue
		step_hero_local(h, cmd, arena, SimConst.DT)
		_step_actions(h, cmd)
	_step_projectiles()


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


## Photographie binaire du monde, envoyée aux clients à chaque pas. Elle doit tenir dans
## un seul paquet : environ 10 + 68 par héros + 26 par projectile, en octets.
func to_snapshot() -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	var shown := mini(projectiles.size(), 255)
	buf.put_u32(tick)
	buf.put_u16(mini(team_kills[0], 0xFFFF))
	buf.put_u16(mini(team_kills[1], 0xFFFF))
	buf.put_u8(heroes.size())
	buf.put_u8(shown)
	for id in heroes:
		var h: SimHero = heroes[id]
		h.write(buf)
	for i in shown:
		projectiles[i].write(buf)
	return buf.data_array


func _step_actions(h: SimHero, cmd: SimInput) -> void:
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
		p.id = _next_id
		_next_id += 1
		p.kind = slot
		p.team = h.team
		p.owner_id = h.id
		p.radius = ability["radius"]
		p.damage = ability["damage"]
		p.range_left = ability["range"]
		p.pierce = ability["pierce"]
		var speed: float = ability["speed"]
		p.vel = h.facing * speed
		p.pos = h.pos + h.facing * (hero_radius + p.radius)
		projectiles.append(p)


func _step_projectiles() -> void:
	var kept: Array[SimProjectile] = []
	for p in projectiles:
		var travel := minf(p.vel.length() * SimConst.DT, p.range_left)
		var from := p.pos
		var to := from + p.vel.normalized() * travel
		var wall := arena.segment_block_fraction(from, to, p.radius)
		var spent := false

		# Héros adverses croisés pendant ce pas, du plus proche au plus lointain.
		var hits: Array = []
		for id in heroes:
			var h: SimHero = heroes[id]
			if not h.alive or h.team == p.team or p.hit_ids.has(h.id):
				continue
			var hero_radius: float = HeroDefs.get_def(h.def_id)["radius"]
			var t := SimArena.segment_circle_fraction(from, to, h.pos, hero_radius + p.radius)
			if t <= 1.0 and t <= wall:
				hits.append([t, h.id])
		hits.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		for hit in hits:
			var target: SimHero = heroes[hit[1]]
			_damage(target, p.damage, p.owner_id)
			p.hit_ids.append(target.id)
			if not p.pierce:
				spent = true
				break

		p.pos = to
		p.range_left -= travel
		if wall <= 1.0 or p.range_left <= 0.001 or not arena.is_inside(p.pos):
			spent = true
		if not spent:
			kept.append(p)
	projectiles = kept


func _damage(target: SimHero, amount: float, source_id: int) -> void:
	if not target.alive:
		return
	target.hp = maxf(0.0, target.hp - amount)
	if target.hp > 0.0:
		return
	target.alive = false
	target.respawn_left = SimConst.RESPAWN_TIME
	target.dash_left = 0.0
	target.deaths += 1
	var killer: SimHero = heroes.get(source_id)
	if killer != null:
		killer.kills += 1
	team_kills[1 - target.team] += 1
	events.append({"type": "kill", "killer": source_id, "victim": target.id})


func _place_at_spawn(h: SimHero) -> void:
	var points: Array = arena.spawns[h.team]
	h.pos = points[h.spawn_slot % points.size()]
	h.facing = Vector2.RIGHT if h.team == SimConst.TEAM_DAWN else Vector2.LEFT
	h.hp = h.max_hp
	h.alive = true
	h.respawn_left = 0.0
	h.dash_left = 0.0
	h.dash_vel = Vector2.ZERO
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
