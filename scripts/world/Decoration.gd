extends Node3D
## Decoration — 装饰物（佛像、岩石、灯笼）

enum DecoType { BUDDHA, ROCK, LANTERN, PAGODA }

var deco_type: int = DecoType.ROCK

func _ready() -> void:
	_build()

func _build() -> void:
	match deco_type:
		DecoType.BUDDHA:
			_build_buddha()
		DecoType.ROCK:
			_build_rock()
		DecoType.LANTERN:
			_build_lantern()
		DecoType.PAGODA:
			_build_pagoda()

func _build_buddha() -> void:
	# 莲花座
	var base: MeshInstance3D = MeshInstance3D.new()
	var base_cyl: CylinderMesh = CylinderMesh.new()
	base_cyl.top_radius = 1.2
	base_cyl.bottom_radius = 1.4
	base_cyl.height = 0.4
	base.mesh = base_cyl
	var stone_mat: StandardMaterial3D = StandardMaterial3D.new()
	stone_mat.albedo_color = Color(0.75, 0.72, 0.65)
	stone_mat.roughness = 0.7
	base.material_override = stone_mat
	base.position.y = 0.2
	add_child(base)
	# 佛身
	var body: MeshInstance3D = MeshInstance3D.new()
	var body_sphere: SphereMesh = SphereMesh.new()
	body_sphere.radius = 0.7
	body_sphere.height = 1.4
	body.mesh = body_sphere
	body.material_override = stone_mat
	body.position.y = 1.1
	add_child(body)
	# 佛头
	var head: MeshInstance3D = MeshInstance3D.new()
	var head_sphere: SphereMesh = SphereMesh.new()
	head_sphere.radius = 0.35
	head_sphere.height = 0.7
	head.mesh = head_sphere
	head.material_override = stone_mat
	head.position.y = 2.1
	add_child(head)
	# 光环（用细圆柱）
	var halo: MeshInstance3D = MeshInstance3D.new()
	var halo_torus: CylinderMesh = CylinderMesh.new()
	halo_torus.top_radius = 0.6
	halo_torus.bottom_radius = 0.6
	halo_torus.height = 0.05
	halo.mesh = halo_torus
	var gold_mat: StandardMaterial3D = StandardMaterial3D.new()
	gold_mat.albedo_color = Color(0.9, 0.78, 0.3)
	gold_mat.metallic = 0.8
	gold_mat.roughness = 0.3
	halo.material_override = gold_mat
	halo.position.y = 2.5
	halo.rotation.x = deg_to_rad(90)
	add_child(halo)

func _build_rock() -> void:
	var rock: MeshInstance3D = MeshInstance3D.new()
	var rock_mesh: SphereMesh = SphereMesh.new()
	rock_mesh.radius = randf_range(0.4, 1.0)
	rock_mesh.height = rock_mesh.radius * 1.6
	rock.mesh = rock_mesh
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.5 + randf_range(-0.1, 0.1), 0.48 + randf_range(-0.1, 0.1), 0.42 + randf_range(-0.1, 0.1))
	mat.roughness = 0.95
	rock.material_override = mat
	rock.scale = Vector3(1.0 + randf_range(-0.2, 0.2), 0.7 + randf_range(-0.15, 0.15), 1.0 + randf_range(-0.2, 0.2))
	rock.rotation.y = randf() * TAU
	add_child(rock)

func _build_lantern() -> void:
	# 柱
	var pole: MeshInstance3D = MeshInstance3D.new()
	var pole_cyl: CylinderMesh = CylinderMesh.new()
	pole_cyl.top_radius = 0.05
	pole_cyl.bottom_radius = 0.06
	pole_cyl.height = 2.0
	pole.mesh = pole_cyl
	var wood_mat: StandardMaterial3D = StandardMaterial3D.new()
	wood_mat.albedo_color = Color(0.4, 0.25, 0.15)
	pole.material_override = wood_mat
	pole.position.y = 1.0
	add_child(pole)
	# 灯笼
	var lantern: MeshInstance3D = MeshInstance3D.new()
	var lantern_sphere: SphereMesh = SphereMesh.new()
	lantern_sphere.radius = 0.3
	lantern_sphere.height = 0.45
	lantern.mesh = lantern_sphere
	var red_mat: StandardMaterial3D = StandardMaterial3D.new()
	red_mat.albedo_color = Color(0.8, 0.15, 0.12)
	red_mat.emission_enabled = true
	red_mat.emission = Color(0.6, 0.1, 0.08)
	red_mat.emission_energy_multiplier = 0.5
	lantern.material_override = red_mat
	lantern.position.y = 2.4
	add_child(lantern)
	# 顶盖
	var cap: MeshInstance3D = MeshInstance3D.new()
	var cap_cone: CylinderMesh = CylinderMesh.new()
	cap_cone.bottom_radius = 0.35
	cap_cone.height = 0.15
	cap.mesh = cap_cone
	cap.material_override = wood_mat
	cap.position.y = 2.7
	add_child(cap)

func _build_pagoda() -> void:
	# 多层宝塔
	var wood_mat: StandardMaterial3D = StandardMaterial3D.new()
	wood_mat.albedo_color = Color(0.55, 0.32, 0.18)
	var tile_mat: StandardMaterial3D = StandardMaterial3D.new()
	tile_mat.albedo_color = Color(0.4, 0.15, 0.12)
	tile_mat.roughness = 0.6
	for i in range(5):
		var w: float = 1.8 - i * 0.3
		# 塔身
		var body: MeshInstance3D = MeshInstance3D.new()
		var box: BoxMesh = BoxMesh.new()
		box.size = Vector3(w, 1.2, w)
		body.mesh = box
		body.material_override = wood_mat
		body.position.y = 0.6 + i * 1.4
		add_child(body)
		# 屋檐
		var roof: MeshInstance3D = MeshInstance3D.new()
		var roof_cone: CylinderMesh = CylinderMesh.new()
		roof_cone.top_radius = w * 0.4
		roof_cone.bottom_radius = w * 0.7
		roof_cone.height = 0.4
		roof.mesh = roof_cone
		roof.material_override = tile_mat
		roof.position.y = 1.3 + i * 1.4
		add_child(roof)
	# 塔尖
	var spire: MeshInstance3D = MeshInstance3D.new()
	var spire_cone: CylinderMesh = CylinderMesh.new()
	spire_cone.bottom_radius = 0.15
	spire_cone.height = 1.0
	spire.mesh = spire_cone
	var gold_mat: StandardMaterial3D = StandardMaterial3D.new()
	gold_mat.albedo_color = Color(0.85, 0.7, 0.2)
	gold_mat.metallic = 0.7
	spire.material_override = gold_mat
	spire.position.y = 1.3 + 4 * 1.4 + 0.7
	add_child(spire)
