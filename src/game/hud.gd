class_name Hud
extends Control
## Interface en jeu, dessinée directement : barres de vie au-dessus des héros,
## score, capacités et leurs recharges, journal des éliminations.

const SLOT_SIZE := Vector2(112.0, 78.0)
const SLOT_GAP := 12.0
const KEY_HINTS: Array[String] = ["KEY_ATTACK", "KEY_ABILITY_1", "KEY_ABILITY_2"]
const FEED_DURATION := 6.0

var client: GameClient
var camera: Camera3D
## Héros affichés à cette image, fournis par GameView.
var heroes: Array[SimHero] = []

var _feed: Array = []  # [{text, left}]
var _font: Font


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	client.kill_happened.connect(_on_kill)


func _process(delta: float) -> void:
	for entry: Dictionary in _feed:
		entry["left"] -= delta
	_feed = _feed.filter(func(entry: Dictionary) -> bool: return entry["left"] > 0.0)
	queue_redraw()


func _draw() -> void:
	_draw_overhead_bars()
	_draw_score()
	_draw_feed()
	_text(Vector2(16.0, size.y - 16.0), tr("HUD_LEAVE_HINT"), 13, Palette.TEXT_DIM)
	var me := client.local
	if me == null:
		_text_centered(size.y * 0.5, tr("HUD_WAITING"), 22, Palette.TEXT)
		return
	_draw_ability_bar(me)
	if not me.alive:
		_text_centered(size.y * 0.4, tr("HUD_RESPAWN_IN") % ceili(me.respawn_left), 28, Palette.TEXT)


func _draw_overhead_bars() -> void:
	if camera == null:
		return
	for h in heroes:
		if not h.alive:
			continue
		var world_pos := Vector3(h.pos.x, 2.5, h.pos.y)
		if camera.is_position_behind(world_pos):
			continue
		var at := camera.unproject_position(world_pos)
		var bar := Rect2(at - Vector2(34.0, 4.0), Vector2(68.0, 8.0))
		var color: Color = Palette.TEAM_COLORS[h.team]
		draw_rect(bar.grow(1.5), Palette.HP_BACK)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * h.hp / maxf(h.max_hp, 1.0), bar.size.y)), color)
		var label := client.hero_name(h.id)
		draw_string(_font, Vector2(at.x - 80.0, bar.position.y - 6.0), label,
				HORIZONTAL_ALIGNMENT_CENTER, 160.0, 13, Palette.TEXT)


func _draw_score() -> void:
	var snap := client.latest_snapshot()
	if snap == null:
		return
	var mid := size.x * 0.5
	draw_rect(Rect2(mid - 190.0, 10.0, 380.0, 40.0), Palette.PANEL)
	draw_string(_font, Vector2(mid - 180.0, 37.0), tr(Palette.TEAM_KEYS[0]),
			HORIZONTAL_ALIGNMENT_LEFT, 120.0, 17, Palette.TEAM_COLORS[0])
	draw_string(_font, Vector2(mid + 60.0, 37.0), tr(Palette.TEAM_KEYS[1]),
			HORIZONTAL_ALIGNMENT_RIGHT, 120.0, 17, Palette.TEAM_COLORS[1])
	draw_string(_font, Vector2(mid - 50.0, 39.0), "%d  –  %d" % [snap.team_kills[0], snap.team_kills[1]],
			HORIZONTAL_ALIGNMENT_CENTER, 100.0, 22, Palette.TEXT)


func _draw_feed() -> void:
	var y := 80.0
	for entry: Dictionary in _feed:
		var alpha := clampf(entry["left"], 0.0, 1.0)
		_text(Vector2(16.0, y), entry["text"], 15, Color(Palette.TEXT, alpha))
		y += 22.0


func _draw_ability_bar(me: SimHero) -> void:
	var def: Dictionary = HeroDefs.get_def(me.def_id)
	var abilities: Array = def["abilities"]
	var count := abilities.size()
	var total := count * SLOT_SIZE.x + (count - 1) * SLOT_GAP
	var left := (size.x - total) * 0.5
	var top := size.y - SLOT_SIZE.y - 22.0

	# Barre de vie du joueur, au-dessus des capacités.
	var hp_bar := Rect2(left, top - 30.0, total, 18.0)
	draw_rect(hp_bar.grow(2.0), Palette.HP_BACK)
	draw_rect(Rect2(hp_bar.position, Vector2(hp_bar.size.x * me.hp / maxf(me.max_hp, 1.0), hp_bar.size.y)),
			Palette.TEAM_COLORS[me.team])
	draw_string(_font, Vector2(hp_bar.position.x, hp_bar.position.y + 14.0),
			"%d / %d" % [ceili(me.hp), ceili(me.max_hp)],
			HORIZONTAL_ALIGNMENT_CENTER, hp_bar.size.x, 13, Palette.NIGHT)

	for slot in count:
		var ability: Dictionary = abilities[slot]
		var rect := Rect2(Vector2(left + slot * (SLOT_SIZE.x + SLOT_GAP), top), SLOT_SIZE)
		draw_rect(rect, Palette.PANEL)
		draw_rect(rect, Palette.GROUND_LINE, false, 1.5)
		draw_string(_font, Vector2(rect.position.x, rect.position.y + 22.0), tr(KEY_HINTS[slot]),
				HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 15, Palette.GOLD)
		draw_string(_font, Vector2(rect.position.x + 4.0, rect.end.y - 12.0), tr(ability["name_key"]),
				HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 8.0, 13, Palette.TEXT)
		var left_time: float = me.cooldowns[slot]
		var full_time: float = ability["cooldown"]
		# Les recharges très courtes (attaque de base) ne sont pas affichées.
		if left_time > 0.0 and full_time >= 1.0:
			var covered := rect.size.y * clampf(left_time / full_time, 0.0, 1.0)
			draw_rect(Rect2(rect.position.x, rect.end.y - covered, rect.size.x, covered), Color(0.0, 0.0, 0.0, 0.6))
			draw_string(_font, Vector2(rect.position.x, rect.position.y + 50.0), "%.1f" % left_time,
					HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 22, Palette.TEXT)


func _on_kill(killer_id: int, victim_id: int) -> void:
	var text := tr("FEED_KILL") % [client.hero_name(killer_id), client.hero_name(victim_id)]
	_feed.append({"text": text, "left": FEED_DURATION})
	if _feed.size() > 5:
		_feed.pop_front()


func _text(at: Vector2, text: String, font_size: int, color: Color) -> void:
	draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)


func _text_centered(y: float, text: String, font_size: int, color: Color) -> void:
	draw_string(_font, Vector2(0.0, y), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, color)
