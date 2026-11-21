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
# Effets appliqués au héros touché (connus du serveur seulement).
var stun_ticks: int = 0
var slow_ticks: int = 0
var slow_pct: int = 0
## Déplacement imposé à la cible : positif, elle est repoussée ; négatif, attirée vers le lanceur.
var knockback: float = 0.0
## Part des dégâts rendue en vie au lanceur.
var lifesteal: float = 0.0
## Cibles déjà touchées : type de cible * SimWorld.TARGET_KEY + identifiant.
var hit_ids: Array[int] = []


## Taille d'un projectile dans une photographie, en octets.
const WIRE_SIZE := 13


func write(buf: StreamPeerBuffer) -> void:
	buf.put_u16(id)
	buf.put_u8(kind)
	buf.put_u8(team & 1)
	buf.put_16(SimConst.quantize(pos.x))
	buf.put_16(SimConst.quantize(pos.y))
	buf.put_16(SimConst.quantize(vel.x))
	buf.put_16(SimConst.quantize(vel.y))
	buf.put_u8(clampi(roundi(radius * 100.0), 0, 255))


static func read(buf: StreamPeerBuffer) -> SimProjectile:
	var p := SimProjectile.new()
	p.id = buf.get_u16()
	p.kind = buf.get_u8()
	p.team = buf.get_u8() & 1
	p.pos = Vector2(buf.get_16(), buf.get_16()) / 100.0
	p.vel = Vector2(buf.get_16(), buf.get_16()) / 100.0
	p.radius = buf.get_u8() / 100.0
	return p
