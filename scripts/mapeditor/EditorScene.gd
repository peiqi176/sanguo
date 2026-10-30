extends RefCounted
## EditorScene —— 地图工坊的 3D 画布搭建（环境光 / 地形 / 格子线 / 笔刷圈）
##
## 这些是"进场景搭一次就不再动"的东西，和交互逻辑无关，所以从 MapEditor 里搬出来。
## 地形材质走 TerrainMaterial（和游戏共用的那一份），保证编辑器所见即游戏所得。

const TerrainMaterial = preload("res://scripts/core/TerrainMaterial.gd")
const WaterPlane = preload("res://scripts/world/WaterPlane.gd")

## 网格线抬离地表的高度，防止和地形 z-fighting（会闪）
const GRID_LIFT: float = 0.06
## 笔刷圈抬离地表的高度
const RING_LIFT: float = 0.12

# ---------------------------------------------------------------- 环境

## 阳光 + 天空 + 雾。参数刻意和 Main.tscn 接近，否则"编辑器里调好、进游戏变味"。
static func build_environment(parent: Node3D) -> void:
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-55), deg_to_rad(45), 0)
	sun.light_energy = 1.15   # 1.55→1.15：亮材质（泥0.74/路芯0.85）直射下暖白过曝，AoE4 的太阳没这么猛
	sun.light_color = Color(1.0, 0.95, 0.85)
	sun.shadow_enabled = true
	sun.shadow_normal_bias = 0.4
	sun.shadow_bias = 0.06
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	parent.add_child(sun)

	var we: WorldEnvironment = WorldEnvironment.new()
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky: Sky = Sky.new()
	var sm: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.35, 0.55, 0.80)
	sm.sky_horizon_color = Color(0.70, 0.82, 0.92)
	sm.sky_curve = 0.55
	sm.sun_angle_max = 45.0
	sm.sun_curve = 0.3
	sky.sky_material = sm
	env.sky = sky
	env.background_sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	# ⚠ 与 Main.gd 完全对齐（0.33/0.55）。曾经 0.78/0.6——环境光比游戏亮 2.4 倍，
	# 亮材质（路芯反照率 0.85）直接被推到 RGB 爆白（实测 (255,255,243)）。
	env.ambient_light_energy = 0.33
	env.ambient_light_sky_contribution = 0.55
	# ⚠ 与 Main.gd 的环境口径保持一致（AoE4 观感）——曾经编辑器用 FILMIC + 雾 0.0024，
	# 游戏用 ACES + 雾 0.00085，结果"编辑器里调好、进游戏变了"且编辑器整体发灰。
	env.fog_enabled = true
	env.fog_light_color = Color(0.635, 0.715, 0.815)   # 与 Main 同款偏冷天光色
	env.fog_density = 0.00085
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.82  # 0.96→0.82：亮材质（路芯反照率0.85）直射下爆白，给亮部留头部空间
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.15
	env.adjustment_saturation = 1.12
	env.adjustment_brightness = 1.0
	# ⚠ 必须显式关：泥带/路芯这类亮材质辐照超阈值时，glow 会把亮部晕染成
	# "白色云雾状"斑块（Main.gd 同款问题早修过，编辑器漏了）。
	env.glow_enabled = false
	we.environment = env
	parent.add_child(we)

# ---------------------------------------------------------------- 地形

## 地形是一张平面 + shader 顶点位移（不是真网格），所以这里只需要"够密的平面"。
## 细分太少笔刷改了看不出，太多白烧性能，取高度图分辨率的 75%。
static func build_terrain(parent: Node3D, world_size: float, heightmap_size: int) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(world_size, world_size)
	var sub: int = clampi(int(float(heightmap_size) * 0.75), 96, 400)
	plane.subdivide_width = sub
	plane.subdivide_depth = sub
	mi.mesh = plane
	mi.material_override = TerrainMaterial.build()
	# Godot 4 的 PlaneMesh 默认就是水平 XZ 平面，不要再转 -90°（会立成一堵墙，看不见）
	mi.rotation = Vector3.ZERO
	mi.position = Vector3(world_size * 0.5, 0.0, world_size * 0.5)
	# shader 顶点位移的 AABB 引擎不知道，必须自己撑开，否则低机位会被剔除
	var cull_h: float = float(Terrain.params.max_height) * 2.0 + 8.0
	mi.custom_aabb = AABB(Vector3(-world_size * 0.5, -cull_h, -world_size * 0.5),
		Vector3(world_size, cull_h * 2.0, world_size))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi

# ---------------------------------------------------------------- 水面

## 编辑器水面：与游戏共用 WaterPlane（所见即所得）。
## 平地白纸图高度 1.92m 高于默认水面 -5m，所以看不见水；
## 用「下压」笔刷把地面压到 -5m 以下，水立刻冒出来。
static func build_water(parent: Node3D) -> MeshInstance3D:
	return WaterPlane.build(parent, Terrain.heightmap_tex,
		float(Terrain.params.world_size), float(Terrain.params.max_height),
		float(Terrain.params.water_level))

# ---------------------------------------------------------------- 格子线

## 每 cell_size 一条线，沿地表起伏（不是平面网格），方便判断"一格有多大"
static func build_grid(parent: Node3D, world_size: float, cell: float) -> MeshInstance3D:
	var steps: int = int(world_size / cell)
	var mi: MeshInstance3D = MeshInstance3D.new()
	var im: ImmediateMesh = ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(steps + 1):
		var c: float = float(i) * cell
		im.surface_set_color(Color(1, 1, 1, 0.10))
		for k in range(steps):
			var x0: float = float(k) * cell
			var x1: float = x0 + cell
			im.surface_add_vertex(Vector3(x0, Terrain.get_height(x0, c) + GRID_LIFT, c))
			im.surface_add_vertex(Vector3(x1, Terrain.get_height(x1, c) + GRID_LIFT, c))
		for k in range(steps):
			var z0: float = float(k) * cell
			var z1: float = z0 + cell
			im.surface_add_vertex(Vector3(c, Terrain.get_height(c, z0) + GRID_LIFT, z0))
			im.surface_add_vertex(Vector3(c, Terrain.get_height(c, z1) + GRID_LIFT, z1))
	im.surface_end()
	mi.mesh = im
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	parent.add_child(mi)
	return mi

# ---------------------------------------------------------------- 笔刷圈

## 笔刷圈是沿地表采样的多边形环（不是贴平面的圆），这样在山坡上也贴得准
static func build_brush_ring(parent: Node3D) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = ImmediateMesh.new()
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.85, 0.25, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	parent.add_child(mi)
	return mi

## center 传 Vector3.INF 表示"隐藏"（光标不在地形上）
static func rebuild_brush_ring(mi: MeshInstance3D, center: Vector3, radius: float) -> void:
	if mi == null:
		return
	var im: ImmediateMesh = mi.mesh
	if im == null:
		return
	im.clear_surfaces()
	if center == Vector3.INF:
		return
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	var seg: int = 48
	for i in range(seg + 1):
		var a: float = TAU * float(i) / float(seg)
		var x: float = center.x + cos(a) * radius
		var z: float = center.z + sin(a) * radius
		im.surface_add_vertex(Vector3(x, Terrain.get_height(x, z) + RING_LIFT, z))
	im.surface_end()
