class_name Hud
extends Control
## Interface en jeu, dessinée directement : barres de vie, niveaux d'équipe, relique,
## capacités, journal des événements, minicarte et résultat de la partie.

const SLOT_SIZE := Vector2(112.0, 78.0)
const SLOT_GAP := 12.0
const KEY_HINTS: Array[String] = ["KEY_ATTACK", "KEY_ABILITY_1", "KEY_ABILITY_2", "KEY_AWAKEN"]
const RANK_KEYS: Array[String] = ["RANK_BRONZE", "RANK_SILVER", "RANK_GOLD"]
const ETHER_COLOR := Color("7fe3ff")
const FEED_DURATION := 7.0
const MINIMAP_WIDTH := 250.0
const MINIMAP_WIDTH_TOUCH := 200.0
const TOP_BAR_SIZE := Vector2(660.0, 74.0)
## Bouton Menu de la mise en page tactile.
const LEAVE_SIZE := Vector2(110.0, 56.0)
const TALENT_BOX := Vector2(330.0, 92.0)
const TALENT_GAP := 14.0
const NEUTRAL := Color("8fd6cb")

## Le joueur demande à quitter la partie (bouton tactile).
signal leave_requested

var client: GameClient
var camera: Camera3D
## Mise en page tactile : les capacités sont sur les boutons tactiles, la minicarte passe
## en haut à droite, un bouton remplace la touche Échap.
var touch: bool = false
## Héros et unités affichés à cette image, fournis par GameView.
var heroes: Array[SimHero] = []
var units: Array[SimUnit] = []

var _feed: Array = []  # [{text, left}]
var _font: Font
## Zones touchables, recalculées à chaque image.
var _talent_rects: Array[Rect2] = []
var _leave_rect: Rect2 = Rect2()
var _margins: Vector4 = Vector4.ZERO
## Bas du bandeau du haut et du panneau du tutoriel, pour empiler ce qui vient dessous.
var _top_bottom: float = 82.0
var _tutorial_bottom: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	client.game_event.connect(_on_game_event)


## Un talent se choisit aussi en le touchant ou en cliquant dessus ; le bouton Menu
## (mise en page tactile) quitte la partie.
func _input(event: InputEvent) -> void:
	var pos := Vector2.INF
	if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		pos = (event as InputEventScreenTouch).position
	elif event is InputEventMouseButton and not touch:
		# En tactile, chaque doigt arrive aussi sous la forme d'un clic : ne compter que le doigt.
		var click := event as InputEventMouseButton
		if click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			pos = click.position
	if pos == Vector2.INF:
		return
	for i in _talent_rects.size():
		if _talent_rects[i].has_point(pos):
			client.choose_talent(i + 1)
			get_viewport().set_input_as_handled()
			return
	if touch and _leave_rect.has_point(pos):
		get_viewport().set_input_as_handled()
		leave_requested.emit()


## Vrai si ce point est sur un élément touchable de l'interface (talent, bouton Menu) : les
## commandes tactiles le laissent alors passer au lieu d'y poser le joystick.
func is_interactive_at(pos: Vector2) -> bool:
	if touch and _leave_rect.has_point(pos):
		return true
	for rect in _talent_rects:
		if rect.has_point(pos):
			return true
	return false


# ---------------------------------------------------------------------------
# Mise en page
# ---------------------------------------------------------------------------

## Bande libre en haut de l'écran, [gauche, droite]. En tactile, elle va du bouton Menu à la
## minicarte ; sur ordinateur, la minicarte est en bas et toute la largeur est libre.
static func top_span(screen: Vector2, margins: Vector4, touch_layout: bool) -> Vector2:
	if not touch_layout:
		return Vector2(20.0, screen.x - 20.0)
	return Vector2(
		margins.x + 16.0 + LEAVE_SIZE.x + 12.0,
		screen.x - margins.z - 16.0 - MINIMAP_WIDTH_TOUCH - 3.0 - 12.0)


