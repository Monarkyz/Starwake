class_name SimArena
extends RefCounted
## Carte : tout ce qui est fixe pendant une partie. Terrain, piliers, voies,
## emplacement des bâtiments, des camps, de l'autel et des points d'apparition.
##
## Une carte vide (SimArena.new()) n'a ni voie ni bâtiment : pratique pour les tests.

## Demi-dimensions du terrain, centré sur l'origine.
var half_size: Vector2 = Vector2(22.0, 13.0)
## Piliers : (x, y, rayon). Ils arrêtent les déplacements et les projectiles.
var pillars: Array[Vector3] = []
## Bâtiments encore debout : (x, y, rayon). Ils arrêtent les héros, pas les projectiles
## (qui les touchent) ni les unités. Tenu à jour par set_structures_alive().
var structure_blockers: Array[Vector3] = []
## Points d'apparition des héros, par équipe.
var spawns: Array = [[], []]
## Centre de la fontaine de soin de chaque équipe (vide : pas de fontaine).
var fountains: Array[Vector2] = []
## Voies : chacune est une suite de points allant de la base de l'Aube à celle du Crépuscule.
var lanes: Array = []
## Bâtiments : {team, kind, lane, tier, pos, radius, max_hp, damage, range, cooldown}.
var structures: Array[Dictionary] = []
## Camps de mercenaires : {pos, lane, guards: [positions]}.
var camps: Array[Dictionary] = []
var has_altar: bool = false
var altar: Vector2 = Vector2.ZERO
var altar_radius: float = 3.0


static func make_default() -> SimArena:
	return make_sanctuary()


## Le sanctuaire : deux voies, deux temples par voie et par équipe, un sanctuaire
## final de chaque côté, l'autel de la relique au centre, un camp près de chaque voie.
static func make_sanctuary() -> SimArena:
	var a := SimArena.new()
	a.half_size = Vector2(58.0, 32.0)
	a.pillars = [
		Vector3(-12.0, -10.0, 1.5), Vector3(12.0, -10.0, 1.5),
		Vector3(-12.0, 10.0, 1.5), Vector3(12.0, 10.0, 1.5),
		Vector3(-24.0, 0.0, 2.0), Vector3(24.0, 0.0, 2.0),
		Vector3(-34.0, -8.0, 1.5), Vector3(-34.0, 8.0, 1.5),
		Vector3(34.0, -8.0, 1.5), Vector3(34.0, 8.0, 1.5),
	]
	a.spawns = [
		[Vector2(-54.0, -4.0), Vector2(-54.0, 4.0), Vector2(-54.0, 0.0)],
		[Vector2(54.0, -4.0), Vector2(54.0, 4.0), Vector2(54.0, 0.0)],
	]
	a.fountains = [Vector2(-54.0, 0.0), Vector2(54.0, 0.0)]
	a.lanes = [
		[Vector2(-45.0, -7.0), Vector2(-38.0, -20.0), Vector2(38.0, -20.0), Vector2(45.0, -7.0)],
		[Vector2(-45.0, 7.0), Vector2(-38.0, 20.0), Vector2(38.0, 20.0), Vector2(45.0, 7.0)],
	]
	for team in 2:
		var side := -1.0 if team == SimConst.TEAM_DAWN else 1.0
		for lane in 2:
			var y := -20.0 if lane == 0 else 20.0
			a.structures.append(_temple(team, lane, 0, Vector2(side * 16.0, y), 7000.0))
			a.structures.append(_temple(team, lane, 1, Vector2(side * 32.0, y), 8500.0))
		a.structures.append({
			"team": team, "kind": SimStructure.KIND_CORE, "lane": -1, "tier": 2,
			"pos": Vector2(side * 48.0, 0.0), "radius": 3.0, "max_hp": 14000.0,
			"damage": 180.0, "range": 14.0, "cooldown": 1.0,
		})
	a.camps = [
		{"pos": Vector2(0.0, -9.0), "lane": 0, "guards": [Vector2(-1.6, -9.0), Vector2(1.6, -9.0)]},
		{"pos": Vector2(0.0, 9.0), "lane": 1, "guards": [Vector2(-1.6, 9.0), Vector2(1.6, 9.0)]},
	]
	a.has_altar = true
	a.altar = Vector2.ZERO
	a.altar_radius = 3.0
	var all_alive: Array[bool] = []
	all_alive.resize(a.structures.size())
	all_alive.fill(true)
	a.set_structures_alive(all_alive)
	return a


