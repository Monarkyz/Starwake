class_name TouchControls
extends Control
## Commandes tactiles : un joystick virtuel sous le pouce gauche, les boutons de
## capacités sous le pouce droit.
##
## - Joystick : il apparaît là où le pouce se pose, dans la moitié gauche de l'écran.
## - Attaque de base : maintenir le bouton pour attaquer sans arrêt.
## - Capacités et éveil : toucher puis relâcher pour lancer.
## - Visée : sans glisser, la cible est choisie automatiquement (voir TouchInput) ;
##   en glissant le doigt hors du bouton, on vise à la main dans cette direction.
##
## Ce nœud ne fait que traduire les doigts en intentions ; TouchInput en tire la commande
## envoyée au serveur. Les tests pilotent handle_touch() et handle_drag() directement.

const STICK_RADIUS := 80.0
const STICK_DEADZONE := 0.18
## Distance de glissement à partir de laquelle la visée devient manuelle.
const AIM_THRESHOLD := 28.0
## Tolérance autour des boutons, pour les pouces imprécis.
const TOUCH_SLACK := 14.0
## Nombre de pas pendant lesquels une capacité relâchée reste "pressée".
const PULSE_TICKS := 2
## Boutons : décalage depuis le coin bas-droit de l'écran, puis rayon. L'indice est le créneau.
const BUTTONS: Array = [
	[Vector2(-135.0, -130.0), 68.0],
	[Vector2(-295.0, -100.0), 52.0],
	[Vector2(-262.0, -245.0), 52.0],
	[Vector2(-112.0, -295.0), 52.0],
]

var client: GameClient
## Dit si un point est sur un élément touchable de l'interface (talent, bouton Menu) : un
## doigt posé là n'est pas pour les commandes. Fourni par l'interface de jeu.
var reserved: Callable = Callable()
## Marges de la zone sûre de l'écran (encoche, bords arrondis) : gauche, haut, droite, bas.
var margins: Vector4 = Vector4.ZERO

var _stick_finger: int = -1
var _stick_origin: Vector2 = Vector2.ZERO
var _stick_vector: Vector2 = Vector2.ZERO
## Doigt posé sur chaque bouton, ou -1.
var _fingers: Array[int] = [-1, -1, -1, -1]
## Position du doigt par rapport au centre du bouton.
var _drags: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
var _pulses: Array[int] = [0, 0, 0, 0]
## Direction de visée retenue au relâchement (nulle : visée automatique).
var _pulse_dirs: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
var _font: Font


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font


func _process(_delta: float) -> void:
	margins = SafeArea.margins(self)
	queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if handle_touch(touch.index, touch.position, touch.pressed):
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		handle_drag(drag.index, drag.position)


# ---------------------------------------------------------------------------
# Doigts
# ---------------------------------------------------------------------------

## Un doigt se pose ou se lève. Renvoie vrai si ce doigt concerne les commandes.
func handle_touch(index: int, pos: Vector2, pressed: bool) -> bool:
	if not pressed:
		return _release(index)
	if reserved.is_valid() and reserved.call(pos):
		return false
	for slot in BUTTONS.size():
		var radius: float = BUTTONS[slot][1]
		if _fingers[slot] == -1 and pos.distance_to(button_center(slot)) <= radius + TOUCH_SLACK:
			_fingers[slot] = index
			_drags[slot] = pos - button_center(slot)
			return true
	if _stick_finger == -1 and pos.x < size.x * 0.5:
		_stick_finger = index
		# Garder le socle entier à l'écran.
		_stick_origin = Vector2(
			clampf(pos.x, margins.x + STICK_RADIUS, size.x * 0.5),
			clampf(pos.y, STICK_RADIUS, size.y - margins.w - STICK_RADIUS))
		_stick_vector = Vector2.ZERO
		return true
	return false


func handle_drag(index: int, pos: Vector2) -> void:
	if index == _stick_finger:
		_stick_vector = ((pos - _stick_origin) / STICK_RADIUS).limit_length(1.0)
		return
	for slot in BUTTONS.size():
		if _fingers[slot] == index:
			_drags[slot] = pos - button_center(slot)


func _release(index: int) -> bool:
	if index == _stick_finger:
		_stick_finger = -1
		_stick_vector = Vector2.ZERO
		return true
	for slot in BUTTONS.size():
		if _fingers[slot] != index:
			continue
		_fingers[slot] = -1
		if slot != 0:
			# Les capacités partent au relâchement, dans la direction visée à ce moment.
			_pulses[slot] = PULSE_TICKS
			_pulse_dirs[slot] = _manual_dir(slot)
		_drags[slot] = Vector2.ZERO
		return true
	return false


## Relâche tout (changement d'écran, perte du focus).
func reset() -> void:
	_stick_finger = -1
	_stick_vector = Vector2.ZERO
	for slot in BUTTONS.size():
		_fingers[slot] = -1
		_drags[slot] = Vector2.ZERO
		_pulses[slot] = 0


# ---------------------------------------------------------------------------
# Lecture par TouchInput
# ---------------------------------------------------------------------------

## Largeur occupée par les boutons depuis le bord droit de l'écran, tolérance comprise.
static func reach() -> float:
	var widest := 0.0
	for button: Array in BUTTONS:
		widest = maxf(widest, -(button[0] as Vector2).x + (button[1] as float))
	return widest + TOUCH_SLACK


## Hauteur occupée par les boutons depuis le bas de l'écran, tolérance comprise.
static func top_reach() -> float:
	var highest := 0.0
	for button: Array in BUTTONS:
		highest = maxf(highest, -(button[0] as Vector2).y + (button[1] as float))
	return highest + TOUCH_SLACK


