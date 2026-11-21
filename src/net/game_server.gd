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

var world: SimWorld
var net: NetBridge
## Si non nul, le processus s'arrête après ce nombre d'événements de jeu : élimination,
## relique ou camp pris, bâtiment détruit (tests automatiques).
var exit_after_events: int = 0
## Événements de jeu comptés depuis le démarrage.
var event_count: int = 0

var _peer: ENetMultiplayerPeer
var _players: Dictionary = {}  # peer_id -> {hero_id, queue, last, last_seq}
var _bots: Array = []  # [{hero_id, brain}]
var _roster: Dictionary = {}  # hero_id -> [nom, équipe, est_un_bot]
var _mp_path: NodePath
var _restart_left: float = 0.0


func _enter_tree() -> void:
	_mp_path = get_path()
	get_tree().set_multiplayer(MultiplayerAPI.create_default_interface(), _mp_path)


func _exit_tree() -> void:
	if _peer != null:
		_peer.close()
	get_tree().set_multiplayer(null, _mp_path)


func _ready() -> void:
	net = NetBridge.new()
	net.name = "Net"
	add_child(net)
	net.join_requested.connect(_on_join_requested)
	net.input_received.connect(_on_input_received)


func start(port: int, bot_count: int = 0) -> Error:
	world = SimWorld.new()
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
	for i in mini(bot_count, SimConst.MAX_PLAYERS - 1):
		_add_bot(i)
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

	var snapshot := world.to_snapshot()
	for peer_id in _players:
		net.s2c_snapshot.rpc_id(peer_id, snapshot)

	if not world.events.is_empty():
		var rows: Array = world.events.duplicate(true)
		for ev: Array in rows:
			_log_event(ev)
		for peer_id in _players:
			net.s2c_events.rpc_id(peer_id, rows)
		if exit_after_events > 0 and event_count >= exit_after_events:
			print("[server] event target reached, stopping")
			get_tree().quit(0)

	# Partie terminée : laisser le temps de lire le résultat, puis en relancer une.
	if world.match_over:
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


func _add_bot(index: int) -> void:
	var team := _smaller_team()
	var hero := world.add_hero(team)
	var brain := BotBrain.new()
	# Les deux premiers bots d'une équipe tiennent chacun une voie, le troisième circule.
	brain.lane = hero.spawn_slot % 2
	brain.roamer = hero.spawn_slot >= 2
	_bots.append({"hero_id": hero.id, "brain": brain})
	_roster[hero.id] = [BOT_NAMES[index % BOT_NAMES.size()], team, true]


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
	_players.erase(peer_id)
	_roster.erase(hero_id)
	world.remove_hero(hero_id)
	_broadcast_roster()


func _on_join_requested(peer_id: int, player_name: String, version: int) -> void:
	if _players.has(peer_id):
		return
	if version != SimConst.PROTOCOL_VERSION:
		_reject(peer_id, "REJECT_VERSION")
		return
	if world.heroes.size() >= SimConst.MAX_PLAYERS:
		_reject(peer_id, "REJECT_FULL")
		return
	var team := _smaller_team()
	var hero := world.add_hero(team)
	_players[peer_id] = {"hero_id": hero.id, "queue": [], "last": SimInput.new(), "last_seq": 0}
	_roster[hero.id] = [_clean_name(player_name), team, false]
	print("[server] join name=%s team=%d" % [_hero_name(hero.id), team])
	net.s2c_welcome.rpc_id(peer_id, {"hero_id": hero.id, "tick": world.tick})
	_broadcast_roster()


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
	for peer_id: int in _players:
		# Un pair en cours de déconnexion ne peut plus recevoir de message.
		var packet_peer := _peer.get_peer(peer_id)
		if packet_peer != null and packet_peer.get_state() == ENetPacketPeer.STATE_CONNECTED:
			net.s2c_roster.rpc_id(peer_id, _roster)


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
