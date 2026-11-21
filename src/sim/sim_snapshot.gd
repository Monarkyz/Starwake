class_name SimSnapshot
extends RefCounted
## Photographie de la simulation reçue du serveur, côté client.
## Elle expose les mêmes noms que SimWorld (heroes, units, structures, relic_active,
## arena) pour que le cerveau des bots puisse lire l'une ou l'autre.

const HEADER_SIZE := 20
const BEAM_SIZE := 9
const MAX_PROJECTILES := 16
const MAX_BEAMS := 12

var arena: SimArena
var tick: int = 0
var match_over: bool = false
var winner: int = -1
var team_level: Array[int] = [1, 1]
var team_xp: Array[float] = [0.0, 0.0]
var team_kills: Array[int] = [0, 0]
var relic_active: bool = false
var relic_timer: float = 0.0
var relic_progress: Array[float] = [0.0, 0.0]
## État des camps : {alive, timer}.
var camps: Array[Dictionary] = []
var structures: Array[SimStructure] = []
var heroes: Dictionary = {}  # id -> SimHero
var units: Array[SimUnit] = []
var projectiles: Array[SimProjectile] = []
## Attaques instantanées : [type, départ, arrivée].
var beams: Array = []


## Décode les octets produits par SimWorld.to_snapshot(). La carte fournit ce qui ne
## voyage pas (position des bâtiments, etc.). Renvoie null si les octets sont mal formés.
static func from_bytes(data: PackedByteArray, p_arena: SimArena) -> SimSnapshot:
	if data.size() < HEADER_SIZE:
		return null
	var buf := StreamPeerBuffer.new()
	buf.data_array = data
	var snap := SimSnapshot.new()
	snap.arena = p_arena
	snap.tick = buf.get_u32()
	var flags := buf.get_u8()
	snap.match_over = (flags & 1) != 0
	snap.winner = (flags >> 1) & 1 if snap.match_over else -1
	snap.team_level = [buf.get_u8(), buf.get_u8()]
	snap.team_xp = [float(buf.get_u16()), float(buf.get_u16())]
	snap.team_kills = [buf.get_u16(), buf.get_u16()]
	snap.relic_active = buf.get_u8() != 0
	snap.relic_timer = buf.get_u16() / 10.0
	snap.relic_progress = [buf.get_u8() / 255.0, buf.get_u8() / 255.0]

	var camp_count := _count(buf, 3)
	if camp_count < 0:
		return null
	for i in camp_count:
		snap.camps.append({"alive": buf.get_u8(), "timer": buf.get_u16() / 10.0})

	var structure_count := _count(buf, SimStructure.WIRE_SIZE)
	if structure_count != p_arena.structures.size():
		return null
	for i in structure_count:
		var s := SimStructure.from_def(i, p_arena.structures[i])
		s.read_state(buf)
		snap.structures.append(s)

	var hero_count := _count(buf, SimHero.WIRE_SIZE)
	if hero_count < 0:
		return null
	for i in hero_count:
		var h := SimHero.read(buf)
		snap.heroes[h.id] = h

	var unit_count := _count(buf, SimUnit.WIRE_SIZE)
	if unit_count < 0:
		return null
	for i in unit_count:
		snap.units.append(SimUnit.read(buf))

	var projectile_count := _count(buf, SimProjectile.WIRE_SIZE)
	if projectile_count < 0:
		return null
	for i in projectile_count:
		snap.projectiles.append(SimProjectile.read(buf))

	var beam_count := _count(buf, BEAM_SIZE)
	if beam_count < 0:
		return null
	for i in beam_count:
		var kind := buf.get_u8()
		var from := Vector2(buf.get_16(), buf.get_16()) / 100.0
		var to := Vector2(buf.get_16(), buf.get_16()) / 100.0
		snap.beams.append([kind, from, to])

	if buf.get_available_bytes() != 0:
		return null
	return snap


## Lit le nombre d'éléments d'une liste et vérifie qu'il reste assez d'octets pour elle.
## Renvoie -1 sinon.
static func _count(buf: StreamPeerBuffer, item_size: int) -> int:
	if buf.get_available_bytes() < 1:
		return -1
	var count := buf.get_u8()
	if buf.get_available_bytes() < count * item_size:
		return -1
	return count
