class_name SafeArea
## Zone sûre de l'écran sur mobile : la partie qui n'est cachée ni par une encoche ni par
## des bords arrondis. Sur ordinateur, tout l'écran est sûr.


## Marges à respecter, dans les unités de l'interface : (gauche, haut, droite, bas).
static func margins(control: Control) -> Vector4:
	if not OS.has_feature("mobile"):
		return Vector4.ZERO
	var window := Vector2(DisplayServer.window_get_size())
	var safe := DisplayServer.get_display_safe_area()
	if window.x <= 0.0 or window.y <= 0.0 or safe.size.x <= 0 or safe.size.y <= 0:
		return Vector4.ZERO
	# L'interface est mise à l'échelle : convertir les pixels de l'écran en unités d'interface.
	var per_pixel := control.size / window
	return Vector4(
		maxf(0.0, safe.position.x * per_pixel.x),
		maxf(0.0, safe.position.y * per_pixel.y),
		maxf(0.0, (window.x - safe.end.x) * per_pixel.x),
		maxf(0.0, (window.y - safe.end.y) * per_pixel.y))
