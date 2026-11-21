class_name SimUnit
extends RefCounted
## Unité non jouée : sbire d'une voie, mercenaire recruté ou gardien de camp.

const TARGET_NONE := 0
const TARGET_HERO := 1
const TARGET_UNIT := 2
const TARGET_STRUCTURE := 3

## Taille d'une unité dans une photographie, en octets.
const WIRE_SIZE := 9

var id: int = 0
## Rang de sa fiche dans UnitDefs.DEFS.
var kind: int = 0
var team: int = 0
var pos: Vector2 = Vector2.ZERO
var hp: float = 0.0
var max_hp: float = 1.0
var alive: bool = true
## Vrai pendant le pas où l'unité a frappé (sert à l'animation).
var attacked: bool = false

# --- Connu du serveur seulement ---
## Points à suivre, dans le sens de la marche.
var path: Array[Vector2] = []
var wp: int = 0
## Décalage par rapport au chemin, pour marcher en formation.
var offset: Vector2 = Vector2.ZERO
var target_type: int = TARGET_NONE
var target_id: int = 0
var attack_cd: float = 0.0
## Camp gardé (gardiens neutres), sinon -1.
var camp: int = -1
var home: Vector2 = Vector2.ZERO


func write(buf: StreamPeerBuffer) -> void:
	buf.put_u16(id)
	buf.put_u8(kind)
	buf.put_u8((team & 3) | (4 if attacked else 0))
	buf.put_16(SimConst.quantize(pos.x))
	buf.put_16(SimConst.quantize(pos.y))
	buf.put_u8(clampi(ceili(hp / maxf(max_hp, 1.0) * 255.0), 1, 255))


static func read(buf: StreamPeerBuffer) -> SimUnit:
	var u := SimUnit.new()
	u.id = buf.get_u16()
	u.kind = clampi(buf.get_u8(), 0, UnitDefs.DEFS.size() - 1)
	var flags := buf.get_u8()
	u.team = mini(flags & 3, SimConst.TEAM_NEUTRAL)
	u.attacked = (flags & 4) != 0
	u.pos = Vector2(buf.get_16(), buf.get_16()) / 100.0
	u.max_hp = UnitDefs.get_def(u.kind)["max_hp"]
	u.hp = buf.get_u8() / 255.0 * u.max_hp
	return u
