class_name UnitDefs
## Fiches des unités non jouées : sbires des voies et gardiens des camps.
## Le rang d'une fiche dans DEFS est le "kind" de l'unité.
##
##   range          portée d'attaque, mesurée jusqu'au bord de la cible
##   aggro          distance à laquelle l'unité repère un adversaire
##   structure_mult multiplicateur de dégâts contre les temples et le sanctuaire
##   ranged         attaque à distance (affichée par un trait)

const FOOTMAN := 0
const ARCHER := 1
const GUARDIAN := 2
## Mannequin du tutoriel : immobile et inoffensif.
const DUMMY := 3

const DEFS: Array[Dictionary] = [
	{
		"id": "footman", "max_hp": 320.0, "speed": 3.6, "radius": 0.45,
		"damage": 20.0, "cooldown": 1.0, "range": 1.0, "aggro": 6.5,
		"xp": 30.0, "structure_mult": 1.0, "ranged": false,
	},
	{
		"id": "archer", "max_hp": 220.0, "speed": 3.6, "radius": 0.4,
		"damage": 28.0, "cooldown": 1.2, "range": 6.0, "aggro": 7.5,
		"xp": 30.0, "structure_mult": 1.0, "ranged": true,
	},
	{
		"id": "guardian", "max_hp": 1300.0, "speed": 3.8, "radius": 0.8,
		"damage": 65.0, "cooldown": 1.1, "range": 1.2, "aggro": 6.0,
		"xp": 90.0, "structure_mult": 1.5, "ranged": false,
	},
	{
		"id": "dummy", "max_hp": 250.0, "speed": 0.0, "radius": 0.5,
		"damage": 0.0, "cooldown": 1.0, "range": 0.0, "aggro": 0.0,
		"xp": 0.0, "structure_mult": 0.0, "ranged": false,
	},
]

## Composition d'une vague : [kind, décalage latéral].
const WAVE: Array = [
	[FOOTMAN, Vector2(0.0, -1.2)],
	[FOOTMAN, Vector2(0.0, 0.0)],
	[FOOTMAN, Vector2(0.0, 1.2)],
	[ARCHER, Vector2(0.0, 0.6)],
]


static func get_def(kind: int) -> Dictionary:
	return DEFS[clampi(kind, 0, DEFS.size() - 1)]
