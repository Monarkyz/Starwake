class_name SimConst
## Constantes partagées par la simulation, le serveur et le client.

## Version du protocole réseau : un client d'une autre version est refusé.
const PROTOCOL_VERSION := 2

## Nombre de pas de simulation par seconde (doit suivre physics_ticks_per_second).
const TICK_RATE := 30
const DT := 1.0 / TICK_RATE

const TEAM_DAWN := 0
const TEAM_DUSK := 1
## Équipe des gardiens de camp, hostiles aux deux autres.
const TEAM_NEUTRAL := 2

## 3 contre 3.
const MAX_PLAYERS := 6

## Le bouton du créneau i d'un héros est le bit (1 << i).
const BTN_ATTACK := 1
const BTN_ABILITY_1 := 2
const BTN_ABILITY_2 := 4

# --- Expérience d'équipe ---------------------------------------------------
const MAX_LEVEL := 20
## Chaque niveau multiplie la vie et les dégâts des héros.
const LEVEL_SCALING := 1.04
const XP_PASSIVE_PER_SECOND := 3.0
## Un sbire adverse ne rapporte de l'expérience que si un héros allié est à cette distance.
const XP_SOAK_RANGE := 14.0
const XP_HERO_KILL := 150.0
const XP_HERO_KILL_PER_LEVEL := 30.0
const XP_STRUCTURE := 500.0

# --- Héros -----------------------------------------------------------------
const RESPAWN_TIME := 5.0
const RESPAWN_PER_LEVEL := 1.0
const RESPAWN_MAX := 30.0
## Sans dégât reçu pendant ce délai, le héros récupère lentement.
const REGEN_DELAY := 6.0
const REGEN_RATE := 0.015
const FOUNTAIN_RADIUS := 7.0
const FOUNTAIN_RATE := 0.12

# --- Sbires ----------------------------------------------------------------
const FIRST_WAVE := 8.0
const WAVE_INTERVAL := 25.0
## Au-delà, les vagues attendent : l'état du monde doit tenir dans un paquet réseau.
const MAX_UNITS := 56
const MAX_UNITS_HARD := 64
## Les unités frappent les bâtiments plus fort à chaque minute de jeu, pour éviter les enlisements.
const SIEGE_GROWTH_PER_MINUTE := 0.2

# --- Relique ---------------------------------------------------------------
const RELIC_FIRST := 60.0
const RELIC_INTERVAL := 75.0
const RELIC_CHANNEL_TIME := 5.0
## Temps pour perdre toute la progression quand plus personne ne canalise.
const RELIC_DECAY_TIME := 2.5
## Un héros touché ne peut pas canaliser pendant ce délai.
const RELIC_INTERRUPT := 1.0
const RELIC_TEMPLE_DAMAGE := 2000.0
const RELIC_CORE_DAMAGE := 1500.0
## Chaque relique prise dans la partie rend la suivante plus forte : les parties se décident.
const RELIC_GROWTH := 0.4

# --- Camps de mercenaires ----------------------------------------------------
const CAMP_FIRST := 30.0
const CAMP_RESPAWN := 100.0
## Distance au camp au-delà de laquelle les gardiens abandonnent la poursuite.
const CAMP_LEASH := 9.0

## Délai entre la fin d'une partie et le début de la suivante.
const MATCH_RESTART_DELAY := 12.0


## Expérience nécessaire pour passer du niveau donné au suivant.
static func xp_needed(level: int) -> float:
	return 600.0 + 130.0 * (level - 1)


static func level_multiplier(level: int) -> float:
	return pow(LEVEL_SCALING, level - 1)


static func respawn_time(level: int) -> float:
	return minf(RESPAWN_TIME + RESPAWN_PER_LEVEL * (level - 1), RESPAWN_MAX)


## Position ou vitesse sur 16 bits pour le réseau, au centième d'unité.
static func quantize(value: float) -> int:
	return clampi(roundi(value * 100.0), -32768, 32767)
