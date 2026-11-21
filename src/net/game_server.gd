class_name GameServer
extends Node
## Serveur de partie : il fait tourner la simulation et fait autorité sur tout.
## Les clients n'envoient que leurs commandes ; ils reçoivent l'état du monde à chaque pas.
##
## Ce nœud possède sa propre branche réseau, ce qui permet de lancer un serveur
## et un client dans le même processus (entraînement local).

## Commandes en attente gardées par joueur ; au-delà, les plus anciennes sont jetées.
const MAX_INPUT_QUEUE := 5
## Délai laissé à un pair connecté pour envoyer sa demande d'entrée.
const JOIN_TIMEOUT := 5.0
const BOT_NAMES: Array[String] = ["Orion", "Véga", "Altaïr", "Sirius", "Rigel", "Deneb"]
## Rôles donnés aux bots d'une équipe, dans l'ordre : un tank, un assassin, un soutien.
const BOT_ROLES: Array[String] = ["ROLE_TANK", "ROLE_ASSASSIN", "ROLE_SUPPORT"]

var world: SimWorld
var net: NetBridge
## Si non nul, le processus s'arrête après ce nombre d'événements de jeu : élimination,
## relique ou camp pris, bâtiment détruit (tests automatiques).
var exit_after_events: int = 0
## Événements de jeu comptés depuis le démarrage.
var event_count: int = 0
## Si vrai, des bots occupent toutes les places libres : un joueur qui arrive en remplace
## un, un joueur qui part est remplacé.
var fill_bots: bool = false

var _peer: ENetMultiplayerPeer
var _players: Dictionary = {}  # peer_id -> {hero_id, queue, last, last_seq}
var _bots: Array = []  # [{hero_id, brain}]
var _roster: Dictionary = {}  # hero_id -> [nom, équipe, est_un_bot]
var _mp_path: NodePath
var _restart_left: float = 0.0
## Scénario du tutoriel quand le serveur tourne dans ce mode, sinon null.
var _tutorial: TutorialDirector


func _enter_tree() -> void:
	_mp_path = get_path()
	get_tree().set_multiplayer(MultiplayerAPI.create_default_interface(), _mp_path)


func _exit_tree() -> void:
	if _peer != null:
		_peer.close()
	# La branche réseau n'est retirée qu'une fois ce nœud et ses enfants sortis de l'arbre :
	# le moteur finit ainsi de délier le nœud "Net" avant qu'elle ne disparaisse.
	var tree := get_tree()
	var path := _mp_path
	tree_exited.connect(func() -> void: tree.set_multiplayer(null, path), CONNECT_ONE_SHOT)


func _ready() -> void:
	net = NetBridge.new()
	net.name = "Net"
	add_child(net)
	net.join_requested.connect(_on_join_requested)
	net.input_received.connect(_on_input_received)
	net.talent_requested.connect(_on_talent_requested)


## Lance le serveur. En mode tutoriel, il accueille un seul joueur sur la carte du
## tutoriel et déroule le scénario à la place d'une partie normale.
func start(port: int, bot_count: int = 0, fill: bool = false, tutorial: bool = false) -> Error:
	world = TutorialDirector.make_world() if tutorial else SimWorld.new()
	_tutorial = TutorialDirector.new() if tutorial else null
	_peer = ENetMultiplayerPeer.new()
	# Deux connexions de plus que de places, pour pouvoir répondre "complet".
	var err := _peer.create_server(port, SimConst.MAX_PLAYERS + 2)
	if err != OK:
		_peer = null
		world = null
		return err
	multiplayer.multiplayer_peer = _peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	fill_bots = fill and not tutorial
	var wanted := SimConst.MAX_PLAYERS if fill else mini(bot_count, SimConst.MAX_PLAYERS - 1)
	if tutorial:
		wanted = 0
	for i in wanted:
		_add_bot(_smaller_team())
	return OK


func _physics_process(_delta: float) -> void:
	if world == null:
		return
	var inputs: Dictionary = {}
	for peer_id in _players:
		var player: Dictionary = _players[peer_id]
		var queue: Array = player["queue"]
		if not queue.is_empty():
			player["last"] = queue.pop_front()
		inputs[player["hero_id"]] = player["last"]
	for bot: Dictionary in _bots:
		var hero: SimHero = world.heroes.get(bot["hero_id"])
		if hero != null:
			var brain: BotBrain = bot["brain"]
			inputs[hero.id] = brain.think(hero, world)

	world.step(inputs)
	if world.tick % SimConst.TICK_RATE == 0:
		_pick_bot_talents()
	if _tutorial != null and not _players.is_empty():
		var pupil: SimHero = world.heroes.get(_players.values()[0]["hero_id"])
		if _tutorial.update(world, pupil):
			print("[server] tutorial step=%d time=%ds" % [_tutorial.step, int(world.tick * SimConst.DT)])
			world.events.append(["tutorial", _tutorial.step, 0])

	var peers := _connected_peers()
	var snapshot := world.to_snapshot()
	for peer_id in peers:
		net.s2c_snapshot.rpc_id(peer_id, snapshot)

	if not world.events.is_empty():
		var rows: Array = world.events.duplicate(true)
		for ev: Array in rows:
			_log_event(ev)
		for peer_id in peers:
			net.s2c_events.rpc_id(peer_id, rows)
		if exit_after_events > 0 and event_count >= exit_after_events:
			print("[server] event target reached, stopping")
			get_tree().quit(0)

	# Partie terminée : laisser le temps de lire le résultat, puis en relancer une.
	if world.match_over and _tutorial == null:
		_restart_left -= SimConst.DT
		if _restart_left <= 0.0:
			print("[server] new match")
			world.reset_match()
	else:
		_restart_left = SimConst.MATCH_RESTART_DELAY


