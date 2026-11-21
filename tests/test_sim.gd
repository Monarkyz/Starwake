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
	_test_prediction_matches_server()
	_test_input_validation()
	_test_waves_meet_and_fight()
	_test_minion_xp_needs_a_hero_nearby()
	_test_levels_scale_heroes()
	_test_temple_attacks_and_blocks()
	_test_temples_fall_in_order()
	_test_core_ends_the_match()
	_test_relic()
	_test_camp()
	_test_fountain_and_regen()
	_test_snapshot_roundtrip()
	_test_snapshot_fits_in_a_packet()
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


## Monde vide (ni voie ni bâtiment), avec un héros par équipe placé aux positions données.
func _duel(pos_a: Vector2, pos_b: Vector2) -> Array:
	var arena := SimArena.new()
	arena.spawns = [[pos_a], [pos_b]]
	var world := SimWorld.new(arena)
	var a := world.add_hero(SimConst.TEAM_DAWN)
	var b := world.add_hero(SimConst.TEAM_DUSK)
	return [world, a, b]


func _has_event(world: SimWorld, type: String) -> bool:
	for ev: Array in world.events:
		if ev[0] == type:
			return true
	return false


func _steps(world: SimWorld, seconds: float, inputs: Dictionary = {}) -> void:
	for i in roundi(seconds * SimConst.TICK_RATE):
		world.step(inputs)


func _structure(world: SimWorld, team: int, lane: int, tier: int) -> SimStructure:
	for s in world.structures:
		if s.team == team and s.lane == lane and s.tier == tier:
			return s
	return null


func _count_units(world: SimWorld, team: int) -> int:
	var count := 0
	for u in world.units:
		if u.team == team and u.alive:
			count += 1
	return count


# ---------------------------------------------------------------------------
# Héros et combat
# ---------------------------------------------------------------------------

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
	var arena := SimArena.new()
	arena.pillars = [Vector3(0.0, 0.0, 2.0)]
	arena.spawns = [[Vector2(-6.0, 0.0)], [Vector2(15.0, 10.0)]]
	var world := SimWorld.new(arena)
	var a := world.add_hero(SimConst.TEAM_DAWN)
	for i in SimConst.TICK_RATE * 3:
		world.step({a.id: _input(Vector2.RIGHT, Vector2.ZERO)})
	# Pilier de rayon 2, héros de rayon 0,6.
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
	var arena := SimArena.new()
	arena.pillars = [Vector3(0.0, 0.0, 2.0)]
	arena.spawns = [[Vector2(-5.0, 0.0)], [Vector2(5.0, 0.0)]]
	var world := SimWorld.new(arena)
	var a := world.add_hero(SimConst.TEAM_DAWN)
	var b := world.add_hero(SimConst.TEAM_DUSK)
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
		for ev: Array in world.events:
			if ev[0] == "kill" and ev[1] == a.id and ev[2] == b.id:
				saw_kill = true
	_check(not b.alive, "a hero at zero hp is dead")
	_check(saw_kill, "the kill is reported as an event")
	_check(world.team_kills[SimConst.TEAM_DAWN] == 1 and a.kills == 1 and b.deaths == 1, "kills are counted")
	_check(world.team_xp[SimConst.TEAM_DAWN] > 150.0, "a kill gives experience to the team")
	var dead_pos := b.pos
	world.step({b.id: _input(Vector2.RIGHT, Vector2.ZERO)})
	_check(b.pos == dead_pos, "a dead hero does not move")
	_steps(world, SimConst.RESPAWN_TIME + 0.1)
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


## Le client rejoue les mêmes commandes que le serveur et doit arriver au même endroit,
## y compris contre les piliers et les bâtiments de la vraie carte.
func _test_prediction_matches_server() -> void:
	var world := SimWorld.new()
	var a := world.add_hero(SimConst.TEAM_DAWN)
	var client_arena := SimArena.make_default()
	var predicted := a.copy()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var worst := 0.0
	var move := Vector2.ZERO
	for i in 900:
		if i % 20 == 0:
			move = Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
		if i % 200 < 60:
			move = (Vector2(-48.0, 0.0) - predicted.pos).normalized()  # Foncer vers son sanctuaire.
		var cmd := _input(move, Vector2(rng.randf_range(-20.0, 20.0), rng.randf_range(-12.0, 12.0)),
				SimConst.BTN_ABILITY_2 if rng.randf() < 0.05 else 0, i + 1)
		SimWorld.step_hero_local(predicted, cmd, client_arena, SimConst.DT)
		world.step({a.id: cmd})
		worst = maxf(worst, predicted.pos.distance_to(a.pos))
	_check(worst < 0.0001, "client prediction matches the server (worst gap %s)" % worst)
	_check(is_equal_approx(predicted.cooldowns[2], a.cooldowns[2]), "predicted dash cooldown matches the server")
	_check(a.pos.distance_to(Vector2(-48.0, 0.0)) >= 3.6 - 0.001, "a standing sanctuary blocks heroes")


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


