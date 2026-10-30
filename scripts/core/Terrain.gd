extends Node
## Terrain — 高度场 + 生物群系地形系统（autoload）
## 由 MapParams 驱动生成，支持种子复现、多条河流/多个湖泊、可调群系密度。
## 生成两张图（CPU 与 GPU 共用，保证视觉与实体贴地一致）：
##   1) heightmap_img  (RF)        高度场，实体/网格通过 get_height 查询地面高度
##   2) biome_img      (RGBA8)     生物群系权重图  R=森林  G=土地  B=石板
## 地形特征：岛屿（四周沉入水下）+ 蜿蜒河流 + 湖泊；山地区域由着色器按坡度/海拔叠加裸岩与雪。

const WORLD_SIZE: float = 300.0      # 地形世界边长（2026-10-25 用户要求"地图做大一些"，200→300）
# 256 → 512：与 MapParams 默认对齐。用户口径"地图拼接要细致、地面尽量平直"——
# 512² 在 200m 上 = 0.39m/像素，缓坡不再有一段段折面。
const HM_SIZE: int = 512             # 高度图分辨率
const BIOME_SIZE: int = 512          # 群系图分辨率
## 拼图层分辨率。
## ⚠ 512 → 2048（2026-10-27）：512² 对 300m = 0.59m/格，笔刷权重按格跳变，
## 用户实测"黄色草和绿色草之间一格一格的"。AoE4 S5 地形重做的核心就是把
## 权重精度提到逐像素级。2048² = 0.146m/格，方格不可见；RGBA8 两张共 32MB 内存，
## 换贴图上传 16MB/帧在桌面 GPU 上无压力。旧存档由 set_splat_image 自动缩放兼容。
const SPLAT_SIZE: int = 2048
const MAX_HEIGHT: float = 16.0       # 最大海拔（山峰）
const WATER_LEVEL: float = -2.0      # 水面高度（2026-10-25 用户要求从 -5m 提到 -2m：压 ~4m 见水）

var params = null  # MapParams（延迟注册，用弱类型避免 autoload 解析时序问题）
var heightmap_img: Image = null
var heightmap_tex: ImageTexture = null
var biome_img: Image = null
var biome_tex: ImageTexture = null
## 拼图层：R=沙地 G=泥土 B=岩石 A=森林地被（0~1 覆盖强度）。
## 与 biome 的差别：biome 是**程序按噪声算出来**的群系权重，
## splat 是**人工用笔刷画上去**的覆盖层，永远盖在 biome 之上。
var splat_img: Image = null
var splat_tex: ImageTexture = null
## 第二张拼图：石板路(R) / 土路(G)。与 splat 同尺寸，层 4/5 住这里。
var splat2_img: Image = null
var splat2_tex: ImageTexture = null

# 内部噪声（每次 generate 按 params 重建）
var _noise: FastNoiseLite = null
var _moist: FastNoiseLite = null
var _rock: FastNoiseLite = null
var _ridge: FastNoiseLite = null
# 河流/湖泊布局（仅依赖 seed，保证可复现）
var _rivers: Array = []
var _lakes: Array = []

func _ready() -> void:
	generate(default_params())

## 默认参数（保持与旧版一致的地形观感）
func default_params() -> MapParams:  # 返回 MapParams
	var p := preload("res://scripts/core/MapParams.gd").new()
	p.world_size = WORLD_SIZE
	p.heightmap_size = HM_SIZE
	p.biome_size = BIOME_SIZE
	p.max_height = MAX_HEIGHT
	p.water_level = WATER_LEVEL
	return p

