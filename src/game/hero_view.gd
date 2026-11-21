class_name HeroView
extends Node3D
## Apparence provisoire d'un héros, faite de formes simples. L'avant du modèle est l'axe +X.
## Elle sera remplacée par les modèles low-poly achetés.

var _cloth: StandardMaterial3D
var _flash: float = 0.0
var _last_hp: float = -1.0


func setup(team: int, is_local: bool) -> void:
	var team_color: Color = Palette.TEAM_COLORS[team]

	_cloth = StandardMaterial3D.new()
	_cloth.albedo_color = team_color.darkened(0.12)
	_cloth.roughness = 0.9
	_cloth.emission = Color.WHITE
	_cloth.emission_energy_multiplier = 1.5

	var armor := StandardMaterial3D.new()
	armor.albedo_color = Palette.BRONZE
	armor.metallic = 0.7
	armor.roughness = 0.35

	var skin := StandardMaterial3D.new()
	skin.albedo_color = Palette.SKIN

	var glow := StandardMaterial3D.new()
	glow.albedo_color = team_color
	glow.emission_enabled = true
	glow.emission = team_color
	glow.emission_energy_multiplier = 1.6

	var body := CapsuleMesh.new()
	body.radius = 0.42
	body.height = 1.5
	body.radial_segments = 10
	body.rings = 3
	_add_mesh(body, _cloth, Vector3(0.0, 0.8, 0.0))

	var head := SphereMesh.new()
	head.radius = 0.27
	head.height = 0.54
	head.radial_segments = 10
	head.rings = 6
	_add_mesh(head, skin, Vector3(0.0, 1.8, 0.0))

	var chest := BoxMesh.new()
	chest.size = Vector3(0.6, 0.55, 0.8)
	_add_mesh(chest, armor, Vector3(0.05, 1.2, 0.0))

	var shoulder := BoxMesh.new()
	shoulder.size = Vector3(0.42, 0.3, 0.38)
	_add_mesh(shoulder, armor, Vector3(0.0, 1.5, 0.55))
	_add_mesh(shoulder, armor, Vector3(0.0, 1.5, -0.55))

	# Trait lumineux tenu vers l'avant : indique où le héros regarde.
	var arrow := BoxMesh.new()
	arrow.size = Vector3(0.9, 0.07, 0.07)
	_add_mesh(arrow, glow, Vector3(0.85, 1.15, 0.0))

	var ring := TorusMesh.new()
	ring.inner_radius = 0.72 if is_local else 0.66
	ring.outer_radius = 0.86 if is_local else 0.72
	ring.rings = 24
	ring.ring_segments = 6
	_add_mesh(ring, glow, Vector3(0.0, 0.04, 0.0)).scale = Vector3(1.0, 0.15, 1.0)


func apply(h: SimHero, delta: float) -> void:
	visible = h.alive
	position = Vector3(h.pos.x, 0.0, h.pos.y)
	rotation.y = atan2(-h.facing.y, h.facing.x)
	# Éclair blanc bref quand le héros perd de la vie.
	if _last_hp >= 0.0 and h.hp < _last_hp - 0.5:
		_flash = 0.15
	_last_hp = h.hp
	_flash = maxf(0.0, _flash - delta)
	_cloth.emission_enabled = _flash > 0.0


func _add_mesh(mesh: Mesh, material: Material, at: Vector3) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = at
	add_child(node)
	return node
