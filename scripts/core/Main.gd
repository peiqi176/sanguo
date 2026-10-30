extends Node3D
const TerrainMaterial = preload("res://scripts/core/TerrainMaterial.gd")
const MapIO = preload("res://scripts/mapformat/MapIO.gd")
const ObjectSpawner = preload("res://scripts/mapruntime/ObjectSpawner.gd")
const TerrainPicker = preload("res://scripts/mapeditor/TerrainPicker.gd")
const CameraController = preload("res://scripts/core/CameraController.gd")
const GroundDetail = preload("res://scripts/world/GroundDetail.gd")
const BorderForest = preload("res://scripts/world/BorderForest.gd")
const SplatBrush = preload("res://scripts/mapeditor/SplatBrush.gd")
## Main — 主场景
## 初始化游戏世界：地形、网格、相机、初始建筑/单位、AI

@onready var camera_controller: Node3D = $CameraController
@onready var grid = $GridManager
@onready var pathfinder = $Pathfinder
@onready var selection = $SelectionManager
@onready var ui: CanvasLayer = $GameUI

var _build_mode: String = ""
var _build_ghost: MeshInstance3D = null
var _terrain: MeshInstance3D = null

## 从地图工坊载入的文档（含 objects[]）。null 表示走"程序生成"那条老路。
var _loaded_doc = null

func _ready() -> void:
	# 🎯 设计 v3：最早应用开局自定义（AI反应延迟/资源倍率/黑雾/灾祸...）
	GameManager.apply_settings()

	# 🧪 测试阶段：初始资源拉满 999999（用户 2026-10-24 要求）。
	# 玩家和 AI 都给——AI 穷得造不出兵会导致测试局没有对抗强度。
	# ⚠️ 转正式版时删掉这段即可恢复原开局（粮200/木200/铁100/金150）。
	for fid in GameManager.factions.keys():
		for k in ["food", "wood", "iron", "gold"]:
			GameManager.factions[fid].resources[k] = 999999
	print("[Main] 🧪 测试模式：所有势力初始资源 999999")

	# 🎯 设计 v3：应用初始资源倍率（玩家=资源阶层 0.6/1.0/1.6，AI=难度倍率 1.0/1.2/1.8/2.5）
	for fid in GameManager.factions.keys():
		var mult: float = GameManager.initial_resources_mult if fid == GameManager.player_faction else GameManager.ai_starting_resources_mult
		if absf(mult - 1.0) > 0.01:
			for k in GameManager.factions[fid].resources.keys():
				GameManager.factions[fid].resources[k] = int(GameManager.factions[fid].resources[k] * mult)
			print("[Main] 💰 %s 初始资源 ×%.1f" % [fid, mult])

	# 🎯 设计 v3：挂载灾祸系统（开局设置"灾祸模式"开关控制）
	var disaster_sys := Node.new()
	disaster_sys.name = "DisasterSystem"
	disaster_sys.set_script(load("res://scripts/core/DisasterSystem.gd"))
	add_child(disaster_sys)

	# === 势力与颜色已在 apply_settings() 中统一处理（override 优先，其次 user:// 存档，最后 JSON 默认）===
	print("[Main] 玩家势力 = %s, 颜色 = %s" % [GameManager.player_faction, GameManager.get_faction_color(GameManager.player_faction)])
	
	# === AI 势力默认颜色（跟玩家不同） ===
	var player_fc: Color = GameManager.get_faction_color(GameManager.player_faction)
	var all_colors: Array = ["red", "blue", "yellow", "purple", "orange", "green", "cyan", "brown", "black"]
	var ai_colors_used: Array = [GameManager.get_faction_color(GameManager.player_faction)]
	for faction_id in ["wei", "shu", "wu"]:
		if faction_id == GameManager.player_faction:
			continue
		# 给 AI 选一个跟玩家不同的颜色
		for cname in all_colors:
			var cc: Color = GameManager.FACTION_COLORS[cname]
			if not cc in ai_colors_used:
				GameManager.set_faction_color(faction_id, cname)
				ai_colors_used.append(cc)
				break
	
	print("[Main] 势力颜色表: wei=%s shu=%s wu=%s" % [GameManager.get_faction_color("wei"), GameManager.get_faction_color("shu"), GameManager.get_faction_color("wu")])

	# === 地图模式：根据主菜单/编辑器选择，先生成/载入/缩放地形与网格 ===
	# 🗺 进游戏第一件事：关掉编辑器模式。
	# 从地图工坊 F5 过来时它是 true（那边摆的建筑不该自己跑），
	# 漏了这句，整局游戏会变成"所有单位站着不动、建筑不产资源"。
	GameManager.editor_mode = false
	_apply_map_mode()

	GameManager.grid = grid
	GameManager.pathfinder = pathfinder
	GameManager.cell_size = grid.cell_size
	GameManager.map_size = grid.map_size
	_setup_terrain()
	_spawn_water()

	# 地图内容从哪来：
	#   ① 编辑器存的地图 → 按 doc.objects 铺（用户放了什么就是什么）
	#   ② 否则 → 沿用程序生成（随机/预设/参数图，手感一行都不能变）
	# 判据用"有没有建筑"：只画了地形没放基地的图，仍然回退到程序生成，
	# 否则玩家进图会发现自己是光杆司令、连官府都没有。
	if _loaded_doc != null and _loaded_doc.count_by_kind("building") > 0:
		_spawn_ai()
		_spawn_from_doc(_loaded_doc)
	else:
		_spawn_decorations()
		_spawn_initial_forces()
		_spawn_resource_nodes()
		_spawn_villages()
		_spawn_relics()
		_spawn_wild_horses()

	# 地表装饰（草簇/碎石/灌木）必须放在所有实体之后：它要避开已经占用的格子，
	# 也要避开建筑脚下 —— 反过来会让草长在屋子正中。
	# ⚠️ 数量别乱加：2026-10-24 实测草簇是**填充率瓶颈**，2600→4200 直接 51→29.7fps
	# （几乎线性）。想加密度先重跑 _probe_perf。
	var gd: Dictionary = GroundDetail.populate(self, grid, {"tufts": 2600, "rocks": 520, "bushes": 240})
	print("[Main] 地表装饰：草簇 %d / 碎石 %d / 灌木 %d / 道具 %d" % [
		int(gd.get("tufts", 0)), int(gd.get("rocks", 0)),
		int(gd.get("bushes", 0)), int(gd.get("props", 0))])

	# 🔲 边界密林墙（AoE4 式边界）：最外 4 格已由 GridManager 标成不可通行，
	# 这里种一圈密集深色针叶林把它"画"出来。程序生成与编辑器地图都生效。
	BorderForest.populate(self, grid)
	
	# � 修复相机初始位置：从 (20,0,20) 调到地图中心
	var map_center: Vector3 = _player_home_or_center()
	camera_controller.focus_on(map_center)
	
	# � 胜负信号连接 → 弹窗 + 返回主菜单
	EventBus.victory.connect(_on_victory)
	EventBus.defeat.connect(_on_defeat)
	
	print("[Main] 游戏世界初始化完成")

## 开局镜头对准玩家的官府（找不到就退回地图中心）。
## 没有这个的话，进游戏第一眼是一片空地 —— 锁了视角又不能转动找家，体验会更差。
func _player_home_or_center() -> Vector3:
	var best: Node3D = null
	for n in get_children():
		if n.get("building_id") == "government" and str(n.get("faction")) == GameManager.player_faction:
			best = n
			break
	if best == null:
		for n in get_children():
			if n.get("building_id") == "government":
				best = n
				break
	if best != null:
		# 不要在这里加偏移：相机会把焦点 y 吸附到"焦点所在位置"的地形高度，
		# 一旦把焦点挪到基地旁边 3 米，焦点就落到坡上，镜头会对着坡看，
		# 基地被挤到屏幕最下沿（实测就是这样）。
		return best.global_position
	return Vector3(Terrain.params.world_size * 0.5, 0.0, Terrain.params.world_size * 0.5)

