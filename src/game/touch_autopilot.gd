class_name TouchAutopilot
extends RefCounted
## Pilote automatique tactile : il décide comme un bot, puis joue en posant des doigts
## virtuels sur les commandes tactiles. Sert aux tests : la partie passe ainsi par tout le
## chemin tactile (joystick, boutons, visée), sans téléphone.

const STICK_FINGER := 0
## Doigt utilisé pour le bouton du créneau i : BUTTON_FINGER + i.
const BUTTON_FINGER := 1

var controls: TouchControls
var _input := TouchInput.new()
var _brain := BotBrain.new()
var _stick_down: bool = false
var _attack_down: bool = false
var _ticks: int = 0


func sample(client: GameClient) -> SimInput:
	var snap := client.latest_snapshot()
	var me := client.local
	if snap == null or me == null:
		return SimInput.new()
	_input.controls = controls
	_brain.lane = client.my_hero_id % 2
	_brain.roamer = true
	_ticks += 1
	if _ticks % SimConst.TICK_RATE == 0 and client.pending_talent_tier() >= 0:
		client.choose_talent(randi_range(1, 2))

	var wanted := _brain.think(me, snap)
	_drive_stick(wanted.move)
	var aim_dir := (wanted.aim - me.pos).normalized()
	_drive_attack((wanted.buttons & SimConst.BTN_ATTACK) != 0, aim_dir)
	for slot in range(1, TouchControls.BUTTONS.size()):
		if (wanted.buttons & (1 << slot)) == 0:
			continue
		var ready := me.ether >= SimConst.ETHER_MAX if slot == 3 else me.cooldowns[slot] <= 0.0
		if ready:
			_tap(slot, aim_dir)
	return _input.sample(client)


func _drive_stick(move: Vector2) -> void:
	var home := controls.stick_home()
	if move.length_squared() < 0.01:
		if _stick_down:
			controls.handle_touch(STICK_FINGER, home, false)
			_stick_down = false
		return
	if not _stick_down:
		controls.handle_touch(STICK_FINGER, home, true)
		_stick_down = true
	controls.handle_drag(STICK_FINGER, home + move.limit_length(1.0) * TouchControls.STICK_RADIUS)


func _drive_attack(pressed: bool, aim_dir: Vector2) -> void:
	var center := controls.button_center(0)
	if not pressed:
		if _attack_down:
			controls.handle_touch(BUTTON_FINGER, center, false)
			_attack_down = false
		return
	if not _attack_down:
		controls.handle_touch(BUTTON_FINGER, center, true)
		_attack_down = true
	controls.handle_drag(BUTTON_FINGER, center + aim_dir * (TouchControls.AIM_THRESHOLD + 30.0))


## Toucher un bouton, glisser pour viser, relâcher.
func _tap(slot: int, aim_dir: Vector2) -> void:
	var center := controls.button_center(slot)
	var finger := BUTTON_FINGER + slot
	controls.handle_touch(finger, center, true)
	controls.handle_drag(finger, center + aim_dir * (TouchControls.AIM_THRESHOLD + 30.0))
	controls.handle_touch(finger, center, false)
