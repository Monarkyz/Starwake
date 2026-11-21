class_name HeroDefs
## Fiches des héros : caractéristiques, capacités et talents, décrits en données.
##
## L'indice d'une capacité dans "abilities" est son créneau (bouton 1 << indice) :
## 0 attaque de base, 1 et 2 capacités, 3 capacité ultime de l'éveil ("awakening": true,
## déclenchée par la jauge d'éther et non par une recharge).
##
## Types de capacité :
##   "projectile" : cooldown, damage, speed, range, radius, pierce
##                  options : slow (0 à 1), slow_duration, stun
##   "volley"     : comme projectile, plus count et spread (degrés)
##   "melee"      : cooldown, damage, range (depuis le centre du héros), arc (degrés)
##                  option : stun
##   "dash"       : cooldown, distance, duration
##   "shield"     : cooldown, amount, duration
##   "heal_area"  : cooldown, amount, range, radius ; options : self (centré sur le héros), shield
##
## "ai" indique aux bots quand appuyer : "damage" (adversaire à portée), "escape" (repli),
## "shield" (blessé et menacé), "heal" (allié blessé), "awaken" (combat de héros).
##
## Talents : un palier par entrée de SimConst.TALENT_LEVELS, deux choix par palier.
## Chaque choix multiplie des valeurs : {slot, key, mult}, slot -1 pour le héros lui-même.

const DEFAULT_HERO := "sagitta"

const DEFS: Dictionary = {
	"sagitta": {
		"name_key": "HERO_SAGITTA",
		"role_key": "ROLE_ASSASSIN",
		"look": "archer",
		"max_hp": 1000.0,
		"speed": 6.0,
		"radius": 0.6,
		"preferred_range": 7.5,
		"abilities": [
			{
				"name_key": "ABILITY_SAGITTA_ATTACK", "type": "projectile", "ai": "damage",
				"cooldown": 0.6, "damage": 90.0, "speed": 22.0, "range": 9.5, "radius": 0.22, "pierce": false,
			},
			{
				"name_key": "ABILITY_SAGITTA_BOLT", "type": "projectile", "ai": "damage",
				"cooldown": 6.0, "damage": 260.0, "speed": 30.0, "range": 16.0, "radius": 0.35, "pierce": true,
			},
			{
				"name_key": "ABILITY_SAGITTA_STEP", "type": "dash", "ai": "escape",
				"cooldown": 8.0, "distance": 6.0, "duration": 0.2,
			},
			{
				"name_key": "ABILITY_SAGITTA_ULT", "type": "volley", "ai": "awaken", "awakening": true,
				"cooldown": 0.0, "damage": 200.0, "speed": 30.0, "range": 14.0, "radius": 0.35, "pierce": true,
				"count": 7.0, "spread": 50.0,
			},
		],
		"talents": [
			[
				{"name_key": "TALENT_SAGITTA_1A", "desc_key": "TALENT_SAGITTA_1A_DESC", "mods": [{"slot": 0, "key": "damage", "mult": 1.2}]},
				{"name_key": "TALENT_SAGITTA_1B", "desc_key": "TALENT_SAGITTA_1B_DESC", "mods": [{"slot": 1, "key": "cooldown", "mult": 0.75}]},
			],
			[
				{"name_key": "TALENT_SAGITTA_2A", "desc_key": "TALENT_SAGITTA_2A_DESC", "mods": [{"slot": 1, "key": "range", "mult": 1.3}]},
				{"name_key": "TALENT_SAGITTA_2B", "desc_key": "TALENT_SAGITTA_2B_DESC", "mods": [{"slot": 2, "key": "cooldown", "mult": 0.65}]},
			],
			[
				{"name_key": "TALENT_SAGITTA_3A", "desc_key": "TALENT_SAGITTA_3A_DESC", "mods": [{"slot": 1, "key": "damage", "mult": 1.4}]},
				{"name_key": "TALENT_SAGITTA_3B", "desc_key": "TALENT_SAGITTA_3B_DESC", "mods": [{"slot": -1, "key": "speed", "mult": 1.12}]},
			],
		],
	},
	"scutum": {
		"name_key": "HERO_SCUTUM",
		"role_key": "ROLE_TANK",
		"look": "tank",
		"max_hp": 1700.0,
		"speed": 5.6,
		"radius": 0.75,
		"preferred_range": 1.6,
		"abilities": [
			{
				"name_key": "ABILITY_SCUTUM_ATTACK", "type": "melee", "ai": "damage",
				"cooldown": 0.9, "damage": 110.0, "range": 2.6, "arc": 120.0,
			},
			{
				"name_key": "ABILITY_SCUTUM_SHOCK", "type": "melee", "ai": "damage",
				"cooldown": 8.0, "damage": 150.0, "range": 4.5, "arc": 100.0, "stun": 1.0,
			},
			{
				"name_key": "ABILITY_SCUTUM_WALL", "type": "shield", "ai": "shield",
				"cooldown": 12.0, "amount": 450.0, "duration": 4.0,
			},
			{
				"name_key": "ABILITY_SCUTUM_ULT", "type": "melee", "ai": "awaken", "awakening": true,
				"cooldown": 0.0, "damage": 300.0, "range": 6.5, "arc": 360.0, "stun": 1.5,
			},
		],
		"talents": [
			[
				{"name_key": "TALENT_SCUTUM_1A", "desc_key": "TALENT_SCUTUM_1A_DESC", "mods": [{"slot": -1, "key": "max_hp", "mult": 1.15}]},
				{"name_key": "TALENT_SCUTUM_1B", "desc_key": "TALENT_SCUTUM_1B_DESC", "mods": [{"slot": 0, "key": "damage", "mult": 1.25}]},
			],
			[
				{"name_key": "TALENT_SCUTUM_2A", "desc_key": "TALENT_SCUTUM_2A_DESC", "mods": [{"slot": 2, "key": "amount", "mult": 1.4}]},
				{"name_key": "TALENT_SCUTUM_2B", "desc_key": "TALENT_SCUTUM_2B_DESC", "mods": [{"slot": 1, "key": "stun", "mult": 1.5}]},
			],
			[
				{"name_key": "TALENT_SCUTUM_3A", "desc_key": "TALENT_SCUTUM_3A_DESC", "mods": [{"slot": -1, "key": "max_hp", "mult": 1.2}]},
				{"name_key": "TALENT_SCUTUM_3B", "desc_key": "TALENT_SCUTUM_3B_DESC", "mods": [{"slot": 2, "key": "cooldown", "mult": 0.7}]},
			],
		],
	},
	"columba": {
		"name_key": "HERO_COLUMBA",
		"role_key": "ROLE_SUPPORT",
		"look": "support",
		"max_hp": 900.0,
		"speed": 6.0,
		"radius": 0.55,
		"preferred_range": 8.0,
		"abilities": [
			{
				"name_key": "ABILITY_COLUMBA_ATTACK", "type": "projectile", "ai": "damage",
				"cooldown": 0.7, "damage": 65.0, "speed": 22.0, "range": 9.5, "radius": 0.22, "pierce": false,
			},
			{
				"name_key": "ABILITY_COLUMBA_HEAL", "type": "heal_area", "ai": "heal",
				"cooldown": 7.0, "amount": 220.0, "range": 10.0, "radius": 3.2,
			},
			{
				"name_key": "ABILITY_COLUMBA_SNARE", "type": "projectile", "ai": "damage",
				"cooldown": 9.0, "damage": 80.0, "speed": 24.0, "range": 12.0, "radius": 0.4, "pierce": false,
				"slow": 0.5, "slow_duration": 2.5,
			},
			{
				"name_key": "ABILITY_COLUMBA_ULT", "type": "heal_area", "ai": "awaken", "awakening": true,
				"cooldown": 0.0, "amount": 400.0, "range": 0.0, "radius": 9.0, "self": true, "shield": 250.0,
			},
		],
		"talents": [
			[
				{"name_key": "TALENT_COLUMBA_1A", "desc_key": "TALENT_COLUMBA_1A_DESC", "mods": [{"slot": 1, "key": "amount", "mult": 1.2}]},
				{"name_key": "TALENT_COLUMBA_1B", "desc_key": "TALENT_COLUMBA_1B_DESC", "mods": [{"slot": 0, "key": "damage", "mult": 1.2}]},
			],
			[
				{"name_key": "TALENT_COLUMBA_2A", "desc_key": "TALENT_COLUMBA_2A_DESC", "mods": [{"slot": 1, "key": "radius", "mult": 1.35}]},
				{"name_key": "TALENT_COLUMBA_2B", "desc_key": "TALENT_COLUMBA_2B_DESC", "mods": [{"slot": 2, "key": "slow_duration", "mult": 1.5}]},
			],
			[
				{"name_key": "TALENT_COLUMBA_3A", "desc_key": "TALENT_COLUMBA_3A_DESC", "mods": [{"slot": 1, "key": "cooldown", "mult": 0.75}]},
				{"name_key": "TALENT_COLUMBA_3B", "desc_key": "TALENT_COLUMBA_3B_DESC", "mods": [{"slot": -1, "key": "speed", "mult": 1.12}]},
			],
		],
	},
}