## Place un bloc de cette largeur dans une bande : au milieu de l'écran s'il y tient, sinon
## décalé, et rétréci s'il est plus large que la bande. Renvoie (bord gauche, échelle).
static func fit_in_span(span: Vector2, screen_width: float, width: float) -> Vector2:
	var room := maxf(span.y - span.x, 1.0)
	var scale := minf(1.0, room / width)
	var fitted := width * scale
	return Vector2(clampf((screen_width - fitted) * 0.5, span.x, span.y - fitted), scale)


## Cases des deux talents proposés. Sur ordinateur, elles sont au-dessus de la barre de
## capacités. En tactile, elles sont en haut de l'écran (à partir de top) et s'arrêtent avant
## les boutons de capacités, quitte à être plus étroites et plus hautes.
static func talent_layout(screen: Vector2, margins: Vector4, touch_layout: bool, top: float) -> Array[Rect2]:
	var box := TALENT_BOX
	var left := (screen.x - box.x * 2.0 - TALENT_GAP) * 0.5
	if touch_layout:
		var span := Vector2(margins.x + 16.0, screen.x - margins.z - TouchControls.reach())
		box.x = clampf((span.y - span.x - TALENT_GAP) * 0.5, 160.0, TALENT_BOX.x)
		if box.x < 260.0:
			box.y = 112.0
		left = fit_in_span(span, screen.x, box.x * 2.0 + TALENT_GAP).x
	else:
		top = screen.y - SLOT_SIZE.y - 22.0 - 44.0 - box.y - 26.0
	var rects: Array[Rect2] = []
	for i in 2:
		rects.append(Rect2(Vector2(left + i * (box.x + TALENT_GAP), top), box))
	return rects


func _process(delta: float) -> void:
	_margins = SafeArea.margins(self)
	for entry: Dictionary in _feed:
		entry["left"] -= delta
	_feed = _feed.filter(func(entry: Dictionary) -> bool: return entry["left"] > 0.0)
	queue_redraw()


func _draw() -> void:
	var snap := client.latest_snapshot()
	var me := client.local
	if snap == null or me == null:
		_text_centered(size.y * 0.5, tr("HUD_WAITING"), 22, Palette.TEXT)
		return
	_draw_overhead_bars(snap)
	_draw_top_bar(snap)
	_draw_feed()
	_draw_minimap(snap)
	_tutorial_bottom = 0.0
	if snap.match_over and client.tutorial_step >= 0:
		# Fin du tutoriel : le panneau de conclusion reste affiché sous le résultat.
		_draw_tutorial()
	if touch:
		_leave_rect = Rect2(Vector2(_margins.x + 16.0, _margins.y + 16.0), LEAVE_SIZE)
		draw_rect(_leave_rect, Palette.PANEL)
		draw_rect(_leave_rect, Palette.GROUND_LINE, false, 1.5)
		draw_string(_font, _leave_rect.position + Vector2(0.0, 35.0), tr("HUD_MENU"),
				HORIZONTAL_ALIGNMENT_CENTER, _leave_rect.size.x, 17, Palette.TEXT)
	else:
		_text(Vector2(16.0, size.y - 16.0), tr("HUD_LEAVE_HINT"), 13, Palette.TEXT_DIM)
	_draw_ability_bar(me)
	_talent_rects.clear()
	if snap.match_over:
		_draw_match_end(snap, me)
		return
	_draw_tutorial()
	_draw_talent_choice(me)
	if not me.alive:
		_text_centered(size.y * 0.4, tr("HUD_RESPAWN_IN") % ceili(me.respawn_left), 28, Palette.TEXT)
	elif me.stun_ticks > 0:
		_text_centered(size.y * 0.4, tr("HUD_STUNNED"), 28, Palette.GOLD)
	elif me.channeling:
		_draw_channel(snap.relic_progress[me.team], Palette.TEAM_COLORS[me.team])


# ---------------------------------------------------------------------------
# Au-dessus des entités
# ---------------------------------------------------------------------------

