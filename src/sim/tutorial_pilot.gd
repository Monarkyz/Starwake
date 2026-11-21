class_name TutorialPilot
extends RefCounted
## Pilote automatique du tutoriel : il accomplit chaque étape comme le ferait un joueur
## appliqué. Sert aux tests, pour vérifier que le tutoriel se termine du début à la fin.
## Le choix du talent reste à faire par l'appelant, qui seul peut le demander au serveur.

var _brain := BotBrain.new(1)


func think(me: SimHero, view: Variant, step: int) -> SimInput:
	var cmd := SimInput.new()
	cmd.aim = me.pos + me.facing
	if not me.alive:
		return cmd
	match step:
		TutorialDirector.STEP_MOVE:
			cmd.move = (TutorialDirector.marker(step) - me.pos).limit_length(1.0)
			cmd.aim = me.pos + cmd.move
		TutorialDirector.STEP_ATTACK, TutorialDirector.STEP_BOLT:
			_attack_units(me, view, cmd)
		TutorialDirector.STEP_DASH:
			cmd.move = Vector2.RIGHT
			cmd.aim = me.pos + Vector2.RIGHT
			cmd.buttons = SimConst.BTN_ABILITY_2
		TutorialDirector.STEP_AWAKEN:
			_attack_units(me, view, cmd)
			if me.ether >= SimConst.ETHER_MAX:
				cmd.buttons |= SimConst.BTN_AWAKEN
		TutorialDirector.STEP_RELIC:
			var arena: SimArena = view.arena
			if me.pos.distance_to(arena.altar) > arena.altar_radius - 1.2:
				cmd.move = (arena.altar - me.pos).limit_length(1.0)
		TutorialDirector.STEP_TEMPLE, TutorialDirector.STEP_CORE:
			return _brain.think(me, view)
	return cmd


## Viser l'unité adverse la plus proche, s'en approcher si besoin, et tirer.
func _attack_units(me: SimHero, view: Variant, cmd: SimInput) -> void:
	var target: SimUnit = null
	var best := INF
	for u: SimUnit in view.units:
		if u.team == me.team or not u.alive:
			continue
		var d := u.pos.distance_squared_to(me.pos)
		if d < best:
			best = d
			target = u
	if target == null:
		return
	cmd.aim = target.pos
	if sqrt(best) > 7.5:
		cmd.move = (target.pos - me.pos).normalized()
	else:
		cmd.buttons = SimConst.BTN_ATTACK | SimConst.BTN_ABILITY_1
