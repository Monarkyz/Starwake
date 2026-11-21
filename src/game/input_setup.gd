class_name InputSetup
## Déclare les actions de jeu. Les touches sont repérées par leur position physique :
## le déplacement est donc sur ZQSD en AZERTY et sur WASD en QWERTY, sans réglage.


static func ensure_actions() -> void:
	_key("move_up", KEY_W)
	_key("move_up", KEY_UP)
	_key("move_down", KEY_S)
	_key("move_down", KEY_DOWN)
	_key("move_left", KEY_A)
	_key("move_left", KEY_LEFT)
	_key("move_right", KEY_D)
	_key("move_right", KEY_RIGHT)
	_mouse("attack", MOUSE_BUTTON_LEFT)
	_mouse("ability_1", MOUSE_BUTTON_RIGHT)
	_key("ability_2", KEY_SPACE)
	_key("awaken", KEY_R)
	_key("talent_1", KEY_1)
	_key("talent_1", KEY_KP_1)
	_key("talent_2", KEY_2)
	_key("talent_2", KEY_KP_2)
	_key("leave_game", KEY_ESCAPE)


static func _ensure(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)


static func _key(action: String, physical_key: Key) -> void:
	_ensure(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = physical_key
	InputMap.action_add_event(action, ev)


static func _mouse(action: String, button: MouseButton) -> void:
	_ensure(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)