func _draw_overhead_bars(snap: SimSnapshot) -> void:
	if camera == null:
		return
	# Unités : une petite barre, seulement quand elles sont blessées.
	for u in units:
		if u.hp >= u.max_hp * 0.99:
			continue
		var at := _on_screen(Vector3(u.pos.x, 1.9 if u.kind == UnitDefs.GUARDIAN else 1.3, u.pos.y))
		if at == Vector2.INF:
			continue
		_bar(Rect2(at - Vector2(16.0, 2.0), Vector2(32.0, 4.0)), u.hp / u.max_hp, _team_color(u.team))
	for s in snap.structures:
		if not s.alive:
			continue
		var at := _on_screen(Vector3(s.pos.x, 4.8 if s.kind == SimStructure.KIND_CORE else 4.0, s.pos.y))
		if at == Vector2.INF:
			continue
		# Un bâtiment encore protégé a une barre grisée.
		var color: Color = Palette.TEAM_COLORS[s.team] if s.vulnerable else Palette.TEXT_DIM
		_bar(Rect2(at - Vector2(46.0, 5.0), Vector2(92.0, 10.0)), s.hp / s.max_hp, color)
	for h in heroes:
		if not h.alive:
			continue
		var at := _on_screen(Vector3(h.pos.x, 2.5, h.pos.y))
		if at == Vector2.INF:
			continue
		var bar := Rect2(at - Vector2(34.0, 4.0), Vector2(68.0, 8.0))
		_bar(bar, h.hp / maxf(h.max_hp, 1.0), Palette.TEAM_COLORS[h.team])
		if h.shield > 0.0:
			# Le bouclier s'ajoute par-dessus la vie, en clair.
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(h.shield / maxf(h.max_hp, 1.0), 0.0, 1.0), 3.0)), Color(0.85, 0.95, 1.0))
		draw_string(_font, Vector2(at.x - 80.0, bar.position.y - 6.0), client.hero_name(h.id),
				HORIZONTAL_ALIGNMENT_CENTER, 160.0, 13, Palette.TEXT)


## Position à l'écran d'un point du monde, ou Vector2.INF s'il est hors champ.
func _on_screen(world_pos: Vector3) -> Vector2:
	if camera.is_position_behind(world_pos):
		return Vector2.INF
	var at := camera.unproject_position(world_pos)
	if at.x < -60.0 or at.y < -30.0 or at.x > size.x + 60.0 or at.y > size.y + 30.0:
		return Vector2.INF
	return at


# ---------------------------------------------------------------------------
# Bandeau du haut : niveaux, score, relique
# ---------------------------------------------------------------------------

func _draw_top_bar(snap: SimSnapshot) -> void:
	# Le bandeau se dessine dans son propre repère : sur un écran étroit, il est décalé ou
	# rétréci pour tenir entre le bouton Menu et la minicarte.
	var fit := fit_in_span(top_span(size, _margins, touch), size.x, TOP_BAR_SIZE.x)
	_top_bottom = _margins.y + (8.0 + TOP_BAR_SIZE.y) * fit.y
	draw_set_transform(Vector2(fit.x, _margins.y), 0.0, Vector2(fit.y, fit.y))
	_draw_top_bar_content(snap)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_top_bar_content(snap: SimSnapshot) -> void:
	var mid := TOP_BAR_SIZE.x * 0.5
	draw_rect(Rect2(Vector2(0.0, 8.0), TOP_BAR_SIZE), Palette.PANEL)
	for team in 2:
		var color: Color = Palette.TEAM_COLORS[team]
		var left := mid - 318.0 if team == 0 else mid + 68.0
		var alignment := HORIZONTAL_ALIGNMENT_LEFT if team == 0 else HORIZONTAL_ALIGNMENT_RIGHT
		var rank := tr(RANK_KEYS[SimConst.armor_rank(snap.team_level[team])])
		draw_string(_font, Vector2(left, 30.0), "%s · %s · %s" % [tr(Palette.TEAM_KEYS[team]), tr("HUD_LEVEL") % snap.team_level[team], rank],
				alignment, 250.0, 16, color)
		# Expérience accumulée dans le niveau en cours.
		var ratio := 1.0
		if snap.team_level[team] < SimConst.MAX_LEVEL:
			ratio = snap.team_xp[team] / SimConst.xp_needed(snap.team_level[team])
		_bar(Rect2(left, 38.0, 250.0, 5.0), ratio, color.lightened(0.3))
	draw_string(_font, Vector2(mid - 60.0, 37.0), "%d  –  %d" % [snap.team_kills[0], snap.team_kills[1]],
			HORIZONTAL_ALIGNMENT_CENTER, 120.0, 22, Palette.TEXT)

	if not client.arena.has_altar:
		return
	if client.tutorial_step >= 0 and not snap.relic_active:
		# Dans le tutoriel, la relique n'apparaît que quand le scénario l'appelle.
		return
	if snap.relic_active:
		draw_string(_font, Vector2(mid - 258.0, 62.0), tr("HUD_RELIC_ACTIVE"), HORIZONTAL_ALIGNMENT_CENTER, 516.0, 14, Palette.GOLD)
		_bar(Rect2(mid - 258.0, 69.0, 250.0, 6.0), snap.relic_progress[0], Palette.TEAM_COLORS[0])
		_bar(Rect2(mid + 8.0, 69.0, 250.0, 6.0), snap.relic_progress[1], Palette.TEAM_COLORS[1])
	else:
		var seconds := ceili(snap.relic_timer)
		draw_string(_font, Vector2(mid - 258.0, 66.0), tr("HUD_RELIC_IN") % ("%d:%02d" % [seconds / 60, seconds % 60]),
				HORIZONTAL_ALIGNMENT_CENTER, 516.0, 14, Palette.TEXT_DIM)