func _on_victory(winner: String) -> void:
	_show_game_over_dialog(true, winner)

func _on_defeat(loser: String) -> void:
	"""玩家失败（如果玩家势力被灭）弹窗"""
	if loser == GameManager.player_faction:
		_show_game_over_dialog(false, loser)

func _show_game_over_dialog(player_won: bool, faction_key: String) -> void:
	GameManager.paused = true
	var fc: Color = GameManager.get_faction_color(faction_key)
	var panel := Panel.new()
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	var pmat := StyleBoxFlat.new()
	pmat.bg_color = Color(0, 0, 0, 0.7)  # 半透明黑遮罩
	panel.add_theme_stylebox_override("panel", pmat)
	add_child(panel)
	
	var vbox := VBoxContainer.new()
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 20)
	panel.add_child(vbox)
	
	# 标题
	var title := Label.new()
	title.text = "🏆 胜利！" if player_won else "💀 失败"
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", fc if player_won else Color(1.0, 0.3, 0.3))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	# 副标题
	var sub := Label.new()
	var FACTION_INFO := {"wei": "曹魏", "shu": "蜀汉", "wu": "东吴"}
	var winner_name: String = FACTION_INFO.get(faction_key, faction_key)
	sub.text = "势力 %s %s 三国归一统！" % [winner_name, "扫平群雄" if player_won else "霸业未成…"]
	sub.add_theme_font_size_override("font_size", 28)
	sub.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(sub)
	
	# 按钮栏
	var btn_box := HBoxContainer.new()
	btn_box.add_theme_constant_override("separation", 20)
	btn_box.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_box)
	
	var replay_btn := Button.new()
	replay_btn.text = "再战一局"
	replay_btn.custom_minimum_size = Vector2(180, 56)
	replay_btn.add_theme_font_size_override("font_size", 22)
	replay_btn.pressed.connect(func(): get_tree().reload_current_scene())
	btn_box.add_child(replay_btn)
	
	var menu_btn := Button.new()
	menu_btn.text = "返回主菜单"
	menu_btn.custom_minimum_size = Vector2(180, 56)
	menu_btn.add_theme_font_size_override("font_size", 22)
	menu_btn.pressed.connect(_back_to_main_menu)
	btn_box.add_child(menu_btn)

func _back_to_main_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

func _spawn_ai() -> void:
	for faction_id in GameManager.factions.keys():
		if faction_id != GameManager.player_faction:
			var ai_script: GDScript = load("res://scripts/ai/AIController.gd")
			if ai_script:
				var ai: Node = ai_script.new()
				ai.faction = faction_id
				ai.name = "AI_" + faction_id
				add_child(ai)

# ===================== 地图模式 / 尺寸解析 =====================
# 尺寸档位 -> 网格数（cell_size=2，world_size = n*2 与网格完全重合）
# 帝国时代风格：整体放大，large 为真·大地图
const SIZE_KEY_TO_N: Dictionary = { "small": 84, "medium": 120, "large": 168 }

## 根据 GameManager.map_mode 准备地形 + 网格尺寸。
## 统一规则：地形 world_size 与网格一致（world_size = grid_size * cell_size），
## 从而「地图大小」真正驱动玩法范围与地形规模（此前 maps.json 的 size 从未生效）。
func _apply_map_mode() -> void:
	var n: int
	var ws: float
	match GameManager.map_mode:
		"random":
			var seed: int = GameManager.map_seed if GameManager.map_seed != 0 else randi()
			n = int(SIZE_KEY_TO_N.get(GameManager.map_size_key, 84))
			ws = float(n) * grid.cell_size
			var p = Terrain.default_params()
			p.seed = seed
			p.world_size = ws
			_configure_island(p, ws)
			Terrain.generate(p)
			GameManager.map_seed = seed
		"seed":
			n = int(SIZE_KEY_TO_N.get(GameManager.map_size_key, 84))
			ws = float(n) * grid.cell_size
			var p = Terrain.default_params()
			p.seed = GameManager.map_seed
			p.world_size = ws
			_configure_island(p, ws)
			Terrain.generate(p)
		"saved":
			var sp = MapSave.load_map(GameManager.map_saved_name)
			if sp == null:
				sp = Terrain.default_params()
				Terrain.generate(sp)
			ws = sp.world_size
			n = int(round(ws / grid.cell_size))
		"custom":
			# 地图工坊（MapEditor）保存出来的地图。
			# 磁盘格式的全部知识都在 MapIO 里，这里不再自己解析 height.raw ——
			# 之前那份手写解析和 MapIO 各存一套，改格式时必然会漏掉一处。
			var loaded: Dictionary = MapIO.load_map(GameManager.map_saved_name)
			var cp = Terrain.default_params()
			if not loaded.is_empty():
				_loaded_doc = loaded["doc"]
				_loaded_doc.apply_terrain_to(cp)     # 28 个地形参数全部还原
			ws = cp.world_size
			n = int(round(ws / grid.cell_size))
			var hi: Image = loaded.get("height", null) if not loaded.is_empty() else null
			if hi == null:
				push_warning("[Main] custom 地图缺少 height.raw，退回程序生成")
				_configure_island(cp, ws)
				Terrain.generate(cp)
			else:
				Terrain.apply_images(hi, loaded.get("biome", null), cp,
					loaded.get("splat", null), loaded.get("splat2", null))
				var nobj: int = _loaded_doc.objects.size() if _loaded_doc != null else 0
				var nsp: int = 0
				if Terrain.splat_img != null:
					nsp = int(round(SplatBrush.painted_ratio(Terrain.splat_img) * 100.0))
				print("[Main] ✅ 已载入自定义地图 %s（%d²，%.0f m，%d 个对象，地表手刷 %d%%）" % [
					GameManager.map_saved_name, hi.get_width(), ws, nobj, nsp])
		"live":
			# 由地图编辑器（MapGenerator）直接生成，Terrain.params 已是目标地图，不再重生成
			ws = Terrain.params.world_size if Terrain.params != null else (float(int(SIZE_KEY_TO_N.get(GameManager.map_size_key, 84))) * grid.cell_size)
			n = int(round(ws / grid.cell_size))
		_:  # preset（默认）
			var mid: String = GameManager.selected_map_id
			n = _preset_size(mid)
			ws = float(n) * grid.cell_size
			var p = Terrain.default_params()
			p.seed = _hash_map_id(mid)
			p.world_size = ws
			_configure_island(p, ws)
			Terrain.generate(p)
	# 应用到网格：网格覆盖 [0, ws]，与地形完全重合
	grid.map_size = Vector2i(n, n)
	grid._init_grid()
	print("[Main] 地图模式=%s 尺寸=%dx%d world_size=%.1f" % [GameManager.map_mode, n, n, ws])

## 让岛屿居中并铺满整张网格（边缘即海岸线），保证任意尺寸都是可玩陆地
func _configure_island(p, ws: float) -> void:  # p 
	p.island_center_factor = 0.5
	p.island_radius = ws * 0.95
	p.island_falloff_inner = 0.78
	p.island_falloff_outer = 1.05

## 预设地图尺寸（取自 maps.json）
func _preset_size(mid: String) -> int:
	var maps: Dictionary = DataLoader.maps.get("maps", {})
	if maps.has(mid):
		return int(maps[mid].get("size", 84))
	return 84

## 用预设 id 派生稳定种子，让同一预设每次地形一致
func _hash_map_id(mid: String) -> int:
	var h: int = 0
	for ch in mid:
		h = (h * 31 + int(ch.unicode_at(0))) & 0x7fffffff
	return h

## 把旧 84 参考坐标系下的网格坐标缩放到当前网格尺寸
func _sc(v: float) -> int:
	return int(round(v / 84.0 * float(grid.map_size.x)))