# ---------------------------------------------------------------------------
# Sanctuaire : sbires, expérience, bâtiments, relique, camps
# ---------------------------------------------------------------------------

func _test_waves_meet_and_fight() -> void:
	var world := SimWorld.new()
	_steps(world, SimConst.FIRST_WAVE + 0.2)
	_check(_count_units(world, SimConst.TEAM_DAWN) == 8 and _count_units(world, SimConst.TEAM_DUSK) == 8,
			"the first wave sends 4 minions per lane and per team")
	_steps(world, 20.0)
	var dawn := _count_units(world, SimConst.TEAM_DAWN)
	var wounded := false
	for u in world.units:
		if u.team != SimConst.TEAM_NEUTRAL and u.hp < u.max_hp:
			wounded = true
		_check(absf(u.pos.x) < 30.0 or u.team == SimConst.TEAM_NEUTRAL, "minions reach the middle of their lane")
	_check(wounded, "opposing minions fight when they meet")
	_steps(world, 40.0)
	_check(_count_units(world, SimConst.TEAM_DAWN) != dawn or world.units.size() > 16, "waves keep coming and minions die")
	var top := _structure(world, SimConst.TEAM_DAWN, 0, 0)
	_check(top.alive, "without heroes, the lanes stay balanced early on")


func _test_minion_xp_needs_a_hero_nearby() -> void:
	var arena := SimArena.new()
	arena.spawns = [[Vector2(-30.0, 0.0)], [Vector2(8.0, 0.0)]]
	arena.half_size = Vector2(40.0, 20.0)
	var world := SimWorld.new(arena)
	var far := world.add_hero(SimConst.TEAM_DAWN)
	var near := world.add_hero(SimConst.TEAM_DUSK)
	# Deux sbires face à face : celui de l'Aube n'a presque plus de vie.
	var weak := world._spawn_unit(UnitDefs.FOOTMAN, SimConst.TEAM_DAWN, Vector2(0.0, 0.0))
	var strong := world._spawn_unit(UnitDefs.FOOTMAN, SimConst.TEAM_DUSK, Vector2(1.5, 0.0))
	weak.hp = 10.0
	_steps(world, 3.0)
	_check(not world.units.has(weak), "the weak minion dies")
	_check(world.team_xp[SimConst.TEAM_DUSK] >= 30.0, "a hero close to the fight earns the experience")
	# Dans l'autre sens, le héros de l'Aube est trop loin.
	var xp_before := world.team_xp[SimConst.TEAM_DAWN]
	strong.hp = 1.0
	var avenger := world._spawn_unit(UnitDefs.FOOTMAN, SimConst.TEAM_DAWN, Vector2(0.0, 0.0))
	_steps(world, 3.0)
	_check(not world.units.has(strong) and world.units.has(avenger), "the second fight is won by the fresh minion")
	_check(world.team_xp[SimConst.TEAM_DAWN] - xp_before < 15.0, "a hero far from the fight earns nothing from it")
	_check(far.alive and near.alive, "heroes are untouched")


