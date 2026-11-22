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
## Mise en page pour téléphone : deux colonnes, boutons à la taille d'un doigt.
var _compact: bool = false
var _scroll: ScrollContainer
var _frame: MarginContainer
var _box: VBoxContainer
var _keyboard_height: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(Starfield.new())
	_compact = UiScale.compact

	# Le menu défile s'il ne tient pas dans l'écran (petit téléphone, clavier ouvert).
	_scroll = ScrollContainer.new()
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_frame = MarginContainer.new()
	_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_frame)
	var center := CenterContainer.new()
	_frame.add_child(center)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 7)
	center.add_child(_box)

	var title := _label("STARWAKE", 34 if _compact else 44, Palette.GOLD)
	title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_box.add_child(title)
	_box.add_child(_label("MENU_SUBTITLE", 14 if _compact else 16, Palette.TEXT_DIM))

	_status = _label("", 15, Palette.GOLD)
	_status.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	if _compact:
		# Le message d'état reste en haut, toujours visible sans défiler.
		_box.add_child(_status)
		_status.visible = false
		var columns := HBoxContainer.new()
		columns.add_theme_constant_override("separation", 20)
		_box.add_child(columns)
		var left := _column(400.0, 1.5)
		var right := _column(240.0, 1.0)
		columns.add_child(left)
		columns.add_child(right)
		_build_hero_picker(left)
		_build_actions(right)
	else:
		_build_hero_picker(_box)
		_build_actions(_box)
		_box.add_child(_status)

	var goal := _label("MENU_GOAL", _small(), Palette.TEXT)
	goal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(goal)

	_controls_label = _label("MENU_CONTROLS", _small(), Palette.TEXT_DIM)
	_controls_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(_controls_label)
	_refresh_controls_label()

	resized.connect(_update_layout)
	_update_layout()


## Nom du joueur et choix du héros : une ligne par rôle, un bouton par héros (son prénom).
func _build_hero_picker(parent: Container) -> void:
	_name_edit = _line_edit("MENU_NAME_PLACEHOLDER", Settings.player_name)
	_name_edit.max_length = 16
	parent.add_child(_name_edit)

	for role_key in HeroDefs.ROLES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var role_label := _label(role_key, 13, Palette.TEXT_DIM)
		role_label.custom_minimum_size = Vector2(70.0 if _compact else 84.0, 0.0)
		role_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.add_child(role_label)
		for def_id: String in HeroDefs.ids_by_role(role_key):
			var button := Button.new()
			button.toggle_mode = true
			button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			button.custom_minimum_size = Vector2(0.0, _target(38.0))
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.clip_text = true
			button.add_theme_font_size_override("font_size", 15 if _compact else 14)
			button.pressed.connect(func() -> void: _select_hero(def_id))
			row.add_child(button)
			_hero_buttons[def_id] = button
		parent.add_child(row)
	# Sous les boutons : le nom complet du héros choisi et ses capacités.
	_hero_detail = _label("", _small(), Palette.GOLD)
	_hero_detail.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_hero_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(_hero_detail)
	_select_hero(Settings.hero)


## Lancer une partie seul, rejoindre un serveur, changer de langue, quitter.
func _build_actions(parent: Container) -> void:
	# Sur téléphone, les deux boutons sont l'un sous l'autre : côte à côte, leur texte ne tient pas.
	var solo: BoxContainer = VBoxContainer.new() if _compact else HBoxContainer.new()
	solo.add_theme_constant_override("separation", 7 if _compact else 8)
	for entry: Array in [["MENU_TUTORIAL", func() -> void: tutorial_requested.emit(_player_name())], ["MENU_TRAINING", _on_training]]:
		var solo_button := _button(entry[0], entry[1])
		solo_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		solo.add_child(solo_button)
	parent.add_child(solo)

	_address_edit = _line_edit("MENU_ADDRESS_PLACEHOLDER", Settings.address)
	_address_edit.text_submitted.connect(func(_text: String) -> void: _on_join())
	parent.add_child(_address_edit)
	parent.add_child(_button("MENU_JOIN", _on_join))

	var languages := HBoxContainer.new()
	languages.alignment = BoxContainer.ALIGNMENT_CENTER
	languages.add_theme_constant_override("separation", 12)
	for entry: Array in [["fr", "Français"], ["en", "English"]]:
		var code: String = entry[0]
		var button := Button.new()
		button.text = entry[1]
		button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		button.custom_minimum_size = Vector2(110.0 if _compact else 120.0, _target(36.0))
		if _compact:
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func() -> void: Settings.set_locale(code))
		languages.add_child(button)
	parent.add_child(languages)

	if OS.has_feature("mobile"):
		# Sur téléphone, on quitte une application avec les gestes du système.
		return
	# Sur ordinateur, on peut essayer les commandes tactiles à la souris.
	var touch_toggle := CheckButton.new()
	touch_toggle.text = "MENU_TOUCH"
	touch_toggle.button_pressed = Settings.touch
	touch_toggle.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	touch_toggle.toggled.connect(func(on: bool) -> void:
		Settings.touch = on
		Settings.save_settings()
		_refresh_controls_label()
	)
	if _compact:
		parent.add_child(touch_toggle)
	else:
		languages.add_child(touch_toggle)
	parent.add_child(_button("MENU_QUIT", func() -> void: get_tree().quit()))


func _column(min_width: float, ratio: float) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(min_width, 0.0)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_stretch_ratio = ratio
	column.add_theme_constant_override("separation", 7)
	return column


## Hauteur d'un bouton : celle d'une cible tactile sur téléphone, sinon la hauteur donnée.
func _target(desktop_height: float) -> float:
	return UiScale.TOUCH_TARGET if _compact else desktop_height


func _small() -> int:
	return 14 if _compact else 13


## Marges de la zone sûre de l'écran, largeur du menu, place laissée au clavier virtuel.
func _update_layout() -> void:
	var margins := SafeArea.margins(self)
	var pad := 12.0
	_frame.add_theme_constant_override("margin_left", int(margins.x + pad))
	_frame.add_theme_constant_override("margin_top", int(margins.y + pad))
	_frame.add_theme_constant_override("margin_right", int(margins.z + pad))
	_frame.add_theme_constant_override("margin_bottom", int(maxf(margins.w, _keyboard_height) + pad))
	if _compact:
		_box.custom_minimum_size.x = clampf(size.x - margins.x - margins.z - pad * 2.0, 660.0, 1000.0)
	else:
		_box.custom_minimum_size.x = 600.0


func _process(_delta: float) -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		return
	# Clavier virtuel ouvert : le menu se réserve sa hauteur et garde le champ saisi visible.
	var window_height := float(DisplayServer.window_get_size().y)
	var height := 0.0
	if window_height > 0.0:
		height = minf(DisplayServer.virtual_keyboard_get_height() * size.y / window_height, size.y * 0.7)
	if is_equal_approx(height, _keyboard_height):
		return
	_keyboard_height = height
	_update_layout()
	var focused := get_viewport().gui_get_focus_owner()
	if height > 0.0 and focused != null and _scroll.is_ancestor_of(focused):
		_scroll.ensure_control_visible.call_deferred(focused)


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
	if _compact:
		_status.visible = not text.is_empty()
		_scroll.scroll_vertical = 0


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
	edit.custom_minimum_size = Vector2(0.0, _target(38.0))
	edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	return edit


func _button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0.0, _target(42.0))
	button.pressed.connect(on_pressed)
	_buttons.append(button)
	return button


func _spacer(height: float) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, height)
	return spacer