# --- 小工具：平滑插值（smoothstep）---
func _ss(e0: float, e1: float, x: float) -> float:
	var t: float = clamp((x - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

## 用给定的 MapParams 重新生成整张地图（含高度场与生物群系）。
## 不依赖场景树，可随时调用（菜单/调参面板/读档后）。
func generate(p) -> void:
	params = p
	var ws: float = p.world_size
	var hms: int = p.heightmap_size
	var bms: int = p.biome_size

	# --- 平地快速通道（地图编辑器白纸图）---
	# 不建噪声对象、不做逐像素高度/群系计算：512² 全图填充比噪声生成快两个数量级，
	# 编辑器进场/新建秒开。群系图 R/G/B 全 0 = 纯草地（shader 里草地是残差底色）。
	if p.flat_ground:
		_generate_flat(p)
		return

	# 注意：get_noise_2d 内部不乘 frequency，故把 .frequency 固定为 1.0，
	# 真正的空间频率由 get_noise_2d(x * freq, ...) 的乘子决定（避免重复叠加）。
	_init_noises(p)

	# 预生成河流/湖泊布局：确定性，仅依赖 seed（与像素无关，避免逐像素调 rng）
	var rng := RandomNumberGenerator.new()
	rng.seed = p.seed
	_rivers = []
	for i in p.river_count:
		var orient: bool = (i % 2 == 0)   # 偶数河流纵向蜿蜒，奇数横向蜿蜒
		_rivers.append({
			"orient": orient,
			"k1": 0.011 * rng.randf_range(0.8, 1.2),
			"k2": 0.041 * rng.randf_range(0.8, 1.2),
			"a1": p.river_wind * rng.randf_range(0.7, 1.3),
			"a2": p.river_wind2 * rng.randf_range(0.7, 1.3),
			"ph1": rng.randf_range(0.0, TAU),
			"ph2": rng.randf_range(0.0, TAU),
			"off": p.island_center_factor * ws + rng.randf_range(-18.0, 18.0),
		})
	_lakes = []
	for i in p.lake_count:
		_lakes.append({
			"x": p.island_center_factor * ws + rng.randf_range(-p.island_radius * 0.55, p.island_radius * 0.55),
			"z": p.island_center_factor * ws + rng.randf_range(-p.island_radius * 0.55, p.island_radius * 0.55),
			"r": p.lake_radius * rng.randf_range(0.6, 1.4),
		})

	var center: float = p.island_center_factor * ws
	var island_r: float = p.island_radius

	heightmap_img = Image.create(hms, hms, false, Image.FORMAT_RF)
	biome_img = Image.create(bms, bms, false, Image.FORMAT_RGBA8)
	# --- 第一遍：高度场（含岛屿下沉 + 河流 carving + 湖泊）---
	for py in range(hms):
		var v: float = float(py) / float(hms - 1)
		for px in range(hms):
			var u: float = float(px) / float(hms - 1)
			var wx: float = (u - 0.5) * ws + (ws * 0.5)
			var wz: float = (ws * 0.5) - (v - 0.5) * ws
			# ⚠ 这里曾经写成 `wx * _noise.frequency`，而 _noise.frequency 被固定成 1.0
			# → 等于用世界坐标原样采样。FastNoiseLite 的 frequency 是**内部**生效的
			# （实测 property=0.01 @(37,11) 与 property=1.0 @(0.37,0.11) 结果完全相同），
			# 于是频率变成"每米变化 0.57"的白噪声：相邻高度图像素高差 ±9 米。
			# 表现就是地形完全不可读、单位在地面上乱抖。必须用 MapParams.noise_frequency。
			var nf: float = p.noise_frequency
			var raw: float = _noise.get_noise_2d(wx * nf, wz * nf)
			# 山脊项：1-|n| 取三次方 → 只有脊线附近才抬升，两侧迅速跌落
			# （一次方太平缓、二次方还是圆，三次才有"刃"）。
			# 乘 island 之外再乘一个低频遮罩，让山地成片出现而不是满地尖刺。
			var rg: float = 1.0 - absf(_ridge.get_noise_2d(wx * p.ridge_frequency, wz * p.ridge_frequency))
			rg = rg * rg * rg
			var ridge_mask: float = _ss(0.37, 0.78, _ridge.get_noise_2d(wx * 0.008 + 41.0, wz * 0.008 + 17.0) * 0.5 + 0.5)
			var h: float = raw * p.height_scale + rg * p.ridge_scale * ridge_mask + p.base_height
			# 岛屿遮罩：边缘沉入水下
			var d: float = sqrt((wx - center) * (wx - center) + (wz - center) * (wz - center))
			var island: float = _ss(p.island_falloff_outer, p.island_falloff_inner, d / island_r)
			h = lerp(p.ocean_depth, h, island)
			# 方形边界遮罩：圆形岛屿遮罩管不到"地图的四条直边"。
			# 实测 x=0 处还有 +2.3m 的陆地，于是地图边界被切成一道直立土墙、
			# 墙外直接是天空背景 —— 整块地图像一块漂浮的板（实拍见 shot_terrain_now）。
			# 这里再叠一层"到最近边界的距离"遮罩，保证四周一定平滑沉到海平面以下。
			var edge_d: float = minf(minf(wx, wz), minf(ws - wx, ws - wz))
			# 边界距离加噪声扰动：否则整张地图的海岸线是四条笔直的斜线，
			# 从上往下看就是一块"切得方方正正的年糕"（实拍见过）。
			edge_d += (_rock.get_noise_2d(wx * 0.035, wz * 0.035)) * ws * 0.045
			var edge: float = _ss(0.0, ws * p.edge_falloff, maxf(edge_d, 0.0))
			h = lerp(p.ocean_depth, h, edge)
			# 河流 carving（取所有河中最大下切）
			var carve := 0.0
			for r in _rivers:
				var dist: float
				if r.orient:
					var rx: float = r.off + r.a1 * sin(wz * r.k1 + r.ph1) + r.a2 * sin(wz * r.k2 + r.ph2)
					dist = abs(wx - rx)
				else:
					var rz: float = r.off + r.a1 * sin(wx * r.k1 + r.ph1) + r.a2 * sin(wx * r.k2 + r.ph2)
					dist = abs(wz - rz)
				var c: float = _ss(p.river_width, 0.0, dist) * island
				carve = max(carve, c * p.river_depth)
			h = lerp(h, -0.55, carve)
			# 湖泊（取最深的一个）
			var lake := 0.0
			for lk in _lakes:
				var ld: float = sqrt((wx - lk.x) * (wx - lk.x) + (wz - lk.z) * (wz - lk.z))
				var lv: float = _ss(lk.r, 0.0, ld) * island
				lake = max(lake, lv * p.lake_depth)
			h = lerp(h, -0.5, lake)
			heightmap_img.set_pixel(px, py, Color(h, 0.0, 0.0, 1.0))

	_rebuild_biome()
	heightmap_tex = ImageTexture.create_from_image(heightmap_img)
	biome_tex = ImageTexture.create_from_image(biome_img)
	# 拼图层每次重生成都清空：换种子/换地图就该是一张"没人画过"的新图。
	# 读档时 apply_images() 会在 generate() 之后把磁盘上的 splat 盖回来。
	splat_clear()
	# 丰富地图：程序生成图自动修两条路（土路商路 + 石板古道），确定性依赖 seed
	_paint_generated_roads()

## 给程序生成的地图自动修两条路（2026-10-28「丰富地图」）：
##   ① 土路商路：横穿地图（随机东西/南北向），蜿蜒前进，遇水横移绕行，绕不过就地断头（像渡口）
##   ② 石板古道：从土路中段附近向随机方向延伸一条 25~40m 的铺装路
## 只依赖 params.seed（同种子同路）；平地白纸图不走这里（flat_ground 提前 return）。
## 石板变种不需要在这里区分 —— shader 按世界噪声自动分带换石头。
func _paint_generated_roads() -> void:
	if params == null or splat_img == null or splat2_img == null:
		return
	var brush := preload("res://scripts/mapeditor/TerrainBrush.gd")
	var sb := preload("res://scripts/mapeditor/SplatBrush.gd")
	var ws: float = params.world_size
	var ssz: int = SPLAT_SIZE
	var water: float = params.water_level
	var rng := RandomNumberGenerator.new()
	rng.seed = int(params.seed) ^ 0x5A17D0AD
	sb.stroke_seed = rng.randi()

	# ---- ① 土路商路：横穿地图 ----
	var horiz: bool = rng.randf() < 0.5
	var base_y: float = ws * rng.randf_range(0.32, 0.68)
	var a1: float = ws * rng.randf_range(0.05, 0.10)
	var k1: float = TAU / (ws * rng.randf_range(0.45, 0.70))
	var ph1: float = rng.randf_range(0.0, TAU)
	var r_d: float = brush.world_radius_to_pixel(3.2, ws, ssz)
	var mid_wp := Vector2.ZERO
	var have_mid := false
	var t: float = 0.0
	# 岛图边缘是水：先快进到第一块陆地再开始修路
	while t < ws - 3.0 and get_height(t if horiz else base_y, base_y if horiz else t) < water + 0.35:
		t += 1.5
	var skip_run: int = 0
	while t < ws - 3.0:
		var lat: float = base_y + a1 * sin(t * k1 + ph1)
		var wx: float = t
		var wz: float = lat
		if not horiz:
			wx = lat
			wz = t
		# 遇水：横移找陆地（最多 ±18m），找不到就跳过这一段（像渡口）
		if get_height(wx, wz) < water + 0.35:
			var fixed := false
			for off in range(2, 20, 2):
				for sgn in [1.0, -1.0]:
					var l2: float = lat + sgn * float(off)
					var hx: float = t if horiz else l2
					var hz: float = l2 if horiz else t
					if get_height(hx, hz) >= water + 0.35:
						wx = hx
						wz = hz
						fixed = true
						break
				if fixed:
					break
			if not fixed:
				skip_run += 1
				t += 1.5
				if skip_run > 18:   # 连续 ~27m 水域：路到此为止
					break
				continue
		skip_run = 0
		var px: Vector2 = brush.world_to_pixel(Vector3(wx, 0.0, wz), ws, ssz)
		sb.paint_road(splat_img, splat2_img, px, r_d, sb.Layer.ROAD, 0.45)
		if not have_mid and t > ws * 0.5:
			mid_wp = Vector2(wx, wz)
			have_mid = true
		t += 1.1

	# ---- ② 石板古道：从土路中段（没取到就用图心）向随机方向铺 25~40m ----
	var start := mid_wp if have_mid else Vector2(ws * 0.5, ws * 0.5)
	var ang: float = rng.randf_range(0.0, TAU)
	var len_m: float = rng.randf_range(25.0, 40.0)
	var r_p: float = brush.world_radius_to_pixel(2.6, ws, ssz)
	var s2: float = 2.0
	while s2 < len_m:
		var wx2: float = start.x + cos(ang) * s2
		var wz2: float = start.y + sin(ang) * s2
		if wx2 < 3.0 or wx2 > ws - 3.0 or wz2 < 3.0 or wz2 > ws - 3.0:
			break
		if get_height(wx2, wz2) < water + 0.35:
			break
		var px2: Vector2 = brush.world_to_pixel(Vector3(wx2, 0.0, wz2), ws, ssz)
		sb.apply(splat_img, px2, r_p, sb.Layer.PAVED, 0.6, splat2_img)
		s2 += 1.0

	refresh_splat_texture()
	refresh_splat2_texture()

## 建 4 个噪声对象（主噪声/湿度/岩石/山脊）。generate 与 _generate_flat 共用，
## 平地模式也要建：笔刷塑形后 _rebuild_biome 靠它们出裸土/岩石。
func _init_noises(p) -> void:
	# 注意：get_noise_2d 内部不乘 frequency，故把 .frequency 固定为 1.0，
	# 真正的空间频率由 get_noise_2d(x * freq, ...) 的乘子决定（避免重复叠加）。
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.frequency = 1.0
	_noise.fractal_octaves = p.noise_octaves
	_noise.fractal_lacunarity = 2.0
	_noise.fractal_gain = 0.5
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.seed = p.seed

	_moist = FastNoiseLite.new()
	_moist.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_moist.frequency = 1.0
	_moist.fractal_octaves = 4
	_moist.fractal_gain = 0.5
	_moist.fractal_type = FastNoiseLite.FRACTAL_FBM
	_moist.seed = p.seed + 7777

	_rock = FastNoiseLite.new()
	_rock.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_rock.frequency = 1.0
	_rock.fractal_octaves = 3
	_rock.fractal_gain = 0.5
	_rock.fractal_type = FastNoiseLite.FRACTAL_FBM
	_rock.seed = p.seed + 3331

	# 山脊噪声：fbm 只会给出"馒头"一样的圆丘（实测整张图坡度不到 3°，永远露不出岩石）。
	# 用 ridged noise（1-|n| 再取幂）才能压出山脊线和陡坡，山才有"块面"。
	_ridge = FastNoiseLite.new()
	_ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_ridge.frequency = 1.0
	_ridge.fractal_octaves = 4
	_ridge.fractal_gain = 0.5
	_ridge.fractal_type = FastNoiseLite.FRACTAL_FBM
	_ridge.seed = p.seed + 9021

## 平地地图：高度恒为 base_height、群系全草地，无河无湖无海无山。
## 编辑器进场/新建用 —— AoE4 式"白纸"，起伏全部交给地形笔刷。
## ⚠ 噪声对象仍要建好：之后笔刷塑形会触发 _rebuild_biome（山坡露岩/裸土靠它），
##    缺了 _moist/_rock 它会静默返回，塑过的山永远不出岩石。
func _generate_flat(p) -> void:
	_init_noises(p)
	heightmap_img = Image.create(p.heightmap_size, p.heightmap_size, false, Image.FORMAT_RF)
	heightmap_img.fill(Color(p.base_height, 0.0, 0.0, 1.0))
	biome_img = Image.create(p.biome_size, p.biome_size, false, Image.FORMAT_RGBA8)
	biome_img.fill(Color(0.0, 0.0, 0.0, 1.0))
	heightmap_tex = ImageTexture.create_from_image(heightmap_img)
	biome_tex = ImageTexture.create_from_image(biome_img)
	splat_clear()

## 用新种子重生成（保留其余参数）—— 菜单「随机地图」/ 调参面板「换一张」用
func regenerate(seed: int) -> void:
	if params == null:
		params = default_params()
	params.seed = seed
	generate(params)

## 随机一个新种子并重生成，返回该种子（便于 UI 显示/存档）
func randomize_seed() -> int:
	var s: int = randi()
	regenerate(s)
	return s

## 世界坐标 (x,z) -> 地形高度（世界 Y）。CPU/GPU 同一映射。
func get_height(x: float, z: float) -> float:
	if heightmap_img == null or params == null:
		return 0.0
	var sz: int = heightmap_img.get_width()
	var u: float = (x - params.world_size * 0.5) / params.world_size + 0.5
	var v: float = (params.world_size * 0.5 - z) / params.world_size + 0.5
	u = clamp(u, 0.0, 1.0)
	v = clamp(v, 0.0, 1.0)
	var fx: float = u * float(sz - 1)
	var fy: float = v * float(sz - 1)
	var x0: int = int(floor(fx))
	var y0: int = int(floor(fy))
	var x1: int = mini(x0 + 1, sz - 1)
	var y1: int = mini(y0 + 1, sz - 1)
	var tx: float = fx - float(x0)
	var ty: float = fy - float(y0)
	var h00: float = heightmap_img.get_pixel(x0, y0).r
	var h10: float = heightmap_img.get_pixel(x1, y0).r
	var h01: float = heightmap_img.get_pixel(x0, y1).r
	var h11: float = heightmap_img.get_pixel(x1, y1).r
	var h: float = (h00 * (1.0 - tx) + h10 * tx) * (1.0 - ty) + (h01 * (1.0 - tx) + h11 * tx) * ty
	return h * params.max_height

## 是否水下（低于水面）
func is_water(x: float, z: float) -> bool:
	return get_height(x, z) < params.water_level

## 是否树林（群系图 R 通道 = 森林权重）
## 用于树林伏兵：林内不可见、出林获得短时攻击加成
func is_forest(x: float, z: float, threshold: float = 0.55) -> bool:
	if biome_img == null or params == null:
		return false
	var sz: int = biome_img.get_width()
	var ws: float = params.world_size
	var u: float = clampf(x / ws, 0.0, 1.0)
	var v: float = clampf(1.0 - z / ws, 0.0, 1.0)
	var px: int = clampi(int(u * float(sz - 1)), 0, sz - 1)
	var py: int = clampi(int(v * float(sz - 1)), 0, sz - 1)
	return biome_img.get_pixel(px, py).r >= threshold

## 直接接受外部高度图 / 群系图（地图编辑器存档、读档用），跳过噪声生成。
## 内部先跑一遍 generate()，目的是把 _moist / _rock 这些噪声对象按 params 建好，
## 这样后续 _rebuild_biome() 才有得用；随后用外部图覆盖，噪声结果不参与高度。
func apply_images(h_img: Image, b_img: Image, p, s_img: Image = null, s2_img: Image = null) -> void:
	if p != null:
		params = p
	generate(params)
	if h_img != null:
		var hi: Image = h_img
		if hi.get_format() != Image.FORMAT_RF:
			hi = hi.duplicate()
			hi.convert(Image.FORMAT_RF)
		heightmap_img = hi
		heightmap_tex = ImageTexture.create_from_image(heightmap_img)
		params.heightmap_size = heightmap_img.get_width()
	if b_img != null:
		biome_img = b_img
		biome_tex = ImageTexture.create_from_image(biome_img)
		params.biome_size = biome_img.get_width()
	else:
		_rebuild_biome()
	# 拼图层：磁盘上有就盖回来，没有就保持 generate() 清空后的空图。
	# 注意必须在 generate() **之后**赋值 —— generate() 内部会 splat_clear()。
	if s_img != null:
		set_splat_image(s_img)
	else:
		if splat_img == null or splat_img.get_width() != SPLAT_SIZE:
			splat_img = Image.create(SPLAT_SIZE, SPLAT_SIZE, false, Image.FORMAT_RGBA8)
			splat_img.fill(Color(0, 0, 0, 0))
		splat_tex = ImageTexture.create_from_image(splat_img)
	# 第二张拼图（石板路/土路）同样处理
	if s2_img != null:
		set_splat2_image(s2_img)
	else:
		ensure_splat2(SPLAT_SIZE)

## 导出当前图（编辑器保存用）
func export_images() -> Dictionary:
	return {"height": heightmap_img, "biome": biome_img, "splat": splat_img, "splat2": splat2_img}

## 就地改完 heightmap_img / biome_img / splat_img 之后调用这个重建纹理。
##
## 为什么必须有这一步：ImageTexture 在 create_from_image 那一刻就把像素拷走了，
## 之后改 Image 数据纹理不会跟着变。自动生成器做完对称化如果不刷新，
## 就会出现「存盘的地图是对称的、屏幕上看到的还是原来那张」。
func refresh_textures() -> void:
	if heightmap_img != null:
		heightmap_tex = ImageTexture.create_from_image(heightmap_img)
	if biome_img != null:
		biome_tex = ImageTexture.create_from_image(biome_img)
	if splat_img != null:
		splat_tex = ImageTexture.create_from_image(splat_img)
	if splat2_img != null:
		splat2_tex = ImageTexture.create_from_image(splat2_img)

# ---------------------------------------------------------------- 拼图层

## 保证 splat_img 存在且尺寸正确（编辑器启动 / 换图尺寸后都要过一遍）
func ensure_splat(size: int = SPLAT_SIZE) -> void:
	var n: int = maxi(size, 8)
	if splat_img != null and splat_img.get_width() == n and splat_img.get_height() == n:
		if splat_tex == null:
			splat_tex = ImageTexture.create_from_image(splat_img)
		return
	var img: Image = Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))
	splat_img = img
	splat_tex = ImageTexture.create_from_image(splat_img)

