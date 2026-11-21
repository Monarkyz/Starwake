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
	for i in SimConst.MAX_PLAYERS:
		var hero := world.add_hero(i % 2)
		var brain := BotBrain.new(seed_value * 100 + i)
		brain.lane = hero.spawn_slot % 2
		brain.roamer = hero.spawn_slot >= 2
		brains[hero.id] = brain

	var counts: Dictionary = {"kill": 0, "structure": 0, "relic": 0, "camp": 0}
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
		for ev: Array in world.events:
			if counts.has(ev[0]):
				counts[ev[0]] += 1
		max_units = maxi(max_units, world.units.size())
		if world.tick % 30 == 0:
			max_bytes = maxi(max_bytes, world.to_snapshot().size())

	var minutes := world.tick * SimConst.DT / 60.0
	var per_tick_ms := (Time.get_ticks_usec() - started) / 1000.0 / world.tick
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
	failures += _check(max_bytes <= 1300, "the world state always fits in one packet (%d bytes)" % max_bytes)
	# Un pas dure 33 ms en temps réel : la simulation doit en prendre une petite fraction.
	failures += _check(per_tick_ms < 8.0, "the simulation is fast enough (%.2f ms per step)" % per_tick_ms)
	return failures


func _check(condition: bool, label: String) -> int:
	if condition:
		return 0
	printerr("FAIL: " + label)
	return 1
