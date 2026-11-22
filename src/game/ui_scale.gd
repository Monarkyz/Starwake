class_name UiScale
## Taille de l'interface selon la taille réelle de l'écran.
##
## L'interface est dessinée pour une hauteur de 720 unités, ce qui convient à un écran
## d'ordinateur. Sur un téléphone, la même hauteur tient dans six ou sept centimètres : les
## boutons deviennent trop petits pour un doigt. On grossit donc toute l'interface, ce qui
## revient à la dessiner pour une hauteur plus faible (480 unités au minimum).

## Taille de référence de l'interface, celle du projet : l'écran en montre au moins autant.
const BASE_WIDTH := 1280.0
const BASE_HEIGHT := 720.0
## Taille la plus faible pour laquelle les écrans sont mis en page.
const MIN_WIDTH := 960.0
const MIN_HEIGHT := 480.0
## Unités d'interface par "dp" d'Android (1 dp = 1/160 de pouce). À 1,25, un bouton de
## 60 unités mesure 48 dp, soit 7,6 mm : la taille conseillée pour une cible tactile.
const UNITS_PER_DP := 1.25
## Hauteur d'une cible tactile dans les menus, en unités d'interface.
const TOUCH_TARGET := 60.0

## Grossissement appliqué à l'interface (1 sur ordinateur).
static var factor: float = 1.0
## Mise en page compacte : écran de téléphone, ou grossissement imposé pour les essais.
static var compact: bool = false

static var _forced: float = 0.0


## Grossissement à appliquer pour une fenêtre de cette taille (en pixels) sur un écran de
## cette densité (en points par pouce). Sans densité fiable, on ne touche à rien.
static func compute(window: Vector2i, dpi: int) -> float:
	if dpi < 100 or window.x <= 0 or window.y <= 0:
		return 1.0
	var width := float(maxi(window.x, window.y))
	var height := float(mini(window.x, window.y))
	# Taille de l'interface sans grossissement : l'écran montre au moins 1280 × 720 unités.
	var base := Vector2(width, height) / minf(width / BASE_WIDTH, height / BASE_HEIGHT)
	var dp_height := height * 160.0 / float(dpi)
	var wanted_height := clampf(dp_height * UNITS_PER_DP, MIN_HEIGHT, base.y)
	# Sur un écran peu allongé, on grossit moins pour garder assez de largeur.
	return maxf(1.0, minf(base.y / wanted_height, base.x / MIN_WIDTH))


## Applique le grossissement à la fenêtre et le tient à jour quand elle change de taille.
## forced > 0 impose une valeur (option --ui-scale, pour essayer sur ordinateur).
static func setup(root: Window, forced: float = 0.0) -> void:
	_forced = clampf(forced, 0.0, BASE_HEIGHT / MIN_HEIGHT)
	compact = OS.has_feature("mobile") or _forced > 0.0
	root.size_changed.connect(func() -> void: _apply(root))
	_apply(root)


static func _apply(root: Window) -> void:
	var wanted := 1.0
	if _forced > 0.0:
		wanted = _forced
	elif OS.has_feature("mobile"):
		wanted = compute(root.size, DisplayServer.screen_get_dpi())
	if not is_equal_approx(root.content_scale_factor, wanted):
		root.content_scale_factor = wanted
	if not is_equal_approx(factor, wanted):
		# Trace utile pour comprendre un écran mal dimensionné sur un appareil.
		print("[ui] window=%s dpi=%d scale=%.2f" % [root.size, DisplayServer.screen_get_dpi(), wanted])
	factor = wanted
