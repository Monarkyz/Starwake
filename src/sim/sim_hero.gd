class_name SimHero
extends RefCounted
## État d'un héros dans la simulation.

var id: int = 0
var team: int = 0
var def_id: String = HeroDefs.DEFAULT_HERO
var pos: Vector2 = Vector2.ZERO
var facing: Vector2 = Vector2.RIGHT
var hp: float = 0.0
var max_hp: float = 0.0
var alive: bool = true
var respawn_left: float = 0.0
## Temps de recharge restant par créneau de capacité.
var cooldowns: Array[float] = [0.0, 0.0, 0.0]
var dash_left: float = 0.0
var dash_vel: Vector2 = Vector2.ZERO
## Dernière commande du joueur prise en compte par le serveur.
var last_seq: int = 0
var kills: int = 0
var deaths: int = 0

## Emplacement de réapparition dans son équipe (non transmis).
var spawn_slot: int = 0


func copy() -> SimHero:
	var h := SimHero.new()
	h.id = id
	h.team = team
	h.def_id = def_id
	h.pos = pos
	h.facing = facing
	h.hp = hp
	h.max_hp = max_hp
	h.alive = alive
	h.respawn_left = respawn_left
	h.cooldowns = cooldowns.duplicate()
	h.dash_left = dash_left
	h.dash_vel = dash_vel
	h.last_seq = last_seq
	h.kills = kills
	h.deaths = deaths
	h.spawn_slot = spawn_slot
	return h


## Taille d'un héros dans une photographie, en octets.
const WIRE_SIZE := 68


func write(buf: StreamPeerBuffer) -> void:
	buf.put_u32(id)
	buf.put_u8(team)
	buf.put_u8(HeroDefs.index_of(def_id))
	buf.put_u8(1 if alive else 0)
	buf.put_u8(0)
	buf.put_float(pos.x)
	buf.put_float(pos.y)
	buf.put_float(facing.x)
	buf.put_float(facing.y)
	buf.put_float(hp)
	buf.put_float(max_hp)
	buf.put_float(respawn_left)
	for i in 3:
		buf.put_float(cooldowns[i])
	buf.put_float(dash_left)
	buf.put_float(dash_vel.x)
	buf.put_float(dash_vel.y)
	buf.put_u32(last_seq)
	buf.put_u16(mini(kills, 0xFFFF))
	buf.put_u16(mini(deaths, 0xFFFF))


static func read(buf: StreamPeerBuffer) -> SimHero:
	var h := SimHero.new()
	h.id = buf.get_u32()
	h.team = buf.get_u8() & 1
	h.def_id = HeroDefs.id_at(buf.get_u8())
	h.alive = buf.get_u8() != 0
	buf.get_u8()
	h.pos = Vector2(buf.get_float(), buf.get_float())
	h.facing = Vector2(buf.get_float(), buf.get_float())
	h.hp = buf.get_float()
	h.max_hp = buf.get_float()
	h.respawn_left = buf.get_float()
	for i in 3:
		h.cooldowns[i] = buf.get_float()
	h.dash_left = buf.get_float()
	h.dash_vel = Vector2(buf.get_float(), buf.get_float())
	h.last_seq = buf.get_u32()
	h.kills = buf.get_u16()
	h.deaths = buf.get_u16()
	return h