func _log_event(ev: Array) -> void:
	match ev[0]:
		"kill":
			event_count += 1
			print("[server] kill killer=%s victim=%s score=%d-%d" % [
				_hero_name(ev[1]), _hero_name(ev[2]), world.team_kills[0], world.team_kills[1],
			])
		"structure":
			event_count += 1
			print("[server] structure destroyed index=%d by_team=%d" % [ev[1], ev[2]])
		"relic":
			event_count += 1
			print("[server] relic captured team=%d" % ev[1])
		"camp":
			event_count += 1
			print("[server] camp captured team=%d camp=%d" % [ev[1], ev[2]])
		"level":
			print("[server] level team=%d level=%d" % [ev[1], ev[2]])
		"match_end":
			print("[server] match end winner=%d time=%ds" % [ev[1], int(world.tick * SimConst.DT)])


func _add_bot(team: int) -> void:
	var hero := world.add_hero(team, pick_bot_hero(world, team))
	var brain := BotBrain.new()
	# Les deux premiers emplacements d'une équipe tiennent chacun une voie, le troisième circule.
	brain.lane = hero.spawn_slot % 2
	brain.roamer = hero.spawn_slot >= 2
	_bots.append({"hero_id": hero.id, "brain": brain})
	var used: Array = []
	for row: Array in _roster.values():
		used.append(row[0])
	var bot_name := BOT_NAMES[0]
	for candidate in BOT_NAMES:
		if not used.has(candidate):
			bot_name = candidate
			break
	_roster[hero.id] = [bot_name, team, true]


## Héros d'un nouveau bot : au hasard parmi ceux du premier rôle qui manque à l'équipe,
## en évitant les héros déjà pris par ses coéquipiers.
static func pick_bot_hero(p_world: SimWorld, team: int, rng: RandomNumberGenerator = null) -> String:
	var taken: Array = []
	var roles: Array = []
	for id in p_world.heroes:
		var mate: SimHero = p_world.heroes[id]
		if mate.team == team:
			taken.append(mate.def_id)
			roles.append(HeroDefs.get_def(mate.def_id)["role_key"])
	var role: String = BOT_ROLES[p_world.team_size(team) % BOT_ROLES.size()]
	for candidate in BOT_ROLES:
		if not roles.has(candidate):
			role = candidate
			break
	var choices: Array = []
	for def_id: String in HeroDefs.ids_by_role(role):
		if not taken.has(def_id):
			choices.append(def_id)
	if choices.is_empty():
		choices = HeroDefs.ids_by_role(role)
	var pick := rng.randi_range(0, choices.size() - 1) if rng != null else randi_range(0, choices.size() - 1)
	return choices[pick]


func _remove_bot(bot: Dictionary) -> void:
	var hero_id: int = bot["hero_id"]
	_bots.erase(bot)
	_roster.erase(hero_id)
	world.remove_hero(hero_id)


## Bot à remplacer par un joueur : dans l'équipe qui compte le moins de joueurs, de
## préférence celui qui joue le héros demandé.
func _bot_to_replace(def_id: String) -> Dictionary:
	var humans: Array[int] = [0, 0]
	for peer_id in _players:
		var hero: SimHero = world.heroes.get(_players[peer_id]["hero_id"])
		if hero != null:
			humans[hero.team] += 1
	var team := SimConst.TEAM_DUSK if humans[SimConst.TEAM_DUSK] < humans[SimConst.TEAM_DAWN] else SimConst.TEAM_DAWN
	var fallback: Dictionary = {}
	for order: int in [team, 1 - team]:
		for bot: Dictionary in _bots:
			var hero: SimHero = world.heroes.get(bot["hero_id"])
			if hero == null or hero.team != order:
				continue
			if hero.def_id == def_id:
				return bot
			if fallback.is_empty():
				fallback = bot
		if not fallback.is_empty():
			return fallback
	return fallback


## Les bots prennent un talent au hasard dès qu'un palier s'ouvre.
func _pick_bot_talents() -> void:
	for bot: Dictionary in _bots:
		var hero: SimHero = world.heroes.get(bot["hero_id"])
		if hero == null:
			continue
		var tier := HeroDefs.pending_talent_tier(hero, world.team_level[hero.team])
		if tier >= 0:
			world.choose_talent(hero.id, tier, randi_range(1, 2))