func _test_levels_scale_heroes() -> void:
	var duel := _duel(Vector2(-3.0, 0.0), Vector2(3.0, 0.0))
	var world: SimWorld = duel[0]
	var a: SimHero = duel[1]
	var b: SimHero = duel[2]
	a.hp = 500.0
	world._grant_xp(SimConst.TEAM_DAWN, SimConst.xp_needed(1) + SimConst.xp_needed(2) + 5.0)
	_check(world.team_level[SimConst.TEAM_DAWN] == 3 and world.team_level[SimConst.TEAM_DUSK] == 1, "experience raises the team level")
	_check(is_equal_approx(a.max_hp, 1000.0 * 1.04 * 1.04), "a level raises max hp by 4%%")
	_check(is_equal_approx(a.hp / a.max_hp, 0.5), "current hp keeps its ratio on level up")
	_check(_has_event(world, "level"), "level events are emitted")
	for i in 15:
		world.step({a.id: _input(Vector2.ZERO, b.pos, SimConst.BTN_ATTACK)})
	_check(is_equal_approx(b.max_hp - b.hp, 90.0 * 1.04 * 1.04), "a level raises damage by 4%% (dealt %s)" % (b.max_hp - b.hp))
	b.hp = 1.0
	world.step({a.id: _input(Vector2.ZERO, b.pos, SimConst.BTN_ABILITY_1)})
	_steps(world, 0.5)
	_check(not b.alive and b.respawn_left > SimConst.RESPAWN_TIME - 0.6, "the victim waits for its respawn")


func _test_temple_attacks_and_blocks() -> void:
	var world := SimWorld.new()
	var temple := _structure(world, SimConst.TEAM_DUSK, 0, 0)
	var hero := world.add_hero(SimConst.TEAM_DAWN)
	hero.pos = temple.pos + Vector2(-6.0, 0.0)
	_steps(world, 2.5, {hero.id: _input(Vector2.ZERO, temple.pos)})
	_check(hero.hp < hero.max_hp, "a temple attacks an enemy hero in range")
	var hp_before := hero.hp
	# Avec un sbire allié à portée, le temple le vise en priorité.
	var minion := world._spawn_unit(UnitDefs.FOOTMAN, SimConst.TEAM_DAWN, temple.pos + Vector2(-4.0, 0.0))
	_steps(world, 2.0, {hero.id: _input(Vector2.ZERO, temple.pos)})
	_check(is_equal_approx(hero.hp, hp_before) and minion.hp < minion.max_hp, "a temple shoots minions before heroes")
	# Le héros ne peut pas traverser un temple debout.
	_steps(world, 3.0, {hero.id: _input(Vector2.RIGHT, temple.pos)})
	_check(hero.pos.distance_to(temple.pos) >= temple.radius + 0.6 - 0.001 or not hero.alive, "a standing temple blocks heroes")
	# Ses tirs touchent le temple.
	hero.hp = hero.max_hp
	hero.pos = temple.pos + Vector2(-5.0, 0.0)
	_steps(world, 1.0, {hero.id: _input(Vector2.ZERO, temple.pos, SimConst.BTN_ATTACK)})
	_check(temple.hp < temple.max_hp, "hero projectiles damage an enemy temple")


func _test_temples_fall_in_order() -> void:
	var world := SimWorld.new()
	var outer := _structure(world, SimConst.TEAM_DUSK, 0, 0)
	var inner := _structure(world, SimConst.TEAM_DUSK, 0, 1)
	var core := _structure(world, SimConst.TEAM_DUSK, -1, 2)
	_check(outer.vulnerable and not inner.vulnerable and not core.vulnerable, "only outer temples can be attacked at first")
	world._damage_structure(inner, 99999.0, SimConst.TEAM_DAWN)
	world._damage_structure(core, 99999.0, SimConst.TEAM_DAWN)
	_check(inner.alive and is_equal_approx(inner.hp, inner.max_hp) and core.alive, "protected buildings take no damage")
	world._damage_structure(outer, 99999.0, SimConst.TEAM_DAWN)
	_check(not outer.alive and inner.vulnerable and not core.vulnerable, "destroying the outer temple opens the inner one")
	_check(world.team_xp[SimConst.TEAM_DAWN] >= SimConst.XP_STRUCTURE, "destroying a temple gives experience")
	_check(_has_event(world, "structure"), "a destroyed temple is reported as an event")
	world._damage_structure(inner, 99999.0, SimConst.TEAM_DAWN)
	_check(not inner.alive and core.vulnerable, "destroying an inner temple opens the sanctuary")
	_check(not world.match_over, "the match goes on while the sanctuary stands")


