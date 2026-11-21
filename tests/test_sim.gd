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
	_test_tank_melee_and_stun()
	_test_shield()
	_test_support_heal_and_slow()
	_test_talents()
	_test_ether_and_awakening()
	_test_armor_ranks()
	_test_all_heroes_are_well_formed()
	_test_every_ability_can_be_cast()
	_test_delayed_zone()
	_test_knockback_and_pull()
	_test_charging_dash()
	_test_haste_and_lifesteal()
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
func _duel(pos_a: Vector2, pos_b: Vector2, hero_a: String = "sagitta", hero_b: String = "sagitta") -> Array:
	var arena := SimArena.new()
	arena.spawns = [[pos_a], [pos_b]]
	var world := SimWorld.new(arena)
	var a := world.add_hero(SimConst.TEAM_DAWN, hero_a)
	var b := world.add_hero(SimConst.TEAM_DUSK, hero_b)
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
		var buttons := SimConst.BTN_ABILITY_2 if rng.randf() < 0.05 else 0
		if i == 300:
			# Le serveur étourdit puis ralentit le héros : le client l'apprend par la photographie.
			a.stun_ticks = 20
			a.slow_ticks = 90
			a.slow_pct = 50
			predicted = a.copy()
		if i == 500:
			a.ether = SimConst.ETHER_MAX
			predicted = a.copy()
			buttons |= SimConst.BTN_AWAKEN
		var cmd := _input(move, Vector2(rng.randf_range(-20.0, 20.0), rng.randf_range(-12.0, 12.0)), buttons, i + 1)
		SimWorld.step_hero_local(predicted, cmd, client_arena, SimConst.DT)
		world.step({a.id: cmd})
		worst = maxf(worst, predicted.pos.distance_to(a.pos))
		if i == 500:
			_check(a.is_awakened() and predicted.awaken_ticks == a.awaken_ticks, "awakening is predicted on the same step")
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
# Héros : rôles, talents, éther, rangs d'armures
# ---------------------------------------------------------------------------

func _test_tank_melee_and_stun() -> void:
	var arena := SimArena.new()
	arena.spawns = [[Vector2.ZERO], [Vector2(2.0, 0.0), Vector2(-2.0, 0.0), Vector2(9.0, 0.0)]]
	var world := SimWorld.new(arena)
	var tank := world.add_hero(SimConst.TEAM_DAWN, "scutum")
	var front := world.add_hero(SimConst.TEAM_DUSK)
	var behind := world.add_hero(SimConst.TEAM_DUSK)
	var far := world.add_hero(SimConst.TEAM_DUSK)
	_check(is_equal_approx(tank.max_hp, 1700.0), "the tank has its own max hp")
	var minion := world._spawn_unit(UnitDefs.FOOTMAN, SimConst.TEAM_DUSK, Vector2(1.5, 1.0))
	minion.attack_cd = 1000.0
	world.step({tank.id: _input(Vector2.ZERO, front.pos, SimConst.BTN_ATTACK)})
	_check(is_equal_approx(front.max_hp - front.hp, 110.0), "a melee hit damages the enemy in front")
	_check(is_equal_approx(behind.hp, behind.max_hp) and is_equal_approx(far.hp, far.max_hp), "a melee hit misses enemies behind or out of reach")
	_check(is_equal_approx(minion.max_hp - minion.hp, 110.0), "a melee hit also damages minions in its arc")
	_check(world.beams.size() >= 1 and world.beams[0][0] == SimWorld.FX_SLASH, "a melee hit is reported for display")

	# L'onde de choc étourdit : la victime ne bouge plus et n'agit plus pendant une seconde.
	world.step({tank.id: _input(Vector2.ZERO, front.pos, SimConst.BTN_ABILITY_1)})
	# La victime, mise à jour après le tank dans le même pas, a déjà écoulé un pas d'étourdissement.
	_check(front.stun_ticks == 29, "the shockwave stuns for one second (%d steps left)" % front.stun_ticks)
	var stuck := front.pos
	var projectiles := world.projectiles.size()
	_steps(world, 0.9, {front.id: _input(Vector2.UP, tank.pos, SimConst.BTN_ATTACK)})
	_check(front.pos == stuck and world.projectiles.size() == projectiles, "a stunned hero neither moves nor attacks")
	_steps(world, 0.5, {front.id: _input(Vector2.UP, tank.pos)})
	_check(front.pos.y < stuck.y - 1.0, "the stun wears off")


