class_name GameView
extends Node3D
## Affichage 3D de la partie : carte, bâtiments, héros, unités, projectiles, caméra et interface.
## Il ne décide de rien : il lit l'état fourni par le client et le dessine.
## Le plan de jeu (x, y) de la simulation correspond au sol (x, z) de la scène.

## Caméra lointaine à champ étroit : peu de déformation sur les bords, comme dans les jeux du genre.
const CAMERA_OFFSET := Vector3(0.0, 31.0, 18.0)
const NEUTRAL_COLOR := Color("5fb3a8")
## Durée d'affichage et épaisseur des traits d'attaque, par type (voir SimWorld.BEAM_*).
const BEAM_LIFE: Array[float] = [0.14, 0.1, 0.7]
const BEAM_WIDTH: Array[float] = [0.14, 0.06, 0.5]

var client: GameClient
var camera: Camera3D
var hud: Hud
## Commandes tactiles à afficher par-dessus la partie (fournies par le point d'entrée), ou null.
var touch_controls: TouchControls

var _hero_views: Dictionary = {}  # id -> HeroView
var _unit_views: Dictionary = {}  # id -> MeshInstance3D
var _projectile_views: Dictionary = {}  # id -> MeshInstance3D
var _structure_views: Array[StructureView] = []
var _relic_orb: MeshInstance3D
var _beams: Array = []  # [{node, left}]
var _team_ranks: Array[int] = [0, 0]
var _focus: Vector3 = Vector3.ZERO
var _focus_ready: bool = false
var _time: float = 0.0
var _aim_line: MeshInstance3D

var _projectile_meshes: Array[SphereMesh] = []
var _projectile_materials: Array[StandardMaterial3D] = []
var _unit_meshes: Array[Mesh] = []
var _unit_heights: Array[float] = []
var _unit_materials: Array[StandardMaterial3D] = []
var _beam_mesh: BoxMesh
var _beam_materials: Array[StandardMaterial3D] = []
var _disc_mesh: CylinderMesh
var _disc_materials: Dictionary = {}  # type d'effet -> matériau


func setup(p_client: GameClient) -> void:
	client = p_client


func _ready() -> void:
	_build_environment()
	_build_map(client.arena)
	_build_shared_resources()

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
	hud.touch = touch_controls != null
	layer.add_child(hud)
	if touch_controls != null:
		layer.add_child(touch_controls)

	if client.input_source == null:
		var input := LocalInput.new()
		input.camera = camera
		client.input_source = input

	# Trait de visée affiché pendant qu'on vise au doigt.
	_aim_line = MeshInstance3D.new()
	_aim_line.mesh = _beam_mesh
	_aim_line.material_override = _beam_materials[SimWorld.BEAM_STRUCTURE]
	_aim_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aim_line.visible = false
	add_child(_aim_line)


func _process(delta: float) -> void:
	_time += delta
	var heroes := client.get_render_heroes()
	var units := client.get_render_units()
	var snap := client.latest_snapshot()
	if snap != null:
		for team in 2:
			_team_ranks[team] = SimConst.armor_rank(snap.team_level[team])
	_sync_heroes(heroes, delta)
	_sync_units(units)
	_sync_projectiles(client.get_render_projectiles())
	_sync_beams(delta)
	hud.heroes = heroes
	hud.units = units
	_update_aim_line()

	if snap != null:
		for i in mini(snap.structures.size(), _structure_views.size()):
			_structure_views[i].apply(snap.structures[i])
		if _relic_orb != null:
			_relic_orb.visible = snap.relic_active
			_relic_orb.scale = Vector3.ONE * (1.0 + 0.12 * sin(_time * 4.0))

	if client.local != null:
		var p := client.get_local_render_pos()
		var half := client.arena.half_size
		# La caméra s'arrête avant les bords pour ne pas montrer le vide autour du terrain.
		var target := Vector3(clampf(p.x, -half.x + 15.0, half.x - 15.0), 0.0, clampf(p.y, -half.y + 9.0, half.y - 5.0))
		if _focus_ready:
			_focus = _focus.lerp(target, 1.0 - exp(-10.0 * delta))
		else:
			_focus = target
			_focus_ready = true
	camera.position = _focus + CAMERA_OFFSET


# ---------------------------------------------------------------------------
# Entités mobiles
# ---------------------------------------------------------------------------

func _sync_heroes(heroes: Array[SimHero], delta: float) -> void:
	var seen: Dictionary = {}
	for h in heroes:
		seen[h.id] = true
		var view: HeroView = _hero_views.get(h.id)
		if view == null:
			view = HeroView.new()
			add_child(view)
			view.setup(h.team, h.id == client.my_hero_id, h.def_id)
			_hero_views[h.id] = view
		view.apply(h, delta, _team_ranks[h.team])
	for id: int in _hero_views.keys():
		if not seen.has(id):
			_hero_views[id].queue_free()
			_hero_views.erase(id)