static func _temple(team: int, lane: int, tier: int, pos: Vector2, max_hp: float) -> Dictionary:
	return {
		"team": team, "kind": SimStructure.KIND_TEMPLE, "lane": lane, "tier": tier,
		"pos": pos, "radius": 2.0, "max_hp": max_hp,
		# La portée dépasse celle des héros : impossible d'assiéger un temple sans s'exposer.
		"damage": 130.0, "range": 13.0, "cooldown": 1.0,
	}


## Indique quels bâtiments sont debout, pour qu'ils bloquent le passage des héros.
func set_structures_alive(alive: Array[bool]) -> void:
	structure_blockers.clear()
	for i in mini(alive.size(), structures.size()):
		if alive[i]:
			var def: Dictionary = structures[i]
			var pos: Vector2 = def["pos"]
			var radius: float = def["radius"]
			structure_blockers.append(Vector3(pos.x, pos.y, radius))


## Points d'une voie dans le sens de marche de l'équipe donnée.
func lane_path(lane: int, team: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	out.assign(lanes[lane])
	if team == SimConst.TEAM_DUSK:
		out.reverse()
	return out


## Ramène un héros à une position valide : hors des piliers et des bâtiments, dans le terrain.
func resolve_circle(pos: Vector2, radius: float) -> Vector2:
	var p := pos
	for _pass in 2:
		p = _push_out(p, radius, pillars)
		p = _push_out(p, radius, structure_blockers)
		p.x = clampf(p.x, -half_size.x + radius, half_size.x - radius)
		p.y = clampf(p.y, -half_size.y + radius, half_size.y - radius)
	return p


## Comme resolve_circle, mais sans tenir compte des bâtiments (unités non jouées).
func resolve_unit(pos: Vector2, radius: float) -> Vector2:
	var p := _push_out(pos, radius, pillars)
	p.x = clampf(p.x, -half_size.x + radius, half_size.x - radius)
	p.y = clampf(p.y, -half_size.y + radius, half_size.y - radius)
	return p


func is_inside(pos: Vector2) -> bool:
	return absf(pos.x) <= half_size.x and absf(pos.y) <= half_size.y


## Fraction (0 à 1) du segment à laquelle un cercle mobile touche un pilier ; 2.0 s'il n'en touche aucun.
func segment_block_fraction(from: Vector2, to: Vector2, radius: float) -> float:
	var best := 2.0
	for pillar in pillars:
		var t := segment_circle_fraction(from, to, Vector2(pillar.x, pillar.y), pillar.z + radius)
		if t < best:
			best = t
	return best


## Fraction (0 à 1) du segment à laquelle il entre dans le cercle ; 2.0 s'il ne le touche pas.
static func segment_circle_fraction(from: Vector2, to: Vector2, center: Vector2, radius: float) -> float:
	var d := to - from
	var f := from - center
	var c := f.dot(f) - radius * radius
	if c <= 0.0:
		return 0.0
	var a := d.dot(d)
	if a < 0.000000001:
		return 2.0
	var b := 2.0 * f.dot(d)
	var disc := b * b - 4.0 * a * c
	if disc < 0.0:
		return 2.0
	var t := (-b - sqrt(disc)) / (2.0 * a)
	if t < 0.0 or t > 1.0:
		return 2.0
	return t


static func _push_out(pos: Vector2, radius: float, circles: Array[Vector3]) -> Vector2:
	var p := pos
	for circle in circles:
		var center := Vector2(circle.x, circle.y)
		var min_dist := circle.z + radius
		var offset := p - center
		var dist := offset.length()
		if dist < min_dist:
			if dist < 0.0001:
				offset = Vector2.RIGHT
				dist = 1.0
			p = center + offset / dist * min_dist
	return p