func _test_core_ends_the_match() -> void:
	var world := SimWorld.new()
	var hero := world.add_hero(SimConst.TEAM_DAWN)
	_steps(world, 10.0)
	for tier in 2:
		world._damage_structure(_structure(world, SimConst.TEAM_DUSK, 1, tier), 99999.0, SimConst.TEAM_DAWN)
	world._damage_structure(_structure(world, SimConst.TEAM_DUSK, -1, 2), 99999.0, SimConst.TEAM_DAWN)
	_check(world.match_over and world.winner == SimConst.TEAM_DAWN, "destroying the sanctuary wins the match")
	_check(_has_event(world, "match_end"), "the end of the match is reported as an event")
	var tick := world.tick
	var units := world.units.size()
	_steps(world, 1.0, {hero.id: _input(Vector2.RIGHT, Vector2.ZERO)})
	_check(world.tick == tick + 30 and world.units.size() == units, "the world is frozen once the match is over")
	hero.kills = 3
	world.reset_match()
	_check(not world.match_over and world.winner == -1 and world.units.is_empty(), "a new match starts clean")
	_check(_structure(world, SimConst.TEAM_DUSK, -1, 2).alive and world.team_level == [1, 1], "buildings and levels are reset")
	_check(world.heroes.has(hero.id) and hero.kills == 0 and hero.pos.x < -50.0, "heroes stay and return to their base")
	_check(world.tick > tick, "the clock keeps running across matches")


func _test_relic() -> void:
	var world := SimWorld.new()
	var a := world.add_hero(SimConst.TEAM_DAWN)
	var b := world.add_hero(SimConst.TEAM_DUSK)
	var still_a := {a.id: _input(Vector2.ZERO, Vector2(5.0, 0.0))}
	a.pos = Vector2(1.0, 0.0)
	b.pos = Vector2(40.0, -20.0)
	_steps(world, 3.0, still_a)
	_check(not world.relic_active and is_zero_approx(world.relic_progress[0]), "nothing to channel before the relic appears")
	world.relic_timer = 0.1
	_steps(world, 0.2, still_a)
	_check(world.relic_active, "the relic appears when its timer runs out")

	# Canaliser, puis être interrompu par un coup.
	_steps(world, 2.0, still_a)
	_check(a.channeling and world.relic_progress[0] > 0.3, "standing still on the altar channels the relic")
	world._damage_hero(a, 10.0, SimConst.TEAM_DUSK, b.id)
	world.step(still_a)
	_check(not a.channeling, "taking damage interrupts the channel")
	var after_hit := world.relic_progress[0]
	_steps(world, 0.5, still_a)
	_check(world.relic_progress[0] < after_hit, "progress decays while nobody channels")
	# Bouger ou attaquer empêche aussi de canaliser.
	_steps(world, 1.5, {a.id: _input(Vector2.ZERO, Vector2(5.0, 0.0), SimConst.BTN_ATTACK)})
	_check(not a.channeling, "attacking prevents channeling")

	# Canalisation complète : l'onde frappe le premier temple adverse de chaque voie.
	var top := _structure(world, SimConst.TEAM_DUSK, 0, 0)
	var bottom := _structure(world, SimConst.TEAM_DUSK, 1, 0)
	world._damage_structure(bottom, 99999.0, SimConst.TEAM_DAWN)
	var bottom_inner := _structure(world, SimConst.TEAM_DUSK, 1, 1)
	var captured := false
	for i in SimConst.TICK_RATE * 8:
		world.step(still_a)
		if _has_event(world, "relic"):
			captured = true
			break
	_check(captured and not world.relic_active, "a full channel captures the relic")
	_check(is_equal_approx(top.max_hp - top.hp, SimConst.RELIC_TEMPLE_DAMAGE), "the wave hits the outer temple of an intact lane")
	_check(is_equal_approx(bottom_inner.max_hp - bottom_inner.hp, SimConst.RELIC_TEMPLE_DAMAGE), "the wave hits the next temple of an open lane")
	_check(is_equal_approx(world.relic_timer, SimConst.RELIC_INTERVAL), "the relic comes back later")
	_check(_structure(world, SimConst.TEAM_DAWN, 0, 0).hp == _structure(world, SimConst.TEAM_DAWN, 0, 0).max_hp, "the capturing team's temples are untouched")