func _setup_terrain() -> void:
	# === 地形：高度场（Heightmap）===
	_terrain = MeshInstance3D.new()
	var plane_mesh: PlaneMesh = PlaneMesh.new()
	plane_mesh.size = Vector2(Terrain.params.world_size, Terrain.params.world_size)
	var _sub: int = clampi(int(Terrain.params.world_size), 64, 400)
	plane_mesh.subdivide_width = _sub
	plane_mesh.subdivide_depth = _sub
	_terrain.mesh = plane_mesh
	_terrain.material_override = _create_terrain_material()
	# ⚠ 不要转 -90°！Godot 4 的 PlaneMesh 默认就在 XZ 平面（AABB 高度为 0），
	# 再转一次会立起来变成一张"墙"，俯视时完全看不见 → 表现成"没有铺地面"。
	# 曾因此让整个地形消失了很久，真正的原因不是材质也不是贴图。
	_terrain.rotation = Vector3.ZERO
	_terrain.position = Vector3(Terrain.params.world_size * 0.5, 0.0, Terrain.params.world_size * 0.5)
	# 顶点位移是在 shader 里做的，引擎不知道地形被抬高了 16 米，
	# 不撑开 AABB 的话镜头一低地形就会被视锥剔除（又是"地面突然没了"）。
	var _cull_h: float = float(Terrain.params.max_height) * 2.0 + 8.0
	_terrain.custom_aabb = AABB(
		Vector3(-Terrain.params.world_size * 0.5, -_cull_h, -Terrain.params.world_size * 0.5),
		Vector3(Terrain.params.world_size, _cull_h * 2.0, Terrain.params.world_size))
	add_child(_terrain)
	
	# === DirectionalLight3D：主阳光 ===
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation = TerrainMaterial.SUN_EULER_DEG * (PI / 180.0)  # 与地形 shader 同一颗太阳
	sun.light_energy = 1.15  # 与 EditorScene 同步：亮材质防爆白
	sun.light_color = Color(1.0, 0.915, 0.76)  # 暖日光（对齐 AoE4 截图的暖金调，2026-10-24 再暖一档）
	sun.shadow_enabled = true
	sun.light_angular_distance = 0.5
	# 4096 阴影图（project.godot 已配）：图大了模糊补偿可以收小，边缘更"硬朗"
	sun.shadow_blur = 1.4
	sun.shadow_normal_bias = 0.4
	sun.shadow_bias = 0.06
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 170.0
	sun.directional_shadow_fade_start = 0.85
	add_child(sun)
	
	# === 天空 + 环境光 + 雾 ===
	var env: WorldEnvironment = WorldEnvironment.new()
	var env_resource: Environment = Environment.new()
	
	# 渐变天空（用 Sky + ProceduralSkyMaterial 更真实）
	env_resource.background_mode = Environment.BG_SKY
	var sky: Sky = Sky.new()
	var sky_mat: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.30, 0.50, 0.78)
	sky_mat.sky_horizon_color = Color(0.66, 0.78, 0.88)
	sky_mat.sky_curve = 0.45
	sky_mat.sky_energy_multiplier = 1.0
	sky_mat.sun_angle_max = 45.0
	sky_mat.sun_curve = 0.3
	sky.sky_material = sky_mat
	env_resource.sky = sky
	env_resource.background_sky = sky
	
	# 环境光（来自天空的漫射）
	# ⚠ 这里原先是 0.78：环境光太强 → 阴影和受光面亮度接近 → 整片地像被洗过一遍的灰绿。
	# AoE4 的观感是"主光很硬、环境光是冷的补光"，靠明暗差出体积。降到 0.40 才有对比。
	env_resource.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env_resource.ambient_light_energy = 0.33
	env_resource.ambient_light_sky_contribution = 0.55

	# 雾效：远处淡色空气透视（大地图拉远）
	# ⚠ 原先是 density 0.0024 + 高度雾 0.006：在 dist=150 的全景下几乎把整张地图糊成一层灰绿，
	# 这是"颜色发闷、看不出草地"的主要元凶之一。这里只留很薄的一层远雾。
	env_resource.fog_enabled = true
	env_resource.fog_light_color = Color(0.635, 0.715, 0.815)   # 偏冷的天光色，不是草绿
	env_resource.fog_density = 0.00085
	env_resource.fog_height = 2.0
	env_resource.fog_height_density = 0.0
	env_resource.fog_aerial_perspective = 0.35
	
	# 色调 + 辉光微调（让像素化 sprite 边缘更清晰）
	env_resource.glow_enabled = false  # 关掉避免 sprite 边缘发光
	# Filmic 会把中间调压平 → 画面发灰；ACES 高光滚降自然且保饱和，更接近 AoE4 的观感
	env_resource.tonemap_mode = Environment.TONE_MAPPER_ACES
	env_resource.tonemap_exposure = 0.82  # 与 EditorScene 同步：亮材质防爆白
	# 一次性把对比/饱和拉到位：地形贴图本身是低对比的（为了不出现平铺花纹），
	# 观感必须靠后期补，否则就是"一块洗褪色的布"。
	env_resource.adjustment_enabled = true
	env_resource.adjustment_contrast = 1.15
	env_resource.adjustment_saturation = 1.12   # AoE4 截图是高饱和暖调（1.06 → 1.12）
	env_resource.adjustment_brightness = 1.0
	env_resource.sdfgi_enabled = false  # RTS 不需要 SDFGI

	# 🎨 SSAO 接触阴影：树脚/墙脚/山脚的"贴在地上"感主要靠它。
	# AoE4 的地面物体都有一圈柔和的接触变暗 —— 没有它模型就像浮在地面上。
	# 用 light 档（半分辨率）。
	# ✅ 2026-10-24 复测（后台已清，nvidia-smi GPU 19%/993MiB 空闲）：
	#    基线(全关) 55.7fps → SSAO+MSAA2x 57.2fps → SSAO+MSAA4x 57.8fps。
	#    三档几乎无差 → 瓶颈在 CPU 侧（4400+ Sprite3D 逻辑），GPU 填充率富余。
	#    结论：SSAO + MSAA 4x 全开保留（msaa_3d=3 在 project.godot）。
	#    若日后加大量粒子/后处理掉帧，优先怀疑 GPU，再回来降 MSAA。
	env_resource.ssao_enabled = true
	env_resource.ssao_radius = 1.2
	env_resource.ssao_intensity = 1.6
	env_resource.ssao_power = 1.6
	env_resource.ssao_detail = 0.6
	env_resource.ssao_light_affect = 0.15    # 主要压暗环境光，几乎不动直接光
	
	env.environment = env_resource
	add_child(env)
	
	# === 轻微的边缘地形色变化（靠 Decal 或后期点光） ===
	# 在三个基地附近加暖色点光，让基地更显眼
	add_base_lights()



func _create_terrain_material() -> ShaderMaterial:
	# 统一走 TerrainMaterial：与地图编辑器 MapEditor 共用同一份 shader + 贴图加载，
	# 顺带修掉「max_height / water_level 读常量而不读 params」的老 Bug。
	var mat: ShaderMaterial = TerrainMaterial.build()
	# 战争迷雾：把雾罩贴图挂到地形 shader（FogOfWar 每 0.35s 更新）
	if FogOfWar != null:
		FogOfWar.register_terrain_material(mat)
	return mat

func _load_terrain_tex(name: String, fallback: Color) -> Texture2D:
	# 兼容旧调用点：真正的加载逻辑已移到 TerrainMaterial.load_terrain_tex()，
	# 那里会真的读 res://assets/terrain/<name>.png（含缓存与缺失告警）。
	return TerrainMaterial.load_terrain_tex(name, fallback)

func _make_solid_tex(c: Color) -> ImageTexture:
	var img: Image = Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return ImageTexture.create_from_image(img)

