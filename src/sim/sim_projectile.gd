class_name SimProjectile
extends RefCounted
## Projectile en vol.

var id: int = 0
## Créneau de la capacité qui l'a lancé (sert à choisir son apparence).
var kind: int = 0
var team: int = 0
var owner_id: int = 0
var pos: Vector2 = Vector2.ZERO
var vel: Vector2 = Vector2.ZERO
var radius: float = 0.25
var damage: float = 0.0
var range_left: float = 0.0
## Un projectile perforant traverse les héros et touche chacun une seule fois.
var pierce: bool = false
var hit_ids: Array[int] = []


## Taille d'un projectile dans une photographie, en octets.
const WIRE_SIZE := 26


func write(buf: StreamPeerBuffer) -> void:
	buf.put_u32(id)
	buf.put_u8(kind)
	buf.put_u8(team)
	buf.put_float(pos.x)
	buf.put_float(pos.y)
	buf.put_float(vel.x)
	buf.put_float(vel.y)
	buf.put_float(radius)


static func read(buf: StreamPeerBuffer) -> SimProjectile:
	var p := SimProjectile.new()
	p.id = buf.get_u32()
	p.kind = buf.get_u8()
	p.team = buf.get_u8() & 1
	p.pos = Vector2(buf.get_float(), buf.get_float())
	p.vel = Vector2(buf.get_float(), buf.get_float())
	p.radius = buf.get_float()
	return p