func _test_shield() -> void:
	var duel := _duel(Vector2(-3.0, 0.0), Vector2(3.0, 0.0), "scutum", "sagitta")
	var world: SimWorld = duel[0]
	var tank: SimHero = duel[1]
	var archer: SimHero = duel[2]
	world.step({tank.id: _input(Vector2.ZERO, archer.pos, SimConst.BTN_ABILITY_2)})
	_check(is_equal_approx(tank.shield, 450.0), "the rampart gives a shield")
	world._damage_hero(tank, 300.0, SimConst.TEAM_DUSK, archer.id)
	_check(is_equal_approx(tank.shield, 150.0) and is_equal_approx(tank.hp, tank.max_hp), "the shield absorbs damage before hp")
	world._damage_hero(tank, 300.0, SimConst.TEAM_DUSK, archer.id)
	_check(is_zero_approx(tank.shield) and is_equal_approx(tank.max_hp - tank.hp, 150.0), "damage beyond the shield reaches hp")
	world.step({tank.id: _input(Vector2.ZERO, archer.pos, SimConst.BTN_ABILITY_2)})
	_check(is_zero_approx(tank.shield) and tank.cooldowns[2] > 11.0, "the rampart is on cooldown")
	tank.cooldowns[2] = 0.0
	world.step({tank.id: _input(Vector2.ZERO, archer.pos, SimConst.BTN_ABILITY_2)})
	_steps(world, 4.1)
	_check(is_zero_approx(tank.shield), "an unused shield expires")


func _test_support_heal_and_slow() -> void:
	var arena := SimArena.new()
	arena.spawns = [[Vector2.ZERO, Vector2(6.0, 0.0), Vector2(30.0, 0.0)], [Vector2(6.0, 2.0), Vector2(0.0, 8.0)]]
	arena.half_size = Vector2(40.0, 20.0)
	var world := SimWorld.new(arena)
	var healer := world.add_hero(SimConst.TEAM_DAWN, "columba")
	var ally := world.add_hero(SimConst.TEAM_DAWN)
	var far_ally := world.add_hero(SimConst.TEAM_DAWN)
	var enemy := world.add_hero(SimConst.TEAM_DUSK)
	var runner := world.add_hero(SimConst.TEAM_DUSK)
	for h: SimHero in [healer, ally, far_ally, enemy]:
		h.hp = 300.0
		h.last_hit_tick = world.tick  # Blessé à l'instant : pas de récupération hors combat.
	world.step({healer.id: _input(Vector2.ZERO, ally.pos, SimConst.BTN_ABILITY_1)})
	_check(is_equal_approx(ally.hp, 520.0), "the heal restores hp to an ally in the area")
	_check(is_equal_approx(enemy.hp, 300.0), "the heal ignores enemies")
	_check(is_equal_approx(healer.hp, 300.0), "the heal only reaches heroes inside its radius")
	_check(healer.ether > 0.0, "healing fills the ether gauge")
	# Viser trop loin : le soin se pose à la limite de portée, pas sur la cible.
	healer.cooldowns[1] = 0.0
	world.step({healer.id: _input(Vector2.ZERO, far_ally.pos, SimConst.BTN_ABILITY_1)})
	_check(is_equal_approx(far_ally.hp, 300.0), "the heal cannot be cast beyond its range")
	ally.hp = ally.max_hp - 50.0
	healer.cooldowns[1] = 0.0
	world.step({healer.id: _input(Vector2.ZERO, ally.pos, SimConst.BTN_ABILITY_1)})
	_check(is_equal_approx(ally.hp, ally.max_hp), "the heal does not exceed max hp")

	# L'entrave ralentit de moitié pendant 2,5 secondes.
	world.step({healer.id: _input(Vector2.ZERO, runner.pos, SimConst.BTN_ABILITY_2)})
	_steps(world, 0.5, {healer.id: _input(Vector2.ZERO, runner.pos)})
	_check(runner.slow_ticks > 0 and runner.slow_pct == 50 and runner.hp < runner.max_hp, "the snare damages and slows its target")
	var start := runner.pos
	_steps(world, 1.0, {runner.id: _input(Vector2.DOWN, Vector2.ZERO)})
	_check(absf(runner.pos.y - start.y - 3.0) < 0.05, "a slowed hero moves at half speed (%s)" % (runner.pos.y - start.y))
	_steps(world, 2.0)
	start = runner.pos
	_steps(world, 1.0, {runner.id: _input(Vector2.UP, Vector2.ZERO)})
	_check(absf(start.y - runner.pos.y - 6.0) < 0.05, "the slow wears off")