func _draw_feed() -> void:
	var y := _margins.y + 110.0
	for entry: Dictionary in _feed:
		var alpha := clampf(entry["left"], 0.0, 1.0)
		_text(Vector2(_margins.x + 16.0, y), entry["text"], 15, Color(Palette.TEXT, alpha))
		y += 22.0


# ---------------------------------------------------------------------------
# Bas de l'écran : capacités, vie, canalisation, minicarte
# ---------------------------------------------------------------------------

func _draw_ability_bar(me: SimHero) -> void:
	var def: Dictionary = HeroDefs.get_def(me.def_id)
	var abilities: Array = def["abilities"]
	var count := abilities.size()
	var total := count * SLOT_SIZE.x + (count - 1) * SLOT_GAP
	var left := (size.x - total) * 0.5
	var top := size.y - SLOT_SIZE.y - 22.0
	if touch:
		# Les capacités sont sur les boutons tactiles : ne garder ici que la vie et l'éther.
		total = 380.0
		left = (size.x - total) * 0.5
		top = size.y - _margins.w - 14.0

	# Barre de vie du joueur, au-dessus des capacités.
	var hp_bar := Rect2(left, top - 30.0, total, 18.0)
	_bar(hp_bar, me.hp / maxf(me.max_hp, 1.0), Palette.TEAM_COLORS[me.team])
	var hp_text := "%d / %d" % [ceili(me.hp), ceili(me.max_hp)]
	# Texte clair sur ombre sombre : lisible sur la partie pleine comme sur la partie vide.
	draw_string(_font, Vector2(hp_bar.position.x + 1.0, hp_bar.position.y + 15.0), hp_text,
			HORIZONTAL_ALIGNMENT_CENTER, hp_bar.size.x, 13, Color(0.0, 0.0, 0.0, 0.85))
	draw_string(_font, Vector2(hp_bar.position.x, hp_bar.position.y + 14.0), hp_text,
			HORIZONTAL_ALIGNMENT_CENTER, hp_bar.size.x, 13, Color.WHITE)
	if me.shield > 0.0:
		draw_rect(Rect2(hp_bar.position, Vector2(hp_bar.size.x * clampf(me.shield / maxf(me.max_hp, 1.0), 0.0, 1.0), 4.0)), Color(0.85, 0.95, 1.0))
	# Jauge d'éther, juste sous la vie.
	_bar(Rect2(left, top - 8.0, total, 5.0), me.ether / SimConst.ETHER_MAX, ETHER_COLOR)
	if touch:
		return

	for slot in count:
		var ability: Dictionary = abilities[slot]
		var rect := Rect2(Vector2(left + slot * (SLOT_SIZE.x + SLOT_GAP), top), SLOT_SIZE)
		draw_rect(rect, Palette.PANEL)
		draw_rect(rect, Palette.GROUND_LINE, false, 1.5)
		draw_string(_font, Vector2(rect.position.x, rect.position.y + 22.0), tr(KEY_HINTS[slot]),
				HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 15, Palette.GOLD)
		# Les noms longs passent en plus petit pour tenir dans la case.
		var ability_name := tr(ability["name_key"])
		draw_string(_font, Vector2(rect.position.x + 2.0, rect.end.y - 12.0), ability_name,
				HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 4.0, 13 if ability_name.length() <= 15 else 11, Palette.TEXT)
		if ability.get("awakening", false):
			_draw_awaken_slot(me, rect)
			continue
		var left_time: float = me.cooldowns[slot]
		var full_time := HeroDefs.value(me, slot, "cooldown")
		# Les recharges très courtes (attaque de base) ne sont pas affichées.
		if left_time > 0.0 and full_time >= 1.0:
			var covered := rect.size.y * clampf(left_time / full_time, 0.0, 1.0)
			draw_rect(Rect2(rect.position.x, rect.end.y - covered, rect.size.x, covered), Color(0.0, 0.0, 0.0, 0.6))
			draw_string(_font, Vector2(rect.position.x, rect.position.y + 50.0), "%.1f" % left_time,
					HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 22, Palette.TEXT)


