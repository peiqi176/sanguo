extends Node3D
## GroundDetail — 地表装饰（草簇 / 碎石 / 灌木）
##
## 为什么要有这一层：
##   地形 shader 做到最后，本质上还是"一张贴图 + 法线扰动"。玩家在 30m 视距下判断
##   "这是草地"，靠的是**立起来的东西**：草叶、石块、灌木。没有它们，地面永远是
##   一块绿布——这正是之前被吐槽"草地不像帝国时代4"的根因。
##
## 实现取舍：
##   用 Sprite3D 而不是 MultiMesh。MultiMesh 的 billboard 要在 vertex 里手写
##   MODELVIEW 重建，跟现有的 alpha_cut / 阴影管线容易打架；这里的量级（1000 出头）
##   在 3060 上没压力，先要"对"再要"快"。

const GROUND_DIR: String = "res://assets/ground/"
const PROP_DIR: String = "res://assets/props/"

## 道具库（Agnes 手绘，2K→1024 已裁边）：name -> [数量, 世界高度米]
## AoE4 的地面密诀是"有人生活过的痕迹"：柴堆、树桩、乱石、花丛。
## 数量别乱加——同类 Sprite3D 自动合批，但总量上去后填充率会先顶不住。
const PROP_DEFS: Dictionary = {
	"flowers": [280, 0.50],
	"bush": [300, 1.35],
	"rockpile": [90, 1.15],
	"woodpile": [55, 1.05],
	"stump": [70, 0.80],
}

## 变体贴图缓存：name -> Array[Texture2D]
static var _tex_cache: Dictionary = {}

static func _variants(base_name: String, count: int) -> Array:
	if _tex_cache.has(base_name):
		return _tex_cache[base_name]
	var out: Array = []
	for i in range(count):
		var f: String = base_name + ("" if i == 0 else "_v%d" % (i + 1))
		var p: String = GROUND_DIR + f + ".png"
		# ResourceLoader.exists 对"未导入的 PNG"会说谎，必须用 FileAccess 兜底
		if not ResourceLoader.exists(p) and not FileAccess.file_exists(p):
			continue
		var img: Image = Image.load_from_file(ProjectSettings.globalize_path(p))
		if img == null:
			continue
		out.append(ImageTexture.create_from_image(img))
	_tex_cache[base_name] = out
	return out


