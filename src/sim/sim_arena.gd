class_name SimArena
extends RefCounted
## Géométrie fixe du terrain : un rectangle, des piliers ronds, des points d'apparition.
## Arène provisoire du jalon 1 ; la carte du sanctuaire la remplacera au jalon 2.

## Demi-dimensions du terrain, centré sur l'origine.
var half_size: Vector2 = Vector2(22.0, 13.0)
## Piliers : (x, y, rayon).
var pillars: Array[Vector3] = []
## Points d'apparition, par équipe.
var spawns: Array = [[], []]


static func make_default() -> SimArena:
	var a := SimArena.new()
	a.pillars = [
		Vector3(0.0, 0.0, 2.0),
		Vector3(-8.0, -6.0, 1.2),
		Vector3(-8.0, 6.0, 1.2),
		Vector3(8.0, -6.0, 1.2),
		Vector3(8.0, 6.0, 1.2),
	]
	a.spawns = [
		[Vector2(-19.0, 0.0), Vector2(-19.0, -4.0), Vector2(-19.0, 4.0)],
		[Vector2(19.0, 0.0), Vector2(19.0, -4.0), Vector2(19.0, 4.0)],
	]
	return a


## Ramène un cercle à une position valide : hors des piliers, dans le terrain.
func resolve_circle(pos: Vector2, radius: float) -> Vector2:
	var p := pos
	for _pass in 2:
		for pillar in pillars:
			var center := Vector2(pillar.x, pillar.y)
			var min_dist := pillar.z + radius
			var offset := p - center
			var dist := offset.length()
			if dist < min_dist:
				if dist < 0.0001:
					offset = Vector2.RIGHT
					dist = 1.0
				p = center + offset / dist * min_dist
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
