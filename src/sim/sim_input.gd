class_name SimInput
extends RefCounted
## Commande d'un joueur pour un pas de simulation.

## Numéro croissant donné par le client ; le serveur le renvoie pour la réconciliation.
var seq: int = 0
## Direction de déplacement, longueur 0 à 1.
var move: Vector2 = Vector2.ZERO
## Point visé, en coordonnées du monde.
var aim: Vector2 = Vector2.ZERO
## Masque des boutons maintenus (SimConst.BTN_*).
var buttons: int = 0


## Taille d'une commande sur le réseau, en octets.
const WIRE_SIZE := 21
## Nombre maximal de commandes dans un même envoi.
const MAX_BATCH := 8


func write(buf: StreamPeerBuffer) -> void:
	buf.put_u32(seq)
	buf.put_float(move.x)
	buf.put_float(move.y)
	buf.put_float(aim.x)
	buf.put_float(aim.y)
	buf.put_u8(buttons)


## Lit une commande reçue du réseau. Renvoie null si elle contient une valeur invalide.
static func read(buf: StreamPeerBuffer) -> SimInput:
	var cmd := SimInput.new()
	cmd.seq = buf.get_u32()
	var raw_move := Vector2(buf.get_float(), buf.get_float())
	var raw_aim := Vector2(buf.get_float(), buf.get_float())
	cmd.buttons = buf.get_u8()
	if not (raw_move.is_finite() and raw_aim.is_finite()):
		return null
	cmd.move = raw_move.limit_length(1.0)
	cmd.aim = raw_aim.clampf(-1000.0, 1000.0)
	return cmd


static func encode_batch(cmds: Array[SimInput]) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	for cmd in cmds:
		cmd.write(buf)
	return buf.data_array


## Décode un envoi de commandes. Renvoie un tableau vide s'il est mal formé.
static func decode_batch(data: PackedByteArray) -> Array[SimInput]:
	var out: Array[SimInput] = []
	if data.is_empty() or data.size() % WIRE_SIZE != 0 or data.size() > WIRE_SIZE * MAX_BATCH:
		return out
	var buf := StreamPeerBuffer.new()
	buf.data_array = data
	for i in data.size() / WIRE_SIZE:
		var cmd := SimInput.read(buf)
		if cmd == null:
			out.clear()
			return out
		out.append(cmd)
	return out
