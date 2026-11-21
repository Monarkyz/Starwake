extends Node
## Point d'entrée. Selon les arguments passés après "--", lance un serveur dédié,
## rejoint directement un serveur, ou affiche le menu.
##
##   --server                 serveur dédié (à lancer avec --headless)
##   --port=24565             port d'écoute du serveur
##   --bots=3                 nombre de bots ajoutés par le serveur
##   --connect=hôte[:port]    rejoindre ce serveur sans passer par le menu
##   --training               lancer l'entraînement local sans passer par le menu
##   --name=Nom               nom du joueur
##   --lang=fr                langue de l'interface pour ce lancement (fr ou en)
##   --autopilot              le client joue tout seul (tests)
##   --quit-after=20          quitter après ce nombre de secondes (tests)
##   --exit-after-kills=1     le serveur s'arrête après ce nombre d'éliminations (tests)
##   --screenshot=fichier.png enregistrer une image juste avant de quitter (tests)

const DEFAULT_PORT := 24565
const TRAINING_BOTS := 5

var _opts: Dictionary = {}
var _server: GameServer
var _client: GameClient
var _view: GameView
var _menu: MainMenu
var _headless: bool = false


func _ready() -> void:
	_headless = DisplayServer.get_name() == "headless"
	if _headless:
		# Sans écran, rien ne limite la cadence : éviter d'occuper un cœur entier.
		Engine.max_fps = 60
	_opts = _parse_args(OS.get_cmdline_user_args())
	InputSetup.ensure_actions()
	Settings.load_settings()
	if Settings.LOCALES.has(str(_opts.get("lang", ""))):
		TranslationServer.set_locale(str(_opts["lang"]))

	if _opts.has("quit-after"):
		get_tree().create_timer(float(_opts["quit-after"])).timeout.connect(_on_quit_after)

	if _opts.has("server"):
		_run_dedicated_server()
	elif _opts.has("connect"):
		_join(str(_opts["connect"]), str(_opts.get("name", "Player")))
	elif _opts.has("training"):
		_start_training(str(_opts.get("name", "Player")))
	else:
		_show_menu()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("leave_game") and _client != null and _menu != null:
		_leave_game("")


func _run_dedicated_server() -> void:
	var port := int(_opts.get("port", DEFAULT_PORT))
	_server = _make_server()
	_server.exit_after_kills = int(_opts.get("exit-after-kills", 0))
	var err := _server.start(port, int(_opts.get("bots", 0)))
	if err != OK:
		printerr("[server] cannot listen on port %d (%s)" % [port, error_string(err)])
		get_tree().quit(1)
		return
	print("[server] Starwake %s listening port=%d bots=%d" % [
		ProjectSettings.get_setting("application/config/version"), port, int(_opts.get("bots", 0)),
	])


func _show_menu() -> void:
	_menu = MainMenu.new()
	add_child(_menu)
	_menu.join_requested.connect(_join)
	_menu.training_requested.connect(_start_training)


## Entraînement local : un serveur dans ce même processus, rempli de bots.
func _start_training(player_name: String) -> void:
	_server = _make_server()
	var port := 0
	for candidate in range(DEFAULT_PORT + 1, DEFAULT_PORT + 11):
		if _server.start(candidate, TRAINING_BOTS) == OK:
			port = candidate
			break
	if port == 0:
		_leave_game(tr("STATUS_SERVER_ERROR"))
		return
	_join("127.0.0.1:%d" % port, player_name)


func _join(address: String, player_name: String) -> void:
	var host := address
	var port := DEFAULT_PORT
	var colon := address.rfind(":")
	if colon > 0 and address.substr(colon + 1).is_valid_int():
		host = address.substr(0, colon)
		port = address.substr(colon + 1).to_int()

	_client = GameClient.new()
	_client.name = "Client"
	add_child(_client)
	if _opts.has("autopilot"):
		_client.input_source = AutopilotInput.new()
	_client.state_changed.connect(_on_client_state)
	if _menu != null:
		_menu.set_busy(true)
		_menu.set_status(tr("STATUS_CONNECTING") % address)
	_client.connect_to(host, port, player_name)


func _on_client_state(state: GameClient.State) -> void:
	match state:
		GameClient.State.PLAYING:
			print("[client] joined hero_id=%d" % _client.my_hero_id)
			if _menu != null:
				_menu.visible = false
			if not _headless:
				_view = GameView.new()
				_view.setup(_client)
				add_child(_view)
		GameClient.State.FAILED:
			_end_session("STATUS_FAILED")
		GameClient.State.DISCONNECTED:
			_end_session("STATUS_DISCONNECTED")
		GameClient.State.REJECTED:
			_end_session("STATUS_" + _client.reject_reason)


## Fin de session subie (échec, coupure, refus) : retour au menu, ou arrêt s'il n'y en a pas.
func _end_session(status_key: String) -> void:
	print("[client] session ended: %s" % status_key)
	if _menu == null:
		_print_client_stats()
		get_tree().quit(1)
		return
	# Différé : on est appelé depuis un signal du client, qu'on ne peut pas libérer tout de suite.
	_leave_game.call_deferred(tr(status_key))


func _leave_game(status: String) -> void:
	if _view != null:
		_view.queue_free()
		_view = null
	if _client != null:
		_client.queue_free()
		_client = null
	if _server != null:
		_server.queue_free()
		_server = null
	if _menu != null:
		_menu.visible = true
		_menu.set_busy(false)
		_menu.set_status(status)


func _make_server() -> GameServer:
	var server := GameServer.new()
	server.name = "Server"
	add_child(server)
	return server


func _on_quit_after() -> void:
	var code := 0
	if _opts.has("screenshot") and not _headless:
		get_viewport().get_texture().get_image().save_png(str(_opts["screenshot"]))
	if _client != null:
		_print_client_stats()
		if _client.state != GameClient.State.PLAYING or _client.stats["snapshots"] < 30:
			code = 1
	elif _server != null and _server.exit_after_kills > 0:
		print("[server] kill target not reached (%d)" % _server.total_kills())
		code = 1
	get_tree().quit(code)


func _print_client_stats() -> void:
	var stats := _client.stats
	print("[client] stats state=%s snapshots=%d corrections=%d max_correction=%.3f" % [
		GameClient.State.keys()[_client.state], stats["snapshots"], stats["corrections"], stats["max_correction"],
	])


static func _parse_args(args: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	for arg in args:
		if not arg.begins_with("--"):
			continue
		var body := arg.substr(2)
		var eq := body.find("=")
		if eq < 0:
			out[body] = true
		else:
			out[body.substr(0, eq)] = body.substr(eq + 1)
	return out
