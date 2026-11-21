extends SceneTree
## Test de session : un serveur et un client dans le même processus, comme en entraînement
## local. On joue, on quitte, on relance : la seconde partie doit démarrer comme la première.
## Lancement : godot --headless --path . -s tests/test_session.gd

const PORT := 24588
const TIMEOUT := 20.0

var _server: GameServer
var _client: GameClient
var _round: int = 0
var _elapsed: float = 0.0
## Images à attendre avant de lancer la partie suivante. La première démarre à la première
## image : avant, l'arbre de scène n'est pas encore actif.
var _pause: int = 1
var _failed: bool = false


func _process(delta: float) -> bool:
	if _failed:
		return true
	if _pause > 0:
		# Laisser le moteur libérer les nœuds de la partie précédente.
		_pause -= 1
		if _pause == 0:
			_start_round()
		return false
	_elapsed += delta
	if _elapsed > TIMEOUT:
		return _fail("round %d did not reach a playable state in time" % _round)
	if _client.state != GameClient.State.PLAYING or _client.local == null:
		return false
	var snap := _client.latest_snapshot()
	if snap == null or snap.heroes.size() != SimConst.MAX_PLAYERS or _client.stats["snapshots"] < 30:
		return false

	print("round %d ok: hero=%s snapshots=%d heroes=%d" % [_round, _client.local.def_id, _client.stats["snapshots"], snap.heroes.size()])
	if _client.local.def_id != ["scutum", "columba"][_round - 1]:
		return _fail("round %d: the player did not get the hero it asked for" % _round)
	_client.queue_free()
	_server.queue_free()
	if _round >= 2:
		print("2 rounds, 0 failures")
		quit(0)
		return true
	_pause = 5
	return false


func _start_round() -> void:
	_round += 1
	_elapsed = 0.0
	_server = GameServer.new()
	_server.name = "Server"
	root.add_child(_server)
	if _server.start(PORT, 0, true) != OK:
		_fail("round %d: the server could not start" % _round)
		return
	_client = GameClient.new()
	_client.name = "Client"
	root.add_child(_client)
	_client.connect_to("127.0.0.1", PORT, "Tester", ["scutum", "columba"][_round - 1])


func _fail(message: String) -> bool:
	printerr("FAIL: " + message)
	_failed = true
	quit(1)
	return true
