class_name MainMenu
extends Control
## Menu principal : nom du joueur, serveur à rejoindre, entraînement local, langue.

signal join_requested(address: String, player_name: String, hero: String)
signal training_requested(player_name: String, hero: String)
signal tutorial_requested(player_name: String)

var _name_edit: LineEdit
var _address_edit: LineEdit
var _status: Label
var _buttons: Array[Button] = []
var _hero_buttons: Dictionary = {}  # id du héros -> Button
var _controls_label: Label
var _hero_detail: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(Starfield.new())

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(600.0, 0.0)
	box.add_theme_constant_override("separation", 7)
	center.add_child(box)

	var title := _label("STARWAKE", 44, Palette.GOLD)
	title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	box.add_child(title)
	box.add_child(_label("MENU_SUBTITLE", 16, Palette.TEXT_DIM))

	_name_edit = _line_edit("MENU_NAME_PLACEHOLDER", Settings.player_name)
	_name_edit.max_length = 16
	box.add_child(_name_edit)

	# Choix du héros : une ligne par rôle, un bouton par héros (son prénom).
	for role_key in HeroDefs.ROLES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var role_label := _label(role_key, 13, Palette.TEXT_DIM)
		role_label.custom_minimum_size = Vector2(84.0, 0.0)
		role_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.add_child(role_label)
		for def_id: String in HeroDefs.ids_by_role(role_key):
			var button := Button.new()
			button.toggle_mode = true
			button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			button.custom_minimum_size = Vector2(0.0, 38.0)
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.add_theme_font_size_override("font_size", 14)
			button.pressed.connect(func() -> void: _select_hero(def_id))
			row.add_child(button)
			_hero_buttons[def_id] = button
		box.add_child(row)
	# Sous les boutons : le nom complet du héros choisi et ses capacités.
	_hero_detail = _label("", 13, Palette.GOLD)
	_hero_detail.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_hero_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_hero_detail)
	_select_hero(Settings.hero)
	var solo := HBoxContainer.new()
	solo.add_theme_constant_override("separation", 8)
	for entry: Array in [["MENU_TUTORIAL", func() -> void: tutorial_requested.emit(_player_name())], ["MENU_TRAINING", _on_training]]:
		var solo_button := _button(entry[0], entry[1])
		solo_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		solo.add_child(solo_button)
	box.add_child(solo)

	_address_edit = _line_edit("MENU_ADDRESS_PLACEHOLDER", Settings.address)
	_address_edit.text_submitted.connect(func(_text: String) -> void: _on_join())
	box.add_child(_address_edit)
	box.add_child(_button("MENU_JOIN", _on_join))

	var languages := HBoxContainer.new()
	languages.alignment = BoxContainer.ALIGNMENT_CENTER
	languages.add_theme_constant_override("separation", 12)
	for entry: Array in [["fr", "Français"], ["en", "English"]]:
		var code: String = entry[0]
		var button := Button.new()
		button.text = entry[1]
		button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		button.custom_minimum_size = Vector2(120.0, 36.0)
		button.pressed.connect(func() -> void: Settings.set_locale(code))
		languages.add_child(button)
	box.add_child(languages)

	# Sur ordinateur, on peut essayer les commandes tactiles à la souris.
	if not OS.has_feature("mobile"):
		var touch_toggle := CheckButton.new()
		touch_toggle.text = "MENU_TOUCH"
		touch_toggle.button_pressed = Settings.touch
		touch_toggle.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		touch_toggle.toggled.connect(func(on: bool) -> void:
			Settings.touch = on
			Settings.save_settings()
			_refresh_controls_label()
		)
		languages.add_child(touch_toggle)
	box.add_child(_button("MENU_QUIT", func() -> void: get_tree().quit()))

	_status = _label("", 15, Palette.GOLD)
	_status.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)

	var goal := _label("MENU_GOAL", 13, Palette.TEXT)
	goal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(goal)

	_controls_label = _label("MENU_CONTROLS", 13, Palette.TEXT_DIM)
	_controls_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_controls_label)
	_refresh_controls_label()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and not _hero_buttons.is_empty():
		_refresh_hero_buttons()


func _refresh_controls_label() -> void:
	if _controls_label != null:
		_controls_label.text = "MENU_CONTROLS_TOUCH" if Settings.touch else "MENU_CONTROLS"


func _select_hero(def_id: String) -> void:
	Settings.hero = def_id
	for id: String in _hero_buttons:
		var button: Button = _hero_buttons[id]
		button.button_pressed = id == def_id
	_refresh_hero_buttons()


func _refresh_hero_buttons() -> void:
	for id: String in _hero_buttons:
		var button: Button = _hero_buttons[id]
		# Tous les noms sont de la forme "Prénom de la Constellation" : le bouton montre le prénom.
		button.text = tr(HeroDefs.get_def(id)["name_key"]).get_slice(" ", 0)
	if _hero_detail == null:
		return
	var def: Dictionary = HeroDefs.get_def(Settings.hero)
	var names: Array[String] = []
	for ability: Dictionary in def["abilities"]:
		names.append(tr(ability["name_key"]))
	_hero_detail.text = "%s — %s" % [tr(def["name_key"]), ", ".join(names)]


## Affiche un message d'état déjà traduit (vide pour l'effacer).
func set_status(text: String) -> void:
	_status.text = text


func set_busy(busy: bool) -> void:
	for button in _buttons:
		button.disabled = busy


func _player_name() -> String:
	var typed := _name_edit.text.strip_edges()
	Settings.player_name = typed
	Settings.address = _address_edit.text.strip_edges()
	Settings.save_settings()
	return typed if not typed.is_empty() else tr("DEFAULT_PLAYER_NAME")


func _on_join() -> void:
	var address := _address_edit.text.strip_edges()
	if address.is_empty():
		address = Settings.DEFAULT_ADDRESS
	join_requested.emit(address, _player_name(), Settings.hero)


func _on_training() -> void:
	training_requested.emit(_player_name(), Settings.hero)


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _line_edit(placeholder: String, text: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.text = text
	edit.custom_minimum_size = Vector2(0.0, 38.0)
	edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	return edit


func _button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0.0, 42.0)
	button.pressed.connect(on_pressed)
	_buttons.append(button)
	return button


func _spacer(height: float) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, height)
	return spacer