func _test_camp() -> void:
	var world := SimWorld.new()
	var hero := world.add_hero(SimConst.TEAM_DUSK)
	hero.pos = Vector2(30.0, -2.0)
	_steps(world, SimConst.CAMP_FIRST + 0.2)
	_check(_count_units(world, SimConst.TEAM_NEUTRAL) == 4, "two guardians appear in each camp")
	var guards: Array[SimUnit] = []
	for u in world.units:
		if u.team == SimConst.TEAM_NEUTRAL and u.camp == 0:
			guards.append(u)
	_check(guards.size() == 2, "the north camp has its two guardians")
	if guards.size() != 2:
		return
	var home := guards[0].home
	_steps(world, 5.0)
	_check(guards[0].pos.distance_to(home) < 0.3, "guardians stay at their post")

	# Un héros qui s'approche est attaqué ; s'il s'éloigne, les gardiens rentrent et se soignent.
	hero.pos = Vector2(3.0, -9.0)
	_steps(world, 3.0, {hero.id: _input(Vector2.ZERO, Vector2.ZERO)})
	_check(hero.hp < hero.max_hp, "guardians attack a hero who comes close")
	guards[0].hp = 400.0
	hero.pos = Vector2(30.0, -2.0)
	_steps(world, 6.0)
	_check(guards[0].pos.distance_to(home) < 0.3 and is_equal_approx(guards[0].hp, guards[0].max_hp), "guardians return and heal when the hero leaves")

	# Vaincre le camp : ses mercenaires rejoignent l'équipe et partent vers la base adverse.
	for g in guards:
		world._damage_unit(g, 99999.0, SimConst.TEAM_DUSK, hero.id)
	_check(_has_event(world, "camp") and world.camps[0]["alive"] == 0, "the camp is captured")
	world.step({})
	var mercs: Array[SimUnit] = []
	for u in world.units:
		if u.team == SimConst.TEAM_DUSK and u.kind == UnitDefs.GUARDIAN:
			mercs.append(u)
	_check(mercs.size() == 2, "two mercenaries join the capturing team")
	_check(world.camps[0]["timer"] > SimConst.CAMP_RESPAWN - 1.0, "the camp comes back later")
	if mercs.size() == 2:
		_steps(world, 6.0)
		_check(mercs[0].pos.x < -5.0 and mercs[0].pos.y < -12.0, "mercenaries walk down the nearby lane towards the enemy (pos=%s)" % mercs[0].pos)


func _test_fountain_and_regen() -> void:
	var world := SimWorld.new()
	var a := world.add_hero(SimConst.TEAM_DAWN)
	a.hp = 100.0
	a.last_hit_tick = world.tick
	_steps(world, 2.0)
	_check(a.hp > 300.0, "the fountain heals a hero at its base (hp=%s)" % a.hp)
	a.pos = Vector2(-20.0, 0.0)
	a.hp = 100.0
	a.last_hit_tick = world.tick
	_steps(world, 3.0)
	_check(is_equal_approx(a.hp, 100.0), "no regeneration right after taking damage")
	_steps(world, SimConst.REGEN_DELAY)
	_check(a.hp > 100.0 and a.hp < 200.0, "slow regeneration out of combat (hp=%s)" % a.hp)


# ---------------------------------------------------------------------------
# Réseau : photographie du monde
# ---------------------------------------------------------------------------