func button_center(slot: int) -> Vector2:
	var offset: Vector2 = BUTTONS[slot][0]
	return size - Vector2(margins.z, margins.w) + offset


## Position de repos du joystick, affichée tant qu'aucun doigt n'est posé.
func stick_home() -> Vector2:
	return Vector2(margins.x + 150.0, size.y - margins.w - 150.0)


## Direction de déplacement voulue, longueur 0 à 1.
func move_vector() -> Vector2:
	var strength := _stick_vector.length()
	if strength < STICK_DEADZONE:
		return Vector2.ZERO
	# Au-delà de la zone morte, la force reprend de zéro pour un dosage fin.
	return _stick_vector / strength * ((strength - STICK_DEADZONE) / (1.0 - STICK_DEADZONE))


## Boutons pressés pour le pas de simulation en cours. À appeler une fois par pas.
func take_buttons() -> int:
	var buttons := 0
	if _fingers[0] != -1:
		buttons |= 1
	for slot in range(1, BUTTONS.size()):
		if _pulses[slot] > 0:
			_pulses[slot] -= 1
			buttons |= 1 << slot
	return buttons


## Capacité qui décide de la visée pour ce pas : [créneau, direction manuelle ou zéro].
## Créneau -1 si aucun bouton n'est en jeu. À lire avant take_buttons().
func active_aim() -> Array:
	for slot in range(BUTTONS.size() - 1, 0, -1):
		if _pulses[slot] > 0:
			return [slot, _pulse_dirs[slot]]
	if _fingers[0] != -1:
		return [0, _manual_dir(0)]
	return [-1, Vector2.ZERO]


## Visée manuelle en cours, pour l'afficher sur le terrain : [créneau, direction], ou [-1, zéro].
func preview() -> Array:
	for slot in range(BUTTONS.size() - 1, -1, -1):
		if _fingers[slot] != -1 and _manual_dir(slot) != Vector2.ZERO:
			return [slot, _manual_dir(slot)]
	return [-1, Vector2.ZERO]


func _manual_dir(slot: int) -> Vector2:
	var drag := _drags[slot]
	return drag.normalized() if drag.length() >= AIM_THRESHOLD else Vector2.ZERO


# ---------------------------------------------------------------------------
# Dessin
# ---------------------------------------------------------------------------

func _draw() -> void:
	var me: SimHero = client.local if client != null else null
	var base := _stick_origin if _stick_finger != -1 else stick_home()
	var alpha := 0.38 if _stick_finger != -1 else 0.16
	# Au repos, le joystick s'efface si un élément de l'interface occupe sa place.
	if _stick_finger != -1 or not _home_is_covered():
		draw_circle(base, STICK_RADIUS, Color(1.0, 1.0, 1.0, alpha * 0.45))
		draw_arc(base, STICK_RADIUS, 0.0, TAU, 48, Color(1.0, 1.0, 1.0, alpha), 2.0)
		draw_circle(base + _stick_vector * STICK_RADIUS, 34.0, Color(1.0, 1.0, 1.0, alpha + 0.2))

	if me == null:
		return
	var abilities: Array = HeroDefs.get_def(me.def_id)["abilities"]
	for slot in mini(BUTTONS.size(), abilities.size()):
		_draw_button(slot, abilities[slot], me)


func _home_is_covered() -> bool:
	if not reserved.is_valid():
		return false
	var home := stick_home()
	for offset: Vector2 in [Vector2.ZERO, Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		if reserved.call(home + offset * STICK_RADIUS):
			return true
	return false


func _draw_button(slot: int, ability: Dictionary, me: SimHero) -> void:
	var center := button_center(slot)
	var radius: float = BUTTONS[slot][1]
	var held := _fingers[slot] != -1
	var is_awaken: bool = ability.get("awakening", false)
	var ready := true
	var label := ""
	if is_awaken:
		ready = me.ether >= SimConst.ETHER_MAX or me.is_awakened()
		if me.is_awakened():
			label = "%.0f" % ceilf(me.awaken_ticks * SimConst.DT)
		elif not ready:
			label = "%d %%" % int(me.ether / SimConst.ETHER_MAX * 100.0)
	elif me.cooldowns[slot] > 0.0 and HeroDefs.value(me, slot, "cooldown") >= 1.0:
		ready = false
		label = "%.0f" % ceilf(me.cooldowns[slot])

	var fill := Color(0.05, 0.07, 0.15, 0.78 if held else 0.6)
	draw_circle(center, radius, fill)
	if is_awaken and not me.is_awakened():
		# La jauge d'éther remplit le tour du bouton.
		draw_arc(center, radius - 3.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(me.ether / SimConst.ETHER_MAX, 0.0, 1.0), 40, Hud.ETHER_COLOR, 5.0)
	var outline := Palette.GOLD if ready else Palette.TEXT_DIM
	if is_awaken and ready:
		outline = Hud.ETHER_COLOR
	draw_arc(center, radius, 0.0, TAU, 40, outline, 3.0 if held else 2.0)
	var name_color := Palette.TEXT if ready else Palette.TEXT_DIM
	var ability_name := tr(ability["name_key"])
	draw_string(_font, center + Vector2(-radius, radius * 0.5 if label != "" else 5.0), ability_name,
			HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, 12 if ability_name.length() <= 14 else 10, name_color)
	if label != "":
		draw_string(_font, center + Vector2(-radius, 2.0), label, HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, 22, Color.WHITE)
	if held and _manual_dir(slot) != Vector2.ZERO:
		draw_line(center, center + _drags[slot], Palette.GOLD, 3.0)
		draw_circle(center + _drags[slot], 12.0, Palette.GOLD)
