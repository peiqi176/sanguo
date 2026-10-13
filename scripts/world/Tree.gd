extends Node3D
## Tree — 低多边形3D树木（树干+树冠）

enum TreeType { PINE, OAK, BIRCH, DEAD }

var tree_type: int = TreeType.PINE
var _sway_offset: float = 0.0

func _ready() -> void:
	_sway_offset = randf() * TAU
	_build_tree()

func _build_tree() -> void:
	match tree_type:
		TreeType.PINE:
			_build_pine()
		TreeType.OAK:
			_build_oak()
		TreeType.BIRCH:
			_build_birch()
		TreeType.DEAD:
			_build_dead()

func _create_trunk(height: float, radius: float, color: Color) -> MeshInstance3D:
	var trunk: MeshInstance3D = MeshInstance3D.new()
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = radius * 0.6
	cyl.bottom_radius = radius
	cyl.height = height
	trunk.mesh = cyl
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	trunk.material_override = mat
	trunk.position.y = height / 2.0
	return trunk

func _create_foliage(radius: float, height: float, color: Color, pos: Vector3) -> MeshInstance3D:
	var fol: MeshInstance3D = MeshInstance3D.new()
	var cone: CylinderMesh = CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = radius
	cone.height = height
	fol.mesh = cone
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.8
	fol.material_override = mat
	fol.position = pos
	return fol

func _build_pine() -> void:
	var trunk_h: float = 2.0 + randf_range(-0.3, 0.5)
	var trunk: MeshInstance3D = _create_trunk(trunk_h, 0.25, Color(0.35, 0.22, 0.12))
	add_child(trunk)
	# 三层树冠
	var green: Color = Color(0.15 + randf_range(-0.05, 0.08), 0.40 + randf_range(-0.08, 0.1), 0.12)
	add_child(_create_foliage(1.4, 2.0, green, Vector3(0, trunk_h + 0.5, 0)))
	add_child(_create_foliage(1.1, 1.8, green.darkened(0.1), Vector3(0, trunk_h + 1.8, 0)))
	add_child(_create_foliage(0.7, 1.5, green.darkened(0.15), Vector3(0, trunk_h + 2.8, 0)))
	scale.y = 1.0 + randf_range(-0.15, 0.2)

func _build_oak() -> void:
	var trunk_h: float = 1.5 + randf_range(-0.2, 0.4)
	var trunk: MeshInstance3D = _create_trunk(trunk_h, 0.3, Color(0.4, 0.25, 0.14))
	add_child(trunk)
	var green: Color = Color(0.2 + randf_range(-0.05, 0.1), 0.45 + randf_range(-0.08, 0.12), 0.15)
	# 球形树冠（用圆锥近似）
	add_child(_create_foliage(1.6, 2.2, green, Vector3(0, trunk_h + 0.8, 0)))
	add_child(_create_foliage(1.2, 1.8, green.darkened(0.1), Vector3(0.6, trunk_h + 1.2, 0.3)))
	add_child(_create_foliage(1.0, 1.5, green.lightened(0.1), Vector3(-0.5, trunk_h + 1.4, -0.2)))
	scale.y = 1.0 + randf_range(-0.1, 0.25)

func _build_birch() -> void:
	var trunk_h: float = 2.5 + randf_range(-0.2, 0.5)
	var trunk: MeshInstance3D = _create_trunk(trunk_h, 0.18, Color(0.85, 0.82, 0.78))
	add_child(trunk)
	var green: Color = Color(0.3, 0.5, 0.2)
	add_child(_create_foliage(1.0, 1.6, green, Vector3(0, trunk_h + 0.4, 0)))
	add_child(_create_foliage(0.8, 1.4, green.darkened(0.1), Vector3(0.4, trunk_h + 1.2, 0.2)))
	scale.y = 1.0 + randf_range(-0.1, 0.2)

func _build_dead() -> void:
	var trunk_h: float = 2.0 + randf_range(-0.3, 0.5)
	var trunk: MeshInstance3D = _create_trunk(trunk_h, 0.22, Color(0.3, 0.22, 0.15))
	add_child(trunk)
	# 枯枝
	for i in range(3):
		var branch: MeshInstance3D = MeshInstance3D.new()
		var cyl: CylinderMesh = CylinderMesh.new()
		cyl.top_radius = 0.05
		cyl.bottom_radius = 0.1
		cyl.height = 1.0 + randf() * 0.8
		branch.mesh = cyl
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = Color(0.35, 0.25, 0.16)
		branch.material_override = mat
		var angle: float = randf() * TAU
		branch.position = Vector3(cos(angle) * 0.3, trunk_h * 0.7, sin(angle) * 0.3)
		branch.rotation = Vector3(randf_range(-0.5, 0.5), angle, randf_range(-0.3, 0.3))
		add_child(branch)

func _process(delta: float) -> void:
	# 微风吹动
	rotation.z = sin(Time.get_ticks_msec() / 1000.0 + _sway_offset) * 0.02
	rotation.x = cos(Time.get_ticks_msec() / 1200.0 + _sway_offset) * 0.015
