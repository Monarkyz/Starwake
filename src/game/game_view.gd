class_name GameView
extends Node3D
## Affichage 3D de la partie : terrain, héros, projectiles, caméra et interface.
## Il ne décide de rien : il lit l'état fourni par le client et le dessine.
## Le plan de jeu (x, y) de la simulation correspond au sol (x, z) de la scène.

## Caméra lointaine à champ étroit : peu de déformation sur les bords, comme dans les jeux du genre.
const CAMERA_OFFSET := Vector3(0.0, 31.0, 18.0)

var client: GameClient
var camera: Camera3D
var hud: Hud

var _hero_views: Dictionary = {}  # id -> HeroView
var _projectile_views: Dictionary = {}  # id -> MeshInstance3D
var _focus: Vector3 = Vector3.ZERO
var _projectile_meshes: Array[SphereMesh] = []
var _projectile_materials: Array[StandardMaterial3D] = []


func setup(p_client: GameClient) -> void:
	client = p_client


func _ready() -> void:
	_build_environment()
	_build_arena(client.arena)
	_build_projectile_resources()

	camera = Camera3D.new()
	camera.fov = 30.0
	add_child(camera)
	camera.position = CAMERA_OFFSET
	camera.look_at(Vector3.ZERO)
	camera.current = true

	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Hud.new()
	hud.client = client
	hud.camera = camera
	layer.add_child(hud)

	var input := LocalInput.new()
	input.camera = camera
	if client.input_source == null:
		client.input_source = input


func _process(delta: float) -> void:
	var heroes := client.get_render_heroes()
	_sync_heroes(heroes, delta)
	_sync_projectiles(client.get_render_projectiles())
	hud.heroes = heroes

	if client.local != null:
		var p := client.get_local_render_pos()
		var half := client.arena.half_size
		# La caméra s'arrête avant les bords pour ne pas montrer le vide autour du terrain.
		var target := Vector3(clampf(p.x, -half.x + 15.0, half.x - 15.0), 0.0, clampf(p.y, -half.y + 9.0, half.y - 5.0))
		_focus = _focus.lerp(target, 1.0 - exp(-10.0 * delta))
	camera.position = _focus + CAMERA_OFFSET


func _sync_heroes(heroes: Array[SimHero], delta: float) -> void:
	var seen: Dictionary = {}
	for h in heroes:
		seen[h.id] = true
		var view: HeroView = _hero_views.get(h.id)
		if view == null:
			view = HeroView.new()
			add_child(view)
			view.setup(h.team, h.id == client.my_hero_id)
			_hero_views[h.id] = view
		view.apply(h, delta)
	for id: int in _hero_views.keys():
		if not seen.has(id):
			_hero_views[id].queue_free()
			_hero_views.erase(id)


func _sync_projectiles(projectiles: Array[SimProjectile]) -> void:
	var seen: Dictionary = {}
	for p in projectiles:
		seen[p.id] = true
		var node: MeshInstance3D = _projectile_views.get(p.id)
		if node == null:
			node = MeshInstance3D.new()
			node.mesh = _projectile_meshes[mini(p.kind, 1)]
			node.material_override = _projectile_materials[p.team]
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(node)
			_projectile_views[p.id] = node
		node.position = Vector3(p.pos.x, 1.15, p.pos.y)
	for id: int in _projectile_views.keys():
		if not seen.has(id):
			_projectile_views[id].queue_free()
			_projectile_views.erase(id)


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Palette.NIGHT
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("8f9ad6")
	env.ambient_light_energy = 0.55
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.light_color = Color("fff1d6")
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	add_child(sun)


func _build_arena(arena: SimArena) -> void:
	var half := arena.half_size

	var ground := PlaneMesh.new()
	ground.size = half * 2.0
	_add_static(ground, _flat(Palette.GROUND), Vector3.ZERO)

	# Bordure basse autour du terrain.
	var border_material := _flat(Palette.GROUND_LINE)
	var long_side := BoxMesh.new()
	long_side.size = Vector3(half.x * 2.0 + 1.0, 0.6, 0.5)
	_add_static(long_side, border_material, Vector3(0.0, 0.3, -half.y - 0.25))
	_add_static(long_side, border_material, Vector3(0.0, 0.3, half.y + 0.25))
	var short_side := BoxMesh.new()
	short_side.size = Vector3(0.5, 0.6, half.y * 2.0)
	_add_static(short_side, border_material, Vector3(-half.x - 0.25, 0.3, 0.0))
	_add_static(short_side, border_material, Vector3(half.x + 0.25, 0.3, 0.0))

	# Ligne médiane.
	var midline := BoxMesh.new()
	midline.size = Vector3(0.12, 0.02, half.y * 2.0)
	_add_static(midline, _flat(Palette.GROUND_LINE), Vector3(0.0, 0.01, 0.0))

	var stone := _flat(Palette.STONE)
	for pillar in arena.pillars:
		var column := CylinderMesh.new()
		column.top_radius = pillar.z * 0.92
		column.bottom_radius = pillar.z
		column.height = 1.8
		column.radial_segments = 10
		_add_static(column, stone, Vector3(pillar.x, 0.9, pillar.y))
		var cap := CylinderMesh.new()
		cap.top_radius = pillar.z * 1.08
		cap.bottom_radius = pillar.z * 1.08
		cap.height = 0.3
		cap.radial_segments = 10
		_add_static(cap, stone, Vector3(pillar.x, 1.95, pillar.y))

	# Dalles d'apparition, à la couleur de chaque équipe.
	for team in 2:
		var pad_material := _flat(Palette.TEAM_COLORS[team].darkened(0.45))
		var points: Array = arena.spawns[team]
		for point: Vector2 in points:
			var pad := CylinderMesh.new()
			pad.top_radius = 1.1
			pad.bottom_radius = 1.1
			pad.height = 0.06
			pad.radial_segments = 16
			_add_static(pad, pad_material, Vector3(point.x, 0.03, point.y))


func _build_projectile_resources() -> void:
	for radius: float in [0.22, 0.38]:
		var mesh := SphereMesh.new()
		mesh.radius = radius
		mesh.height = radius * 2.0
		mesh.radial_segments = 8
		mesh.rings = 4
		_projectile_meshes.append(mesh)
	for team in 2:
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Palette.TEAM_COLORS[team].lightened(0.45)
		_projectile_materials.append(material)


func _add_static(mesh: Mesh, material: Material, at: Vector3) -> void:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = at
	add_child(node)


func _flat(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.95
	return material