## Tutoriel : l'étape en cours et sa consigne, sous le bandeau du haut.
func _draw_tutorial() -> void:
	var step := client.tutorial_step
	if step < 0:
		return
	var key := "TUTORIAL_%d" % step
	# Certaines consignes ont une version tactile.
	if touch and tr(key + "_TOUCH") != key + "_TOUCH":
		key += "_TOUCH"
	var span := top_span(size, _margins, touch)
	var top := _top_bottom + 10.0
	var text := tr(key)
	var width := minf(700.0, span.y - span.x)
	var lines := _font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, width - 28.0, 15).y
	if touch and top + lines + 44.0 > size.y - _margins.w - TouchControls.top_reach():
		# Le panneau descendrait sur les boutons de capacités : il s'arrête avant eux.
		span.y = minf(span.y, size.x - _margins.z - TouchControls.reach())
		width = minf(700.0, span.y - span.x)
		lines = _font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, width - 28.0, 15).y
	var left := fit_in_span(span, size.x, width).x
	draw_rect(Rect2(left, top, width, lines + 44.0), Palette.PANEL)
	draw_rect(Rect2(left, top, width, lines + 44.0), Palette.GOLD, false, 1.5)
	var title := tr("HUD_TUTORIAL_DONE")
	if step < TutorialDirector.STEP_DONE:
		title = tr("HUD_TUTORIAL_STEP") % [step + 1, TutorialDirector.STEP_DONE]
	draw_string(_font, Vector2(left + 14.0, top + 22.0), title, HORIZONTAL_ALIGNMENT_LEFT, width - 28.0, 14, Palette.GOLD)
	draw_multiline_string(_font, Vector2(left + 14.0, top + 44.0), text, HORIZONTAL_ALIGNMENT_LEFT, width - 28.0, 15, -1, Palette.TEXT)
	_tutorial_bottom = top + lines + 44.0


## Créneau de l'éveil : il se remplit avec l'éther, puis affiche le temps d'éveil restant.
func _draw_awaken_slot(me: SimHero, rect: Rect2) -> void:
	if me.is_awakened():
		draw_rect(rect, Color(ETHER_COLOR, 0.25))
		draw_rect(rect, ETHER_COLOR, false, 2.5)
		draw_string(_font, Vector2(rect.position.x, rect.position.y + 50.0), "%.1f" % (me.awaken_ticks * SimConst.DT),
				HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 22, Color.WHITE)
		return
	var ratio := clampf(me.ether / SimConst.ETHER_MAX, 0.0, 1.0)
	if ratio >= 1.0:
		draw_rect(rect, ETHER_COLOR, false, 2.5)
		draw_string(_font, Vector2(rect.position.x, rect.position.y + 48.0), tr("HUD_READY"),
				HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 16, ETHER_COLOR)
		return
	var empty := rect.size.y * (1.0 - ratio)
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, empty)), Color(0.0, 0.0, 0.0, 0.6))
	draw_string(_font, Vector2(rect.position.x, rect.position.y + 50.0), "%d %%" % int(ratio * 100.0),
			HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 18, Palette.TEXT)


