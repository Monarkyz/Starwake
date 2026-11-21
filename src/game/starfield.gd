class_name Starfield
extends Control
## Fond étoilé du menu, toujours identique d'un lancement à l'autre.

const STAR_COUNT := 220


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Palette.NIGHT)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261121
	for i in STAR_COUNT:
		var at := Vector2(rng.randf() * size.x, rng.randf() * size.y)
		var radius := rng.randf_range(0.5, 1.8)
		var tint: Color = [Color.WHITE, Palette.GOLD, Palette.TEAM_COLORS[1]][rng.randi_range(0, 2)]
		draw_circle(at, radius, Color(tint, rng.randf_range(0.25, 0.9)))