func _sync_units(units: Array[SimUnit]) -> void:
	var seen: Dictionary = {}
	for u in units:
		seen[u.id] = true
		var node: MeshInstance3D = _unit_views.get(u.id)
		if node == null:
			node = MeshInstance3D.new()
			node.mesh = _unit_meshes[u.kind]
			node.material_override = _unit_materials[u.team]
			add_child(node)
			_unit_views[u.id] = node
		node.position = Vector3(u.pos.x, _unit_heights[u.kind] * 0.5, u.pos.y)
		# Petit sursaut au moment où l'unité frappe.
		node.scale = Vector3.ONE * (1.25 if u.attacked else 1.0)
	for id: int in _unit_views.keys():
		if not seen.has(id):
			_unit_views[id].queue_free()
			_unit_views.erase(id)


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


## Traits brefs pour les attaques instantanées : tirs des temples, des archers, onde de la relique.
func _sync_beams(delta: float) -> void:
	for beam: Array in client.take_beams():
		var from: Vector2 = beam[1]
		var to: Vector2 = beam[2]
		if from.distance_to(to) < 0.1:
			continue
		if beam[0] >= SimWorld.FX_SLASH:
			_spawn_disc(beam[0], from, to)
			continue
		var kind: int = clampi(beam[0], 0, BEAM_LIFE.size() - 1)
		var start := Vector3(from.x, 2.2 if kind != SimWorld.BEAM_ARCHER else 0.9, from.y)
		var end := Vector3(to.x, 0.9, to.y)
		var node := MeshInstance3D.new()
		node.mesh = _beam_mesh
		node.material_override = _beam_materials[kind]
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		node.look_at_from_position((start + end) * 0.5, end)
		node.scale = Vector3(BEAM_WIDTH[kind], BEAM_WIDTH[kind], start.distance_to(end))
		_beams.append({"node": node, "left": BEAM_LIFE[kind]})
	var kept: Array = []
	for entry: Dictionary in _beams:
		entry["left"] -= delta
		if entry["left"] > 0.0:
			kept.append(entry)
		else:
			entry["node"].queue_free()
	_beams = kept


## Pendant une visée au doigt, montre sur le terrain où partira la capacité.
func _update_aim_line() -> void:
	_aim_line.visible = false
	if touch_controls == null or client.local == null or not client.local.alive:
		return
	var aim: Array = touch_controls.preview()
	var slot: int = aim[0]
	if slot < 0:
		return
	var dir: Vector2 = aim[1]
	var length := maxf(TouchInput.reach(client.local, slot), 3.0)
	var from := client.get_local_render_pos()
	var start := Vector3(from.x, 0.25, from.y)
	var end := start + Vector3(dir.x, 0.0, dir.y) * length
	_aim_line.look_at_from_position((start + end) * 0.5, end)
	_aim_line.scale = Vector3(0.12, 0.05, length)
	_aim_line.visible = true


## Effet de zone bref, sous forme de disque au sol : coup au corps à corps, onde, soin.
func _spawn_disc(kind: int, from: Vector2, to: Vector2) -> void:
	var center := from
	var radius := from.distance_to(to)
	var life := 0.35
	if kind == SimWorld.FX_SLASH:
		# Le coup porte devant le héros : un disque à mi-chemin de sa portée.
		center = (from + to) * 0.5
		radius *= 0.55
		life = 0.16
	elif kind == SimWorld.FX_HEAL:
		life = 0.5
	var node := MeshInstance3D.new()
	node.mesh = _disc_mesh
	node.material_override = _disc_materials.get(kind, _disc_materials[SimWorld.FX_RING])
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.position = Vector3(center.x, 0.08, center.y)
	node.scale = Vector3(radius, 1.0, radius)
	add_child(node)
	_beams.append({"node": node, "left": life})


# ---------------------------------------------------------------------------
# Construction de la scène
# ---------------------------------------------------------------------------

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
	# Les ombres coûtent cher sur téléphone.
	sun.shadow_enabled = not OS.has_feature("mobile")
	sun.directional_shadow_max_distance = 90.0
	sun.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	add_child(sun)