## Choix de talent : deux propositions, à prendre avec les touches 1 et 2 ou en les touchant.
func _draw_talent_choice(me: SimHero) -> void:
	var tier := client.pending_talent_tier()
	if tier < 0:
		return
	var options: Array = HeroDefs.get_def(me.def_id)["talents"][tier]
	# En tactile, les cases passent sous le bandeau du haut (ou sous le panneau du tutoriel).
	var rects := talent_layout(size, _margins, touch, maxf(_top_bottom, _tutorial_bottom) + 40.0)
	var left := rects[0].position.x
	var top := rects[0].position.y
	var total := rects[1].end.x - left
	draw_rect(Rect2(left, top - 30.0, total, 26.0), Palette.PANEL)
	var title_key := "HUD_TALENT_TITLE_TOUCH" if touch else "HUD_TALENT_TITLE"
	draw_string(_font, Vector2(left, top - 11.0), tr(title_key) % SimConst.TALENT_LEVELS[tier],
			HORIZONTAL_ALIGNMENT_CENTER, total, 16 if total >= 560.0 else 14, Palette.GOLD)
	for i in 2:
		var option: Dictionary = options[i]
		var rect := rects[i]
		_talent_rects.append(rect)
		draw_rect(rect, Palette.PANEL)
		draw_rect(rect, Palette.GOLD, false, 1.5)
		var title := tr(option["name_key"]) if touch else "[%d]  %s" % [i + 1, tr(option["name_key"])]
		draw_string(_font, rect.position + Vector2(12.0, 26.0), title,
				HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 24.0, 16, Palette.GOLD)
		draw_multiline_string(_font, rect.position + Vector2(12.0, 50.0), tr(option["desc_key"]),
				HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 24.0, 13, 2 if rect.size.y <= TALENT_BOX.y else 3, Palette.TEXT)


func _draw_channel(progress: float, color: Color) -> void:
	var bar := Rect2(size.x * 0.5 - 150.0, size.y * 0.62, 300.0, 14.0)
	_text_centered(bar.position.y - 10.0, tr("HUD_CHANNELING"), 18, Palette.TEXT)
	_bar(bar, progress, color)


func _draw_minimap(snap: SimSnapshot) -> void:
	var arena := client.arena
	var half := arena.half_size
	var map_width := MINIMAP_WIDTH_TOUCH if touch else MINIMAP_WIDTH
	var map_size := Vector2(map_width, map_width * half.y / half.x)
	var origin := size - map_size - Vector2(16.0, 16.0)
	if touch:
		# En bas à droite se trouvent les boutons : la minicarte monte dans le coin du haut.
		origin = Vector2(size.x - _margins.z - map_size.x - 16.0, _margins.y + 16.0)
	draw_rect(Rect2(origin - Vector2(3.0, 3.0), map_size + Vector2(6.0, 6.0)), Palette.PANEL)
	draw_rect(Rect2(origin, map_size), Color(Palette.GROUND, 0.9))
	var to_map := func(p: Vector2) -> Vector2:
		return origin + (p + half) / (half * 2.0) * map_size

	for lane: Array in arena.lanes:
		for i in lane.size() - 1:
			draw_line(to_map.call(lane[i]), to_map.call(lane[i + 1]), Palette.LANE, 3.0)
	for i in arena.camps.size():
		var camp_pos: Vector2 = arena.camps[i]["pos"]
		var ready: bool = i < snap.camps.size() and snap.camps[i]["alive"] > 0
		draw_circle(to_map.call(camp_pos), 4.0, NEUTRAL if ready else Color(NEUTRAL, 0.25))
	if arena.has_altar:
		draw_circle(to_map.call(arena.altar), 5.0, Color.WHITE if snap.relic_active else Color(1.0, 1.0, 1.0, 0.25))
	for u in units:
		if u.team != SimConst.TEAM_NEUTRAL:
			draw_circle(to_map.call(u.pos), 1.5, Palette.TEAM_COLORS[u.team])
	for s in snap.structures:
		var half_side := 5.0 if s.kind == SimStructure.KIND_CORE else 3.5
		var rect := Rect2(to_map.call(s.pos) - Vector2(half_side, half_side), Vector2(half_side, half_side) * 2.0)
		if s.alive:
			draw_rect(rect, Palette.TEAM_COLORS[s.team])
		else:
			draw_rect(rect, Color(Palette.TEAM_COLORS[s.team], 0.35), false, 1.0)
	var goal := TutorialDirector.marker(client.tutorial_step)
	if goal != Vector2.INF:
		draw_arc(to_map.call(goal), 7.0, 0.0, TAU, 20, Color("fff4d6"), 2.0)
	for h in heroes:
		if not h.alive:
			continue
		var at: Vector2 = to_map.call(h.pos)
		if h.id == client.my_hero_id:
			draw_circle(at, 6.0, Color.WHITE)
		draw_circle(at, 4.0, Palette.TEAM_COLORS[h.team])


