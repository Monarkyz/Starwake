extends SceneTree
## Tests des commandes tactiles : des doigts virtuels sont posés sur TouchControls, et
## l'on vérifie la commande que TouchInput en tire pour le serveur.
## Lancement : godot --headless --path . -s tests/test_touch.gd

const SCREEN := Vector2(1280.0, 720.0)

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	_test_joystick()
	_test_attack_button_and_auto_aim()
	_test_ability_tap_and_manual_aim()
	_test_heal_auto_aim()
	_test_awaken_and_multitouch()
	_test_interface_scale()
	_test_reserved_areas()
	_test_small_screen_layout()
	print("%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + label)


func _controls() -> TouchControls:
	var controls := TouchControls.new()
	controls.size = SCREEN
	return controls


func _input_for(controls: TouchControls) -> TouchInput:
	var input := TouchInput.new()
	input.controls = controls
	return input


## Monde vide vu par le client : un héros du joueur et ce qu'on y ajoute.
func _world(hero: String = "sagitta") -> Array:
	var arena := SimArena.new()
	arena.half_size = Vector2(40.0, 20.0)
	arena.spawns = [[Vector2.ZERO, Vector2(4.0, 3.0), Vector2(-6.0, 0.0)], [Vector2(8.0, 0.0), Vector2(5.0, 0.0), Vector2(30.0, 0.0)]]
	var world := SimWorld.new(arena)
	var me := world.add_hero(SimConst.TEAM_DAWN, hero)
	return [world, me]


func _snapshot(world: SimWorld) -> SimSnapshot:
	return SimSnapshot.from_bytes(world.to_snapshot(), world.arena)


func _test_joystick() -> void:
	var controls := _controls()
	_check(controls.move_vector() == Vector2.ZERO, "the joystick is at rest without a finger")
	var origin := Vector2(200.0, 500.0)
	_check(controls.handle_touch(0, origin, true), "a finger on the left half grabs the joystick")
	controls.handle_drag(0, origin + Vector2(TouchControls.STICK_RADIUS, 0.0))
	_check(controls.move_vector().is_equal_approx(Vector2.RIGHT), "a full push to the right moves right at full speed")
	controls.handle_drag(0, origin + Vector2(0.0, -400.0))
	_check(controls.move_vector().is_equal_approx(Vector2.UP), "a push beyond the rim is clamped to full speed")
	controls.handle_drag(0, origin + Vector2(TouchControls.STICK_RADIUS * 0.1, 0.0))
	_check(controls.move_vector() == Vector2.ZERO, "a tiny push stays inside the dead zone")
	controls.handle_drag(0, origin + Vector2(TouchControls.STICK_RADIUS * 0.6, 0.0))
	var half := controls.move_vector().length()
	_check(half > 0.3 and half < 0.7, "a partial push gives a partial speed (%s)" % half)
	# Un second doigt ailleurs à gauche ne vole pas le joystick.
	_check(not controls.handle_touch(5, Vector2(100.0, 300.0), true), "a second finger cannot grab the joystick")
	controls.handle_drag(5, Vector2(600.0, 300.0))
	_check(absf(controls.move_vector().length() - half) < 0.001, "the joystick only follows its own finger")
	_check(controls.handle_touch(0, origin, false) and controls.move_vector() == Vector2.ZERO, "lifting the finger stops the hero")
	_check(not controls.handle_touch(0, Vector2(700.0, 200.0), true), "a touch on empty space is left to the rest of the interface")

	# Sans bouton pressé, le héros regarde là où il va.
	var setup := _world()
	var me: SimHero = setup[1]
	var input := _input_for(controls)
	controls.handle_touch(0, origin, true)
	controls.handle_drag(0, origin + Vector2(0.0, TouchControls.STICK_RADIUS))
	var cmd := input.build(me, _snapshot(setup[0]))
	_check(cmd.buttons == 0 and cmd.move.is_equal_approx(Vector2.DOWN), "the joystick alone presses no button")
	_check((cmd.aim - me.pos).normalized().is_equal_approx(Vector2.DOWN), "the hero faces its direction of travel")
	controls.free()


func _test_attack_button_and_auto_aim() -> void:
	var controls := _controls()
	var input := _input_for(controls)
	var setup := _world()
	var world: SimWorld = setup[0]
	var me: SimHero = setup[1]
	me.facing = Vector2.UP

	# Rien à portée : le tir part droit devant.
	controls.handle_touch(1, controls.button_center(0), true)
	var cmd := input.build(me, _snapshot(world))
	_check(cmd.buttons == SimConst.BTN_ATTACK, "holding the attack button attacks")
	_check((cmd.aim - me.pos).normalized().is_equal_approx(Vector2.UP), "with no target, the attack goes straight ahead")
	cmd = input.build(me, _snapshot(world))
	_check(cmd.buttons == SimConst.BTN_ATTACK, "the attack keeps going while the button is held")

	# Un bâtiment, puis une unité, puis un héros : chacun passe devant le précédent.
	var far_hero := world.add_hero(SimConst.TEAM_DUSK)  # (8, 0) : à portée de tir
	far_hero.pos = Vector2(30.0, 0.0)
	var unit := world._spawn_unit(UnitDefs.FOOTMAN, SimConst.TEAM_DUSK, Vector2(0.0, 6.0))
	cmd = input.build(me, _snapshot(world))
	_check(cmd.aim.distance_to(unit.pos) < 0.05, "the attack auto-aims at an enemy minion in range")
	var ally_unit := world._spawn_unit(UnitDefs.FOOTMAN, SimConst.TEAM_DAWN, Vector2(0.0, 2.0))
	cmd = input.build(me, _snapshot(world))
	_check(cmd.aim.distance_to(unit.pos) < 0.05 and ally_unit.alive, "allied minions are never targeted")
	far_hero.pos = Vector2(-7.0, 0.0)
	cmd = input.build(me, _snapshot(world))
	_check(cmd.aim.distance_to(far_hero.pos) < 0.05, "an enemy hero in range is preferred over a closer minion")
	far_hero.alive = false
	cmd = input.build(me, _snapshot(world))
	_check(cmd.aim.distance_to(unit.pos) < 0.05, "a dead hero is ignored")

	# Glisser hors du bouton : visée manuelle, qui prime sur la visée automatique.
	controls.handle_drag(1, controls.button_center(0) + Vector2(-60.0, 0.0))
	cmd = input.build(me, _snapshot(world))
	_check((cmd.aim - me.pos).normalized().is_equal_approx(Vector2.LEFT), "dragging off the button aims by hand")
	_check(controls.preview()[0] == 0 and (controls.preview()[1] as Vector2).is_equal_approx(Vector2.LEFT), "the manual aim is available for display")
	controls.handle_touch(1, Vector2.ZERO, false)
	cmd = input.build(me, _snapshot(world))
	_check(cmd.buttons == 0, "releasing the attack button stops attacking")
	controls.free()


func _test_ability_tap_and_manual_aim() -> void:
	var controls := _controls()
	var input := _input_for(controls)
	var setup := _world()
	var world: SimWorld = setup[0]
	var me: SimHero = setup[1]
	var enemy := world.add_hero(SimConst.TEAM_DUSK)  # (8, 0)

	controls.handle_touch(2, controls.button_center(1), true)
	var cmd := input.build(me, _snapshot(world))
	_check(cmd.buttons == 0, "an ability does not fire while its button is held")
	controls.handle_touch(2, controls.button_center(1), false)
	cmd = input.build(me, _snapshot(world))
	_check(cmd.buttons == SimConst.BTN_ABILITY_1, "an ability fires when its button is released")
	_check(cmd.aim.distance_to(enemy.pos) < 0.05, "a simple tap auto-aims at the enemy hero")
	var pulses := 1
	while input.build(me, _snapshot(world)).buttons != 0 and pulses < 10:
		pulses += 1
	_check(pulses == TouchControls.PULSE_TICKS, "a tap presses the ability for a couple of steps only (%d)" % pulses)

	# Viser à la main : toucher, glisser, relâcher.
	controls.handle_touch(2, controls.button_center(1), true)
	controls.handle_drag(2, controls.button_center(1) + Vector2(0.0, -80.0))
	_check(controls.preview()[0] == 1, "the aimed ability is shown while dragging")
	controls.handle_touch(2, controls.button_center(1) + Vector2(0.0, -80.0), false)
	cmd = input.build(me, _snapshot(world))
	_check(cmd.buttons == SimConst.BTN_ABILITY_1, "a dragged ability fires on release")
	_check((cmd.aim - me.pos).normalized().is_equal_approx(Vector2.UP), "it goes where the finger pointed, not at the enemy")
	_check(is_equal_approx((cmd.aim - me.pos).length(), 16.0), "the aim point sits at the ability's range")
	_check(controls.preview()[0] == -1, "the aim display ends with the drag")

	# La commande fait bien partir le trait dans la simulation.
	me.cooldowns[1] = 0.0
	var shots := world.projectiles.size()
	world.step({me.id: cmd})
	_check(world.projectiles.size() == shots + 1 and world.projectiles[-1].vel.normalized().is_equal_approx(Vector2.UP), "the simulation fires the bolt in that direction")
	controls.free()


func _test_heal_auto_aim() -> void:
	var controls := _controls()
	var input := _input_for(controls)
	var setup := _world("columba")
	var world: SimWorld = setup[0]
	var me: SimHero = setup[1]
	var near_ally := world.add_hero(SimConst.TEAM_DAWN)  # (4, 3)
	var other_ally := world.add_hero(SimConst.TEAM_DAWN)  # (-6, 0)
	var enemy := world.add_hero(SimConst.TEAM_DUSK)  # (8, 0)
	enemy.hp = 10.0
	near_ally.hp = near_ally.max_hp * 0.6
	other_ally.hp = other_ally.max_hp * 0.3

	controls.handle_touch(2, controls.button_center(1), true)
	controls.handle_touch(2, controls.button_center(1), false)
	var cmd := input.build(me, _snapshot(world))
	_check(cmd.aim.distance_to(other_ally.pos) < 0.05, "the heal auto-aims at the most wounded ally, not at an enemy")
	other_ally.hp = other_ally.max_hp
	near_ally.hp = near_ally.max_hp
	me.hp = me.max_hp * 0.5
	controls.reset()
	controls.handle_touch(2, controls.button_center(1), true)
	controls.handle_touch(2, controls.button_center(1), false)
	cmd = input.build(me, _snapshot(world))
	_check(cmd.aim.distance_to(me.pos) < 0.05, "the heal lands on the healer when she is the one wounded")
	controls.free()


func _test_awaken_and_multitouch() -> void:
	var controls := _controls()
	var input := _input_for(controls)
	var setup := _world()
	var world: SimWorld = setup[0]
	var me: SimHero = setup[1]
	world.add_hero(SimConst.TEAM_DUSK)
	me.ether = SimConst.ETHER_MAX

	# Trois doigts à la fois : joystick, attaque maintenue, éveil touché.
	var origin := Vector2(220.0, 520.0)
	controls.handle_touch(0, origin, true)
	controls.handle_drag(0, origin + Vector2(-TouchControls.STICK_RADIUS, 0.0))
	controls.handle_touch(1, controls.button_center(0), true)
	controls.handle_touch(2, controls.button_center(3), true)
	controls.handle_touch(2, controls.button_center(3), false)
	var cmd := input.build(me, _snapshot(world))
	_check(cmd.move.is_equal_approx(Vector2.LEFT), "the joystick works while buttons are pressed")
	_check(cmd.buttons == (SimConst.BTN_ATTACK | SimConst.BTN_AWAKEN), "attack and awakening are pressed together")
	world.step({me.id: cmd})
	_check(me.is_awakened() and world.projectiles.size() >= 7, "the awakening triggers and fires the ultimate")

	# Les boutons ne se chevauchent pas et tiennent dans l'écran.
	for a in TouchControls.BUTTONS.size():
		var center_a := controls.button_center(a)
		var radius_a: float = TouchControls.BUTTONS[a][1]
		_check(center_a.x + radius_a <= SCREEN.x and center_a.y + radius_a <= SCREEN.y and center_a.x - radius_a > SCREEN.x * 0.5, "button %d fits on the right side of the screen" % a)
		for b in range(a + 1, TouchControls.BUTTONS.size()):
			var radius_b: float = TouchControls.BUTTONS[b][1]
			_check(center_a.distance_to(controls.button_center(b)) >= radius_a + radius_b + 8.0, "buttons %d and %d do not overlap" % [a, b])
	controls.reset()
	_check(controls.move_vector() == Vector2.ZERO and input.build(me, _snapshot(world)).buttons == 0, "reset releases every finger")
	controls.free()


## Grossissement de l'interface selon la taille réelle de l'écran.
func _test_interface_scale() -> void:
	_check(UiScale.compute(Vector2i(1920, 1080), 96) == 1.0, "a screen without a reliable density is left alone")
	_check(UiScale.compute(Vector2i(0, 0), 420) == 1.0, "an empty window is left alone")
	# Téléphone courant : 2400 × 1080 à 420 points par pouce, soit 411 dp de haut.
	var phone := UiScale.compute(Vector2i(2400, 1080), 420)
	_check(phone > 1.35 and phone < 1.45, "the interface grows by about 40 %% on a common phone (%s)" % phone)
	_check(is_equal_approx(UiScale.compute(Vector2i(1080, 2400), 420), phone), "the result does not depend on the orientation")
	# Une cible de menu mesure alors au moins 45 dp (7 mm).
	var target_dp := UiScale.TOUCH_TARGET * phone * (411.0 / UiScale.BASE_HEIGHT)
	_check(target_dp >= 45.0, "a menu button is finger-sized on a common phone (%s dp)" % target_dp)
	# Petit téléphone allongé : on s'arrête à 480 unités de haut.
	_check(is_equal_approx(UiScale.compute(Vector2i(2340, 1080), 480), 1.5), "a small phone gets the largest scale")
	# Téléphone 16:9 : on grossit moins pour garder 960 unités de large.
	var old_phone := UiScale.compute(Vector2i(1920, 1080), 480)
	_check(is_equal_approx(old_phone, 1280.0 / UiScale.MIN_WIDTH), "a 16:9 phone keeps enough width (%s)" % old_phone)
	_check(UiScale.compute(Vector2i(2560, 1600), 320) == 1.0, "a tablet keeps the computer layout")
	for dpi: int in [160, 240, 320, 420, 560, 640]:
		for window: Vector2i in [Vector2i(1280, 720), Vector2i(2400, 1080), Vector2i(3120, 1440), Vector2i(2048, 1536)]:
			var scale := UiScale.compute(window, dpi)
			var logical := Vector2(window) / (minf(window.x / UiScale.BASE_WIDTH, window.y / UiScale.BASE_HEIGHT) * scale)
			_check(scale >= 1.0 and logical.x >= UiScale.MIN_WIDTH - 0.01 and logical.y >= UiScale.MIN_HEIGHT - 0.01,
					"the interface never gets smaller than its minimum layout (%s at %d dpi: %s)" % [window, dpi, logical])


## Un doigt posé sur un élément de l'interface (talent, bouton Menu) n'est pas pour le joystick.
func _test_reserved_areas() -> void:
	var controls := _controls()
	var talent := Rect2(300.0, 400.0, 330.0, 92.0)
	controls.reserved = func(pos: Vector2) -> bool: return talent.has_point(pos)
	_check(not controls.handle_touch(0, Vector2(400.0, 440.0), true), "a finger on a talent is left to the interface")
	_check(controls.move_vector() == Vector2.ZERO and not controls.handle_touch(0, Vector2(400.0, 440.0), false),
			"that finger never becomes the joystick")
	_check(controls.handle_touch(1, Vector2(200.0, 600.0), true), "a finger next to the talent still grabs the joystick")


## Sur un écran de téléphone, rien ne se chevauche : bandeau, talents, boutons.
func _test_small_screen_layout() -> void:
	var desktop := Hud.talent_layout(SCREEN, Vector4.ZERO, false, 0.0)
	_check(desktop[0].position.is_equal_approx(Vector2(303.0, 458.0)) and desktop[1].end.x == 977.0,
			"on a computer the talents stay above the ability bar (%s)" % desktop[0])
	_check(Hud.fit_in_span(Hud.top_span(SCREEN, Vector4.ZERO, false), SCREEN.x, Hud.TOP_BAR_SIZE.x) == Vector2(310.0, 1.0),
			"on a computer the top bar stays centred at full size")
	var notch := Vector4(44.0, 0.0, 0.0, 21.0)
	for screen: Vector2 in [Vector2(960.0, 540.0), Vector2(1067.0, 480.0), Vector2(1142.0, 514.0), Vector2(1600.0, 720.0)]:
		for margins: Vector4 in [Vector4.ZERO, notch]:
			var label := "%s with margins %s" % [screen, margins]
			var controls := TouchControls.new()
			controls.size = screen
			controls.margins = margins
			# Bandeau du haut : entre le bouton Menu et la minicarte, encore lisible.
			var span := Hud.top_span(screen, margins, true)
			var fit := Hud.fit_in_span(span, screen.x, Hud.TOP_BAR_SIZE.x)
			_check(fit.x >= span.x - 0.01 and fit.x + Hud.TOP_BAR_SIZE.x * fit.y <= span.y + 0.01, "the top bar fits between the menu button and the minimap (%s)" % label)
			_check(fit.y >= 0.75, "the top bar stays readable (%s, scale %s)" % [label, fit.y])
			_check(span.x >= margins.x + 16.0 + Hud.LEAVE_SIZE.x, "the top bar leaves the menu button free (%s)" % label)
			# Talents : dans l'écran, assez larges, et jamais sous un bouton de capacité.
			var rects := Hud.talent_layout(screen, margins, true, 122.0)
			_check(rects[0].position.x >= margins.x and rects[1].end.x <= screen.x - margins.z, "the talents stay on screen (%s)" % label)
			_check(rects[0].size.x >= 240.0 and rects[0].end.x < rects[1].position.x, "the talents are wide enough and side by side (%s)" % label)
			for slot in TouchControls.BUTTONS.size():
				var center := controls.button_center(slot)
				var radius: float = TouchControls.BUTTONS[slot][1] + TouchControls.TOUCH_SLACK
				for rect in rects:
					var nearest := center.clamp(rect.position, rect.end)
					_check(nearest.distance_to(center) > radius, "no talent sits under ability button %d (%s)" % [slot, label])
				_check(center.y - radius > 0.0 and center.x + radius - TouchControls.TOUCH_SLACK <= screen.x, "ability button %d is on screen (%s)" % [slot, label])
			controls.free()
