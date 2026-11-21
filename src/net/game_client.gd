class_name GameClient
extends Node
## Client de partie : envoie les commandes du joueur, reçoit l'état du monde.
##
## Le héros du joueur est prédit localement (réponse immédiate aux commandes), puis
## recalé sur l'état du serveur à chaque photographie reçue. Les autres héros et les
## projectiles sont affichés avec un léger retard, interpolés entre deux photographies.

signal state_changed(new_state: State)
signal roster_changed
signal kill_happened(killer_id: int, victim_id: int)

enum State { IDLE, CONNECTING, JOINING, PLAYING, FAILED, DISCONNECTED, REJECTED }

## Retard d'affichage des entités distantes, en pas de simulation.
const INTERP_TICKS := 3.0
const CONNECT_TIMEOUT := 8.0
## Au-delà de cet écart, la correction est appliquée d'un coup (réapparition, etc.).
const SNAP_DISTANCE := 4.0

var state: State = State.IDLE
var net: NetBridge
var arena: SimArena = SimArena.make_default()
var my_hero_id: int = 0
## État prédit du héros du joueur ; null avant la première photographie.
var local: SimHero
var roster: Dictionary = {}  # hero_id -> [nom, équipe, est_un_bot]
var reject_reason: String = ""
## Objet doté de sample(client) -> SimInput : clavier/souris, tactile ou pilote automatique.
var input_source: RefCounted
var stats: Dictionary = {"snapshots": 0, "corrections": 0, "max_correction": 0.0}

var _peer: ENetMultiplayerPeer
var _mp_path: NodePath
var _player_name: String = ""
var _connect_elapsed: float = 0.0
var _seq: int = 0
var _pending: Array[SimInput] = []
var _snaps: Array[SimSnapshot] = []
var _clock_offset: float = 0.0
var _clock_ready: bool = false
var _prev_pos: Vector2 = Vector2.ZERO
var _visual_offset: Vector2 = Vector2.ZERO


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
	net.welcomed.connect(_on_welcomed)
	net.rejected.connect(_on_rejected)
	net.roster_received.connect(_on_roster)
	net.snapshot_received.connect(_on_snapshot)
	net.events_received.connect(_on_events)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func() -> void: _set_state(State.FAILED))
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func connect_to(address: String, port: int, player_name: String) -> Error:
	_player_name = player_name
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(address, port)
	if err != OK:
		_peer = null
		_set_state(State.FAILED)
		return err
	multiplayer.multiplayer_peer = _peer
	_connect_elapsed = 0.0
	_set_state(State.CONNECTING)
	return OK


func latest_snapshot() -> SimSnapshot:
	return _snaps.back() if not _snaps.is_empty() else null


## Héros de la dernière photographie reçue, sans interpolation.
func get_latest_heroes() -> Array:
	var snap := latest_snapshot()
	return snap.heroes.values() if snap != null else []


func hero_name(hero_id: int) -> String:
	var row: Array = roster.get(hero_id, [])
	return row[0] if not row.is_empty() else "?"


## Position affichée du héros du joueur : prédite, lissée entre deux pas.
func get_local_render_pos() -> Vector2:
	if local == null:
		return Vector2.ZERO
	var fraction := Engine.get_physics_interpolation_fraction()
	return _prev_pos.lerp(local.pos, fraction) + _visual_offset


## Héros à afficher : celui du joueur est prédit, les autres sont interpolés.
func get_render_heroes() -> Array[SimHero]:
	var out: Array[SimHero] = []
	if _snaps.is_empty():
		return out
	var pair := _bracket(_render_tick())
	var a: SimSnapshot = pair[0]
	var b: SimSnapshot = pair[1]
	var alpha: float = pair[2]
	for id in b.heroes:
		var hb: SimHero = b.heroes[id]
		var h: SimHero
		if id == my_hero_id and local != null:
			h = local.copy()
			h.pos = get_local_render_pos()
		else:
			h = hb.copy()
			var ha: SimHero = a.heroes.get(id)
			if ha != null and ha.alive == hb.alive and ha.pos.distance_to(hb.pos) < SNAP_DISTANCE * 1.5:
				h.pos = ha.pos.lerp(hb.pos, alpha)
				var facing := ha.facing.lerp(hb.facing, alpha)
				if facing.length_squared() > 0.0001:
					h.facing = facing.normalized()
		out.append(h)
	return out


## Projectiles à afficher, prolongés en ligne droite depuis la photographie précédente.
func get_render_projectiles() -> Array[SimProjectile]:
	var out: Array[SimProjectile] = []
	if _snaps.is_empty():
		return out
	var render_tick := _render_tick()
	var a: SimSnapshot = _bracket(render_tick)[0]
	var elapsed := clampf((render_tick - a.tick) * SimConst.DT, 0.0, 0.2)
	for p in a.projectiles:
		var shown := SimProjectile.new()
		shown.id = p.id
		shown.kind = p.kind
		shown.team = p.team
		shown.radius = p.radius
		shown.vel = p.vel
		shown.pos = p.pos + p.vel * elapsed
		out.append(shown)
	return out