func _test_talents() -> void:
	var duel := _duel(Vector2(-3.0, 0.0), Vector2(3.0, 0.0))
	var world: SimWorld = duel[0]
	var a: SimHero = duel[1]
	var b: SimHero = duel[2]
	_check(HeroDefs.pending_talent_tier(a, 1) == -1, "no talent is offered at level 1")
	_check(not world.choose_talent(a.id, 0, 1), "a talent cannot be chosen before its level")
	world.team_level[SimConst.TEAM_DAWN] = 3
	_check(HeroDefs.pending_talent_tier(a, 3) == 0, "the first tier opens at level 3")
	_check(not world.choose_talent(a.id, 0, 3) and not world.choose_talent(a.id, 1, 1) and not world.choose_talent(99, 0, 1), "invalid choices are refused")
	_check(world.choose_talent(a.id, 0, 1), "an open tier accepts a choice")
	_check(not world.choose_talent(a.id, 0, 2), "a tier cannot be chosen twice")
	_check(HeroDefs.pending_talent_tier(a, 3) == -1 and a.talents == [1, 0, 0], "the choice is recorded")
	for i in 15:
		world.step({a.id: _input(Vector2.ZERO, b.pos, SimConst.BTN_ATTACK)})
	var expected := 90.0 * 1.2 * SimConst.level_multiplier(3)
	_check(is_equal_approx(b.max_hp - b.hp, expected), "the talent raises basic attack damage by 20%% (dealt %s)" % (b.max_hp - b.hp))
	# Talent de recharge sur la ruée : il s'applique aussi à la prédiction du client.
	world.team_level[SimConst.TEAM_DAWN] = 6
	_check(world.choose_talent(a.id, 1, 2), "the second tier opens at level 6")
	var predicted := a.copy()
	var dash := _input(Vector2.UP, b.pos, SimConst.BTN_ABILITY_2)
	SimWorld.step_hero_local(predicted, dash, world.arena, SimConst.DT)
	world.step({a.id: dash})
	_check(is_equal_approx(a.cooldowns[2], 8.0 * 0.65) and is_equal_approx(predicted.cooldowns[2], a.cooldowns[2]), "a cooldown talent applies on the server and in prediction")

	# Talent de vie maximale : la proportion de vie est conservée.
	var tank := world.add_hero(SimConst.TEAM_DUSK, "scutum")
	world.team_level[SimConst.TEAM_DUSK] = 3
	tank.max_hp = world._hero_max_hp(tank)
	tank.hp = tank.max_hp * 0.5
	var before := tank.max_hp
	_check(world.choose_talent(tank.id, 0, 1), "the tank takes its max hp talent")
	_check(is_equal_approx(tank.max_hp, before * 1.15) and is_equal_approx(tank.hp / tank.max_hp, 0.5), "a max hp talent keeps the hp ratio")
	world.reset_match()
	_check(a.talents == [0, 0, 0] and tank.talents == [0, 0, 0] and is_equal_approx(tank.max_hp, 1700.0), "talents are reset for a new match")
	# Chaque héros a deux choix pour chaque palier.
	for def_id: String in HeroDefs.ids():
		var tiers: Array = HeroDefs.get_def(def_id)["talents"]
		_check(tiers.size() == SimConst.TALENT_LEVELS.size(), "%s has one talent tier per talent level" % def_id)
		for tier: Array in tiers:
			_check(tier.size() == 2, "%s has two choices per tier" % def_id)


func _test_ether_and_awakening() -> void:
	var duel := _duel(Vector2(-3.0, 0.0), Vector2(3.0, 0.0))
	var world: SimWorld = duel[0]
	var a: SimHero = duel[1]
	var b: SimHero = duel[2]
	for i in 15:
		world.step({a.id: _input(Vector2.ZERO, b.pos, SimConst.BTN_ATTACK)})
	_check(a.ether > 1.5 and b.ether > 0.8 and a.ether > b.ether, "dealing and taking damage fills the ether gauge (%s, %s)" % [a.ether, b.ether])
	var partial := a.ether
	world.step({a.id: _input(Vector2.ZERO, b.pos, SimConst.BTN_AWAKEN)})
	_check(not a.is_awakened() and a.ether >= partial, "awakening needs a full gauge")

	b.hp = b.max_hp
	a.ether = SimConst.ETHER_MAX
	a.cooldowns[0] = 0.0
	world.projectiles.clear()
	world.step({a.id: _input(Vector2.ZERO, b.pos, SimConst.BTN_AWAKEN)})
	_check(a.awaken_ticks == SimConst.AWAKEN_TICKS and is_zero_approx(a.ether), "a full gauge triggers the awakening and empties")
	_check(_has_event(world, "awaken"), "the awakening is reported as an event")
	_check(world.projectiles.size() == 7, "the archer's ultimate fires a volley of seven bolts")
	_steps(world, 0.5, {a.id: _input(Vector2.ZERO, b.pos, SimConst.BTN_AWAKEN)})
	_check(b.hp < b.max_hp and world.projectiles.size() <= 7, "the volley hits and holding the button does not fire it again")
	_check(is_zero_approx(a.ether), "the gauge stays empty during the awakening")

	# Pendant l'éveil : dégâts +25 %, déplacement +15 %.
	b.hp = b.max_hp
	b.pos = Vector2(3.0, 0.0)
	a.pos = Vector2(-3.0, 0.0)
	world.projectiles.clear()
	for i in 15:
		world.step({a.id: _input(Vector2.ZERO, b.pos, SimConst.BTN_ATTACK)})
	_check(is_equal_approx(b.max_hp - b.hp, 90.0 * SimConst.AWAKEN_POWER), "damage is raised during the awakening (dealt %s)" % (b.max_hp - b.hp))
	var start := a.pos
	_steps(world, 1.0, {a.id: _input(Vector2.UP, Vector2(0.0, -50.0))})
	_check(absf(start.y - a.pos.y - 6.0 * SimConst.AWAKEN_SPEED) < 0.05, "movement is faster during the awakening")
	_steps(world, 8.0)
	_check(not a.is_awakened() and a.ether > 0.0, "the awakening ends and the gauge fills again")

	# Les deux autres capacités ultimes.
	var arena := SimArena.new()
	arena.spawns = [[Vector2.ZERO, Vector2(2.0, 0.0)], [Vector2(-4.0, 0.0), Vector2(0.0, 5.0)]]
	var other := SimWorld.new(arena)
	var tank := other.add_hero(SimConst.TEAM_DAWN, "scutum")
	var healer := other.add_hero(SimConst.TEAM_DAWN, "columba")
	var foe_a := other.add_hero(SimConst.TEAM_DUSK)
	var foe_b := other.add_hero(SimConst.TEAM_DUSK)
	tank.ether = SimConst.ETHER_MAX
	other.step({tank.id: _input(Vector2.ZERO, Vector2(10.0, 0.0), SimConst.BTN_AWAKEN)})
	_check(foe_a.hp < foe_a.max_hp and foe_b.hp < foe_b.max_hp and foe_a.stun_ticks == 44, "the tank's ultimate hits and stuns all around")
	tank.hp = 500.0
	healer.hp = 200.0
	healer.ether = SimConst.ETHER_MAX
	other.step({healer.id: _input(Vector2.ZERO, Vector2(10.0, 0.0), SimConst.BTN_AWAKEN)})
	_check(tank.hp > 900.0 and healer.hp > 600.0, "the support's ultimate heals nearby allies")
	_check(tank.shield > 250.0 and healer.shield > 250.0, "the support's ultimate shields nearby allies")