func _build_map(arena: SimArena) -> void:
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

	# Voies : une bande claire le long de chaque tronçon.
	var lane_material := _flat(Palette.LANE)
	for lane: Array in arena.lanes:
		for i in lane.size() - 1:
			var a: Vector2 = lane[i]
			var b: Vector2 = lane[i + 1]
			var strip := BoxMesh.new()
			strip.size = Vector3(a.distance_to(b) + 4.0, 0.02, 5.0)
			var node := _add_static(strip, lane_material, Vector3((a.x + b.x) * 0.5, 0.01, (a.y + b.y) * 0.5))
			node.rotation.y = -(b - a).angle()
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

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

	for def in arena.structures:
		var view := StructureView.new()
		add_child(view)
		view.setup(def)
		_structure_views.append(view)

	# Fontaines de soin et dalles d'apparition, à la couleur de chaque équipe.
	for team in 2:
		var color: Color = Palette.TEAM_COLORS[team]
		if team < arena.fountains.size():
			var pool := CylinderMesh.new()
			pool.top_radius = SimConst.FOUNTAIN_RADIUS
			pool.bottom_radius = SimConst.FOUNTAIN_RADIUS
			pool.height = 0.04
			pool.radial_segments = 32
			var center: Vector2 = arena.fountains[team]
			_add_static(pool, _flat(color.darkened(0.7)), Vector3(center.x, 0.02, center.y)).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var points: Array = arena.spawns[team]
		for point: Vector2 in points:
			var pad := CylinderMesh.new()
			pad.top_radius = 1.1
			pad.bottom_radius = 1.1
			pad.height = 0.06
			pad.radial_segments = 16
			_add_static(pad, _flat(color.darkened(0.45)), Vector3(point.x, 0.05, point.y))

	# Camps de mercenaires : un cercle au sol.
	for camp in arena.camps:
		var center: Vector2 = camp["pos"]
		var ring := TorusMesh.new()
		ring.inner_radius = 3.0
		ring.outer_radius = 3.2
		ring.rings = 32
		ring.ring_segments = 4
		var node := _add_static(ring, _flat(NEUTRAL_COLOR.darkened(0.3)), Vector3(center.x, 0.03, center.y))
		node.scale = Vector3(1.0, 0.15, 1.0)

	if arena.has_altar:
		var dais := CylinderMesh.new()
		dais.top_radius = arena.altar_radius
		dais.bottom_radius = arena.altar_radius + 0.3
		dais.height = 0.12
		dais.radial_segments = 24
		_add_static(dais, _flat(Palette.ALTAR), Vector3(arena.altar.x, 0.06, arena.altar.y))
		var glow := StandardMaterial3D.new()
		glow.albedo_color = Color.WHITE
		glow.emission_enabled = true
		glow.emission = Color("fff4d6")
		glow.emission_energy_multiplier = 2.5
		var orb := SphereMesh.new()
		orb.radius = 0.7
		orb.height = 1.4
		orb.radial_segments = 12
		orb.rings = 6
		_relic_orb = _add_static(orb, glow, Vector3(arena.altar.x, 1.7, arena.altar.y))
		_relic_orb.visible = false


func _build_shared_resources() -> void:
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

	# Unités, dans l'ordre de UnitDefs.DEFS : fantassin, archer, gardien.
	var footman := BoxMesh.new()
	footman.size = Vector3(0.6, 0.85, 0.6)
	var archer := CylinderMesh.new()
	archer.top_radius = 0.12
	archer.bottom_radius = 0.32
	archer.height = 1.05
	archer.radial_segments = 6
	var guardian := BoxMesh.new()
	guardian.size = Vector3(1.25, 1.6, 1.25)
	_unit_meshes = [footman, archer, guardian]
	_unit_heights = [0.85, 1.05, 1.6]
	for color: Color in [Palette.TEAM_COLORS[0], Palette.TEAM_COLORS[1], NEUTRAL_COLOR]:
		_unit_materials.append(_flat(color.darkened(0.15)))

	_disc_mesh = CylinderMesh.new()
	_disc_mesh.top_radius = 1.0
	_disc_mesh.bottom_radius = 1.0
	_disc_mesh.height = 0.05
	_disc_mesh.radial_segments = 32
	for entry: Array in [[SimWorld.FX_SLASH, Color(1.0, 0.95, 0.8, 0.45)], [SimWorld.FX_RING, Color(1.0, 0.85, 0.5, 0.4)], [SimWorld.FX_HEAL, Color(0.55, 1.0, 0.7, 0.4)]]:
		var disc_material := StandardMaterial3D.new()
		disc_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		disc_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		disc_material.albedo_color = entry[1]
		_disc_materials[entry[0]] = disc_material

	_beam_mesh = BoxMesh.new()
	_beam_mesh.size = Vector3.ONE
	for color: Color in [Color("ffe9b0"), Color("d8dcff"), Color.WHITE]:
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = color
		_beam_materials.append(material)


func _add_static(mesh: Mesh, material: Material, at: Vector3) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = at
	add_child(node)
	return node


func _flat(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.95
	return material
