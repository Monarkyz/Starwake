extends SceneTree
## Tests de la simulation, sans réseau ni affichage.
## Lancement : godot --headless --path . -s tests/test_sim.gd

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	_test_movement_and_bounds()
	_test_pillar_blocks_hero()
	_test_basic_attack_hits()
	_test_pillar_blocks_projectile()
	_test_bolt_pierces_but_basic_attack_does_not()
	_test_no_friendly_fire()
	_test_kill_and_respawn()
	_test_dash()
	_test_snapshot_roundtrip()
	_test_prediction_matches_server()
	_test_input_validation()
	_test_translations_complete()
	print("%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + label)


func _input(move: Vector2, aim: Vector2, buttons: int = 0, seq: int = 0) -> SimInput:
	var cmd := SimInput.new()
	cmd.move = move
	cmd.aim = aim
	cmd.buttons = buttons
	cmd.seq = seq
	return cmd


## Monde sans pilier, avec un héros par équipe placé aux positions données.
func _duel(pos_a: Vector2, pos_b: Vector2) -> Array:
	var arena := SimArena.new()
	arena.spawns = [[pos_a], [pos_b]]
	var world := SimWorld.new(arena)
	var a := world.add_hero(SimConst.TEAM_DAWN)
	var b := world.add_hero(SimConst.TEAM_DUSK)
	return [world, a, b]


func _test_movement_and_bounds() -> void:
	var duel := _duel(Vector2.ZERO, Vector2(15.0, 10.0))
	var world: SimWorld = duel[0]
	var a: SimHero = duel[1]
	for i in SimConst.TICK_RATE:
		world.step({a.id: _input(Vector2.RIGHT, Vector2(100.0, 0.0))})
	_check(absf(a.pos.x - 6.0) < 0.01, "one second of movement covers the hero's speed")
	for i in SimConst.TICK_RATE * 10:
		world.step({a.id: _input(Vector2.RIGHT, Vector2(100.0, 0.0))})
	_check(absf(a.pos.x - (world.arena.half_size.x - 0.6)) < 0.01, "the hero stops at the arena border")
	# Une commande plus longue que 1 ne fait pas aller plus vite.
	var before := a.pos.y
	world.step({a.id: _input(Vector2(0.0, 5.0), Vector2(100.0, 0.0))})
	_check(absf(a.pos.y - before - 6.0 * SimConst.DT) < 0.001, "oversized move input is clamped")


func _test_pillar_blocks_hero() -> void:
	var world := SimWorld.new()
	var a := world.add_hero(SimConst.TEAM_DAWN)
	a.pos = Vector2(-6.0, 0.0)
	for i in SimConst.TICK_RATE * 3:
		world.step({a.id: _input(Vector2.RIGHT, Vector2.ZERO)})
	# Pilier central de rayon 2, héros de rayon 0,6.
	_check(a.pos.length() >= 2.6 - 0.001, "the hero cannot enter a pillar")
	_check(a.pos.x < 0.0, "the hero stays on its side of the pillar")


func _test_basic_attack_hits() -> void:
	var duel := _duel(Vector2(-3.0, 0.0), Vector2(3.0, 0.0))
	var world: SimWorld = duel[0]
	var a: SimHero = duel[1]
	var b: SimHero = duel[2]
	for i in 15:
		world.step({a.id: _input(Vector2.ZERO, b.pos, SimConst.BTN_ATTACK)})
	_check(is_equal_approx(b.hp, 910.0), "a basic attack deals its damage once (hp=%s)" % b.hp)
	_check(world.projectiles.is_empty(), "the projectile is consumed on hit")
	_check(a.cooldowns[0] > 0.0, "the attack is on cooldown")


func _test_pillar_blocks_projectile() -> void:
	var world := SimWorld.new()
	var a := world.add_hero(SimConst.TEAM_DAWN)
	var b := world.add_hero(SimConst.TEAM_DUSK)
	a.pos = Vector2(-5.0, 0.0)
	b.pos = Vector2(5.0, 0.0)
	for i in SimConst.TICK_RATE:
		world.step({a.id: _input(Vector2.ZERO, b.pos, SimConst.BTN_ATTACK | SimConst.BTN_ABILITY_1)})
	_check(is_equal_approx(b.hp, b.max_hp), "projectiles do not cross a pillar")


func _test_bolt_pierces_but_basic_attack_does_not() -> void:
	var arena := SimArena.new()
	arena.spawns = [[Vector2(-4.0, 0.0)], [Vector2(2.0, 0.0), Vector2(5.0, 0.0)]]
	var world := SimWorld.new(arena)
	var a := world.add_hero(SimConst.TEAM_DAWN)
	var near := world.add_hero(SimConst.TEAM_DUSK)
	var far := world.add_hero(SimConst.TEAM_DUSK)
	world.step({a.id: _input(Vector2.ZERO, far.pos, SimConst.BTN_ABILITY_1)})
	for i in 20:
		world.step({a.id: _input(Vector2.ZERO, far.pos)})
	_check(is_equal_approx(near.hp, 740.0) and is_equal_approx(far.hp, 740.0), "the bolt pierces and hits each enemy once")
	world.step({a.id: _input(Vector2.ZERO, far.pos, SimConst.BTN_ATTACK)})
	for i in 20:
		world.step({a.id: _input(Vector2.ZERO, far.pos)})
	_check(is_equal_approx(near.hp, 650.0) and is_equal_approx(far.hp, 740.0), "a basic attack stops on the first enemy")


func _test_no_friendly_fire() -> void:
	var arena := SimArena.new()
	arena.spawns = [[Vector2(-4.0, 0.0), Vector2(0.0, 0.0)], [Vector2(15.0, 10.0)]]
	var world := SimWorld.new(arena)
	var a := world.add_hero(SimConst.TEAM_DAWN)
	var ally := world.add_hero(SimConst.TEAM_DAWN)
	for i in 20:
		world.step({a.id: _input(Vector2.ZERO, ally.pos, SimConst.BTN_ATTACK | SimConst.BTN_ABILITY_1)})
	_check(is_equal_approx(ally.hp, ally.max_hp), "allies are not damaged")


func _test_kill_and_respawn() -> void:
	var duel := _duel(Vector2(-3.0, 0.0), Vector2(3.0, 0.0))
	var world: SimWorld = duel[0]
	var a: SimHero = duel[1]
	var b: SimHero = duel[2]
	b.hp = 50.0
	b.pos = Vector2(4.0, 1.0)
	var saw_kill := false
	for i in 15:
		world.step({a.id: _input(Vector2.ZERO, b.pos, SimConst.BTN_ATTACK)})
		for ev: Dictionary in world.events:
			if ev["type"] == "kill" and ev["killer"] == a.id and ev["victim"] == b.id:
				saw_kill = true
	_check(not b.alive, "a hero at zero hp is dead")
	_check(saw_kill, "the kill is reported as an event")
	_check(world.team_kills[SimConst.TEAM_DAWN] == 1 and a.kills == 1 and b.deaths == 1, "kills are counted")
	var dead_pos := b.pos
	world.step({b.id: _input(Vector2.RIGHT, Vector2.ZERO)})
	_check(b.pos == dead_pos, "a dead hero does not move")
	for i in int(SimConst.RESPAWN_TIME * SimConst.TICK_RATE) + 2:
		world.step({})
	_check(b.alive and is_equal_approx(b.hp, b.max_hp), "the hero respawns with full hp")
	_check(b.pos.is_equal_approx(Vector2(3.0, 0.0)), "the hero respawns at its spawn point")


func _test_dash() -> void:
	var duel := _duel(Vector2.ZERO, Vector2(15.0, 10.0))
	var world: SimWorld = duel[0]
	var a: SimHero = duel[1]
	world.step({a.id: _input(Vector2.UP, Vector2(10.0, 0.0), SimConst.BTN_ABILITY_2)})
	for i in 6:
		world.step({a.id: _input(Vector2.ZERO, Vector2(10.0, 0.0), SimConst.BTN_ABILITY_2)})
	_check(absf(a.pos.y + 6.0) < 0.01 and absf(a.pos.x) < 0.01, "the dash covers its distance in the move direction (pos=%s)" % a.pos)
	_check(a.cooldowns[2] > 7.0, "the dash is on cooldown and does not chain")


func _test_snapshot_roundtrip() -> void:
	var duel := _duel(Vector2(-3.0, 0.0), Vector2(3.0, 0.0))
	var world: SimWorld = duel[0]
	var a: SimHero = duel[1]
	var b: SimHero = duel[2]
	for i in 3:
		world.step({a.id: _input(Vector2(0.3, 0.7), b.pos, SimConst.BTN_ATTACK, i + 1)})
	var wire := world.to_snapshot()
	var snap := SimSnapshot.from_bytes(wire)
	_check(snap != null, "a snapshot decodes")
	if snap == null:
		return
	var a2: SimHero = snap.heroes[a.id]
	_check(snap.tick == world.tick and snap.heroes.size() == 2, "tick and heroes survive the roundtrip")
	_check(a2.pos.is_equal_approx(a.pos) and a2.last_seq == 3 and a2.team == a.team, "hero fields survive the roundtrip")
	_check(is_equal_approx(a2.cooldowns[0], a.cooldowns[0]), "cooldowns survive the roundtrip")
	_check(snap.projectiles.size() == world.projectiles.size() and snap.projectiles.size() == 1, "projectiles survive the roundtrip")
	_check(snap.projectiles[0].pos.is_equal_approx(world.projectiles[0].pos), "projectile position survives the roundtrip")
	_check(SimSnapshot.from_bytes(PackedByteArray([1, 2, 3])) == null, "a short snapshot is rejected")
	_check(SimSnapshot.from_bytes(wire.slice(0, wire.size() - 1)) == null, "a truncated snapshot is rejected")

	# Partie pleine où tout le monde tire : la photographie doit tenir dans un paquet (1392 octets).
	var full := SimWorld.new()
	for i in SimConst.MAX_PLAYERS:
		full.add_hero(i % 2)
	var largest := 0
	for i in SimConst.TICK_RATE * 20:
		var inputs: Dictionary = {}
		for id: int in full.heroes:
			inputs[id] = _input(Vector2.ZERO, Vector2(0.0, 12.0), SimConst.BTN_ATTACK | SimConst.BTN_ABILITY_1)
		full.step(inputs)
		largest = maxi(largest, full.to_snapshot().size())
	_check(largest < 1200, "a full match snapshot fits in one packet (%d bytes)" % largest)


## Le client rejoue les mêmes commandes que le serveur et doit arriver au même endroit.
func _test_prediction_matches_server() -> void:
	var world := SimWorld.new()
	var a := world.add_hero(SimConst.TEAM_DAWN)
	var predicted := a.copy()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var worst := 0.0
	for i in 600:
		var cmd := _input(
			Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)),
			Vector2(rng.randf_range(-20.0, 20.0), rng.randf_range(-12.0, 12.0)),
			SimConst.BTN_ABILITY_2 if rng.randf() < 0.05 else 0,
			i + 1)
		if i % 40 == 0:
			cmd.move = (Vector2.ZERO - predicted.pos).normalized()  # Foncer vers le pilier central.
		SimWorld.step_hero_local(predicted, cmd, world.arena, SimConst.DT)
		world.step({a.id: cmd})
		worst = maxf(worst, predicted.pos.distance_to(a.pos))
	_check(worst < 0.0001, "client prediction matches the server (worst gap %s)" % worst)
	_check(is_equal_approx(predicted.cooldowns[2], a.cooldowns[2]), "predicted dash cooldown matches the server")