static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, DEFS[DEFAULT_HERO])


static func has_hero(id: String) -> bool:
	return DEFS.has(id)


static func ids() -> Array:
	return DEFS.keys()


## Numéro d'un héros sur le réseau : son rang dans DEFS.
static func index_of(id: String) -> int:
	return maxi(DEFS.keys().find(id), 0)


static func id_at(index: int) -> String:
	var all: Array = DEFS.keys()
	return all[index] if index >= 0 and index < all.size() else DEFAULT_HERO


## Valeur d'une capacité (slot >= 0) ou du héros (slot -1), talents choisis compris.
static func value(h: SimHero, slot: int, key: String) -> float:
	var def: Dictionary = get_def(h.def_id)
	var base: float
	if slot >= 0:
		var abilities: Array = def["abilities"]
		base = abilities[slot][key]
	else:
		base = def[key]
	var tiers: Array = def["talents"]
	for tier in mini(h.talents.size(), tiers.size()):
		var choice := h.talents[tier]
		if choice <= 0:
			continue
		var options: Array = tiers[tier]
		var mods: Array = options[choice - 1]["mods"]
		for mod: Dictionary in mods:
			if mod["slot"] == slot and mod["key"] == key:
				var mult: float = mod["mult"]
				base *= mult
	return base


## Premier palier de talents ouvert et pas encore choisi, ou -1.
static func pending_talent_tier(h: SimHero, team_level: int) -> int:
	for tier in SimConst.TALENT_LEVELS.size():
		if team_level >= SimConst.TALENT_LEVELS[tier] and h.talents[tier] == 0:
			return tier
	return -1
