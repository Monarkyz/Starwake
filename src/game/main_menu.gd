class_name MainMenu
extends Control
## Menu principal : nom du joueur, serveur à rejoindre, entraînement local, langue.

signal join_requested(address: String, player_name: String)
signal training_requested(player_name: String)

var _name_edit: LineEdit
var _address_edit: LineEdit
var _status: Label
var _buttons: Array[Button] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(Starfield.new())

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(440.0, 0.0)
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)

	var title := _label("STARWAKE", 68, Palette.GOLD)
	title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	box.add_child(title)
	box.add_child(_label("MENU_SUBTITLE", 16, Palette.TEXT_DIM))
	box.add_child(_spacer(12.0))

	_name_edit = _line_edit("MENU_NAME_PLACEHOLDER", Settings.player_name)
	_name_edit.max_length = 16
	box.add_child(_name_edit)
	box.add_child(_button("MENU_TRAINING", _on_training))
	box.add_child(_spacer(8.0))

	_address_edit = _line_edit("MENU_ADDRESS_PLACEHOLDER", Settings.address)
	_address_edit.text_submitted.connect(func(_text: String) -> void: _on_join())
	box.add_child(_address_edit)
	box.add_child(_button("MENU_JOIN", _on_join))
	box.add_child(_spacer(8.0))

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
	box.add_child(_button("MENU_QUIT", func() -> void: get_tree().quit()))

	_status = _label("", 15, Palette.GOLD)
	_status.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)

	var goal := _label("MENU_GOAL", 13, Palette.TEXT)
	goal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(goal)

	var controls := _label("MENU_CONTROLS", 13, Palette.TEXT_DIM)
	controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(controls)


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
	join_requested.emit(address, _player_name())


func _on_training() -> void:
	training_requested.emit(_player_name())


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
	edit.custom_minimum_size = Vector2(0.0, 42.0)
	edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	return edit


func _button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0.0, 46.0)
	button.pressed.connect(on_pressed)
	_buttons.append(button)
	return button


func _spacer(height: float) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, height)
	return spacer