## 清空所有手刷痕迹（"还原成程序生成的样子"）
func splat_clear() -> void:
	ensure_splat(SPLAT_SIZE)
	splat_img.fill(Color(0.0, 0.0, 0.0, 0.0))
	splat_tex = ImageTexture.create_from_image(splat_img)
	ensure_splat2(SPLAT_SIZE)
	splat2_img.fill(Color(0.0, 0.0, 0.0, 0.0))
	splat2_tex = ImageTexture.create_from_image(splat2_img)

## 从外部图（读档）设置拼图层。格式/尺寸不对时统一转成 RGBA8 并缩放。
func set_splat_image(src: Image) -> void:
	if src == null:
		ensure_splat(SPLAT_SIZE)
		return
	var img: Image = src
	if img.get_format() != Image.FORMAT_RGBA8:
		img = img.duplicate()
		img.convert(Image.FORMAT_RGBA8)
	# 存档可能来自别的分辨率，直接缩放会丢掉通道语义吗？不会 —— RGBA 通道
	# 是逐通道独立的，双线性缩放不会串道。但为了可复现，只在尺寸不符时才缩放。
	if img.get_width() != SPLAT_SIZE or img.get_height() != SPLAT_SIZE:
		img.resize(SPLAT_SIZE, SPLAT_SIZE, Image.INTERPOLATE_BILINEAR)
	splat_img = img
	splat_tex = ImageTexture.create_from_image(splat_img)

