extends SceneTree
## Le tutoriel doit pouvoir se jouer du début à la fin : un pilote automatique accomplit
## chaque étape dans la simulation, sans réseau ni affichage.
## Lancement : godot --headless --path . -s tests/test_tutorial.gd

const MAX_MINUTES := 8.0


func _init() -> void:
	var world := TutorialDirector.make_world()
	var hero := world.add_hero(SimConst.TEAM_DAWN, TutorialDirector.HERO)
	var director := TutorialDirector.new()
	var pilot := TutorialPilot.new()
	var reached: Array[int] = []
	var times: Array[float] = []
	var failures := 0
	var deaths := 0
	var was_alive := true

	var max_ticks := int(MAX_MINUTES * 60.0 * SimConst.TICK_RATE)
	while director.step < TutorialDirector.STEP_DONE and world.tick < max_ticks:
		var inputs: Dictionary = {}
		if director.step >= 0:
			inputs[hero.id] = pilot.think(hero, world, director.step)
		world.step(inputs)
		if director.update(world, hero):
			reached.append(director.step)
			times.append(world.tick * SimConst.DT)
		if director.step == TutorialDirector.STEP_TALENT and world.tick % SimConst.TICK_RATE == 0:
			world.choose_talent(hero.id, 0, 1)
		if was_alive and not hero.alive:
			deaths += 1
		was_alive = hero.alive

	for i in reached.size():
		print("step %d reached at %.1f s" % [reached[i], times[i]])
	var expected: Array[int] = []
	for i in TutorialDirector.STEP_COUNT:
		expected.append(i)
	failures += _check(reached == expected, "every step is reached, in order (%s)" % [reached])
	failures += _check(world.match_over and world.winner == SimConst.TEAM_DAWN, "the tutorial ends with the player's victory")
	failures += _check(world.team_level[SimConst.TEAM_DAWN] >= 3 and hero.talents[0] != 0, "the player levels up and picks a talent")
	failures += _check(world.relics_taken == 1, "the relic is captured once")
	failures += _check(deaths <= 1, "an attentive player barely dies (%d deaths)" % deaths)
	var minutes := world.tick * SimConst.DT / 60.0
	failures += _check(minutes >= 0.5 and minutes <= 6.0, "the tutorial takes a few minutes (%.1f)" % minutes)
	# Chaque étape a son texte, pour le clavier et pour le tactile quand il diffère.
	var french: Translation = load("res://i18n/fr.po")
	var english: Translation = load("res://i18n/en.po")
	for i in TutorialDirector.STEP_COUNT:
		for translation: Translation in [french, english]:
			failures += _check(not String(translation.get_message("TUTORIAL_%d" % i)).is_empty(), "step %d has its text" % i)
	# Sans joueur attentif : le scénario ne doit pas avancer tout seul.
	var idle_world := TutorialDirector.make_world()
	var idle_hero := idle_world.add_hero(SimConst.TEAM_DAWN, TutorialDirector.HERO)
	var idle := TutorialDirector.new()
	for i in SimConst.TICK_RATE * 60:
		idle_world.step({})
		idle.update(idle_world, idle_hero)
	failures += _check(idle.step == TutorialDirector.STEP_MOVE, "the tutorial waits for the player (step %d)" % idle.step)
	failures += _check(idle_world.units.is_empty() and idle_world.team_level == [1, 1] and not idle_world.relic_active, "nothing happens on its own in the tutorial world")

	print("tutorial: %.1f minutes, %d deaths, %d failures" % [minutes, deaths, failures])
	quit(1 if failures > 0 else 0)


func _check(condition: bool, label: String) -> int:
	if condition:
		return 0
	printerr("FAIL: " + label)
	return 1
