class_name HeroDefs
## Fiches des héros : caractéristiques et capacités, décrites en données.
## L'indice d'une capacité dans "abilities" est son créneau (bouton 1 << indice).
##
## Types de capacité :
##   "projectile" : cooldown, damage, speed, range, radius, pierce
##   "dash"       : cooldown, distance, duration

const DEFAULT_HERO := "sagitta"

const DEFS: Dictionary = {
	"sagitta": {
		"name_key": "HERO_SAGITTA",
		"role": "assassin",
		"max_hp": 1000.0,
		"speed": 6.0,
		"radius": 0.6,
		"abilities": [
			{
				"name_key": "ABILITY_SAGITTA_ATTACK",
				"type": "projectile",
				"cooldown": 0.6,
				"damage": 90.0,
				"speed": 22.0,
				"range": 9.5,
				"radius": 0.22,
				"pierce": false,
			},
			{
				"name_key": "ABILITY_SAGITTA_BOLT",
				"type": "projectile",
				"cooldown": 6.0,
				"damage": 260.0,
				"speed": 30.0,
				"range": 16.0,
				"radius": 0.35,
				"pierce": true,
			},
			{
				"name_key": "ABILITY_SAGITTA_STEP",
				"type": "dash",
				"cooldown": 8.0,
				"distance": 6.0,
				"duration": 0.2,
			},
		],
	},
}


static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, DEFS[DEFAULT_HERO])


## Numéro d'un héros sur le réseau : son rang dans DEFS.
static func index_of(id: String) -> int:
	return maxi(DEFS.keys().find(id), 0)


static func id_at(index: int) -> String:
	var ids: Array = DEFS.keys()
	return ids[index] if index >= 0 and index < ids.size() else DEFAULT_HERO
