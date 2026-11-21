class_name AutopilotInput
extends RefCounted
## Pilote automatique : joue à la place du joueur, à partir de ce que le client voit.
## Sert aux tests de bout en bout (client sans écran).

var _brain := BotBrain.new()
var _ticks: int = 0


func sample(client: GameClient) -> SimInput:
	var snap := client.latest_snapshot()
	if snap == null:
		return SimInput.new()
	_brain.lane = client.my_hero_id % 2
	# Aller chercher la relique d'où qu'il soit : les tests comptent sur cet événement.
	_brain.roamer = true
	_ticks += 1
	if _ticks % SimConst.TICK_RATE == 0 and client.pending_talent_tier() >= 0:
		client.choose_talent(randi_range(1, 2))
	return _brain.think(client.local, snap)
