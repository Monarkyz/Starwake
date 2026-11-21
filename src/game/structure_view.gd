class_name StructureView
extends Node3D
## Apparence provisoire d'un bâtiment : temple à colonnes ou sanctuaire au cristal.
## Détruit, il ne reste que son socle.

var _standing: Node3D
var _flame: StandardMaterial3D
var _team_color: Color


func setup(def: Dictionary) -> void:
	var pos: Vector2 = def["pos"]
	var radius: float = def["radius"]
	var reach: float = def["range"]
	_team_color = Palette.TEAM_COLORS[def["team"]]
	position = Vector3(pos.x, 0.0, pos.y)

	var stone := StandardMaterial3D.new()
	stone.albedo_color = Palette.STONE
	stone.roughness = 0.95

	_flame = StandardMaterial3D.new()
	_flame.albedo_color = _team_color
	_flame.emission_enabled = true
	_flame.emission = _team_color
	_flame.emission_energy_multiplier = 1.8

	var base := CylinderMesh.new()
	base.top_radius = radius
	base.bottom_radius = radius * 1.08
	base.height = 0.35
	base.radial_segments = 12
	_add(self, base, stone, Vector3(0.0, 0.175, 0.0))

	_standing = Node3D.new()
	add_child(_standing)

	var column := CylinderMesh.new()
	column.top_radius = 0.16
	column.bottom_radius = 0.2
	column.height = 2.2
	column.radial_segments = 6
	var column_count := 6
	for i in column_count:
		var angle := TAU * i / column_count
		_add(_standing, column, stone, Vector3(cos(angle) * radius * 0.8, 1.45, sin(angle) * radius * 0.8))

	if def["kind"] == SimStructure.KIND_CORE:
		# Sanctuaire : un grand cristal à la couleur de l'équipe.
		var crystal := CylinderMesh.new()
		crystal.top_radius = 0.0
		crystal.bottom_radius = 1.1
		crystal.height = 3.6
		crystal.radial_segments = 5
		_add(_standing, crystal, _flame, Vector3(0.0, 2.6, 0.0))
		var foot := CylinderMesh.new()
		foot.top_radius = 1.1
		foot.bottom_radius = 0.0
		foot.height = 0.8
		foot.radial_segments = 5
		_add(_standing, foot, _flame, Vector3(0.0, 0.75, 0.0))
	else:
		var roof := CylinderMesh.new()
		roof.top_radius = 0.25
		roof.bottom_radius = radius * 1.02
		roof.height = 0.9
		roof.radial_segments = 6
		_add(_standing, roof, stone, Vector3(0.0, 3.0, 0.0))
		var flame := SphereMesh.new()
		flame.radius = 0.5
		flame.height = 1.0
		flame.radial_segments = 8
		flame.rings = 4
		_add(_standing, flame, _flame, Vector3(0.0, 1.2, 0.0))

	# Limite de la portée de tir, tracée au sol.
	var ring_material := StandardMaterial3D.new()
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_material.albedo_color = Color(_team_color, 0.22)
	var ring := TorusMesh.new()
	ring.inner_radius = reach - 0.07
	ring.outer_radius = reach + 0.07
	ring.rings = 64
	ring.ring_segments = 4
	var ring_node := _add(_standing, ring, ring_material, Vector3(0.0, 0.03, 0.0))
	ring_node.scale = Vector3(1.0, 0.1, 1.0)
	ring_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func apply(s: SimStructure) -> void:
	_standing.visible = s.alive
	# Un bâtiment encore protégé brille moins.
	_flame.emission_energy_multiplier = 1.8 if s.vulnerable else 0.5


func _add(parent: Node3D, mesh: Mesh, material: Material, at: Vector3) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = at
	parent.add_child(node)
	return node
