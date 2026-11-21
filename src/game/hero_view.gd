class_name HeroView
extends Node3D
## Apparence provisoire d'un héros, faite de formes simples. L'avant du modèle est l'axe +X.
## La silhouette dépend du héros ("look" dans HeroDefs), la couleur de l'armure du rang
## de l'équipe. Elle sera remplacée par les modèles low-poly achetés.

const ARMOR_COLORS: Array[Color] = [Color("b0703c"), Color("cfd6e2"), Color("f5c84a")]

var _cloth: StandardMaterial3D
var _armor: StandardMaterial3D
var _glow: StandardMaterial3D
var _flash: float = 0.0
var _last_hp: float = -1.0
var _rank: int = -1
var _shield: MeshInstance3D
var _aura: MeshInstance3D
var _stun: MeshInstance3D
var _ring: MeshInstance3D
var _time: float = 0.0


func setup(team: int, is_local: bool, def_id: String) -> void:
	var team_color: Color = Palette.TEAM_COLORS[team]

	_cloth = StandardMaterial3D.new()
	_cloth.albedo_color = team_color.darkened(0.12)
	_cloth.roughness = 0.9
	_cloth.emission = Color.WHITE
	_cloth.emission_energy_multiplier = 1.5

	_armor = StandardMaterial3D.new()
	_armor.metallic = 0.7
	_armor.roughness = 0.35

	var skin := StandardMaterial3D.new()
	skin.albedo_color = Palette.SKIN

	_glow = StandardMaterial3D.new()
	_glow.albedo_color = team_color
	_glow.emission_enabled = true
	_glow.emission = team_color
	_glow.emission_energy_multiplier = 1.6

	var look: String = HeroDefs.get_def(def_id)["look"]
	var height := 1.8
	match look:
		"tank":
			height = _build_tank(skin)
		"support":
			height = _build_support(skin)
		"duelist":
			height = _build_duelist(skin)
		"mage":
			height = _build_mage(skin)
		_:
			height = _build_archer(skin)

	var ring := TorusMesh.new()
	ring.inner_radius = 0.72 if is_local else 0.66
	ring.outer_radius = 0.86 if is_local else 0.72
	ring.rings = 24
	ring.ring_segments = 6
	_ring = _add_mesh(ring, _glow, Vector3(0.0, 0.04, 0.0))
	_ring.scale = Vector3(1.0, 0.15, 1.0)

	# Bouclier : une bulle translucide autour du héros.
	var bubble_material := StandardMaterial3D.new()
	bubble_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bubble_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bubble_material.albedo_color = Color(0.75, 0.9, 1.0, 0.28)
	var bubble := SphereMesh.new()
	bubble.radius = 1.25
	bubble.height = 2.5
	bubble.radial_segments = 12
	bubble.rings = 6
	_shield = _add_mesh(bubble, bubble_material, Vector3(0.0, 1.0, 0.0))
	_shield.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shield.visible = false

	# Éveil : une colonne de lumière à la couleur de l'équipe.
	var aura_material := StandardMaterial3D.new()
	aura_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	aura_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	aura_material.albedo_color = Color(team_color.lightened(0.5), 0.3)
	var column := CylinderMesh.new()
	column.top_radius = 0.7
	column.bottom_radius = 1.15
	column.height = 3.4
	column.radial_segments = 12
	_aura = _add_mesh(column, aura_material, Vector3(0.0, 1.7, 0.0))
	_aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aura.visible = false

	# Étourdissement : une étoile qui tourne au-dessus de la tête.
	var star_material := StandardMaterial3D.new()
	star_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	star_material.albedo_color = Color("fff07a")
	var star := BoxMesh.new()
	star.size = Vector3(0.28, 0.28, 0.28)
	_stun = _add_mesh(star, star_material, Vector3(0.45, height + 0.45, 0.0))
	_stun.visible = false


func apply(h: SimHero, delta: float, rank: int) -> void:
	_time += delta
	visible = h.alive
	position = Vector3(h.pos.x, 0.0, h.pos.y)
	rotation.y = atan2(-h.facing.y, h.facing.x)
	if rank != _rank:
		_rank = rank
		_armor.albedo_color = ARMOR_COLORS[clampi(rank, 0, ARMOR_COLORS.size() - 1)]
	# Éclair blanc bref quand le héros perd de la vie.
	if _last_hp >= 0.0 and h.hp < _last_hp - 0.5:
		_flash = 0.15
	_last_hp = h.hp
	_flash = maxf(0.0, _flash - delta)
	_cloth.emission_enabled = _flash > 0.0
	_shield.visible = h.shield > 0.0
	# Hâte : l'anneau au sol s'élargit.
	_ring.scale = Vector3(1.35, 0.15, 1.35) if h.haste_ticks > 0 else Vector3(1.0, 0.15, 1.0)
	_aura.visible = h.is_awakened()
	if _aura.visible:
		_aura.scale = Vector3.ONE * (1.0 + 0.08 * sin(_time * 9.0))
	_stun.visible = h.stun_ticks > 0
	if _stun.visible:
		var angle := _time * 7.0
		_stun.position.x = cos(angle) * 0.45
		_stun.position.z = sin(angle) * 0.45
		_stun.rotation.y = angle


