class_name SimStructure
extends RefCounted
## Bâtiment d'une équipe : temple d'une voie ou sanctuaire final.
## Sa position et ses caractéristiques viennent de la carte (SimArena.structures) ;
## seuls sa vie et son état voyagent sur le réseau.

const KIND_TEMPLE := 0
const KIND_CORE := 1

## Taille de l'état d'un bâtiment dans une photographie, en octets.
const WIRE_SIZE := 3

## Rang dans SimArena.structures.
var index: int = 0
var team: int = 0
var kind: int = KIND_TEMPLE
## Voie défendue, ou -1 pour le sanctuaire.
var lane: int = -1
## 0 : temple extérieur, 1 : temple intérieur, 2 : sanctuaire.
var tier: int = 0
var pos: Vector2 = Vector2.ZERO
var radius: float = 2.0
var max_hp: float = 1.0
var hp: float = 1.0
var alive: bool = true
## Un bâtiment n'est attaquable qu'une fois celui qui le précède détruit.
var vulnerable: bool = false
var damage: float = 0.0
var attack_range: float = 0.0
var cooldown: float = 1.0
var attack_cd: float = 0.0


static func from_def(p_index: int, def: Dictionary) -> SimStructure:
	var s := SimStructure.new()
	s.index = p_index
	s.team = def["team"]
	s.kind = def["kind"]
	s.lane = def["lane"]
	s.tier = def["tier"]
	s.pos = def["pos"]
	s.radius = def["radius"]
	s.max_hp = def["max_hp"]
	s.hp = s.max_hp
	s.damage = def["damage"]
	s.attack_range = def["range"]
	s.cooldown = def["cooldown"]
	return s


func write_state(buf: StreamPeerBuffer) -> void:
	buf.put_u16(clampi(ceili(hp), 0, 0xFFFF))
	buf.put_u8((1 if alive else 0) | (2 if vulnerable else 0))


func read_state(buf: StreamPeerBuffer) -> void:
	hp = buf.get_u16()
	var flags := buf.get_u8()
	alive = (flags & 1) != 0
	vulnerable = (flags & 2) != 0
