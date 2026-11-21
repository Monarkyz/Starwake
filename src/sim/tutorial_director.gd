class_name TutorialDirector
extends RefCounted
## Scénario du tutoriel : une séquence solo qui apprend à jouer, étape par étape.
## Le serveur l'appelle après chaque pas de simulation ; il fait apparaître ce dont
## l'étape a besoin et passe à la suivante quand l'objectif est atteint.
##
## Les textes de l'étape n sont TUTORIAL_<n> (et TUTORIAL_<n>_TOUCH pour le tactile).

const HERO := "sagitta"

const STEP_MOVE := 0
const STEP_ATTACK := 1
const STEP_BOLT := 2
const STEP_DASH := 3
const STEP_AWAKEN := 4
const STEP_TALENT := 5
const STEP_TEMPLE := 6
const STEP_RELIC := 7
const STEP_CORE := 8
const STEP_DONE := 9
const STEP_COUNT := 10

## Repère affiché au sol pour les étapes qui demandent d'aller quelque part.
const MARKERS: Dictionary = {
	STEP_MOVE: Vector2(-17.0, 0.0),
	STEP_TEMPLE: Vector2(20.0, 0.0),
	STEP_RELIC: Vector2(8.0, 9.0),
	STEP_CORE: Vector2(32.0, 0.0),
}
const DUMMIES_ATTACK: Array[Vector2] = [Vector2(-8.0, -3.0), Vector2(-6.0, 0.0), Vector2(-8.0, 3.0)]
## Trois mannequins alignés : le tir perforant les traverse tous.
const DUMMIES_BOLT: Array[Vector2] = [Vector2(1.0, 0.0), Vector2(3.5, 0.0), Vector2(6.0, 0.0)]
const GUARD_POS := Vector2(11.0, 0.0)
## Pendant le siège, une vague de sbires alliés arrive régulièrement.
const WAVE_EVERY := 14.0

var step: int = -1

var _targets: Array[SimUnit] = []
var _awakened: bool = false
var _wave_left: float = 0.0


## Monde du tutoriel : sa propre carte, et les règles automatiques coupées.
static func make_world() -> SimWorld:
	var world := SimWorld.new(SimArena.make_tutorial())
	world.auto_waves = false
	world.passive_xp = false
	world.auto_relic = false
	return world


static func marker(p_step: int) -> Vector2:
	return MARKERS.get(p_step, Vector2.INF)


## À appeler après chaque pas de simulation. Renvoie vrai quand l'étape vient de changer.
func update(world: SimWorld, hero: SimHero) -> bool:
	if hero == null:
		return false
	if step < 0:
		_enter(STEP_MOVE, world, hero)
		return true
	if step >= STEP_DONE:
		return false
	if step == STEP_AWAKEN:
		if hero.is_awakened():
			_awakened = true
		elif not _awakened:
			# La jauge reste pleine tant que le joueur n'a pas essayé l'éveil.
			hero.ether = SimConst.ETHER_MAX
	if step >= STEP_TEMPLE and not world.match_over:
		_wave_left -= SimConst.DT
		if _wave_left <= 0.0:
			_wave_left = WAVE_EVERY
			world.spawn_wave(0, SimConst.TEAM_DAWN)
	if not _is_complete(world, hero):
		return false
	_enter(step + 1, world, hero)
	return true


func _is_complete(world: SimWorld, hero: SimHero) -> bool:
	match step:
		STEP_MOVE:
			return hero.pos.distance_to(marker(STEP_MOVE)) < 2.5
		STEP_ATTACK, STEP_BOLT:
			return _targets_down()
		STEP_DASH:
			return hero.dash_left > 0.0 or hero.cooldowns[2] > 0.0
		STEP_AWAKEN:
			return _awakened and _targets_down()
		STEP_TALENT:
			return hero.talents[0] != 0
		STEP_TEMPLE:
			for s in world.structures:
				if s.team == SimConst.TEAM_DUSK and s.kind == SimStructure.KIND_TEMPLE and s.alive:
					return false
			return true
		STEP_RELIC:
			return world.relics_taken > 0
		STEP_CORE:
			return world.match_over
	return false


func _enter(new_step: int, world: SimWorld, hero: SimHero) -> void:
	step = new_step
	_targets.clear()
	match step:
		STEP_ATTACK:
			for pos in DUMMIES_ATTACK:
				_targets.append(world.spawn_static_unit(UnitDefs.DUMMY, SimConst.TEAM_DUSK, pos))
		STEP_BOLT:
			for pos in DUMMIES_BOLT:
				_targets.append(world.spawn_static_unit(UnitDefs.DUMMY, SimConst.TEAM_DUSK, pos))
		STEP_AWAKEN:
			_awakened = false
			hero.ether = SimConst.ETHER_MAX
			_targets.append(world.spawn_static_unit(UnitDefs.GUARDIAN, SimConst.TEAM_DUSK, GUARD_POS))
		STEP_TALENT:
			# Assez d'expérience pour ouvrir le premier palier de talents.
			while world.team_level[SimConst.TEAM_DAWN] < SimConst.TALENT_LEVELS[0]:
				world._grant_xp(SimConst.TEAM_DAWN, SimConst.xp_needed(world.team_level[SimConst.TEAM_DAWN]))
		STEP_TEMPLE:
			_wave_left = 0.0
		STEP_RELIC:
			world.spawn_relic()


func _targets_down() -> bool:
	for u in _targets:
		if u != null and u.alive:
			return false
	return true