# ---------------------------------------------------------------------------
# Silhouettes. Chaque fonction renvoie la hauteur du sommet de la tête.
# ---------------------------------------------------------------------------

func _build_archer(skin: Material) -> float:
	_capsule(0.42, 1.5, Vector3(0.0, 0.8, 0.0))
	_head(skin, 1.8)
	_box(Vector3(0.6, 0.55, 0.8), Vector3(0.05, 1.2, 0.0), _armor)
	_box(Vector3(0.42, 0.3, 0.38), Vector3(0.0, 1.5, 0.55), _armor)
	_box(Vector3(0.42, 0.3, 0.38), Vector3(0.0, 1.5, -0.55), _armor)
	# Trait lumineux tenu vers l'avant : indique où le héros regarde.
	_box(Vector3(0.9, 0.07, 0.07), Vector3(0.85, 1.15, 0.0), _glow)
	return 2.07


func _build_tank(skin: Material) -> float:
	_capsule(0.56, 1.8, Vector3(0.0, 0.95, 0.0))
	_head(skin, 2.1)
	_box(Vector3(0.8, 0.75, 1.1), Vector3(0.05, 1.4, 0.0), _armor)
	_box(Vector3(0.6, 0.42, 0.55), Vector3(0.0, 1.8, 0.75), _armor)
	_box(Vector3(0.6, 0.42, 0.55), Vector3(0.0, 1.8, -0.75), _armor)
	# Grand écu porté devant lui, frappé d'un éclat à la couleur de l'équipe.
	_box(Vector3(0.16, 1.3, 1.15), Vector3(0.78, 1.05, 0.0), _armor)
	_box(Vector3(0.06, 0.4, 0.4), Vector3(0.88, 1.1, 0.0), _glow)
	return 2.37


func _build_support(skin: Material) -> float:
	# Longue robe évasée.
	var robe := CylinderMesh.new()
	robe.top_radius = 0.3
	robe.bottom_radius = 0.6
	robe.height = 1.35
	robe.radial_segments = 10
	_add_mesh(robe, _cloth, Vector3(0.0, 0.68, 0.0))
	_head(skin, 1.65)
	_box(Vector3(0.45, 0.35, 0.62), Vector3(0.02, 1.22, 0.0), _armor)
	# Bâton terminé par une lumière.
	var staff := CylinderMesh.new()
	staff.top_radius = 0.04
	staff.bottom_radius = 0.04
	staff.height = 1.9
	staff.radial_segments = 6
	_add_mesh(staff, _armor, Vector3(0.45, 0.95, 0.5))
	var light := SphereMesh.new()
	light.radius = 0.16
	light.height = 0.32
	light.radial_segments = 8
	light.rings = 4
	_add_mesh(light, _glow, Vector3(0.45, 2.0, 0.5))
	# Halo au-dessus de la tête.
	var halo := TorusMesh.new()
	halo.inner_radius = 0.22
	halo.outer_radius = 0.29
	halo.rings = 16
	halo.ring_segments = 5
	_add_mesh(halo, _glow, Vector3(0.0, 2.05, 0.0)).scale = Vector3(1.0, 0.4, 1.0)
	return 1.92


func _build_duelist(skin: Material) -> float:
	# Silhouette fine, penchée vers l'avant, une lame dans chaque main.
	_capsule(0.36, 1.45, Vector3(0.0, 0.78, 0.0))
	_head(skin, 1.72)
	_box(Vector3(0.5, 0.42, 0.66), Vector3(0.04, 1.2, 0.0), _armor)
	_box(Vector3(0.3, 0.2, 0.3), Vector3(0.0, 1.45, 0.45), _armor)
	_box(Vector3(0.3, 0.2, 0.3), Vector3(0.0, 1.45, -0.45), _armor)
	_box(Vector3(0.75, 0.05, 0.1), Vector3(0.62, 1.0, 0.42), _glow)
	_box(Vector3(0.75, 0.05, 0.1), Vector3(0.62, 1.0, -0.42), _glow)
	return 1.99


func _build_mage(skin: Material) -> float:
	# Robe droite, col d'armure, et un astre qui flotte devant.
	var robe := CylinderMesh.new()
	robe.top_radius = 0.34
	robe.bottom_radius = 0.5
	robe.height = 1.4
	robe.radial_segments = 8
	_add_mesh(robe, _cloth, Vector3(0.0, 0.7, 0.0))
	_head(skin, 1.7)
	_box(Vector3(0.5, 0.28, 0.72), Vector3(0.0, 1.36, 0.0), _armor)
	var orb := SphereMesh.new()
	orb.radius = 0.2
	orb.height = 0.4
	orb.radial_segments = 8
	orb.rings = 4
	_add_mesh(orb, _glow, Vector3(0.7, 1.3, 0.0))
	return 1.97


func _capsule(radius: float, height: float, at: Vector3) -> void:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	mesh.rings = 3
	_add_mesh(mesh, _cloth, at)


func _head(skin: Material, y: float) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.27
	mesh.height = 0.54
	mesh.radial_segments = 10
	mesh.rings = 6
	_add_mesh(mesh, skin, Vector3(0.0, y, 0.0))


func _box(size: Vector3, at: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_add_mesh(mesh, material, at)


func _add_mesh(mesh: Mesh, material: Material, at: Vector3) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = at
	add_child(node)
	return node
