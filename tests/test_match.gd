extends SceneTree
## Partie complète entre six bots, simulée en accéléré : elle doit se terminer par la
## destruction d'un sanctuaire, dans une durée raisonnable, sans ralentir le serveur.
## Lancement : godot --headless --path . -s tests/test_match.gd

const MAX_MINUTES := 30.0


func _init() -> void:
	var failures := 0
	for seed_value: int in [11, 23]:
		failures += _play(seed_value)
	print("%d failures" % failures)
	quit(1 if failures > 0 else 0)


func _play(seed_value: int) -> int:
	var world := SimWorld.new()
	var brains: Dictionary = {}
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in SimConst.MAX_PLAYERS:
		# Chaque équipe aligne un tank, un assassin et un soutien tirés au hasard, comme le fait le serveur.
		var hero := world.add_hero(i % 2, GameServer.pick_bot_hero(world, i % 2, rng))
		var brain := BotBrain.new(seed_value * 100 + i)
		brain.lane = hero.spawn_slot % 2
		brain.roamer = hero.spawn_slot >= 2
		brains[hero.id] = brain

	var counts: Dictionary = {"kill": 0, "structure": 0, "relic": 0, "camp": 0, "awaken": 0}
	var max_units := 0
	var max_bytes := 0
	var slowest_usec := 0
	var started := Time.get_ticks_usec()
	var max_ticks := int(MAX_MINUTES * 60.0 * SimConst.TICK_RATE)
	while not world.match_over and world.tick < max_ticks:
		var inputs: Dictionary = {}
		for id: int in brains:
			var brain: BotBrain = brains[id]
			inputs[id] = brain.think(world.heroes[id], world)
		var before := Time.get_ticks_usec()
		world.step(inputs)
		slowest_usec = maxi(slowest_usec, Time.get_ticks_usec() - before)
		if world.tick % SimConst.TICK_RATE == 0:
			for id: int in world.heroes:
				var hero: SimHero = world.heroes[id]
				var tier := HeroDefs.pending_talent_tier(hero, world.team_level[hero.team])
				if tier >= 0:
					world.choose_talent(id, tier, rng.randi_range(1, 2))
		for ev: Array in world.events:
			if counts.has(ev[0]):
				counts[ev[0]] += 1
		max_units = maxi(max_units, world.units.size())
		if world.tick % 30 == 0:
			max_bytes = maxi(max_bytes, world.to_snapshot().size())

	var minutes := world.tick * SimConst.DT / 60.0
	var per_tick_ms := (Time.get_ticks_usec() - started) / 1000.0 / world.tick
	var lineup: Array = [[], []]
	for id: int in world.heroes:
		var hero: SimHero = world.heroes[id]
		lineup[hero.team].append(hero.def_id)
	print("lineup seed=%d dawn=%s dusk=%s" % [seed_value, ",".join(lineup[0]), ",".join(lineup[1])])
	print("seed=%d winner=%d minutes=%.1f levels=%s kills=%s events=%s max_units=%d max_bytes=%d avg_ms=%.2f slowest_ms=%.1f" % [
		seed_value, world.winner, minutes, world.team_level, world.team_kills, counts,
		max_units, max_bytes, per_tick_ms, slowest_usec / 1000.0,
	])

	var failures := 0
	failures += _check(world.match_over and world.winner >= 0, "the match ends with a winner")
	failures += _check(minutes >= 5.0 and minutes <= 25.0, "the match lasts between 5 and 25 minutes (%.1f)" % minutes)
	failures += _check(counts["structure"] >= 3, "at least two temples and a sanctuary fall")
	failures += _check(counts["kill"] >= 1, "heroes get eliminated")
	failures += _check(counts["relic"] >= 1, "the relic gets captured")
	failures += _check(counts["awaken"] >= 3, "heroes awaken during the match (%d)" % counts["awaken"])
	var talents := 0
	for id: int in world.heroes:
		var hero: SimHero = world.heroes[id]
		for choice in hero.talents:
			if choice > 0:
				talents += 1
	failures += _check(talents >= 6, "heroes pick talents as the team levels up (%d)" % talents)
	failures += _check(max_bytes <= 1300, "the world state always fits in one packet (%d bytes)" % max_bytes)
	# Un pas dure 33 ms en temps réel : la simulation doit en prendre une petite fraction.
	failures += _check(per_tick_ms < 8.0, "the simulation is fast enough (%.2f ms per step)" % per_tick_ms)
	return failures


func _check(condition: bool, label: String) -> int:
	if condition:
		return 0
	printerr("FAIL: " + label)
	return 1