func add_base_lights() -> void:
	"""三个基地各加一个暖色点光源，增强基地区域的存在感"""
	var ws: float = Terrain.params.world_size
	var base_positions: Dictionary = {
		"shu": Vector3(0.12, 2.5, 0.12),    # 玩家蜀 左下
		"wei": Vector3(0.83, 2.5, 0.83),  # 魏 右上
		"wu": Vector3(0.71, 2.5, 0.24)    # 吴 中上
	}
	for faction_id in base_positions.keys():
		var fpos: Vector3 = base_positions[faction_id]
		var bp: Vector3 = Vector3(fpos.x * ws, fpos.y, fpos.z * ws)
		var base_light: OmniLight3D = OmniLight3D.new()
		var fc: Color = GameManager.get_faction_color(faction_id)
		# 势力色光，但偏暖一点
		base_light.light_color = Color(fc.r * 0.8 + 0.2, fc.g * 0.8 + 0.15, fc.b * 0.6 + 0.1)
		base_light.light_energy = 1.2
		base_light.omni_range = 12.0
		base_light.omni_attenuation = 1.5
		base_light.shadow_enabled = false  # 点光不产生阴影（省性能）
		add_child(base_light)              # 先入树，再设置位置，避免 !is_inside_tree 报错
		base_light.position = bp

## 按地图文档铺装全部对象。这是"编辑器地图"和"程序生成地图"的共用出口。
## 失败不中断：某一条放不下（比如地形改过导致建筑压水）就跳过并计数，
## 全部中断会让玩家进图看到半张空地图，更难排查。
func _spawn_from_doc(doc) -> void:
	var ok: int = 0
	var fail: int = 0
	for obj in doc.objects:
		if typeof(obj) != TYPE_DICTIONARY:
			continue
		var node: Node = ObjectSpawner.spawn(self, grid, obj)
		if node == null:
			fail += 1
			print("[Main] ⚠ 对象放不下：%s %s @ %s" % [
				str(obj.get("kind", "")), str(obj.get("id", "")), str(obj.get("grid", []))])
		else:
			ok += 1
	print("[Main] 按地图对象铺装：成功 %d，失败 %d" % [ok, fail])

func _spawn_initial_forces() -> void:
	_spawn_ai()
	var N: int = grid.map_size.x
	# 初始基地按比例分布在网格四角（随地图尺寸缩放）
	_spawn_base("shu", Vector2i(int(round(0.12 * N)), int(round(0.12 * N))))  # 玩家蜀 左下
	_spawn_base("wei", Vector2i(int(round(0.83 * N)), int(round(0.83 * N))))  # 魏 右上
	_spawn_base("wu",  Vector2i(int(round(0.71 * N)), int(round(0.24 * N))))  # 吴 中上

func _spawn_base(faction_id: String, pos: Vector2i) -> void:
	var is_player: bool = faction_id == GameManager.player_faction
	# 官府实际尺寸为 3×3（见 buildings.json），用真实尺寸搜索可放置陆地
	var gov_def: Dictionary = DataLoader.get_building_def("government")
	var gov_size: Vector2i = Vector2i(gov_def.get("size", [3,3])[0], gov_def.get("size", [3,3])[1])
	var place_pos: Vector2i = _find_placeable(pos, gov_size)
	if place_pos == Vector2i(-1, -1):
		print("[Main] ❌ %s 找不到可放置基地（地图过小或全水）" % faction_id)
		return
	# 🎯 设计 v3：初始建筑全档位全势力一样 = 官府 + 牌楼（招募农夫用）
	_spawn_building("government", faction_id, place_pos)
	# 牌楼(2×2)放在官府右侧；若该偏移落水/越界，就近螺旋找一个可放置点
	var pai_def: Dictionary = DataLoader.get_building_def("paifang")
	var pai_size: Vector2i = Vector2i(pai_def.get("size", [2,2])[0], pai_def.get("size", [2,2])[1])
	var pai_pos: Vector2i = _find_placeable(place_pos + Vector2i(gov_size.x, 0), pai_size)
	if pai_pos != Vector2i(-1, -1):
		_spawn_building("paifang", faction_id, pai_pos)
	
	# 🎯 玩家和 AI 默认农夫都是 5（hardcode，不再让玩家选）
	var n_peasants: int = GameManager.initial_peasants if GameManager.initial_peasants > 0 else 5
	for i in range(n_peasants):
		_spawn_unit("peasant", faction_id, grid.grid_to_world(place_pos + Vector2i(0, 1 + i)))
	
	# 🎯 初始士兵组合（按 AI 难度/玩家选择）
	var soldiers_cfg: Dictionary = GameManager.initial_soldiers
	if soldiers_cfg.is_empty():
		# 兜底：基础 2 刀兵 + 2 枪兵 + 2 弓兵
		soldiers_cfg = {"sword":2, "spear":2, "archer":2}
	var ox: int = 2  # 偏移
	var oz: int = 2
	for uid in soldiers_cfg.keys():
		var cnt: int = int(soldiers_cfg[uid])
		for i in range(cnt):
			var spawn_pos = grid.grid_to_world(place_pos + Vector2i(ox, oz))
			_spawn_unit(uid, faction_id, spawn_pos)
			oz += 1
			if oz - 2 > n_peasants + 4: oz = 2; ox += 1
	
	# 🎯 初始文臣（玩家/AI 各带 1 个默认文臣，数量可叠加）
	var n_civils: int = GameManager.initial_civils if GameManager.initial_civils > 0 else 1
	for i in range(n_civils):
		_spawn_general(faction_id, grid.grid_to_world(place_pos + Vector2i(1, 4 + i)))

## 从 preferred 点向外螺旋搜索最近的「可放置」网格（避开水面/已占用）
func _find_placeable(pref: Vector2i, size: Vector2i) -> Vector2i:
	if grid.is_placeable(pref, size):
		return pref
	var R: int = maxi(grid.map_size.x, grid.map_size.y)
	for r in range(1, R):
		# 只扫描半径为 r 的环（避免重复内圈）
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if absi(dx) != r and absi(dz) != r:
					continue
				var p: Vector2i = pref + Vector2i(dx, dz)
				if p.x < 0 or p.y < 0 or p.x + size.x > grid.map_size.x or p.y + size.y > grid.map_size.y:
					continue
				if grid.is_placeable(p, size):
					return p
	return Vector2i(-1, -1)

func _spawn_building(building_id: String, faction_id: String, grid_pos: Vector2i):
	var bdef: Dictionary = DataLoader.get_building_def(building_id)
	var size: Vector2i = Vector2i(bdef.get("size", [2,2])[0], bdef.get("size", [2,2])[1])
	if not grid.is_placeable(grid_pos, size):
		print("[Main] ⚠ 不能放置 %s at %s" % [building_id, grid_pos])
		return null
	var occ_val: int = 1
	if building_id.begins_with("wall_") or building_id == "gate":
		occ_val = 2
	grid.set_occupied(grid_pos, size, occ_val)
	if GameManager.pathfinder:
		GameManager.pathfinder.clear_cache()  # 🔥 新建筑阻挡了旧路径
	var scene: PackedScene = load("res://scenes/Building.tscn")
	if not scene:
		print("[Main] ❌ Building.tscn load 失败")
		return null
	var b = scene.instantiate()
	b.building_id = building_id
	b.faction = faction_id
	b.grid_pos = grid_pos
	# 先 add_child 再 set global_position（确保节点在场景树里）
	add_child(b)
	var wp: Vector3 = grid.grid_to_world(grid_pos)
	b.global_position = wp
	print("[Main] ✅ 建筑 %s spawn at %s (in_tree=%s)" % [building_id, wp, b.is_inside_tree()])
	return b

func _spawn_unit(unit_id: String, faction_id: String, pos: Vector3) -> void:
	var scene: PackedScene = load("res://scenes/Unit.tscn")
	if not scene:
		print("[Main] ❌ Unit.tscn load 失败")
		return
	var u = scene.instantiate()
	u.unit_id = unit_id
	u.faction = faction_id
	add_child(u)
	u.global_position = pos
	print("[Main] ✅ 单位 %s spawn at %s (in_tree=%s)" % [unit_id, pos, u.is_inside_tree()])
	GameManager.change_population(faction_id, DataLoader.get_unit_def(unit_id).get("pop_cost", 1))

