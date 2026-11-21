class_name SimHero
extends RefCounted
## État d'un héros dans la simulation.

## Taille d'un héros dans une photographie, en octets.
const WIRE_SIZE := 62

var id: int = 0
var team: int = 0
var def_id: String = HeroDefs.DEFAULT_HERO
var pos: Vector2 = Vector2.ZERO
var facing: Vector2 = Vector2.RIGHT
var hp: float = 0.0
var max_hp: float = 0.0
var alive: bool = true
var respawn_left: float = 0.0
## Temps de recharge restant des créneaux 0 à 2 (l'éveil dépend de l'éther, pas d'une recharge).
var cooldowns: Array[float] = [0.0, 0.0, 0.0]
var dash_left: float = 0.0
var dash_vel: Vector2 = Vector2.ZERO
## Dernière commande du joueur prise en compte par le serveur.
var last_seq: int = 0
var kills: int = 0
var deaths: int = 0
## Vrai quand le héros canalise la relique.
var channeling: bool = false

## Jauge d'éther, de 0 à SimConst.ETHER_MAX.
var ether: float = 0.0
# Les durées d'état se comptent en pas de simulation : exactes sur le réseau, donc
# rejouées à l'identique par la prédiction du client.
## Pas d'éveil restants.
var awaken_ticks: int = 0
## Étourdi : ni déplacement ni action.
var stun_ticks: int = 0
var slow_ticks: int = 0
## Ralentissement subi, en pourcentage de vitesse perdue.
var slow_pct: int = 0
var haste_ticks: int = 0
## Hâte reçue, en pourcentage de vitesse gagnée.
var haste_pct: int = 0
## Points de bouclier : absorbent les dégâts avant la vie.
var shield: float = 0.0
## Talent choisi à chaque palier : 0 aucun, 1 ou 2.
var talents: Array[int] = [0, 0, 0]

# --- Connu du serveur seulement ---
## Emplacement de réapparition dans son équipe.
var spawn_slot: int = 0
## Pas de simulation du dernier dégât reçu.
var last_hit_tick: int = -100000
## Vrai quand le joueur ne donne aucune commande (condition pour canaliser).
var idle: bool = false
var shield_ticks: int = 0
## Vrai pendant le pas où l'éveil vient d'être déclenché.
var just_awakened: bool = false
## Créneau de la ruée en cours (pour ses dégâts au contact), ou -1.
var dash_slot: int = -1
## Cibles déjà touchées par la ruée en cours.
var dash_hits: Array[int] = []


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
	h.channeling = channeling
	h.ether = ether
	h.awaken_ticks = awaken_ticks
	h.stun_ticks = stun_ticks
	h.slow_ticks = slow_ticks
	h.slow_pct = slow_pct
	h.haste_ticks = haste_ticks
	h.haste_pct = haste_pct
	h.shield = shield
	h.talents = talents.duplicate()
	h.spawn_slot = spawn_slot
	h.last_hit_tick = last_hit_tick
	h.idle = idle
	h.shield_ticks = shield_ticks
	h.just_awakened = just_awakened
	h.dash_slot = dash_slot
	return h


func is_awakened() -> bool:
	return awaken_ticks > 0


func write(buf: StreamPeerBuffer) -> void:
	buf.put_u16(id)
	buf.put_u8((team & 1) | (2 if alive else 0) | (4 if channeling else 0))
	buf.put_u8(HeroDefs.index_of(def_id))
	# La position reste en précision complète : le client s'en sert pour recaler sa prédiction.
	buf.put_float(pos.x)
	buf.put_float(pos.y)
	buf.put_16(roundi(facing.angle() * 10000.0))
	buf.put_u16(clampi(ceili(hp), 0, 0xFFFF))
	buf.put_u16(clampi(ceili(max_hp), 0, 0xFFFF))
	buf.put_u16(clampi(ceili(respawn_left * 100.0), 0, 0xFFFF))
	for i in 3:
		buf.put_float(cooldowns[i])
	buf.put_float(dash_left)
	buf.put_float(dash_vel.x)
	buf.put_float(dash_vel.y)
	buf.put_u32(last_seq)
	buf.put_u16(mini(kills, 0xFFFF))
	buf.put_u16(mini(deaths, 0xFFFF))
	# Arrondi vers le bas : le client ne voit la jauge pleine que si elle l'est vraiment.
	buf.put_u8(clampi(int(ether), 0, 255))
	buf.put_u8(clampi(awaken_ticks, 0, 255))
	buf.put_u8(clampi(stun_ticks, 0, 255))
	buf.put_u8(clampi(slow_ticks, 0, 255))
	buf.put_u8(clampi(slow_pct, 0, 100))
	buf.put_u8(clampi(haste_ticks, 0, 255))
	buf.put_u8(clampi(haste_pct, 0, 200))
	buf.put_u16(clampi(ceili(shield), 0, 0xFFFF))
	buf.put_u8((talents[0] & 3) | ((talents[1] & 3) << 2) | ((talents[2] & 3) << 4))


static func read(buf: StreamPeerBuffer) -> SimHero:
	var h := SimHero.new()
	h.id = buf.get_u16()
	var flags := buf.get_u8()
	h.team = flags & 1
	h.alive = (flags & 2) != 0
	h.channeling = (flags & 4) != 0
	h.def_id = HeroDefs.id_at(buf.get_u8())
	h.pos = Vector2(buf.get_float(), buf.get_float())
	h.facing = Vector2.from_angle(buf.get_16() / 10000.0)
	h.hp = buf.get_u16()
	h.max_hp = buf.get_u16()
	h.respawn_left = buf.get_u16() / 100.0
	for i in 3:
		h.cooldowns[i] = buf.get_float()
	h.dash_left = buf.get_float()
	h.dash_vel = Vector2(buf.get_float(), buf.get_float())
	h.last_seq = buf.get_u32()
	h.kills = buf.get_u16()
	h.deaths = buf.get_u16()
	h.ether = buf.get_u8()
	h.awaken_ticks = buf.get_u8()
	h.stun_ticks = buf.get_u8()
	h.slow_ticks = buf.get_u8()
	h.slow_pct = mini(buf.get_u8(), 100)
	h.haste_ticks = buf.get_u8()
	h.haste_pct = mini(buf.get_u8(), 200)
	h.shield = buf.get_u16()
	var packed := buf.get_u8()
	h.talents = [mini(packed & 3, 2), mini((packed >> 2) & 3, 2), mini((packed >> 4) & 3, 2)]
	return h