func _test_armor_ranks() -> void:
	_check(SimConst.armor_rank(1) == SimConst.RANK_BRONZE and SimConst.armor_rank(4) == SimConst.RANK_BRONZE, "armor is bronze at first")
	_check(SimConst.armor_rank(5) == SimConst.RANK_SILVER and SimConst.armor_rank(9) == SimConst.RANK_SILVER, "armor turns silver at level 5")
	_check(SimConst.armor_rank(10) == SimConst.RANK_GOLD and SimConst.armor_rank(20) == SimConst.RANK_GOLD, "armor turns gold at level 10")
	var duel := _duel(Vector2(-3.0, 0.0), Vector2(3.0, 0.0))
	var world: SimWorld = duel[0]
	var b: SimHero = duel[2]
	world._damage_hero(b, 100.0, SimConst.TEAM_DAWN, 0)
	_check(is_equal_approx(b.max_hp - b.hp, 100.0), "bronze armor absorbs nothing")
	world._grant_xp(SimConst.TEAM_DUSK, 99999.0)
	_check(world.team_level[SimConst.TEAM_DUSK] == SimConst.MAX_LEVEL, "experience is capped at the max level")
	var hp := b.hp
	world._damage_hero(b, 100.0, SimConst.TEAM_DAWN, 0)
	_check(is_equal_approx(hp - b.hp, 85.0), "gold armor absorbs 15%% of the damage (took %s)" % (hp - b.hp))


# ---------------------------------------------------------------------------
# Tous les héros : fiches et capacités
# ---------------------------------------------------------------------------

const ABILITY_KEYS: Dictionary = {
	"projectile": ["cooldown", "damage", "speed", "range", "radius", "pierce"],
	"volley": ["cooldown", "damage", "speed", "range", "radius", "pierce", "count", "spread"],
	"melee": ["cooldown", "damage", "range", "arc"],
	"zone": ["cooldown", "damage", "range", "radius", "delay"],
	"dash": ["cooldown", "distance", "duration"],
	"shield": ["cooldown", "amount", "duration"],
	"heal_area": ["cooldown", "amount", "range", "radius"],
	"haste": ["cooldown", "haste", "duration", "radius"],
}
const AI_ROLES: Array[String] = ["damage", "engage", "escape", "shield", "heal", "haste", "awaken"]