func _spawn_general(faction_id: String, pos: Vector3) -> void:
	var general_ids: Dictionary = { "wei": "cao_cao", "shu": "liubei", "wu": "sunquan" }
	if not general_ids.has(faction_id):
		return
	# V2: Unit.tscn 实例化 + set_script(General.gd) 动态附加
	# General.gd 用 extends "res://scripts/entities/Unit.gd" 路径继承，绕过 class_name 注册时序
	var unit_scene: PackedScene = load("res://scenes/Unit.tscn")
	if not unit_scene:
		return
	var g = unit_scene.instantiate()
	var gen_script: GDScript = load("res://scripts/entities/General.gd")
	if gen_script:
		g.set_script(gen_script)
	g.general_id = general_ids[faction_id]
	g.faction = faction_id
	g.unit_id = "general_" + general_ids[faction_id]
	add_child(g)
	g.global_position = pos
	print("[Main] ✅ 武将 %s spawn at %s" % [general_ids[faction_id], pos])

func _spawn_water() -> void:
	"""整图水面：共用组件（编辑器同款，所见即所得）"""
	WaterPlane.build(self, Terrain.heightmap_tex,
		float(Terrain.params.world_size), float(Terrain.params.max_height),
		float(Terrain.params.water_level))

func _spawn_decorations() -> void:
	"""生成树木、佛像、岩石、灯笼等装饰（坐标按当前网格尺寸缩放）"""
	var deco_script: GDScript = load("res://scripts/world/Decoration.gd")
	if not deco_script:
		return
	var N: int = grid.map_size.x
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	# 🔲 边界禁区（GridManager.BORDER_CELLS）内不散布普通树/岩石——那一圈留给密林墙
	var b0: int = GridManager.BORDER_CELLS + 1
	# 散布树木（约80棵）——GLB 真 3D 树（贴片已下线 2026-10-29）
	var species: PackedStringArray = TreeGLTF.species_list()
	for i in range(80):
		var gx: int = rng.randi_range(b0, N - 2 - b0)
		var gz: int = rng.randi_range(b0, N - 2 - b0)
		# 避开水域（is_placeable 已排除 water=3 格）
		if not grid.is_placeable(Vector2i(gx, gz), Vector2i(1, 1)):
			continue
		var sp: String = species[rng.randi_range(0, species.size() - 1)] if not species.is_empty() else "oak"
		TreeGLTF.spawn(self, sp, grid.grid_to_world(Vector2i(gx, gz)), rng)
	# 佛像（3座）
	var buddha_positions: Array = [Vector2i(_sc(30), _sc(30)), Vector2i(_sc(60), _sc(60)), Vector2i(_sc(20), _sc(70))]
	for bp in buddha_positions:
		if grid.is_placeable(bp, Vector2i(2, 2)):
			var b = deco_script.new()
			b.deco_type = 0  # BUDDHA
			add_child(b)
			b.global_position = grid.grid_to_world(bp)
	# 岩石散布
	for i in range(30):
		var rx: int = rng.randi_range(b0, N - 2 - b0)
		var rz: int = rng.randi_range(b0, N - 2 - b0)
		if not grid.is_placeable(Vector2i(rx, rz), Vector2i(1, 1)):
			continue
		var rock = deco_script.new()
		rock.deco_type = 1  # ROCK
		add_child(rock)
		rock.global_position = grid.grid_to_world(Vector2i(rx, rz))
	# 灯笼（村庄附近）
	var lantern_positions: Array = [Vector2i(_sc(39), _sc(11)), Vector2i(_sc(41), _sc(11)), Vector2i(_sc(9), _sc(39)), Vector2i(_sc(11), _sc(39))]
	for lp in lantern_positions:
		var lantern = deco_script.new()
		lantern.deco_type = 2  # LANTERN
		add_child(lantern)
		lantern.global_position = grid.grid_to_world(lp)

func _spawn_resource_nodes() -> void:
	# 散布资源点（避开边界禁区：那圈不可通行，资源放进去玩家也采不到）
	var N: int = grid.map_size.x
	var b0: int = GridManager.BORDER_CELLS + 1
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for i in range(30):
		var pos: Vector2i = Vector2i(rng.randi_range(b0, N - 2 - b0), rng.randi_range(b0, N - 2 - b0))
		if not grid.is_placeable(pos, Vector2i(1,1)):
			continue
		var res_type: String = "wood" if i % 3 != 1 else "iron"
		if i % 5 == 0:
			res_type = "food"
		_spawn_resource_node(res_type, pos)
	# 🔥 v4 额外生成 6 个矿洞（集中在地图边缘/角落，按尺寸缩放）
	var mine_positions: Array = [
		Vector2i(_sc(5), _sc(75)), Vector2i(_sc(75), _sc(5)), Vector2i(_sc(75), _sc(75)),
		Vector2i(_sc(5), _sc(50)), Vector2i(_sc(50), _sc(5)), Vector2i(_sc(50), _sc(75))
	]
	for mp in mine_positions:
		if grid.is_placeable(mp, Vector2i(2, 2)):
			_spawn_mine_node(mp)

func _spawn_resource_node(res_type: String, grid_pos: Vector2i) -> void:
	var scene: PackedScene = load("res://scenes/ResourceNode.tscn")
	if scene:
		var node = scene.instantiate()
		node.resource_type = res_type
		node.amount = 800.0 + float(randi_range(0, 400))
		node.max_amount = node.amount
		node.init_with_grid_pos(grid_pos)  # 🔥 v4 记住网格坐标
		add_child(node)
		node.global_position = grid.grid_to_world(grid_pos)

# 🔥 v4 生成矿洞（中立归属）
func _spawn_mine_node(grid_pos: Vector2i) -> void:
	var scene: PackedScene = load("res://scenes/ResourceNode.tscn")
	if scene:
		var node = scene.instantiate()
		node.resource_type = "iron"
		node.amount = 99999.0  # 无限
		node.max_amount = 99999.0
		node.is_mine = true
		node.mine_cap = 8
		node.mine_owner = ""  # 中立
		node.init_with_grid_pos(grid_pos)
		add_child(node)
		node.global_position = grid.grid_to_world(grid_pos)
		print("[Main] ⛏️ 矿洞 spawn at %s (中立)" % grid_pos)


func _spawn_villages() -> void:
	# 散布中立村庄（6个，按尺寸缩放）
	var rng := RandomNumberGenerator.new()
	rng.seed = 99999
	var positions: Array = [
		Vector2i(_sc(40), _sc(10)), Vector2i(_sc(10), _sc(40)), Vector2i(_sc(70), _sc(40)),
		Vector2i(_sc(40), _sc(70)), Vector2i(_sc(25), _sc(25)), Vector2i(_sc(55), _sc(55))
	]
	for i in range(positions.size()):
		var pos: Vector2i = positions[i]
		if not grid.is_placeable(pos, Vector2i(2, 2)):
			pos = Vector2i(rng.randi_range(5, grid.map_size.x - 5), rng.randi_range(5, grid.map_size.x - 5))
		_spawn_village("village_%d" % i, pos)

func _spawn_village(vid: String, grid_pos: Vector2i) -> void:
	var scene: PackedScene = load("res://scenes/Village.tscn")
	if scene:
		var v = scene.instantiate()
		v.village_id = vid
		add_child(v)
		v.global_position = grid.grid_to_world(grid_pos)