func _test_snapshot_roundtrip() -> void:
	var world := SimWorld.new()
	var a := world.add_hero(SimConst.TEAM_DAWN)
	var b := world.add_hero(SimConst.TEAM_DUSK)
	a.pos = Vector2(-3.0, 1.0)
	b.pos = Vector2(3.0, 1.0)
	world.relic_timer = 12.3
	world._grant_xp(SimConst.TEAM_DUSK, SimConst.xp_needed(1) + 42.0)
	world._damage_structure(_structure(world, SimConst.TEAM_DAWN, 0, 0), 500.0, SimConst.TEAM_DUSK)
	_steps(world, SimConst.FIRST_WAVE + 1.0, {a.id: _input(Vector2(0.3, 0.7), b.pos, SimConst.BTN_ATTACK, 9)})
	world.step({a.id: _input(Vector2.ZERO, b.pos, SimConst.BTN_ATTACK | SimConst.BTN_ABILITY_1, 10)})
	var wire := world.to_snapshot()
	var snap := SimSnapshot.from_bytes(wire, SimArena.make_default())
	_check(snap != null, "a snapshot decodes")
	if snap == null:
		return
	var a2: SimHero = snap.heroes[a.id]
	_check(snap.tick == world.tick and snap.heroes.size() == 2, "tick and heroes survive the roundtrip")
	_check(a2.pos.is_equal_approx(a.pos) and a2.last_seq == 10 and a2.team == a.team, "hero fields survive the roundtrip")
	_check(a2.facing.is_equal_approx(a.facing) or a2.facing.distance_to(a.facing) < 0.001, "hero facing survives the roundtrip")
	_check(is_equal_approx(a2.hp, ceilf(a.hp)) and is_equal_approx(a2.max_hp, a.max_hp), "hero hp survives the roundtrip")
	_check(is_equal_approx(a2.cooldowns[1], a.cooldowns[1]), "cooldowns survive the roundtrip")
	_check(snap.team_level == [1, 2] and is_equal_approx(snap.team_xp[1], floorf(world.team_xp[1])), "team levels and experience survive the roundtrip")
	_check(absf(snap.relic_timer - world.relic_timer) <= 0.1 and not snap.relic_active, "the relic timer survives the roundtrip")
	_check(snap.units.size() == world.units.size() and snap.units.size() == 16, "units survive the roundtrip")
	var u := world.units[3]
	var u2 := snap.units[3]
	_check(u2.id == u.id and u2.kind == u.kind and u2.team == u.team and u2.pos.distance_to(u.pos) < 0.01, "unit fields survive the roundtrip")
	_check(snap.structures.size() == world.structures.size(), "buildings survive the roundtrip")
	var damaged := _structure(world, SimConst.TEAM_DAWN, 0, 0)
	var damaged2 := snap.structures[damaged.index]
	_check(is_equal_approx(damaged2.hp, damaged.hp) and damaged2.alive and damaged2.vulnerable and damaged2.pos == damaged.pos, "building state survives the roundtrip")
	_check(not snap.structures[_structure(world, SimConst.TEAM_DAWN, 0, 1).index].vulnerable, "protected buildings are flagged")
	_check(snap.projectiles.size() == world.projectiles.size() and snap.projectiles.size() >= 1, "projectiles survive the roundtrip")
	_check(snap.projectiles[0].pos.distance_to(world.projectiles[0].pos) < 0.01, "projectile position survives the roundtrip")
	_check(snap.camps.size() == 2 and absf(snap.camps[0]["timer"] - world.camps[0]["timer"]) <= 0.1, "camp timers survive the roundtrip")
	_check(SimSnapshot.from_bytes(PackedByteArray([1, 2, 3]), world.arena) == null, "a short snapshot is rejected")
	_check(SimSnapshot.from_bytes(wire.slice(0, wire.size() - 1), world.arena) == null, "a truncated snapshot is rejected")
	var padded := wire.duplicate()
	padded.append(0)
	_check(SimSnapshot.from_bytes(padded, world.arena) == null, "a snapshot with trailing bytes is rejected")
	_check(SimSnapshot.from_bytes(wire, SimArena.new()) == null, "a snapshot for another map is rejected")


## Pire cas : partie pleine, tout le monde tire, autant d'unités que le plafond le permet.
func _test_snapshot_fits_in_a_packet() -> void:
	var world := SimWorld.new()
	for i in SimConst.MAX_PLAYERS:
		world.add_hero(i % 2)
	while world.units.size() < SimConst.MAX_UNITS_HARD:
		var u := world._spawn_unit(UnitDefs.ARCHER, world.units.size() % 2, Vector2(world.units.size() - 30.0, 25.0))
		u.attack_cd = 1000.0
	var largest := 0
	for i in SimConst.TICK_RATE * 4:
		var inputs: Dictionary = {}
		for id: int in world.heroes:
			inputs[id] = _input(Vector2.ZERO, Vector2(0.0, -30.0), SimConst.BTN_ATTACK | SimConst.BTN_ABILITY_1)
		world.step(inputs)
		while world.beams.size() < SimSnapshot.MAX_BEAMS + 4:
			world.beams.append([SimWorld.BEAM_ARCHER, Vector2.ZERO, Vector2.ONE])
		largest = maxi(largest, world.to_snapshot().size())
	_check(largest > 900, "the worst case is really exercised (%d bytes)" % largest)
	_check(largest <= 1300, "a full match snapshot fits in one packet (%d bytes)" % largest)
	_check(SimSnapshot.from_bytes(world.to_snapshot(), SimArena.make_default()) != null, "the worst-case snapshot decodes")


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