func _test_all_heroes_are_well_formed() -> void:
	var french: Translation = load("res://i18n/fr.po")
	var per_role: Array[int] = []
	for role in HeroDefs.ROLES:
		per_role.append(HeroDefs.ids_by_role(role).size())
	_check(per_role.min() >= 1 and per_role.min() == per_role.max(), "every role has the same number of heroes %s" % [per_role])
	_check(HeroDefs.ids().size() <= 255, "hero kinds fit in one byte on the network")
	for def_id: String in HeroDefs.ids():
		var def: Dictionary = HeroDefs.get_def(def_id)
		for key: String in ["name_key", "role_key", "look", "max_hp", "speed", "radius", "preferred_range", "abilities", "talents"]:
			_check(def.has(key), "%s has %s" % [def_id, key])
		_check(HeroDefs.ROLES.has(def["role_key"]), "%s has a known role" % def_id)
		_check(not String(french.get_message(def["name_key"])).is_empty(), "%s has a translated name" % def_id)
		_check(HeroDefs.id_at(HeroDefs.index_of(def_id)) == def_id, "%s keeps its identity on the network" % def_id)
		var abilities: Array = def["abilities"]
		_check(abilities.size() == 4, "%s has four abilities" % def_id)
		for slot in abilities.size():
			var ability: Dictionary = abilities[slot]
			var label := "%s ability %d" % [def_id, slot]
			_check(ABILITY_KEYS.has(ability["type"]), "%s has a known type" % label)
			for key: String in ABILITY_KEYS.get(ability["type"], []):
				_check(ability.has(key), "%s has %s" % [label, key])
			_check(AI_ROLES.has(ability.get("ai", "")), "%s tells bots when to use it" % label)
			_check(ability.get("awakening", false) == (slot == 3), "%s: only the fourth ability is the ultimate" % label)
			_check(not String(french.get_message(ability["name_key"])).is_empty(), "%s has a translated name" % label)
			_check(ability.has("slow") == ability.has("slow_duration"), "%s: a slow comes with its duration" % label)
		_check((abilities[3] as Dictionary).get("ai", "") == "awaken", "%s: bots know its ultimate" % def_id)
		# Talents : un palier par niveau de talent, deux choix, chacun modifiant une valeur qui existe.
		var hero := SimHero.new()
		hero.def_id = def_id
		var tiers: Array = def["talents"]
		_check(tiers.size() == SimConst.TALENT_LEVELS.size(), "%s has one talent tier per talent level" % def_id)
		for tier in tiers.size():
			var options: Array = tiers[tier]
			_check(options.size() == 2, "%s tier %d offers two talents" % [def_id, tier])
			for choice in options.size():
				var option: Dictionary = options[choice]
				var label := "%s talent %d%s" % [def_id, tier + 1, "AB"[choice]]
				_check(not String(french.get_message(option["name_key"])).is_empty() and not String(french.get_message(option["desc_key"])).is_empty(), "%s is translated" % label)
				for mod: Dictionary in option["mods"]:
					var slot: int = mod["slot"]
					var target: Dictionary = def if slot < 0 else abilities[slot]
					_check(target.has(mod["key"]), "%s changes a value that exists (%s)" % [label, mod["key"]])
					if not target.has(mod["key"]):
						continue
					var base := HeroDefs.value(hero, slot, mod["key"])
					hero.talents[tier] = choice + 1
					_check(not is_equal_approx(HeroDefs.value(hero, slot, mod["key"]), base), "%s has an effect" % label)
					hero.talents[tier] = 0


## Chaque capacité de chaque héros doit pouvoir se lancer et produire un effet visible.
func _test_every_ability_can_be_cast() -> void:
	for def_id: String in HeroDefs.ids():
		var arena := SimArena.new()
		arena.half_size = Vector2(40.0, 20.0)
		arena.spawns = [[Vector2.ZERO, Vector2(0.0, 2.5)], [Vector2(2.8, 0.0)]]
		var world := SimWorld.new(arena)
		var me := world.add_hero(SimConst.TEAM_DAWN, def_id)
		var ally := world.add_hero(SimConst.TEAM_DAWN)
		var enemy := world.add_hero(SimConst.TEAM_DUSK, "scutum")
		var abilities: Array = HeroDefs.get_def(def_id)["abilities"]
		for slot in abilities.size():
			# Remettre la scène en place : tout le monde blessé, face à face.
			me.pos = Vector2.ZERO
			ally.pos = Vector2(0.0, 2.5)
			enemy.pos = Vector2(2.8, 0.0)  # À portée des coups au corps à corps.
			for h: SimHero in [me, ally, enemy]:
				h.hp = h.max_hp * 0.5
				h.shield = 0.0
				h.haste_ticks = 0
				h.stun_ticks = 0
				h.slow_ticks = 0
				h.dash_left = 0.0
				h.last_hit_tick = world.tick
			me.cooldowns = [0.0, 0.0, 0.0]
			me.awaken_ticks = 0
			me.ether = SimConst.ETHER_MAX if slot == 3 else 0.0
			world.projectiles.clear()
			var before := _signature(world, me, ally, enemy)
			var press := _input(Vector2.ZERO, enemy.pos, 1 << slot)
			if (abilities[slot] as Dictionary)["type"] == "heal_area":
				press.aim = ally.pos
			world.step({me.id: press})
			var cast_ok := me.is_awakened() if slot == 3 else me.cooldowns[slot] > 0.0
			_check(cast_ok, "%s ability %d starts when its button is pressed" % [def_id, slot])
			_steps(world, 1.2, {me.id: _input(Vector2.ZERO, enemy.pos)})
			_check(_signature(world, me, ally, enemy) != before or world.projectiles.size() > 0,
					"%s ability %d has a visible effect" % [def_id, slot])
			_check(me.alive and is_finite(me.pos.x) and world.arena.is_inside(me.pos), "%s ability %d leaves the hero in a sane state" % [def_id, slot])


## Résumé de ce qu'une capacité peut changer autour d'elle.
func _signature(world: SimWorld, me: SimHero, ally: SimHero, enemy: SimHero) -> Array:
	return [
		roundi(enemy.hp), enemy.pos.snappedf(0.1), enemy.stun_ticks > 0, enemy.slow_ticks > 0,
		roundi(ally.hp), ceili(ally.shield), ally.haste_ticks > 0,
		roundi(me.hp), ceili(me.shield), me.haste_ticks > 0, me.pos.snappedf(0.1),
	]


# ---------------------------------------------------------------------------
# Nouvelles mécaniques : zone, repoussement, charge, hâte, vol de vie
# ---------------------------------------------------------------------------

