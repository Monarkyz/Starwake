class_name SimSnapshot
extends RefCounted
## Photographie de la simulation reçue du serveur, côté client.

const HEADER_SIZE := 10

var tick: int = 0
var team_kills: Array[int] = [0, 0]
var heroes: Dictionary = {}  # id -> SimHero
var projectiles: Array[SimProjectile] = []


## Décode les octets produits par SimWorld.to_snapshot(). Renvoie null s'ils sont mal formés.
static func from_bytes(data: PackedByteArray) -> SimSnapshot:
	if data.size() < HEADER_SIZE:
		return null
	var buf := StreamPeerBuffer.new()
	buf.data_array = data
	var snap := SimSnapshot.new()
	snap.tick = buf.get_u32()
	snap.team_kills = [buf.get_u16(), buf.get_u16()]
	var hero_count := buf.get_u8()
	var projectile_count := buf.get_u8()
	var expected := HEADER_SIZE + hero_count * SimHero.WIRE_SIZE + projectile_count * SimProjectile.WIRE_SIZE
	if data.size() != expected:
		return null
	for i in hero_count:
		var h := SimHero.read(buf)
		snap.heroes[h.id] = h
	for i in projectile_count:
		snap.projectiles.append(SimProjectile.read(buf))
	return snap
