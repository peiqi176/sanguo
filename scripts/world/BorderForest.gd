extends Object
## BorderForest — 地图边界"不可逾越密林带"（AoE4 式边界）
##
## 设计口径（用户 2026-10-24）：
##   · 地图最外圈一圈谁都过不去（GridManager 已把最外 BORDER_CELLS 圈标成 occupied=4）；
##   · 视觉上用一圈**很密集**的深色针叶林标出来，玩家一眼就知道"这里过不去"；
##   · 边界树不需要被砍（也砍不动）——它们不是 ResourceNode，没有耐久的概念，
##     等价于"无限耐久"，单位也走不进去。
##
## 为什么用 MultiMesh：密林带 1000+ 棵，逐棵 add_child 会把 draw call 打爆。
## 两层交叉面片（每层一个 MultiMesh）= 全场 2 个 draw call，代价是树不摇——边界树是"墙"。

const BORDER_CELLS: int = 4   # 与 GridManager.BORDER_CELLS 保持一致
const TEX_PATH := "res://assets/trees/pine.png"

## 沿地图四边种一圈密林。host 一般传 Main；grid 是 GridManager 节点。
static func populate(host: Node3D, grid: Node) -> void:
	if host == null or grid == null:
		return
	var n: int = grid.map_size.x
	var cell: float = grid.cell_size
	var rng := RandomNumberGenerator.new()
	rng.seed = 777001   # 固定种子：同一张地图每次进游戏边界长得一样

	# 收集所有种植点：边界带内每隔一格种一棵（带抖动）
	var points: PackedVector3Array = PackedVector3Array()
	var scales: PackedFloat32Array = PackedFloat32Array()
	var inner: int = n - BORDER_CELLS
	for gx in range(n):
		for gz in range(n):
			var in_band: bool = gx < BORDER_CELLS or gz < BORDER_CELLS \
				or gx >= inner or gz >= inner
			if not in_band:
				continue
			# 带内 4 圈全种太挤成实体墙；按 85% 概率种，再加大抖动，密而不呆板
			if rng.randf() > 0.85:
				continue
			var wx: float = grid.origin.x + (float(gx) + 0.5 + rng.randf_range(-0.45, 0.45)) * cell
			var wz: float = grid.origin.z + (float(gz) + 0.5 + rng.randf_range(-0.45, 0.45)) * cell
			points.append(Vector3(wx, Terrain.get_height(wx, wz), wz))
			scales.append(rng.randf_range(0.9, 1.6))

	if points.is_empty():
		return

	var tex: Texture2D = null
	# ResourceLoader.exists 对未导入 PNG 会说谎（历史坑），用 FileAccess + Image 兜底
	if FileAccess.file_exists(TEX_PATH):
		var img: Image = Image.load_from_file(ProjectSettings.globalize_path(TEX_PATH))
		if img != null:
			img.generate_mipmaps()
			tex = ImageTexture.create_from_image(img)

	if tex != null:
		# 手绘立绘交叉面片：两层 MultiMesh（各一个朝向），底边通过 center_offset 抬到地上
		var quad := QuadMesh.new()
		quad.size = Vector2(5.6, 7.6)
		quad.center_offset = Vector3(0.0, quad.size.y * 0.5, 0.0)   # 底边对齐原点（正半高把面片抬上来）
		quad.orientation = PlaneMesh.FACE_Z
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = tex
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold = 0.45
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.roughness = 1.0
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		quad.material = mat
		_add_layer(host, points, scales, quad, deg_to_rad(45.0))    # 主面朝视线
		_add_layer(host, points, scales, quad, deg_to_rad(135.0))   # 交叉面
		print("[BorderForest] 边界密林：%d 棵（手绘面片 ×2 层，draw call 2）" % points.size())
	else:
		# 没有贴图 → 低多边形兜底（保留老三层锥）
		_add_layer(host, points, scales, _make_trunk_mesh(), 0.0)
		_add_layer(host, points, scales, _make_cone_mesh(2.8, 1.25, Color(0.075, 0.145, 0.065)), 1.9)
		_add_layer(host, points, scales, _make_cone_mesh(2.1, 0.85, Color(0.095, 0.175, 0.078)), 3.4)
		print("[BorderForest] 边界密林：%d 棵（低多边形兜底）" % points.size())

static func _add_layer(host: Node3D, points: PackedVector3Array, scales: PackedFloat32Array,
		mesh: Mesh, yaw: float) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = points.size()
	var t := Transform3D()
	for i in range(points.size()):
		var s: float = scales[i]
		var flip: float = -1.0 if (i % 3 == 0) else 1.0   # 1/3 镜像，避免剪贴画感
		var yaw_j: float = yaw + fmod(float(i) * 2.39996, 0.24) - 0.12  # ±7° 抖动
		t = Transform3D(
			Basis(Vector3.UP, yaw_j).scaled(Vector3(flip * s, s, s)),
			points[i])
		mm.set_instance_transform(i, t)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	# 不投影：边界在地图最外圈，阴影收益小、几千个实例投阴影开销大
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(mmi)

static func _make_trunk_mesh() -> Mesh:
	var m := CylinderMesh.new()
	m.top_radius = 0.14
	m.bottom_radius = 0.22
	m.height = 2.2
	m.radial_segments = 5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.23, 0.16, 0.11)
	mat.roughness = 1.0
	m.material = mat
	return m

## top_radius=0 的圆柱就是圆锥（Godot 的 CylinderMesh 自带这个用法）
static func _make_cone_mesh(h: float, r: float, c: Color) -> Mesh:
	var m := CylinderMesh.new()
	m.top_radius = 0.0
	m.bottom_radius = r
	m.height = h
	m.radial_segments = 7
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.roughness = 1.0
	m.material = mat
	return m