func _test_delayed_zone() -> void:
	var duel := _duel(Vector2.ZERO, Vector2(8.0, 0.0), "corona", "sagitta")
	var world: SimWorld = duel[0]
	var mage: SimHero = duel[1]
	var target: SimHero = duel[2]
	var runner := world.add_hero(SimConst.TEAM_DUSK)
	runner.pos = Vector2(8.0, 1.5)
	var minion := world._spawn_unit(UnitDefs.FOOTMAN, SimConst.TEAM_DUSK, Vector2(8.0, -1.5))
	minion.attack_cd = 1000.0
	world.step({mage.id: _input(Vector2.ZERO, target.pos, SimConst.BTN_ABILITY_1)})
	var warned := false
	for beam: Array in world.beams:
		if beam[0] == SimWorld.FX_WARN and (beam[1] as Vector2).is_equal_approx(target.pos):
			warned = true
	_check(warned, "a zone is announced on the ground where it will strike")
	# Le coureur quitte la zone pendant le délai ; la cible reste.
	_steps(world, 0.5, {runner.id: _input(Vector2.DOWN, Vector2.ZERO)})
	_check(is_equal_approx(target.hp, target.max_hp), "a zone does nothing before its delay")
	_steps(world, 0.5, {runner.id: _input(Vector2.DOWN, Vector2.ZERO)})
	_check(is_equal_approx(target.max_hp - target.hp, 250.0), "a zone strikes whoever is still inside (dealt %s)" % (target.max_hp - target.hp))
	_check(is_equal_approx(runner.hp, runner.max_hp), "leaving the zone in time avoids it")
	_check(minion.hp < minion.max_hp, "a zone also hits minions")
	# Hors de portée : la zone se pose à la limite de portée.
	mage.cooldowns[1] = 0.0
	target.pos = Vector2(30.0, 0.0)
	target.hp = target.max_hp
	world.step({mage.id: _input(Vector2.ZERO, target.pos, SimConst.BTN_ABILITY_1)})
	_steps(world, 1.0)
	_check(is_equal_approx(target.hp, target.max_hp), "a zone cannot be cast beyond its range")
	world.reset_match()
	_check(world._zones.is_empty(), "pending zones are cleared for a new match")


func _test_knockback_and_pull() -> void:
	# Lame de fond : un projectile qui repousse dans le sens du tir.
	var duel := _duel(Vector2.ZERO, Vector2(5.0, 0.0), "cetus", "sagitta")
	var world: SimWorld = duel[0]
	var whale: SimHero = duel[1]
	var target: SimHero = duel[2]
	var push := HeroDefs.value(whale, 1, "knockback")
	world.step({whale.id: _input(Vector2.ZERO, target.pos, SimConst.BTN_ABILITY_1)})
	_steps(world, 1.0)
	_check(push > 0.0 and target.hp < target.max_hp and absf(target.pos.x - 5.0 - push) < 0.3, "the groundswell pushes its target away (x=%s)" % target.pos.x)
	_check(target.slow_ticks > 0, "the groundswell also slows its target")
	_check(absf(target.pos.y) < 0.2, "the push follows the direction of the shot")
	# Le client peut rejouer la poussée : elle voyage comme une ruée.
	_check(is_zero_approx(target.dash_left), "the push is over after a moment")

	# Lasso : attire la cible vers le lanceur, sans la faire passer derrière lui.
	var duel2 := _duel(Vector2.ZERO, Vector2(8.0, 0.0), "lynx", "sagitta")
	var world2: SimWorld = duel2[0]
	var huntress: SimHero = duel2[1]
	var prey: SimHero = duel2[2]
	world2.step({huntress.id: _input(Vector2.ZERO, prey.pos, SimConst.BTN_ABILITY_1)})
	_steps(world2, 1.0)
	_check(absf(prey.pos.x - 3.0) < 0.3, "the lasso pulls its target 5 units closer (x=%s)" % prey.pos.x)
	prey.pos = Vector2(3.0, 0.0)
	huntress.cooldowns[1] = 0.0
	world2.step({huntress.id: _input(Vector2.ZERO, prey.pos, SimConst.BTN_ABILITY_1)})
	_steps(world2, 1.0)
	_check(prey.pos.x >= 1.4, "a pull never drags the target past the caster (x=%s)" % prey.pos.x)

	# Ruade : coup au corps à corps qui repousse ; un étourdi est poussé quand même.
	var duel3 := _duel(Vector2.ZERO, Vector2(2.0, 0.0), "centaurus", "sagitta")
	var world3: SimWorld = duel3[0]
	var centaur: SimHero = duel3[1]
	var victim: SimHero = duel3[2]
	victim.stun_ticks = 60
	world3.step({centaur.id: _input(Vector2.ZERO, victim.pos, SimConst.BTN_ABILITY_1)})
	_steps(world3, 0.5)
	_check(absf(victim.pos.x - 7.0) < 0.3, "the hind kick sends a stunned target 5 units away (x=%s)" % victim.pos.x)
	# Contre le bord du terrain, la poussée s'arrête au mur.
	victim.pos = Vector2(world3.arena.half_size.x - 1.5, 0.0)
	centaur.pos = victim.pos - Vector2(2.0, 0.0)
	centaur.cooldowns[1] = 0.0
	world3.step({centaur.id: _input(Vector2.ZERO, victim.pos, SimConst.BTN_ABILITY_1)})
	_steps(world3, 0.5)
	_check(world3.arena.is_inside(victim.pos) and victim.pos.x <= world3.arena.half_size.x - 0.6 + 0.001, "a push stops at the arena border")


