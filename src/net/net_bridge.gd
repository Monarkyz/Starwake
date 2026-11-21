class_name NetBridge
extends Node
## Tous les messages réseau du jeu. Le même nœud, nommé "Net", existe côté serveur
## et côté client ; les préfixes indiquent le sens : c2s (client vers serveur),
## s2c (serveur vers client). Chaque message est relayé par un signal.

signal join_requested(peer_id: int, player_name: String, version: int)
signal input_received(peer_id: int, data: PackedByteArray)
signal welcomed(info: Dictionary)
signal rejected(reason: String)
signal roster_received(roster: Dictionary)
signal snapshot_received(data: PackedByteArray)
signal events_received(events: Array)


@rpc("any_peer", "call_remote", "reliable")
func c2s_join(player_name: String, version: int) -> void:
	if multiplayer.is_server():
		join_requested.emit(multiplayer.get_remote_sender_id(), player_name, version)


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func c2s_input(data: PackedByteArray) -> void:
	if multiplayer.is_server():
		input_received.emit(multiplayer.get_remote_sender_id(), data)


@rpc("authority", "call_remote", "reliable")
func s2c_welcome(info: Dictionary) -> void:
	welcomed.emit(info)


@rpc("authority", "call_remote", "reliable")
func s2c_rejected(reason: String) -> void:
	rejected.emit(reason)


@rpc("authority", "call_remote", "reliable")
func s2c_roster(roster: Dictionary) -> void:
	roster_received.emit(roster)


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func s2c_snapshot(data: PackedByteArray) -> void:
	snapshot_received.emit(data)


@rpc("authority", "call_remote", "reliable")
func s2c_events(events: Array) -> void:
	events_received.emit(events)