func _smaller_team() -> int:
	if world.team_size(SimConst.TEAM_DUSK) < world.team_size(SimConst.TEAM_DAWN):
		return SimConst.TEAM_DUSK
	return SimConst.TEAM_DAWN


func _on_peer_connected(peer_id: int) -> void:
	get_tree().create_timer(JOIN_TIMEOUT).timeout.connect(func() -> void:
		if not _players.has(peer_id):
			_disconnect(peer_id)
	)


func _on_peer_disconnected(peer_id: int) -> void:
	var player: Dictionary = _players.get(peer_id, {})
	if player.is_empty():
		return
	var hero_id: int = player["hero_id"]
	print("[server] leave name=%s" % _hero_name(hero_id))
	var hero: SimHero = world.heroes.get(hero_id)
	_players.erase(peer_id)
	_roster.erase(hero_id)
	world.remove_hero(hero_id)
	if fill_bots and hero != null:
		_add_bot(hero.team)
	_broadcast_roster()


func _on_join_requested(peer_id: int, player_name: String, version: int, hero_def: String) -> void:
	if _players.has(peer_id):
		return
	if version != SimConst.PROTOCOL_VERSION:
		_reject(peer_id, "REJECT_VERSION")
		return
	var def_id := hero_def if HeroDefs.has_hero(hero_def) else HeroDefs.DEFAULT_HERO
	var team := _smaller_team()
	if _tutorial != null:
		# Le tutoriel se joue seul, avec le héros dont il explique les capacités.
		if not _players.is_empty():
			_reject(peer_id, "REJECT_FULL")
			return
		def_id = TutorialDirector.HERO
		team = SimConst.TEAM_DAWN
	if world.heroes.size() >= SimConst.MAX_PLAYERS:
		# Partie pleine : un joueur ne peut entrer qu'à la place d'un bot.
		var bot := _bot_to_replace(def_id)
		if bot.is_empty():
			_reject(peer_id, "REJECT_FULL")
			return
		var replaced: SimHero = world.heroes[bot["hero_id"]]
		team = replaced.team
		_remove_bot(bot)
	var hero := world.add_hero(team, def_id)
	_players[peer_id] = {"hero_id": hero.id, "queue": [], "last": SimInput.new(), "last_seq": 0}
	_roster[hero.id] = [_clean_name(player_name), team, false]
	print("[server] join name=%s team=%d hero=%s heroes=%d" % [_hero_name(hero.id), team, def_id, world.heroes.size()])
	net.s2c_welcome.rpc_id(peer_id, {"hero_id": hero.id, "tick": world.tick, "map": world.arena.map_id})
	_broadcast_roster()


func _on_talent_requested(peer_id: int, tier: int, choice: int) -> void:
	var player: Dictionary = _players.get(peer_id, {})
	if not player.is_empty():
		world.choose_talent(player["hero_id"], tier, choice)


func _on_input_received(peer_id: int, data: PackedByteArray) -> void:
	var player: Dictionary = _players.get(peer_id, {})
	if player.is_empty():
		return
	var queue: Array = player["queue"]
	for cmd in SimInput.decode_batch(data):
		# Chaque envoi répète les dernières commandes : ignorer celles déjà reçues.
		if cmd.seq <= player["last_seq"]:
			continue
		player["last_seq"] = cmd.seq
		queue.append(cmd)
	while queue.size() > MAX_INPUT_QUEUE:
		queue.pop_front()


func _reject(peer_id: int, reason: String) -> void:
	print("[server] reject reason=%s" % reason)
	net.s2c_rejected.rpc_id(peer_id, reason)
	_disconnect(peer_id)


## Ferme la connexion d'un pair après l'envoi des messages en attente.
func _disconnect(peer_id: int) -> void:
	if _peer == null or not multiplayer.get_peers().has(peer_id):
		return
	var packet_peer := _peer.get_peer(peer_id)
	if packet_peer != null:
		packet_peer.peer_disconnect_later()


func _broadcast_roster() -> void:
	for peer_id in _connected_peers():
		net.s2c_roster.rpc_id(peer_id, _roster)


## Joueurs à qui l'on peut encore écrire : un pair en cours de déconnexion ne reçoit plus rien.
func _connected_peers() -> Array[int]:
	var out: Array[int] = []
	for peer_id: int in _players:
		var packet_peer := _peer.get_peer(peer_id)
		if packet_peer != null and packet_peer.get_state() == ENetPacketPeer.STATE_CONNECTED:
			out.append(peer_id)
	return out


func _hero_name(hero_id: int) -> String:
	var row: Array = _roster.get(hero_id, [])
	return row[0] if not row.is_empty() else "-"


static func _clean_name(raw: String) -> String:
	var out := ""
	for c in raw.strip_edges():
		if c.unicode_at(0) >= 32:
			out += c
	out = out.left(16).strip_edges()
	return out if not out.is_empty() else "Player"