func _test_charging_dash() -> void:
	var duel := _duel(Vector2.ZERO, Vector2(4.0, 0.0), "ursa", "sagitta")
	var world: SimWorld = duel[0]
	var bear: SimHero = duel[1]
	var target: SimHero = duel[2]
	var bystander := world.add_hero(SimConst.TEAM_DUSK)
	bystander.pos = Vector2(4.0, 8.0)
	world.step({bear.id: _input(Vector2.RIGHT, target.pos, SimConst.BTN_ABILITY_1)})
	_steps(world, 0.6, {bear.id: _input(Vector2.ZERO, target.pos)})
	_check(is_equal_approx(target.max_hp - target.hp, 140.0), "a charge hits the enemy in its path exactly once (dealt %s)" % (target.max_hp - target.hp))
	_check(target.pos.x > 5.5, "a charge knocks its target back (x=%s)" % target.pos.x)
	_check(is_equal_approx(bystander.hp, bystander.max_hp), "a charge ignores enemies away from its path")
	_check(bear.dash_slot == -1 and bear.dash_hits.is_empty(), "the charge state is cleared at the end")

	# Plongeon : une ruée visée part vers le point visé, même si le héros marche ailleurs.
	var duel2 := _duel(Vector2.ZERO, Vector2(5.0, 0.0), "corvus", "sagitta")
	var world2: SimWorld = duel2[0]
	var raven: SimHero = duel2[1]
	var prey: SimHero = duel2[2]
	var predicted := raven.copy()
	var dive := _input(Vector2.UP, prey.pos, SimConst.BTN_ABILITY_1)
	SimWorld.step_hero_local(predicted, dive, world2.arena, SimConst.DT)
	world2.step({raven.id: dive})
	_check(raven.dash_vel.normalized().is_equal_approx(Vector2.RIGHT), "an aimed dash goes towards the aim point")
	_check(predicted.pos.is_equal_approx(raven.pos) and predicted.dash_vel.is_equal_approx(raven.dash_vel), "an aimed dash is predicted identically by the client")
	_steps(world2, 0.5, {raven.id: _input(Vector2.ZERO, prey.pos)})
	_check(prey.hp < prey.max_hp, "the dive damages its target")

	# Charge du centaure : une ruée en guise de capacité ultime.
	var duel3 := _duel(Vector2.ZERO, Vector2(6.0, 0.0), "centaurus", "sagitta")
	var world3: SimWorld = duel3[0]
	var centaur: SimHero = duel3[1]
	var victim: SimHero = duel3[2]
	centaur.ether = SimConst.ETHER_MAX
	world3.step({centaur.id: _input(Vector2.ZERO, victim.pos, SimConst.BTN_AWAKEN)})
	_check(centaur.is_awakened() and centaur.dash_left > 0.0, "an ultimate dash starts with the awakening")
	_steps(world3, 0.3, {centaur.id: _input(Vector2.ZERO, victim.pos, SimConst.BTN_AWAKEN)})
	_check(victim.hp < victim.max_hp and victim.stun_ticks > 0, "the centaur's charge hits and stuns")
	_steps(world3, 1.0, {centaur.id: _input(Vector2.ZERO, victim.pos, SimConst.BTN_AWAKEN)})
	_check(centaur.pos.x > 9.0 and centaur.pos.x < 12.5, "the ultimate dash happens once (x=%s)" % centaur.pos.x)

	# Tempête de plumes : une volée tout autour, sans deux traits dans la même direction.
	raven.ether = SimConst.ETHER_MAX
	world2.projectiles.clear()
	world2.step({raven.id: _input(Vector2.ZERO, prey.pos, SimConst.BTN_AWAKEN)})
	var directions: Dictionary = {}
	for p in world2.projectiles:
		directions[roundi(rad_to_deg(p.vel.angle()))] = true
	_check(world2.projectiles.size() == 12 and directions.size() == 12, "a full-circle volley spreads evenly (%d directions)" % directions.size())