## 在地图网格上撒装饰。
## opts: { tufts, rocks, bushes, seed, avoid_radius }
static func populate(host: Node3D, grid, opts: Dictionary = {}) -> Dictionary:
	var stats: Dictionary = {"tufts": 0, "rocks": 0, "bushes": 0}
	if host == null or grid == null or Terrain.heightmap_img == null:
		return stats

	var tufts: Array = _variants("grass_tuft", 3)
	var rocks: Array = _variants("rock_small", 2)
	var bushes: Array = _variants("bush_small", 2)
	if tufts.is_empty() and rocks.is_empty() and bushes.is_empty():
		print("[GroundDetail] 缺少装饰贴图，跳过")
		return stats

	var rng := RandomNumberGenerator.new()
	rng.seed = int(opts.get("seed", 20261024))
	var cs: float = float(Terrain.params.world_size) / float(grid.map_size.x)
	var wl: float = float(Terrain.params.water_level)

	var n_tuft: int = int(opts.get("tufts", 2600))
	var n_rock: int = int(opts.get("rocks", 520))
	var n_bush: int = int(opts.get("bushes", 240))

	for kind in ["tufts", "rocks", "bushes"]:
		var total: int = {"tufts": n_tuft, "rocks": n_rock, "bushes": n_bush}[kind]
		var pool: Array = {"tufts": tufts, "rocks": rocks, "bushes": bushes}[kind]
		if pool.is_empty():
			continue
		var placed: int = 0
		var guard: int = 0
		# 撒不满就少撒，绝不无限循环
		while placed < total and guard < total * 40:
			guard += 1
			var gx: int = rng.randi_range(0, int(grid.map_size.x) - 1)
			var gz: int = rng.randi_range(0, int(grid.map_size.y) - 1)
			var gp := Vector2i(gx, gz)
			if not grid.is_in_bounds(gp):
				continue
			# 别长在建筑/资源上，也别长在水里
			if int(grid.occupied[gx][gz]) != 0:
				continue
			var wx: float = (float(gx) + rng.randf_range(0.15, 0.85)) * cs
			var wz: float = (float(gz) + rng.randf_range(0.15, 0.85)) * cs
			var h: float = Terrain.get_height(wx, wz)
			if h < wl + 0.12:
				continue        # 水下或刚好在水线上
			if kind == "tufts" and h < wl + 0.55:
				continue        # 草不贴着水边长
			if kind == "bushes" and h < wl + 1.0:
				continue

			var tex: Texture2D = pool[rng.randi_range(0, pool.size() - 1)]
			var sp := Sprite3D.new()
			sp.texture = tex
			sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			sp.shaded = true                 # 受光：不然一片死绿，跟地形不搭
			sp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
			sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			# 尺寸：草簇 0.5~1.1m 高，石头 0.4~0.9m，灌木 1.0~1.8m
			var base_m: float = {"tufts": 0.46, "rocks": 0.42, "bushes": 1.30}[kind]
			var m: float = base_m * rng.randf_range(0.72, 1.28)
			# 图片是方图，pixel_size 按"图高 = m 米"反推
			sp.pixel_size = m / float(tex.get_height())
			# 底边贴地：精灵原点在图片中心，所以中心要抬半个世界高度。
			# 用 position.y 而不是 offset —— offset 的 y 正方向在 Sprite3D 里是"向下"，
			# 一不小心就整体埋进地里，而且不同版本行为容易记混。
			sp.position = Vector3(wx, h + m * 0.5, wz)
			# 轻微旋转（绕视线的 z 轴）会让一丛丛的朝向有变化
			sp.rotation.z = rng.randf_range(-0.25, 0.25)
			# 灌木/草在暗处调暗一点，避免整片同色
			var v: float = rng.randf_range(0.88, 1.06)
			sp.modulate = Color(v, v * rng.randf_range(0.98, 1.04), v * 0.96, 1.0)
			host.add_child(sp)
			placed += 1
		stats[kind] = placed

	# ---- 道具层：石堆/柴堆/花丛/树桩/手绘灌木（billboard，与上面同管线）----
	var stats_props: int = 0
	for pname in PROP_DEFS.keys():
		var p: String = PROP_DIR + pname + ".png"
		if not ResourceLoader.exists(p) and not FileAccess.file_exists(p):
			continue
		var img: Image = Image.load_from_file(ProjectSettings.globalize_path(p))
		if img == null:
			continue
		var tex: Texture2D = ImageTexture.create_from_image(img)
		var def: Array = PROP_DEFS[pname]
		var total_p: int = int(def[0])
		var base_h: float = float(def[1])
		var placed_p: int = 0
		var guard_p: int = 0
		while placed_p < total_p and guard_p < total_p * 40:
			guard_p += 1
			var gx2: int = rng.randi_range(0, int(grid.map_size.x) - 1)
			var gz2: int = rng.randi_range(0, int(grid.map_size.y) - 1)
			if not grid.is_in_bounds(Vector2i(gx2, gz2)):
				continue
			if int(grid.occupied[gx2][gz2]) != 0:
				continue
			var wx2: float = (float(gx2) + rng.randf_range(0.15, 0.85)) * cs
			var wz2: float = (float(gz2) + rng.randf_range(0.15, 0.85)) * cs
			var h2: float = Terrain.get_height(wx2, wz2)
			if h2 < wl + (1.0 if pname != "flowers" else 0.35):
				continue
			var m2: float = base_h * rng.randf_range(0.75, 1.3)
			var sp2 := Sprite3D.new()
			sp2.texture = tex
			sp2.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			sp2.shaded = true
			sp2.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
			sp2.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			sp2.pixel_size = m2 / float(tex.get_height())
			sp2.position = Vector3(wx2, h2 + m2 * 0.5, wz2)
			sp2.rotation.z = rng.randf_range(-0.18, 0.18)
			var v2: float = rng.randf_range(0.9, 1.05)
			# 调色：花丛(128,133,70)和石堆(145,147,93)贴图本身偏浅，
			# 远看是一坨坨淡黄绿"椭圆色块"浮在地上（截图实测）。压深压绿让它们沉进草地。
			var tint: Color = Color(1.0, 1.0, 1.0)
			match pname:
				"flowers":
					tint = Color(0.70, 0.82, 0.58)
				"rockpile":
					tint = Color(0.80, 0.80, 0.74)
				"bush":
					tint = Color(0.88, 0.94, 0.82)
			sp2.modulate = Color(v2 * tint.r, v2 * tint.g, v2 * tint.b, 1.0)
			host.add_child(sp2)
			placed_p += 1
		stats_props += placed_p
	stats["props"] = stats_props
	return stats