func _test_input_validation() -> void:
	var good := _input(Vector2(0.6, -0.8), Vector2(3.0, 4.0), SimConst.BTN_ATTACK, 42)
	var decoded := SimInput.decode_batch(SimInput.encode_batch([good, good]))
	_check(decoded.size() == 2, "a batch of inputs decodes")
	if decoded.size() == 2:
		var cmd: SimInput = decoded[1]
		_check(cmd.seq == 42 and cmd.buttons == SimConst.BTN_ATTACK, "sequence and buttons survive the roundtrip")
		_check(cmd.move.is_equal_approx(good.move) and cmd.aim.is_equal_approx(good.aim), "move and aim survive the roundtrip")
	_check(SimInput.decode_batch(PackedByteArray()).is_empty(), "an empty batch is rejected")
	_check(SimInput.decode_batch(PackedByteArray([1, 2, 3])).is_empty(), "a truncated batch is rejected")
	var too_many: Array[SimInput] = []
	for i in SimInput.MAX_BATCH + 1:
		too_many.append(good)
	_check(SimInput.decode_batch(SimInput.encode_batch(too_many)).is_empty(), "an oversized batch is rejected")
	_check(SimInput.decode_batch(SimInput.encode_batch([_input(Vector2(NAN, 0.0), Vector2.ZERO)])).is_empty(), "a NaN is rejected")
	_check(SimInput.decode_batch(SimInput.encode_batch([_input(Vector2.ZERO, Vector2(INF, 0.0))])).is_empty(), "an infinity is rejected")
	var big := SimInput.decode_batch(SimInput.encode_batch([_input(Vector2(30.0, 40.0), Vector2(5000.0, 0.0))]))
	_check(big.size() == 1 and is_equal_approx(big[0].move.length(), 1.0), "an oversized move is clamped")
	_check(big.size() == 1 and big[0].aim.x <= 1000.0, "an out-of-range aim is clamped")


## Chaque clé doit être traduite dans les deux langues.
func _test_translations_complete() -> void:
	var keys: Dictionary = {}
	var per_locale: Dictionary = {}
	for locale: String in Settings.LOCALES:
		var translation: Translation = load("res://i18n/%s.po" % locale)
		_check(translation != null, "the %s translation loads" % locale)
		if translation == null:
			return
		per_locale[locale] = translation
		for key in translation.get_message_list():
			keys[key] = true
	for locale: String in per_locale:
		var translation: Translation = per_locale[locale]
		for key: String in keys:
			_check(not String(translation.get_message(key)).is_empty(), "%s is translated in %s" % [key, locale])
	for key: String in ["HERO_SAGITTA", "ABILITY_SAGITTA_ATTACK", "ABILITY_SAGITTA_BOLT", "ABILITY_SAGITTA_STEP",
			"STATUS_REJECT_FULL", "STATUS_REJECT_VERSION", "TEAM_DAWN", "TEAM_DUSK"]:
		_check(keys.has(key), "%s exists in the translations" % key)