func _process(delta: float) -> void:
	_visual_offset *= exp(-12.0 * delta)
	if state == State.CONNECTING or state == State.JOINING:
		_connect_elapsed += delta
		if _connect_elapsed > CONNECT_TIMEOUT:
			if _peer != null:
				_peer.close()
			_set_state(State.FAILED)


func _physics_process(_delta: float) -> void:
	if state != State.PLAYING or local == null:
		return
	var cmd: SimInput
	if input_source != null:
		cmd = input_source.call("sample", self)
	else:
		cmd = SimInput.new()
		cmd.aim = local.pos + local.facing
	_seq += 1
	cmd.seq = _seq
	_pending.append(cmd)
	if _pending.size() > 90:
		_pending.pop_front()

	# Chaque envoi répète les trois dernières commandes, pour tolérer un paquet perdu.
	var recent: Array[SimInput] = _pending.slice(maxi(0, _pending.size() - 3))
	net.c2s_input.rpc_id(1, SimInput.encode_batch(recent))

	_prev_pos = local.pos
	SimWorld.step_hero_local(local, cmd, arena, SimConst.DT)


func _on_connected() -> void:
	_set_state(State.JOINING)
	net.c2s_join.rpc_id(1, _player_name, SimConst.PROTOCOL_VERSION)


func _on_server_disconnected() -> void:
	if state != State.REJECTED:
		_set_state(State.DISCONNECTED)


func _on_welcomed(info: Dictionary) -> void:
	my_hero_id = int(info.get("hero_id", 0))
	_set_state(State.PLAYING)


func _on_rejected(reason: String) -> void:
	reject_reason = reason
	_set_state(State.REJECTED)


func _on_roster(new_roster: Dictionary) -> void:
	roster = new_roster
	roster_changed.emit()


func _on_events(events: Array) -> void:
	for ev: Variant in events:
		if typeof(ev) == TYPE_ARRAY and ev.size() == 3 and ev[0] == "kill":
			kill_happened.emit(int(ev[1]), int(ev[2]))


func _on_snapshot(data: PackedByteArray) -> void:
	var snap := SimSnapshot.from_bytes(data)
	if snap == null:
		return
	if not _snaps.is_empty() and snap.tick <= _snaps.back().tick:
		return
	_snaps.append(snap)
	if _snaps.size() > 40:
		_snaps.pop_front()
	stats["snapshots"] += 1
	_update_clock(snap.tick)

	var mine: SimHero = snap.heroes.get(my_hero_id)
	if mine == null:
		return
	if local == null:
		local = mine.copy()
		_prev_pos = local.pos
		return

	# Réconciliation : repartir de l'état du serveur, puis rejouer les commandes
	# qu'il n'a pas encore prises en compte.
	var before := local.pos
	local = mine.copy()
	while not _pending.is_empty() and _pending[0].seq <= mine.last_seq:
		_pending.pop_front()
	for cmd in _pending:
		SimWorld.step_hero_local(local, cmd, arena, SimConst.DT)

	var correction := local.pos - before
	var error := correction.length()
	if error > 0.05:
		stats["corrections"] += 1
		stats["max_correction"] = maxf(stats["max_correction"], error)
	if error > SNAP_DISTANCE:
		_prev_pos = local.pos
		_visual_offset = Vector2.ZERO
	else:
		# L'écart est absorbé en douceur à l'affichage plutôt que d'un coup.
		_prev_pos += correction
		_visual_offset -= correction


func _update_clock(snap_tick: int) -> void:
	var sample := _now() - snap_tick * SimConst.DT
	if not _clock_ready or absf(sample - _clock_offset) > 0.5:
		_clock_offset = sample
		_clock_ready = true
	else:
		_clock_offset = lerpf(_clock_offset, sample, 0.05)


func _render_tick() -> float:
	return (_now() - _clock_offset) / SimConst.DT - INTERP_TICKS


## Renvoie [photographie avant, photographie après, fraction] pour l'instant demandé.
func _bracket(render_tick: float) -> Array:
	var a: SimSnapshot = _snaps[0]
	var b: SimSnapshot = _snaps[0]
	for i in range(_snaps.size() - 1, -1, -1):
		if _snaps[i].tick <= render_tick:
			a = _snaps[i]
			b = _snaps[mini(i + 1, _snaps.size() - 1)]
			break
	var alpha := 0.0
	if b.tick > a.tick:
		alpha = clampf((render_tick - a.tick) / float(b.tick - a.tick), 0.0, 1.0)
	return [a, b, alpha]


func _set_state(new_state: State) -> void:
	if state == new_state:
		return
	state = new_state
	state_changed.emit(new_state)


static func _now() -> float:
	return Time.get_ticks_usec() / 1000000.0
