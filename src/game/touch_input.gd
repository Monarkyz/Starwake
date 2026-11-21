class_name TouchInput
extends RefCounted
## Commandes tactiles : transforme l'état de TouchControls en commande pour le serveur.
##
## Sur un écran tactile, viser un tir au doigt est plus lent qu'à la souris. Pour que les
## joueurs sur mobile et sur PC puissent s'affronter, une capacité lancée sans glisser
## vise toute seule : le héros adverse le plus proche à portée, sinon une unité, sinon un
## bâtiment. Les soins visent l'allié le plus blessé.

var controls: TouchControls


func sample(client: GameClient) -> SimInput:
	return build(client.local, client.latest_snapshot())


func build(me: SimHero, snap: SimSnapshot) -> SimInput:
	var cmd := SimInput.new()
	cmd.move = controls.move_vector()
	var aim: Array = controls.active_aim()
	cmd.buttons = controls.take_buttons()
	var slot: int = aim[0]
	var dir: Vector2 = aim[1]
	if slot >= 0 and dir != Vector2.ZERO:
		cmd.aim = me.pos + dir * maxf(reach(me, slot), 3.0)
	elif slot >= 0:
		cmd.aim = auto_aim(me, snap, slot)
	elif cmd.move.length_squared() > 0.04:
		# Rien à viser : le héros regarde là où il va.
		cmd.aim = me.pos + cmd.move.normalized() * 5.0
	else:
		cmd.aim = me.pos + me.facing * 5.0
	return cmd


## Portée d'une capacité, pour la visée ; zéro si elle ne se vise pas.
static func reach(me: SimHero, slot: int) -> float:
	var abilities: Array = HeroDefs.get_def(me.def_id)["abilities"]
	if slot < 0 or slot >= abilities.size():
		return 0.0
	var ability: Dictionary = abilities[slot]
	if not ability.has("range"):
		return 0.0
	return HeroDefs.value(me, slot, "range")


## Point visé automatiquement pour une capacité lancée sans glisser.
static func auto_aim(me: SimHero, snap: SimSnapshot, slot: int) -> Vector2:
	var fallback := me.pos + me.facing * 5.0
	var abilities: Array = HeroDefs.get_def(me.def_id)["abilities"]
	if snap == null or slot < 0 or slot >= abilities.size():
		return fallback
	var ability: Dictionary = abilities[slot]
	var type: String = ability["type"]
	var distance := reach(me, slot)

	if type == "heal_area":
		if ability.get("self", false):
			return fallback
		# Soin : l'allié le plus blessé à portée, soi-même compris.
		var radius := HeroDefs.value(me, slot, "radius")
		var target := me.pos
		var worst := 1.0
		for id: int in snap.heroes:
			var ally: SimHero = snap.heroes[id]
			if ally.team != me.team or not ally.alive:
				continue
			var ally_pos := me.pos if ally.id == me.id else ally.pos
			if ally_pos.distance_to(me.pos) > distance + radius * 0.5:
				continue
			var ratio := ally.hp / maxf(ally.max_hp, 1.0)
			if ratio < worst:
				worst = ratio
				target = ally_pos
		return target
	if type == "shield" or type == "dash" or distance <= 0.0:
		return fallback

	# Attaque : un héros adverse d'abord, puis une unité, puis un bâtiment.
	var best := INF
	var found := fallback
	for id: int in snap.heroes:
		var enemy: SimHero = snap.heroes[id]
		if enemy.team == me.team or not enemy.alive:
			continue
		var d := enemy.pos.distance_to(me.pos)
		if d <= distance + 1.5 and d < best:
			best = d
			found = enemy.pos
	if best < INF:
		return found
	for u in snap.units:
		if u.team == me.team or not u.alive:
			continue
		var d := u.pos.distance_to(me.pos)
		if d <= distance + 1.0 and d < best:
			best = d
			found = u.pos
	if best < INF:
		return found
	for s in snap.structures:
		if s.team == me.team or not s.alive or not s.vulnerable:
			continue
		var d := s.pos.distance_to(me.pos) - s.radius
		if d <= distance and d < best:
			best = d
			found = s.pos
	return found