func _draw_match_end(snap: SimSnapshot, me: SimHero) -> void:
	draw_rect(Rect2(0.0, size.y * 0.3, size.x, 130.0), Color(0.0, 0.0, 0.0, 0.6))
	var won := snap.winner == me.team
	_text_centered(size.y * 0.3 + 70.0, tr("HUD_VICTORY") if won else tr("HUD_DEFEAT"), 56,
			Palette.GOLD if won else Palette.TEXT_DIM)
	if client.tutorial_step < 0:
		_text_centered(size.y * 0.3 + 108.0, tr("HUD_NEXT_MATCH"), 16, Palette.TEXT)


# ---------------------------------------------------------------------------
# Journal des événements
# ---------------------------------------------------------------------------

func _on_game_event(type: String, a: int, b: int) -> void:
	match type:
		"kill":
			if a != 0:
				_push_feed(tr("FEED_KILL") % [client.hero_name(a), client.hero_name(b)])
			else:
				_push_feed(tr("FEED_FALLEN") % client.hero_name(b))
		"structure":
			if a >= 0 and a < client.arena.structures.size():
				var def: Dictionary = client.arena.structures[a]
				var key := "FEED_CORE" if def["kind"] == SimStructure.KIND_CORE else "FEED_TEMPLE"
				_push_feed(tr(key) % tr(Palette.TEAM_KEYS[def["team"]]))
		"relic_spawn":
			_push_feed(tr("FEED_RELIC_SPAWN"))
		"relic":
			_push_feed(tr("FEED_RELIC") % tr(Palette.TEAM_KEYS[a & 1]))
		"camp":
			_push_feed(tr("FEED_CAMP") % tr(Palette.TEAM_KEYS[a & 1]))
		"level":
			if client.local != null and a == client.local.team:
				_push_feed(tr("FEED_LEVEL") % b)
				var rank := SimConst.armor_rank(b)
				if rank != SimConst.armor_rank(b - 1):
					_push_feed(tr("FEED_RANK") % tr(RANK_KEYS[rank]))
		"awaken":
			_push_feed(tr("FEED_AWAKEN") % client.hero_name(a))


func _push_feed(text: String) -> void:
	_feed.append({"text": text, "left": FEED_DURATION})
	if _feed.size() > 6:
		_feed.pop_front()


# ---------------------------------------------------------------------------
# Outils de dessin
# ---------------------------------------------------------------------------

func _team_color(team: int) -> Color:
	return Palette.TEAM_COLORS[team] if team < 2 else NEUTRAL


func _bar(rect: Rect2, ratio: float, color: Color) -> void:
	draw_rect(rect.grow(1.5), Palette.HP_BACK)
	draw_rect(Rect2(rect.position, Vector2(rect.size.x * clampf(ratio, 0.0, 1.0), rect.size.y)), color)


func _text(at: Vector2, text: String, font_size: int, color: Color) -> void:
	draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)


func _text_centered(y: float, text: String, font_size: int, color: Color) -> void:
	draw_string(_font, Vector2(0.0, y), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, color)