func _spawn_relics() -> void:
	# 🪨 古碑任务：near 档撒在自家官府附近（轻松），mid 档撒在地图中部（较难）
	var conf: Dictionary = DataLoader.relics.get("spawn", {})
	var defs: Dictionary = DataLoader.relics.get("relics", {})
	if defs.is_empty():
		return
	var near_ids: Array = []
	var mid_ids: Array = []
	for id in defs.keys():
		if str(defs[id].get("tier", "near")) == "mid":
			mid_ids.append(id)
		else:
			near_ids.append(id)
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var home: Vector3 = _player_home_or_center()
	var center: Vector3 = Vector3(Terrain.params.world_size * 0.5, 0.0, Terrain.params.world_size * 0.5)
	var placed: Array = []
	var total: int = 0
	total += _spawn_relic_tier(near_ids, int(conf.get("near_count", 2)),
		home, float(conf.get("near_min", 10.0)), float(conf.get("near_max", 25.0)), placed, rng)
	total += _spawn_relic_tier(mid_ids, int(conf.get("mid_count", 1)),
		center, 0.0, float(conf.get("mid_radius", 22.0)), placed, rng)
	print("[Main] 古碑生成 %d（近城 %d / 中部 %d）" % [total, near_ids.size(), mid_ids.size()])

## 在 center 的环形范围内随机落一块古碑（near_ids 数量不足时循环取）
func _spawn_relic_tier(ids: Array, count: int, center: Vector3, min_d: float, max_d: float,
		placed: Array, rng: RandomNumberGenerator) -> int:
	if ids.is_empty() or count <= 0:
		return 0
	var conf: Dictionary = DataLoader.relics.get("spawn", {})
	var min_gap: float = float(conf.get("min_dist_between", 14.0))
	var made: int = 0
	var tries: int = 0
	while made < count and tries < 800:
		tries += 1
		var gp: Vector2i = Vector2i(rng.randi_range(4, grid.map_size.x - 4), rng.randi_range(4, grid.map_size.y - 4))
		var wp: Vector3 = grid.grid_to_world(gp)
		var d: float = Vector2(wp.x - center.x, wp.z - center.z).length()
		if d < min_d or d > max_d:
			continue
		if Terrain.is_water(wp.x, wp.z) or not grid.is_placeable(gp, Vector2i(1, 1)):
			continue
		var ok: bool = true
		for p in placed:
			if wp.distance_to(p) < min_gap:
				ok = false
				break
		if not ok:
			continue
		placed.append(wp)
		var r = _spawn_relic(str(ids[made % ids.size()]), gp)
		if r != null:
			_spawn_relic_fragments(r)
			made += 1
	return made

func _spawn_relic(relic_id: String, grid_pos: Vector2i):
	var scene: PackedScene = load("res://scenes/AncientStele.tscn")
	if scene == null:
		return null
	var r = scene.instantiate()
	r.relic_id = relic_id
	add_child(r)
	r.global_position = grid.grid_to_world(grid_pos)
	return r

## gather 修复模式的古碑：在碑周围散布残片，需先集齐才能修
func _spawn_relic_fragments(stele) -> void:
	var n: int = int(stele.fragments_needed)
	if n <= 0:
		return
	var scene: PackedScene = load("res://scenes/RelicFragment.tscn")
	if scene == null:
		return
	var conf: Dictionary = DataLoader.relics.get("spawn", {})
	var radius: float = float(conf.get("fragment_radius", 26.0))
	var gap: float = float(conf.get("fragment_min_gap", 8.0))
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var pts: Array = []
	var tries: int = 0
	while pts.size() < n and tries < 400:
		tries += 1
		var ang: float = rng.randf_range(0.0, TAU)
		var dist: float = rng.randf_range(radius * 0.35, radius)
		var p: Vector3 = stele.global_position + Vector3(cos(ang), 0.0, sin(ang)) * dist
		if Terrain.is_water(p.x, p.z):
			continue
		p.y = Terrain.get_height(p.x, p.z)
		var ok: bool = true
		for q in pts:
			if p.distance_to(q) < gap:
				ok = false
				break
		if not ok:
			continue
		pts.append(p)
		var f = scene.instantiate()
		f.relic_id = stele.relic_id
		f.stele = stele
		add_child(f)
		f.global_position = p

