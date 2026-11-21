class_name LocalInput
extends RefCounted
## Commandes au clavier et à la souris : déplacement direct, visée au curseur.

var camera: Camera3D
var _last_aim: Vector2 = Vector2.ZERO


func sample(client: GameClient) -> SimInput:
	var cmd := SimInput.new()
	cmd.move = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	cmd.aim = _aim_point(client)
	if Input.is_action_pressed("attack"):
		cmd.buttons |= SimConst.BTN_ATTACK
	if Input.is_action_pressed("ability_1"):
		cmd.buttons |= SimConst.BTN_ABILITY_1
	if Input.is_action_pressed("ability_2"):
		cmd.buttons |= SimConst.BTN_ABILITY_2
	if Input.is_action_pressed("awaken"):
		cmd.buttons |= SimConst.BTN_AWAKEN
	return cmd


## Point du sol sous le curseur.
func _aim_point(client: GameClient) -> Vector2:
	if camera == null or not is_instance_valid(camera):
		return client.local.pos + client.local.facing
	var mouse := camera.get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(mouse)
	var dir := camera.project_ray_normal(mouse)
	if absf(dir.y) > 0.0001:
		var t := -origin.y / dir.y
		if t > 0.0:
			var hit := origin + dir * t
			_last_aim = Vector2(hit.x, hit.z)
	return _last_aim
