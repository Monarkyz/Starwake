class_name HeroDefs
## Fiches des héros : caractéristiques, capacités et talents, décrits en données.
##
## L'indice d'une capacité dans "abilities" est son créneau (bouton 1 << indice) :
## 0 attaque de base, 1 et 2 capacités, 3 capacité ultime de l'éveil ("awakening": true,
## déclenchée par la jauge d'éther et non par une recharge).
##
## Types de capacité :
##   "projectile" : cooldown, damage, speed, range, radius, pierce
##   "volley"     : comme projectile, plus count et spread (degrés ; 360 : tout autour)
##   "melee"      : cooldown, damage, range (depuis le centre du héros), arc (degrés)
##   "zone"       : cooldown, damage, range, radius, delay ; option self (centrée sur le héros).
##                  Annoncée au sol, elle frappe après le délai.
##   "dash"       : cooldown, distance, duration ; option aim (part vers le point visé plutôt
##                  que dans le sens de la marche) ; avec damage, elle frappe au passage
##   "shield"     : cooldown, amount, duration
##   "heal_area"  : cooldown, amount, range, radius ; options : self (centré sur le héros), shield
##   "haste"      : cooldown, haste (part de vitesse gagnée), duration, radius (0 : soi seulement,
##                  sinon tous les alliés autour)
##
## Effets en option sur projectile, volley, melee, zone et dash offensif :
##   stun (secondes) · slow (0 à 1) avec slow_duration · knockback (distance ; négatif :
##   la cible est attirée vers le lanceur) · lifesteal (part des dégâts rendue en vie)
##
## "ai" indique aux bots quand appuyer : "damage" (adversaire à portée), "engage" (ruée vers
## l'adversaire), "escape" (repli), "shield" (blessé et menacé), "heal" (allié blessé),
## "haste" (combat ou repli), "awaken" (combat de héros).
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
	"ursa": {
		"name_key": "HERO_URSA",
		"role_key": "ROLE_TANK",
		"look": "tank",
		"max_hp": 1600.0,
		"speed": 5.8,
		"radius": 0.75,
		"preferred_range": 1.6,
		"abilities": [
			{"name_key": "ABILITY_URSA_ATTACK", "type": "melee", "ai": "damage", "cooldown": 0.8, "damage": 95.0, "range": 2.6, "arc": 120.0},
			{"name_key": "ABILITY_URSA_CHARGE", "type": "dash", "ai": "engage", "cooldown": 9.0, "distance": 7.0, "duration": 0.25, "damage": 140.0, "knockback": 2.5},
			{"name_key": "ABILITY_URSA_ROAR", "type": "melee", "ai": "damage", "cooldown": 10.0, "damage": 90.0, "range": 4.0, "arc": 360.0, "slow": 0.4, "slow_duration": 2.5},
			{"name_key": "ABILITY_URSA_ULT", "type": "heal_area", "ai": "awaken", "awakening": true, "cooldown": 0.0, "amount": 500.0, "range": 0.0, "radius": 1.0, "self": true, "shield": 350.0},
		],
		"talents": [
			[
				{"name_key": "TALENT_URSA_1A", "desc_key": "TALENT_URSA_1A_DESC", "mods": [{"slot": -1, "key": "max_hp", "mult": 1.15}]},
				{"name_key": "TALENT_URSA_1B", "desc_key": "TALENT_URSA_1B_DESC", "mods": [{"slot": 0, "key": "damage", "mult": 1.25}]},
			],
			[
				{"name_key": "TALENT_URSA_2A", "desc_key": "TALENT_URSA_2A_DESC", "mods": [{"slot": 1, "key": "cooldown", "mult": 0.7}]},
				{"name_key": "TALENT_URSA_2B", "desc_key": "TALENT_URSA_2B_DESC", "mods": [{"slot": 2, "key": "slow_duration", "mult": 1.5}]},
			],
			[
				{"name_key": "TALENT_URSA_3A", "desc_key": "TALENT_URSA_3A_DESC", "mods": [{"slot": 1, "key": "damage", "mult": 1.5}]},
				{"name_key": "TALENT_URSA_3B", "desc_key": "TALENT_URSA_3B_DESC", "mods": [{"slot": -1, "key": "speed", "mult": 1.1}]},
			],
		],
	},
	"corvus": {
		"name_key": "HERO_CORVUS",
		"role_key": "ROLE_ASSASSIN",
		"look": "duelist",
		"max_hp": 950.0,
		"speed": 6.4,
		"radius": 0.55,
		"preferred_range": 1.5,
		"abilities": [
			{"name_key": "ABILITY_CORVUS_ATTACK", "type": "melee", "ai": "damage", "cooldown": 0.55, "damage": 85.0, "range": 2.4, "arc": 100.0, "lifesteal": 0.15},
			{"name_key": "ABILITY_CORVUS_DIVE", "type": "dash", "ai": "engage", "aim": true, "cooldown": 7.0, "distance": 6.5, "duration": 0.18, "damage": 180.0},
			{"name_key": "ABILITY_CORVUS_NIGHT", "type": "haste", "ai": "haste", "cooldown": 11.0, "haste": 0.4, "duration": 3.0, "radius": 0.0},
			{"name_key": "ABILITY_CORVUS_ULT", "type": "volley", "ai": "awaken", "awakening": true, "cooldown": 0.0, "damage": 150.0, "speed": 26.0, "range": 7.0, "radius": 0.3, "pierce": true, "count": 12.0, "spread": 360.0},
		],
		"talents": [
			[
				{"name_key": "TALENT_CORVUS_1A", "desc_key": "TALENT_CORVUS_1A_DESC", "mods": [{"slot": 0, "key": "damage", "mult": 1.2}]},
				{"name_key": "TALENT_CORVUS_1B", "desc_key": "TALENT_CORVUS_1B_DESC", "mods": [{"slot": 1, "key": "cooldown", "mult": 0.75}]},
			],
			[
				{"name_key": "TALENT_CORVUS_2A", "desc_key": "TALENT_CORVUS_2A_DESC", "mods": [{"slot": 2, "key": "duration", "mult": 1.5}]},
				{"name_key": "TALENT_CORVUS_2B", "desc_key": "TALENT_CORVUS_2B_DESC", "mods": [{"slot": 0, "key": "lifesteal", "mult": 2.0}]},
			],
			[
				{"name_key": "TALENT_CORVUS_3A", "desc_key": "TALENT_CORVUS_3A_DESC", "mods": [{"slot": 1, "key": "damage", "mult": 1.4}]},
				{"name_key": "TALENT_CORVUS_3B", "desc_key": "TALENT_CORVUS_3B_DESC", "mods": [{"slot": -1, "key": "max_hp", "mult": 1.15}]},
			],
		],
	},
	"crater": {
		"name_key": "HERO_CRATER",
		"role_key": "ROLE_SUPPORT",
		"look": "support",
		"max_hp": 920.0,
		"speed": 6.0,
		"radius": 0.55,
		"preferred_range": 8.0,
		"abilities": [
			{"name_key": "ABILITY_CRATER_ATTACK", "type": "projectile", "ai": "damage", "cooldown": 0.7, "damage": 60.0, "speed": 22.0, "range": 9.5, "radius": 0.22, "pierce": false},
			{"name_key": "ABILITY_CRATER_NECTAR", "type": "heal_area", "ai": "heal", "cooldown": 5.0, "amount": 160.0, "range": 9.0, "radius": 2.6},
			{"name_key": "ABILITY_CRATER_HASTE", "type": "haste", "ai": "haste", "cooldown": 12.0, "haste": 0.3, "duration": 3.0, "radius": 6.0},
			{"name_key": "ABILITY_CRATER_ULT", "type": "heal_area", "ai": "awaken", "awakening": true, "cooldown": 0.0, "amount": 250.0, "range": 0.0, "radius": 9.0, "self": true, "shield": 400.0},
		],
		"talents": [
			[
				{"name_key": "TALENT_CRATER_1A", "desc_key": "TALENT_CRATER_1A_DESC", "mods": [{"slot": 1, "key": "amount", "mult": 1.2}]},
				{"name_key": "TALENT_CRATER_1B", "desc_key": "TALENT_CRATER_1B_DESC", "mods": [{"slot": 1, "key": "cooldown", "mult": 0.8}]},
			],
			[
				{"name_key": "TALENT_CRATER_2A", "desc_key": "TALENT_CRATER_2A_DESC", "mods": [{"slot": 2, "key": "radius", "mult": 1.4}]},
				{"name_key": "TALENT_CRATER_2B", "desc_key": "TALENT_CRATER_2B_DESC", "mods": [{"slot": 2, "key": "duration", "mult": 1.4}]},
			],
			[
				{"name_key": "TALENT_CRATER_3A", "desc_key": "TALENT_CRATER_3A_DESC", "mods": [{"slot": 1, "key": "radius", "mult": 1.4}]},
				{"name_key": "TALENT_CRATER_3B", "desc_key": "TALENT_CRATER_3B_DESC", "mods": [{"slot": 0, "key": "damage", "mult": 1.3}]},
			],
		],
	},
	"cetus": {
		"name_key": "HERO_CETUS",
		"role_key": "ROLE_TANK",
		"look": "tank",
		"max_hp": 1900.0,
		"speed": 5.3,
		"radius": 0.85,
		"preferred_range": 1.7,
		"abilities": [
			{"name_key": "ABILITY_CETUS_ATTACK", "type": "melee", "ai": "damage", "cooldown": 1.0, "damage": 120.0, "range": 2.8, "arc": 130.0},
			{"name_key": "ABILITY_CETUS_WAVE", "type": "projectile", "ai": "damage", "cooldown": 9.0, "damage": 130.0, "speed": 14.0, "range": 10.0, "radius": 0.9, "pierce": true, "knockback": 3.0},
			{"name_key": "ABILITY_CETUS_SHELL", "type": "shield", "ai": "shield", "cooldown": 13.0, "amount": 550.0, "duration": 4.0},
			{"name_key": "ABILITY_CETUS_ULT", "type": "zone", "ai": "awaken", "awakening": true, "cooldown": 0.0, "damage": 280.0, "range": 0.0, "radius": 7.0, "delay": 0.8, "self": true, "stun": 1.2},
		],
		"talents": [
			[
				{"name_key": "TALENT_CETUS_1A", "desc_key": "TALENT_CETUS_1A_DESC", "mods": [{"slot": -1, "key": "max_hp", "mult": 1.12}]},
				{"name_key": "TALENT_CETUS_1B", "desc_key": "TALENT_CETUS_1B_DESC", "mods": [{"slot": 0, "key": "damage", "mult": 1.25}]},
			],
			[
				{"name_key": "TALENT_CETUS_2A", "desc_key": "TALENT_CETUS_2A_DESC", "mods": [{"slot": 1, "key": "knockback", "mult": 1.5}]},
				{"name_key": "TALENT_CETUS_2B", "desc_key": "TALENT_CETUS_2B_DESC", "mods": [{"slot": 2, "key": "amount", "mult": 1.35}]},
			],
			[
				{"name_key": "TALENT_CETUS_3A", "desc_key": "TALENT_CETUS_3A_DESC", "mods": [{"slot": 1, "key": "cooldown", "mult": 0.7}]},
				{"name_key": "TALENT_CETUS_3B", "desc_key": "TALENT_CETUS_3B_DESC", "mods": [{"slot": 2, "key": "cooldown", "mult": 0.7}]},
			],
		],
	},
	"corona": {
		"name_key": "HERO_CORONA",
		"role_key": "ROLE_ASSASSIN",
		"look": "mage",
		"max_hp": 880.0,
		"speed": 6.0,
		"radius": 0.55,
		"preferred_range": 8.5,
		"abilities": [
			{"name_key": "ABILITY_CORONA_ATTACK", "type": "projectile", "ai": "damage", "cooldown": 0.7, "damage": 80.0, "speed": 24.0, "range": 10.0, "radius": 0.22, "pierce": false},
			{"name_key": "ABILITY_CORONA_STAR", "type": "zone", "ai": "damage", "cooldown": 7.0, "damage": 250.0, "range": 11.0, "radius": 3.0, "delay": 0.8},
			{"name_key": "ABILITY_CORONA_BLINK", "type": "dash", "ai": "escape", "aim": true, "cooldown": 10.0, "distance": 5.5, "duration": 0.1},
			{"name_key": "ABILITY_CORONA_ULT", "type": "zone", "ai": "awaken", "awakening": true, "cooldown": 0.0, "damage": 480.0, "range": 11.0, "radius": 5.5, "delay": 0.8, "slow": 0.5, "slow_duration": 2.0},
		],
		"talents": [
			[
				{"name_key": "TALENT_CORONA_1A", "desc_key": "TALENT_CORONA_1A_DESC", "mods": [{"slot": 1, "key": "radius", "mult": 1.25}]},
				{"name_key": "TALENT_CORONA_1B", "desc_key": "TALENT_CORONA_1B_DESC", "mods": [{"slot": 0, "key": "damage", "mult": 1.2}]},
			],
			[
				{"name_key": "TALENT_CORONA_2A", "desc_key": "TALENT_CORONA_2A_DESC", "mods": [{"slot": 1, "key": "cooldown", "mult": 0.75}]},
				{"name_key": "TALENT_CORONA_2B", "desc_key": "TALENT_CORONA_2B_DESC", "mods": [{"slot": 2, "key": "cooldown", "mult": 0.7}]},
			],
			[
				{"name_key": "TALENT_CORONA_3A", "desc_key": "TALENT_CORONA_3A_DESC", "mods": [{"slot": 1, "key": "damage", "mult": 1.35}]},
				{"name_key": "TALENT_CORONA_3B", "desc_key": "TALENT_CORONA_3B_DESC", "mods": [{"slot": 1, "key": "range", "mult": 1.3}]},
			],
		],
	},
	"delphinus": {
		"name_key": "HERO_DELPHINUS",
		"role_key": "ROLE_SUPPORT",
		"look": "support",
		"max_hp": 950.0,
		"speed": 6.2,
		"radius": 0.55,
		"preferred_range": 7.5,
		"abilities": [
			{"name_key": "ABILITY_DELPHINUS_ATTACK", "type": "projectile", "ai": "damage", "cooldown": 0.7, "damage": 62.0, "speed": 22.0, "range": 9.5, "radius": 0.22, "pierce": false},
			{"name_key": "ABILITY_DELPHINUS_WAVE", "type": "heal_area", "ai": "heal", "cooldown": 8.0, "amount": 170.0, "range": 0.0, "radius": 5.5, "self": true},
			{"name_key": "ABILITY_DELPHINUS_SURF", "type": "projectile", "ai": "damage", "cooldown": 9.0, "damage": 90.0, "speed": 20.0, "range": 11.0, "radius": 0.6, "pierce": false, "knockback": 4.5},
			{"name_key": "ABILITY_DELPHINUS_ULT", "type": "haste", "ai": "awaken", "awakening": true, "cooldown": 0.0, "haste": 0.5, "duration": 5.0, "radius": 9.0},
		],
		"talents": [
			[
				{"name_key": "TALENT_DELPHINUS_1A", "desc_key": "TALENT_DELPHINUS_1A_DESC", "mods": [{"slot": 1, "key": "amount", "mult": 1.2}]},
				{"name_key": "TALENT_DELPHINUS_1B", "desc_key": "TALENT_DELPHINUS_1B_DESC", "mods": [{"slot": -1, "key": "speed", "mult": 1.1}]},
			],
			[
				{"name_key": "TALENT_DELPHINUS_2A", "desc_key": "TALENT_DELPHINUS_2A_DESC", "mods": [{"slot": 1, "key": "radius", "mult": 1.3}]},
				{"name_key": "TALENT_DELPHINUS_2B", "desc_key": "TALENT_DELPHINUS_2B_DESC", "mods": [{"slot": 2, "key": "cooldown", "mult": 0.7}]},
			],
			[
				{"name_key": "TALENT_DELPHINUS_3A", "desc_key": "TALENT_DELPHINUS_3A_DESC", "mods": [{"slot": 1, "key": "cooldown", "mult": 0.75}]},
				{"name_key": "TALENT_DELPHINUS_3B", "desc_key": "TALENT_DELPHINUS_3B_DESC", "mods": [{"slot": 2, "key": "knockback", "mult": 1.5}]},
			],
		],
	},
	"centaurus": {
		"name_key": "HERO_CENTAURUS",
		"role_key": "ROLE_TANK",
		"look": "tank",
		"max_hp": 1650.0,
		"speed": 6.2,
		"radius": 0.8,
		"preferred_range": 1.7,
		"abilities": [
			{"name_key": "ABILITY_CENTAURUS_ATTACK", "type": "melee", "ai": "damage", "cooldown": 0.9, "damage": 105.0, "range": 3.0, "arc": 70.0},
			{"name_key": "ABILITY_CENTAURUS_KICK", "type": "melee", "ai": "damage", "cooldown": 9.0, "damage": 130.0, "range": 3.2, "arc": 140.0, "knockback": 5.0},
			{"name_key": "ABILITY_CENTAURUS_GALLOP", "type": "haste", "ai": "haste", "cooldown": 12.0, "haste": 0.5, "duration": 3.0, "radius": 0.0},
			{"name_key": "ABILITY_CENTAURUS_ULT", "type": "dash", "ai": "awaken", "awakening": true, "aim": true, "cooldown": 0.0, "distance": 11.0, "duration": 0.35, "damage": 320.0, "stun": 1.2},
		],
		"talents": [
			[
				{"name_key": "TALENT_CENTAURUS_1A", "desc_key": "TALENT_CENTAURUS_1A_DESC", "mods": [{"slot": -1, "key": "max_hp", "mult": 1.12}]},
				{"name_key": "TALENT_CENTAURUS_1B", "desc_key": "TALENT_CENTAURUS_1B_DESC", "mods": [{"slot": 0, "key": "damage", "mult": 1.2}]},
			],
			[
				{"name_key": "TALENT_CENTAURUS_2A", "desc_key": "TALENT_CENTAURUS_2A_DESC", "mods": [{"slot": 2, "key": "duration", "mult": 1.4}]},
				{"name_key": "TALENT_CENTAURUS_2B", "desc_key": "TALENT_CENTAURUS_2B_DESC", "mods": [{"slot": 1, "key": "knockback", "mult": 1.4}]},
			],
			[
				{"name_key": "TALENT_CENTAURUS_3A", "desc_key": "TALENT_CENTAURUS_3A_DESC", "mods": [{"slot": 1, "key": "cooldown", "mult": 0.7}]},
				{"name_key": "TALENT_CENTAURUS_3B", "desc_key": "TALENT_CENTAURUS_3B_DESC", "mods": [{"slot": 2, "key": "haste", "mult": 1.4}]},
			],
		],
	},
	"lynx": {
		"name_key": "HERO_LYNX",
		"role_key": "ROLE_ASSASSIN",
		"look": "archer",
		"max_hp": 930.0,
		"speed": 6.3,
		"radius": 0.55,
		"preferred_range": 8.0,
		"abilities": [
			{"name_key": "ABILITY_LYNX_ATTACK", "type": "projectile", "ai": "damage", "cooldown": 0.5, "damage": 70.0, "speed": 26.0, "range": 9.5, "radius": 0.2, "pierce": false},
			{"name_key": "ABILITY_LYNX_LASSO", "type": "projectile", "ai": "damage", "cooldown": 10.0, "damage": 110.0, "speed": 26.0, "range": 11.0, "radius": 0.4, "pierce": false, "knockback": -5.0},
			{"name_key": "ABILITY_LYNX_LEAP", "type": "dash", "ai": "escape", "cooldown": 7.0, "distance": 6.0, "duration": 0.2},
			{"name_key": "ABILITY_LYNX_ULT", "type": "volley", "ai": "awaken", "awakening": true, "cooldown": 0.0, "damage": 300.0, "speed": 32.0, "range": 15.0, "radius": 0.35, "pierce": true, "count": 3.0, "spread": 16.0, "stun": 1.0},
		],
		"talents": [
			[
				{"name_key": "TALENT_LYNX_1A", "desc_key": "TALENT_LYNX_1A_DESC", "mods": [{"slot": 0, "key": "damage", "mult": 1.2}]},
				{"name_key": "TALENT_LYNX_1B", "desc_key": "TALENT_LYNX_1B_DESC", "mods": [{"slot": 2, "key": "cooldown", "mult": 0.7}]},
			],
			[
				{"name_key": "TALENT_LYNX_2A", "desc_key": "TALENT_LYNX_2A_DESC", "mods": [{"slot": 1, "key": "cooldown", "mult": 0.7}]},
				{"name_key": "TALENT_LYNX_2B", "desc_key": "TALENT_LYNX_2B_DESC", "mods": [{"slot": 1, "key": "range", "mult": 1.25}]},
			],
			[
				{"name_key": "TALENT_LYNX_3A", "desc_key": "TALENT_LYNX_3A_DESC", "mods": [{"slot": 0, "key": "cooldown", "mult": 0.85}]},
				{"name_key": "TALENT_LYNX_3B", "desc_key": "TALENT_LYNX_3B_DESC", "mods": [{"slot": -1, "key": "speed", "mult": 1.1}]},
			],
		],
	},
	"ara": {
		"name_key": "HERO_ARA",
		"role_key": "ROLE_SUPPORT",
		"look": "mage",
		"max_hp": 940.0,
		"speed": 5.9,
		"radius": 0.55,
		"preferred_range": 8.0,
		"abilities": [
			{"name_key": "ABILITY_ARA_ATTACK", "type": "projectile", "ai": "damage", "cooldown": 0.7, "damage": 64.0, "speed": 22.0, "range": 9.5, "radius": 0.22, "pierce": false},
			{"name_key": "ABILITY_ARA_HEARTH", "type": "heal_area", "ai": "heal", "cooldown": 7.0, "amount": 200.0, "range": 9.5, "radius": 3.0},
			{"name_key": "ABILITY_ARA_EMBERS", "type": "zone", "ai": "damage", "cooldown": 9.0, "damage": 110.0, "range": 10.0, "radius": 3.2, "delay": 0.8, "slow": 0.45, "slow_duration": 2.5},
			{"name_key": "ABILITY_ARA_ULT", "type": "heal_area", "ai": "awaken", "awakening": true, "cooldown": 0.0, "amount": 350.0, "range": 0.0, "radius": 8.0, "self": true, "shield": 300.0},
		],
		"talents": [
			[
				{"name_key": "TALENT_ARA_1A", "desc_key": "TALENT_ARA_1A_DESC", "mods": [{"slot": 1, "key": "amount", "mult": 1.2}]},
				{"name_key": "TALENT_ARA_1B", "desc_key": "TALENT_ARA_1B_DESC", "mods": [{"slot": 2, "key": "damage", "mult": 1.4}]},
			],
			[
				{"name_key": "TALENT_ARA_2A", "desc_key": "TALENT_ARA_2A_DESC", "mods": [{"slot": 2, "key": "slow_duration", "mult": 1.5}]},
				{"name_key": "TALENT_ARA_2B", "desc_key": "TALENT_ARA_2B_DESC", "mods": [{"slot": 1, "key": "cooldown", "mult": 0.8}]},
			],
			[
				{"name_key": "TALENT_ARA_3A", "desc_key": "TALENT_ARA_3A_DESC", "mods": [{"slot": 1, "key": "radius", "mult": 1.35}]},
				{"name_key": "TALENT_ARA_3B", "desc_key": "TALENT_ARA_3B_DESC", "mods": [{"slot": 2, "key": "radius", "mult": 1.3}]},
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


## Rôles, dans l'ordre d'affichage.
const ROLES: Array[String] = ["ROLE_TANK", "ROLE_ASSASSIN", "ROLE_SUPPORT"]


static func ids_by_role(role_key: String) -> Array:
	var out: Array = []
	for id: String in DEFS:
		if DEFS[id]["role_key"] == role_key:
			out.append(id)
	return out


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