## 保证 splat2_img（石板路/土路层）存在且尺寸正确
func ensure_splat2(size: int = SPLAT_SIZE) -> void:
	var n: int = maxi(size, 8)
	if splat2_img != null and splat2_img.get_width() == n and splat2_img.get_height() == n:
		if splat2_tex == null:
			splat2_tex = ImageTexture.create_from_image(splat2_img)
		return
	var img: Image = Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))
	splat2_img = img
	splat2_tex = ImageTexture.create_from_image(splat2_img)

## 从外部图（读档）设置第二张拼图。格式/尺寸不对时统一转成 RGBA8 并缩放。
func set_splat2_image(src: Image) -> void:
	if src == null:
		ensure_splat2(SPLAT_SIZE)
		return
	var img: Image = src
	if img.get_format() != Image.FORMAT_RGBA8:
		img = img.duplicate()
		img.convert(Image.FORMAT_RGBA8)
	if img.get_width() != SPLAT_SIZE or img.get_height() != SPLAT_SIZE:
		img.resize(SPLAT_SIZE, SPLAT_SIZE, Image.INTERPOLATE_BILINEAR)
	splat2_img = img
	splat2_tex = ImageTexture.create_from_image(splat2_img)

## 编辑器改完 splat_img 后刷新纹理（ImageTexture 不会跟着 Image 自动变）。
## ⚠️ 必须原地 update() 而不是 create_from_image：
##   create_from_image 会返回一个**新的** ImageTexture 对象，
##   而 TerrainMaterial.build() 在场景启动时已经把**旧的**对象绑进材质 uniform 了，
##   换新对象材质根本不知道 —— 表现就是"笔刷刷了、数据变了、画面纹丝不动"。
##   update() 是把像素灌进**同一个**纹理对象，材质才能看到。
##   （只有尺寸对不上时才允许换新对象，那时材质需要重建。）
func refresh_splat_texture() -> void:
	if splat_img == null:
		ensure_splat(SPLAT_SIZE)
		return
	var same_size: bool = (splat_tex != null
		and splat_tex.get_width() == splat_img.get_width()
		and splat_tex.get_height() == splat_img.get_height())
	if same_size:
		splat_tex.update(splat_img)
	else:
		splat_tex = ImageTexture.create_from_image(splat_img)

