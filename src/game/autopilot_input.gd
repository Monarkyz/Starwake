class_name AutopilotInput
extends RefCounted
## Pilote automatique : joue à la place du joueur, à partir de ce que le client voit.
## Sert aux tests de bout en bout (client sans écran).

var _brain := BotBrain.new()


func sample(client: GameClient) -> SimInput:
	return _brain.think(client.local, client.get_latest_heroes(), client.arena)