func _test_haste_and_lifesteal() -> void:
	var duel := _duel(Vector2.ZERO, Vector2(1.8, 0.0), "corvus", "scutum")
	var world: SimWorld = duel[0]
	var raven: SimHero = duel[1]
	var target: SimHero = duel[2]
	# Vol de vie : une part des dégâts infligés revient en vie.
	# Les valeurs viennent de la fiche du héros : l'équilibrage peut les changer.
	var lifesteal := HeroDefs.value(raven, 0, "lifesteal")
	var claw := HeroDefs.value(raven, 0, "damage")
	raven.hp = 500.0
	raven.last_hit_tick = world.tick
	world.step({raven.id: _input(Vector2.ZERO, target.pos, SimConst.BTN_ATTACK)})
	_check(lifesteal > 0.0 and is_equal_approx(target.max_hp - target.hp, claw) and is_equal_approx(raven.hp, 500.0 + claw * lifesteal), "a lifesteal attack heals its user (hp=%s)" % raven.hp)

	# Hâte : +40 % de vitesse pendant 3 secondes, prédite à l'identique par le client.
	target.pos = Vector2(30.0, 10.0)
	raven.pos = Vector2.ZERO
	var haste := HeroDefs.value(raven, 2, "haste")
	world.step({raven.id: _input(Vector2.ZERO, Vector2(0.0, -10.0), SimConst.BTN_ABILITY_2)})
	_check(raven.haste_ticks == 90 and raven.haste_pct == roundi(haste * 100.0) and haste > 0.0, "haste is applied for its duration")
	var predicted := raven.copy()
	var start := raven.pos
	var worst := 0.0
	for i in SimConst.TICK_RATE:
		var cmd := _input(Vector2.UP, Vector2(0.0, -50.0))
		SimWorld.step_hero_local(predicted, cmd, world.arena, SimConst.DT)
		world.step({raven.id: cmd})
		worst = maxf(worst, predicted.pos.distance_to(raven.pos))
	_check(absf(start.y - raven.pos.y - 6.4 * (1.0 + haste)) < 0.05, "a hasted hero moves faster (%s)" % (start.y - raven.pos.y))
	_check(worst < 0.0001, "haste is predicted identically by the client")
	_steps(world, 2.5)
	start = raven.pos
	_steps(world, 1.0, {raven.id: _input(Vector2.DOWN, Vector2(0.0, 50.0))})
	_check(absf(raven.pos.y - start.y - 6.4) < 0.05, "haste wears off")

	# Ivresse divine : les alliés proches accélèrent, pas les adversaires ni les alliés éloignés.
	var arena := SimArena.new()
	arena.half_size = Vector2(40.0, 20.0)
	arena.spawns = [[Vector2.ZERO, Vector2(3.0, 0.0), Vector2(20.0, 0.0)], [Vector2(0.0, 3.0)]]
	var other := SimWorld.new(arena)
	var hebe := other.add_hero(SimConst.TEAM_DAWN, "crater")
	var near := other.add_hero(SimConst.TEAM_DAWN)
	var far := other.add_hero(SimConst.TEAM_DAWN)
	var foe := other.add_hero(SimConst.TEAM_DUSK)
	other.step({hebe.id: _input(Vector2.ZERO, Vector2(5.0, 0.0), SimConst.BTN_ABILITY_2)})
	_check(hebe.haste_ticks > 0 and near.haste_ticks > 0, "an area haste speeds up nearby allies")
	_check(far.haste_ticks == 0 and foe.haste_ticks == 0, "an area haste ignores distant allies and enemies")
	_check(near.shield > 0.0 and hebe.shield > 0.0 and is_zero_approx(far.shield) and is_zero_approx(foe.shield), "a haste can shield the same allies")
	# La hâte voyage sur le réseau.
	var copy := SimSnapshot.from_bytes(other.to_snapshot(), arena)
	var near2: SimHero = copy.heroes[near.id]
	_check(near2.haste_ticks == near.haste_ticks and near2.haste_pct == near.haste_pct and near.haste_pct > 0, "haste survives the network roundtrip")


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
	var tank := world.add_hero(SimConst.TEAM_DAWN, "scutum")
	tank.ether = 63.7
	tank.awaken_ticks = 120
	tank.stun_ticks = 14
	tank.slow_ticks = 40
	tank.slow_pct = 50
	tank.shield = 321.0
	tank.talents = [2, 1, 0]
	var wire := world.to_snapshot()
	var snap := SimSnapshot.from_bytes(wire, SimArena.make_default())
	_check(snap != null, "a snapshot decodes")
	if snap == null:
		return
	var tank2: SimHero = snap.heroes[tank.id]
	_check(tank2.def_id == "scutum" and is_equal_approx(tank2.ether, 63.0), "hero kind and ether survive the roundtrip")
	_check(tank2.awaken_ticks == 120 and tank2.stun_ticks == 14 and tank2.slow_ticks == 40 and tank2.slow_pct == 50, "status timers survive the roundtrip exactly")
	_check(is_equal_approx(tank2.shield, 321.0) and tank2.talents == [2, 1, 0], "shield and talents survive the roundtrip")
	var a2: SimHero = snap.heroes[a.id]
	_check(snap.tick == world.tick and snap.heroes.size() == 3, "tick and heroes survive the roundtrip")
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
		var hero := world.add_hero(i % 2)
		hero.ether = SimConst.ETHER_MAX
	while world.units.size() < SimConst.MAX_UNITS_HARD:
		var u := world._spawn_unit(UnitDefs.ARCHER, world.units.size() % 2, Vector2(world.units.size() - 30.0, 25.0))
		u.attack_cd = 1000.0
	var largest := 0
	for i in SimConst.TICK_RATE * 4:
		var inputs: Dictionary = {}
		for id: int in world.heroes:
			# Tout le monde tire et s'éveille en même temps : six volées de sept traits.
			inputs[id] = _input(Vector2.ZERO, Vector2(0.0, -30.0), SimConst.BTN_ATTACK | SimConst.BTN_ABILITY_1 | SimConst.BTN_AWAKEN)
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