## 编辑器改完 splat2_img（石板路/土路）后刷新纹理。update/create 规则同上。
func refresh_splat2_texture() -> void:
	if splat2_img == null:
		ensure_splat2(SPLAT_SIZE)
		return
	var same_size: bool = (splat2_tex != null
		and splat2_tex.get_width() == splat2_img.get_width()
		and splat2_tex.get_height() == splat2_img.get_height())
	if same_size:
		splat2_tex.update(splat2_img)
	else:
		splat2_tex = ImageTexture.create_from_image(splat2_img)

## 重算群系权重图（森林/土地/石板）。generate() 与地图编辑器共用同一份公式，
## 保证「拖动笔刷改出来的地形」和「程序生成的地形」用的是同一套群系规则。
func _rebuild_biome() -> void:
	if params == null or heightmap_img == null or _moist == null or _rock == null:
		return
	var bms: int = params.biome_size
	var ws: float = params.world_size
	if biome_img == null or biome_img.get_width() != bms:
		biome_img = Image.create(bms, bms, false, Image.FORMAT_RGBA8)
	var sz_h: int = heightmap_img.get_width()

	for py in range(bms):
		var v: float = float(py) / float(bms - 1)
		var hpy: int = clampi(int(v * float(sz_h - 1)), 0, sz_h - 1)
		for px in range(bms):
			var u: float = float(px) / float(bms - 1)
			var hpx: int = clampi(int(u * float(sz_h - 1)), 0, sz_h - 1)
			var wx: float = (u - 0.5) * ws + (ws * 0.5)
			var wz: float = (ws * 0.5) - (v - 0.5) * ws
			# 显式把群系图索引映射到高度图索引：两者分辨率不一致也不会错位
			var hr: float = heightmap_img.get_pixel(hpx, hpy).r
			var world_h: float = hr * params.max_height
			var water_here: float = 1.0 if world_h < params.water_level else 0.0
			var m: float = _moist.get_noise_2d(wx * params.moisture_frequency, wz * params.moisture_frequency)
			var rk: float = _rock.get_noise_2d(wx * params.rock_frequency, wz * params.rock_frequency)

			var forestLo: float = 0.00 - (params.forest_density - 1.0) * 0.30
			var forestHi: float = 0.55
			# 裸土与石板都应该是"点缀"，不是主色。
			# 原阈值 dirtHi=-0.19 / stoneLo=0.30 会让约 35% + 30% 的地面变成
			# 黄褐土斑和灰石板 —— 草地看着就像"秃了一半"，怎么调草地贴图都没用。
			var dirtHi: float = -0.52 + (params.dirt_density - 1.0) * 0.16
			var stoneLo: float = 0.62 - (params.stone_density - 1.0) * 0.16

			var forestW: float = _ss(forestLo, forestHi, m) * (1.0 - _ss(0.45, 0.72, hr)) * (1.0 - water_here)
			var dirtW: float = _ss(dirtHi + 0.26, dirtHi, m) * (1.0 - forestW) * (1.0 - water_here)
			var stoneW: float = _ss(stoneLo, 0.86, rk) * (1.0 - forestW) * (1.0 - water_here)

			biome_img.set_pixel(px, py, Color(clampf(forestW, 0.0, 1.0), clampf(dirtW, 0.0, 1.0), clampf(stoneW, 0.0, 1.0), 1.0))

	biome_tex = ImageTexture.create_from_image(biome_img)

## 地图编辑器改完地形后调用：只刷新群系，不重算高度
func _refresh_biome_from_height() -> void:
	_rebuild_biome()