func _spawn_wild_horses() -> void:
	# 散布野马（8匹，含名马）
	var horse_types: Array = ["white", "white", "white", "red", "red", "chitu", "dilu", "white"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 77777
	for i in range(horse_types.size()):
		var pos: Vector2i = Vector2i(rng.randi_range(5, grid.map_size.x - 5), rng.randi_range(5, grid.map_size.x - 5))
		# 避开水面
		if not grid.is_placeable(pos, Vector2i(1, 1)):
			continue
		_spawn_horse("horse_%d" % i, horse_types[i], pos)

func _spawn_horse(hid: String, htype: String, grid_pos: Vector2i) -> void:
	var scene: PackedScene = load("res://scenes/WildHorse.tscn")
	if scene:
		var h = scene.instantiate()
		h.horse_id = hid
		h.horse_type = htype
		add_child(h)
		h.global_position = grid.grid_to_world(grid_pos)

func _process(_delta: float) -> void:
	if _build_mode != "":
		_update_build_ghost()

func _unhandled_input(event: InputEvent) -> void:
	# 右键下达指令 (Shift+右键 = 加入指令队列)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if _build_mode != "":
			_cancel_build_mode()
			return
		var queue: bool = event.shift_pressed
		var world_pos: Vector3 = _screen_to_world(event.position)
		if world_pos != Vector3.INF:
			var target: Node = _get_entity_at(world_pos)
			# 农夫右键资源节点 -> 采集（duck-type: 有 gather 方法）
			if target and target.has_method("gather") and not target.has_method("get_faction"):
				for u in selection.get_selected_units():
					if u.unit_id == "peasant":
						u.command_gather(target, queue)
				EventBus.float_text.emit("采集" + (" (排队)" if queue else ""), world_pos + Vector3(0, 2, 0), Color.YELLOW)
			# 🪨 右键古碑 + 农夫/工兵 -> 修复任务
			elif target and target.has_method("get_relic_name") and target.has_method("is_damaged") and target.is_damaged():
				for u in selection.get_selected_units():
					if "unit_id" in u and (u.unit_id == "peasant" or u.unit_id == "engineer"):
						u.command_repair(target)
				EventBus.float_text.emit("修复古碑", world_pos + Vector3(0, 2, 0), Color.CYAN)
			# 🚢 右键友方船只 + 陆军 -> 登船
			elif target and target.has_method("receive_passenger") and target.has_method("get_faction") and target.get_faction() == GameManager.player_faction:
				for u in selection.get_selected_units():
					if u.has_method("command_board_ship"):
						u.command_board_ship(target)
				EventBus.float_text.emit("登船", world_pos + Vector3(0, 2, 0), Color.CYAN)
			# 右键受损友方建筑 + 农夫 -> 修理
			elif target and target.has_method("get_faction") and target.has_method("register_builder") and target.get_faction() == GameManager.player_faction and target.is_damaged():
				for u in selection.get_selected_units():
					if u.unit_id == 'peasant':
						u.command_repair(target)
				EventBus.float_text.emit('修理', world_pos + Vector3(0, 2, 0), Color.YELLOW)
			# 右键经济建筑 + 农夫 -> 入岗工作
			elif target and target.has_method("get_faction") and target.has_method("assign_worker") and target.get_faction() == GameManager.player_faction and target.can_accept_workers():
				for u in selection.get_selected_units():
					if u.unit_id == "peasant":
						u.command_work(target)
				EventBus.float_text.emit("入岗工作", world_pos + Vector3(0, 2, 0), Color.CYAN)
			# 右键可驻军友方建筑 -> 入驻
			elif target and target.has_method("get_faction") and target.has_method("garrison") and target.get_faction() == GameManager.player_faction and target.can_garrison:
				for u in selection.get_selected_units():
					u.command_garrison(target)
			# 右键村庄/野马 -> 移动占领/捕获（duck-type: 有 capture 或 tamed 属性）
			elif target and (target.has_method("capture") or target.has("tamed")):
				selection.issue_command(target.global_position, null, queue)
			# 🛡 右键己方护送目标 -> 最近的部队成为护送队，目标跟随部队移动
			elif target and target.get("is_escort") == true and target.has_method("get_faction") and target.get_faction() == GameManager.player_faction:
				var leader = null
				var ldist: float = INF
				for u in selection.get_selected_units():
					if u == target:
						continue
					var dd: float = u.global_position.distance_to(target.global_position)
					if dd < ldist:
						ldist = dd
						leader = u
				if leader != null and target.has_method("command_escort_follow"):
					target.command_escort_follow(leader)
				else:
					selection.issue_command(world_pos, null, queue)
			# 右键敌方单位 -> 攻击
			elif target and target.has_method("get_faction") and target.get_faction() != GameManager.player_faction:
				selection.issue_command(world_pos, target, queue)
			else:
				selection.issue_command(world_pos, null, queue)
		get_viewport().set_input_as_handled()
	
	# 建造模式下左键放置
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and _build_mode != "":
		var world_pos2: Vector3 = _screen_to_world(event.position)
		if world_pos2 != Vector3.INF:
			_place_building(_build_mode, world_pos2)
		get_viewport().set_input_as_handled()
	
	# ESC 取消
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if _build_mode != "":
			_cancel_build_mode()

	# 🏦 存档快捷键：F5 快速存档 / F9 快速读档 / F1-F4 槽1-4
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F5:
			_do_quick_save()
		elif event.keycode == KEY_F9:
			_do_quick_load()
		elif event.keycode == KEY_F1:
			_do_save_load(1)
		elif event.keycode == KEY_F2:
			_do_save_load(2)
		elif event.keycode == KEY_F3:
			_do_save_load(3)
		elif event.keycode == KEY_F4:
			_do_save_load(4)

	# 编队快捷键: Ctrl+1~9 保存, Shift+1~9 追加, 1~9 选择, 双击数字居中视角
	if event is InputEventKey and event.pressed and not event.echo and not event.alt_pressed:
		var key: int = event.keycode
		var group_idx: int = -1
		if key >= KEY_1 and key <= KEY_9:
			group_idx = key - KEY_1
		elif key == KEY_0:
			group_idx = 9
		if group_idx >= 0:
			var ctrl: bool = event.ctrl_pressed
			if ctrl:
				selection.save_group(group_idx)
			elif event.shift_pressed:
				selection.save_group(group_idx, true)
			else:
				# 双击检测
				var now: float = Time.get_ticks_msec() / 1000.0
				var double_tap: bool = (group_idx == selection._last_group_key and (now - selection._last_group_time) < 0.4)
				selection._last_group_key = group_idx
				selection._last_group_time = now
				selection.select_group(group_idx, double_tap)
			get_viewport().set_input_as_handled()

	# S键停止 (清空指令队列)
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_S:
		for u in selection.get_selected_units():
			u.command_queue.clear()
			u.state = u.State.IDLE
			u.attack_target = null
			u.gather_target = null
			u.repair_target = null
		EventBus.float_text.emit("停止", Vector3.ZERO, Color.WHITE)

	# Ctrl+Q/Z/X 武将技能
	if event is InputEventKey and event.pressed and not event.echo and event.ctrl_pressed:
		var generals: Array = []
		for u in selection.get_selected_units():
			if u.has_method("duel_challenge"):  # duck-type General
				generals.append(u)
		if not generals.is_empty():
			if event.keycode == KEY_Q:
				for g in generals:
					g.cast_basic_skill(g.basic_skills[0], g.global_position)
			elif event.keycode == KEY_Z:
				for g in generals:
					g.cast_active_skill(g.global_position)
			elif event.keycode == KEY_X:
				for g in generals:
					g.cast_ultimate(g.global_position)

	# 阵型快捷键: Alt+1 方阵 / Alt+2 圆阵 / Alt+3 雁行 / Alt+0 取消
	# （原来用 Shift+数字，但会被上面的编队选择吞掉，且 Shift+数字现在是"追加编队"）
	if event is InputEventKey and event.pressed and not event.echo and event.alt_pressed:
		var fid: String = ""
		var fname: String = ""
		match event.keycode:
			KEY_1: fid = "square"; fname = "方阵"
			KEY_2: fid = "circle"; fname = "圆阵"
			KEY_3: fid = "echelon"; fname = "雁行"
			KEY_4: fid = "wedge"; fname = "锋矢（骑兵突击）"
			KEY_5: fid = "line"; fname = "横阵"
			KEY_0: fid = ""; fname = "取消阵型"
		if fname != "":
			for u in selection.get_selected_units():
				u.set_formation(fid)
			EventBus.float_text.emit("阵型: %s" % fname, Vector3.ZERO, Color.CYAN)

func start_build_mode(building_id: String) -> void:
	# ⛔ 中立资源建筑（矿洞等）只能由地图生成，玩家不能造——双保险（菜单已过滤）
	var bdef: Dictionary = DataLoader.get_building_def(building_id)
	if bool(bdef.get("is_neutral", false)) or str(bdef.get("category", "")) == "natural":
		EventBus.float_text.emit("这是地图自带的中立资源，无法建造", Vector3.ZERO, Color.ORANGE)
		return
	# ⛔ 官府 / 牌楼：开局自带、不可建造
	if bool(bdef.get("buildable", true)) == false:
		EventBus.float_text.emit("%s 为城池自带建筑，不能自行建造" % str(bdef.get("name", building_id)), Vector3.ZERO, Color.ORANGE)
		return
	_build_mode = building_id
	var size: Vector2i = Vector2i(bdef.get("size", [2,2])[0], bdef.get("size", [2,2])[1])
	
	# 👻 先放一个占位 BoxMesh（地面投影，防止没贴图时完全看不见）
	_build_ghost = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(float(size.x) * 2.0, 0.3, float(size.y) * 2.0)
	_build_ghost.mesh = box
	var box_mat: StandardMaterial3D = StandardMaterial3D.new()
	box_mat.albedo_color = Color(0.2, 0.8, 0.2, 0.3)
	box_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_build_ghost.material_override = box_mat
	_build_ghost.position.y = 0.15
	add_child(_build_ghost)
	
	# 🖼️ 再叠加建筑的半透明 sprite（有贴图时更直观）
	var tex: Texture2D = DataLoader.get_sprite_texture("buildings", building_id)
	if tex:
		var ghost_sprite := Sprite3D.new()
		ghost_sprite.texture = tex
		ghost_sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		# 和真建筑一样正对相机（相机偏航锁 45°）
		ghost_sprite.rotation.y = deg_to_rad(CameraController.DEFAULT_YAW_DEG)
		ghost_sprite.shaded = false
		ghost_sprite.modulate = Color(0.3, 1.0, 0.3, 0.5)  # 绿色半透明剪影
		# ⚠ scale 必须取 asset_map 里的（和 Building 同一个来源）。
		# 原来取的是 buildings.json 的 gameplay 字段，那里压根没有 scale，
		# 于是预览虚影永远按 1.5 画，比真正建出来的建筑小一大圈。
		var adef: Dictionary = DataLoader.get_asset_def("buildings", building_id)
		var s: float = float(adef.get("scale", 1.5)) if not adef.is_empty() else 1.5
		ghost_sprite.scale = Vector3(s, s, s)
		# 与 Building._create_full_appearance 用同一个贴地公式，
		# 但 ghost 节点整体被抬高了 0.15（底板 box 高 0.3 的一半），要扣回，
		# 否则预览影子会比真实建出来的高出一截。
		ghost_sprite.position.y = DataLoader.get_sprite_anchor_y("buildings", building_id, s) - _build_ghost.position.y
		ghost_sprite.name = "GhostSprite"
		_build_ghost.add_child(ghost_sprite)
		print("[Main] 🏗️ 建筑 ghost 预览: %s (有贴图)" % building_id)
	else:
		print("[Main] 🏗️ 建筑 ghost 预览: %s (BoxMesh 占位)" % building_id)

func _update_build_ghost() -> void:
	if _build_ghost == null:
		return
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var world_pos: Vector3 = _screen_to_world(mouse_pos)
	if world_pos != Vector3.INF:
		var grid_pos: Vector2i = grid.world_to_grid(world_pos)
		var bdef: Dictionary = DataLoader.get_building_def(_build_mode)
		var size: Vector2i = Vector2i(bdef.get("size", [2,2])[0], bdef.get("size", [2,2])[1])
		var placeable: bool = grid.is_placeable(grid_pos, size) and GameManager.can_afford(GameManager.player_faction, bdef.get("cost", {}))
		_build_ghost.global_position = grid.grid_to_world(grid_pos)
		var ok: Color = Color(0.2, 0.8, 0.2, 0.3)
		var bad: Color = Color(0.8, 0.2, 0.2, 0.35)
		# 更新 BoxMesh 地面投影颜色
		var bmat: StandardMaterial3D = _build_ghost.material_override as StandardMaterial3D
		bmat.albedo_color = ok if placeable else bad
		# 更新 Sprite3D 剪影颜色
		var gsprite: Sprite3D = _build_ghost.get_node_or_null("GhostSprite")
		if gsprite:
			gsprite.modulate = Color(0.3, 1.0, 0.3, 0.5) if placeable else Color(1.0, 0.3, 0.3, 0.5)

func _place_building(building_id: String, world_pos: Vector3) -> void:
	var grid_pos: Vector2i = grid.world_to_grid(world_pos)
	var bdef: Dictionary = DataLoader.get_building_def(building_id)
	var size: Vector2i = Vector2i(bdef.get("size", [2,2])[0], bdef.get("size", [2,2])[1])
	if not grid.is_placeable(grid_pos, size):
		# 只在失败时说明原因，成功不刷屏（之前每放一栋打 5 行，调试日志全被淹没）
		var why: String = "超出地图" if not grid.is_in_bounds(grid_pos) else "已被占用"
		print("[BUILD] ❌ 无法放置 %s @%s size=%s：%s" % [building_id, grid_pos, size, why])
		EventBus.float_text.emit("无法放置", world_pos + Vector3(0, 2, 0), Color.RED)
		return
	if not GameManager.spend_resources(GameManager.player_faction, bdef.get("cost", {})):
		EventBus.float_text.emit("资源不足", world_pos + Vector3(0, 2, 0), Color.RED)
		return
	var b = _spawn_building(building_id, GameManager.player_faction, grid_pos)
	if b == null:
		return
	EventBus.float_text.emit("建造中: %s" % bdef.get("name", building_id), world_pos + Vector3(0, 2, 0), Color.GREEN)
	# 🏗️ 自动派最近的 2-3 个农夫去建造
	_dispatch_building(b)
	_cancel_build_mode()

func _dispatch_building(b) -> void:
	"""找最近的空闲农夫派去建造"""
	var available: Array = []
	for u in GameManager.all_units:
		if not is_instance_valid(u):
			continue
		if u.get_faction() != GameManager.player_faction:
			continue
		if u.unit_id != "peasant":
			continue
		if u.state != 0 and u.state != 8:  # 0=0, WORKING=8
			continue
		available.append(u)
	if available.is_empty():
		return
	# 按距离排序
	available.sort_custom(func(a, b2): return a.global_position.distance_to(b.global_position) < b2.global_position.distance_to(b.global_position))
	var to_send: int = min(b.get_builder_slots_available(), 3, available.size())
	for i in range(to_send):
		# 🔥 call_deferred 让寻路跨帧，避免同步阻塞主线程
		available[i].call_deferred("command_build", b)
		EventBus.float_text.emit("前往建造", available[i].global_position + Vector3(0, 2.5, 0), Color.CYAN)

func _cancel_build_mode() -> void:
	_build_mode = ""
	if _build_ghost:
		_build_ghost.queue_free()
		_build_ghost = null

# ==================== 🏦 存档快捷键实现 ====================

func _do_quick_save() -> void:
	if get_node_or_null("/root/MapSaveManager") == null:
		return
	var ok: bool = get_node("/root/MapSaveManager").save_game(0)
	EventBus.float_text.emit("💾 快速存档" + (" ✅" if ok else " ❌"), global_position + Vector3(0, 6, 0), Color.GREEN if ok else Color.RED)

func _do_quick_load() -> void:
	if get_node_or_null("/root/MapSaveManager") == null:
		return
	var mgr = get_node("/root/MapSaveManager")
	var saves: Array = mgr.list_saves()
	if saves.is_empty():
		EventBus.float_text.emit("💾 没有存档", global_position + Vector3(0, 6, 0), Color.RED)
		return
	# 加载最新存档
	saves.sort_custom(func(a, b2): return str(a.get("timestamp", "")) > str(b2.get("timestamp", "")))
	var slot: int = int(saves[0].get("slot", 0))
	var ok: bool = mgr.load_game(slot)
	EventBus.float_text.emit("📂 读档" + (" ✅" if ok else " ❌"), global_position + Vector3(0, 6, 0), Color.GREEN if ok else Color.RED)

func _do_save_load(slot: int) -> void:
	var mgr = get_node_or_null("/root/MapSaveManager")
	if mgr == null:
		return
	if Input.is_key_pressed(KEY_SHIFT):
		# Shift+F1-F4 = 读取槽位
		var ok: bool = mgr.load_game(slot)
		EventBus.float_text.emit("📂 读槽%d" % slot + (" ✅" if ok else " ❌"), global_position + Vector3(0, 6, 0), Color.GREEN if ok else Color.RED)
	else:
		# F1-F4 = 存到槽位
		var ok: bool = mgr.save_game(slot)
		EventBus.float_text.emit("💾 存槽%d" % slot + (" ✅" if ok else " ❌"), global_position + Vector3(0, 6, 0), Color.GREEN if ok else Color.RED)

func _screen_to_world(screen_pos: Vector2) -> Vector3:
	# ★ 必须打地形表面，不能打 Y=0 平面。
	# 打 Y=0 时，鼠标指在山坡上，射线要飞得更远才降到 0，
	# 算出来的格子和鼠标实际指的位置差好几格 —— 于是"点哪儿都提示无法放置"。
	var hit = TerrainPicker.world_from_screen(get_viewport(), screen_pos)
	if hit != null:
		return hit
	var camera: Camera3D = camera_controller.get_node("Camera3D")
	var from: Vector3 = camera.project_ray_origin(screen_pos)
	var dir: Vector3 = camera.project_ray_normal(screen_pos)
	if abs(dir.y) < 0.001:
		return Vector3.INF
	var t: float = -from.y / dir.y
	if t < 0:
		return Vector3.INF
	return from + dir * t

func _get_entity_at(pos: Vector3) -> Node:
	var best: Node = null
	var best_dist: float = 1.5
	for u in GameManager.all_units:
		if not is_instance_valid(u):
			continue
		# 船上单位已隐藏，右键应命中船本身而非乘客
		if u.get("on_board") == true:
			continue
		if u.global_position.distance_to(pos) < best_dist:
			best_dist = u.global_position.distance_to(pos)
			best = u
	for b in GameManager.all_buildings:
		if not is_instance_valid(b):
			continue
		if b.global_position.distance_to(pos) < best_dist + 1.0:
			best = b
			break
	# 资源节点
	for rn in GameManager.resource_nodes:
		if is_instance_valid(rn) and rn.global_position.distance_to(pos) < best_dist + 0.5:
			best = rn
			break
	# 古碑（残片不参与右键命中，避免被当成攻击目标）
	for rl in GameManager.relics:
		if is_instance_valid(rl) and rl.has_method("get_relic_name") and rl.global_position.distance_to(pos) < best_dist + 1.0:
			best = rl
			break
	# 村庄
	for v in GameManager.villages:
		if is_instance_valid(v) and v.global_position.distance_to(pos) < best_dist + 1.5:
			best = v
			break
	# 野马
	for h in GameManager.wild_horses:
		if is_instance_valid(h) and h.global_position.distance_to(pos) < best_dist + 0.5:
			best = h
			break
	return best
