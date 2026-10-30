extends RefCounted
## MapGenService —— 一键生成地图的完整管线（无 UI）
##
## 顺序很重要，错了就会出"资源浮在旧地形上"这类问题：
##   ① 先按模板改地形参数 → Terrain.generate()
##   ② 再用**新地形**建临时网格（判定水域/可通行）
##   ③ 才去挑起点、铺资源建筑
##   ④ 最后捕获地形到 doc + 校验
##
## 不直接写盘：调用方拿到 doc 之后自己决定保存还是先用编辑器打开。

const MapDoc = preload("res://scripts/mapformat/MapDoc.gd")
const MapTemplates = preload("res://scripts/mapgen/MapTemplates.gd")
const MapSymmetric = preload("res://scripts/mapgen/MapSymmetric.gd")
const MapValidator = preload("res://scripts/mapgen/MapValidator.gd")
const GridManagerScript = preload("res://scripts/core/GridManager.gd")

## 主入口。
## template: MapTemplates 里的一套（可以是 list() 出来的副本，改过参数也没关系）
## 返回 {
##   "ok": bool, "doc": MapDoc, "grid": GridManager, "report": Dictionary,
##   "text": String, "stats": {...}, "error": String
## }
static func generate(template: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var out: Dictionary = {"ok": false, "doc": null, "grid": null,
		"report": {}, "text": "", "stats": {}, "error": ""}
	if template.is_empty():
		out["error"] = "模板为空"
		return out
	if Terrain == null or Terrain.params == null:
		out["error"] = "Terrain 尚未初始化"
		return out

	var doc = MapDoc.new()
	doc.map_name = str(opts.get("map_name", template.get("name", "生成地图")))
	doc.grid_n = int(template.get("grid_n", 96))
	doc.cell_size = float(template.get("cell_size", 2.0))
	doc.author = str(opts.get("author", ""))

	# ① 地形参数 → 重新生成
	MapTemplates.apply_terrain_params(template, Terrain.params)
	# world_size 必须和网格严格对齐，否则 grid_to_world 会整体偏移
	var ws: float = float(doc.grid_n) * doc.cell_size
	Terrain.params.set("world_size", ws)
	# ★ 岛屿必须铺满整张网格并让边缘沉到水下。
	#   不设的话会在世界边界形成一圈"硬切菱形断崖"，外面直接是虚空 ——
	#   Main 的 random/seed/preset 分支都调了等价逻辑，唯独 custom 分支没有。
	Terrain.params.set("island_center_factor", 0.5)
	Terrain.params.set("island_radius", ws * 0.95)
	Terrain.params.set("heightmap_size", int(opts.get("heightmap_size", 256)))
	Terrain.params.set("biome_size", int(opts.get("biome_size", 256)))
	Terrain.generate(Terrain.params)

	var images: Dictionary = Terrain.export_images()
	var height: Image = images.get("height", null)
	var biome: Image = images.get("biome", null)
	if height == null:
		out["error"] = "地形生成失败（没有高度图）"
		return out

	# ② 用新地形建临时网格：水域 = 3，其余 0
	var grid = _build_grid(doc, height)
	out["grid"] = grid

	# ③ 挑起点 + 铺内容
	var gen: Dictionary = MapTemplates.generate_content(doc, grid, height, template, opts)
	out["stats"] = {
		"starts": gen.get("starts", []),
		"scatter": gen.get("scatter", {}),
		"bases": gen.get("bases", {}),
	}
	if gen.has("error"):
		out["error"] = str(gen["error"])

	# ④ 地形对称化（内容层已在 generate_content 里翻过）
	var mode: int = int(template.get("symmetry", -1))
	if mode >= 0 and bool(opts.get("symmetrize_terrain", true)):
		var px: int = MapSymmetric.apply_height(height, mode)
		if biome != null:
			MapSymmetric.apply_biome(biome, mode)
		# Image 是就地改的，但 ImageTexture 是拷贝 —— 不刷新的话
		# 「存盘的地图对称、屏幕上的还不对称」
		if Terrain.has_method("refresh_textures"):
			Terrain.refresh_textures()
		out["sym_pixels"] = px
		# 地形变了，水域边界跟着变 → 网格要重建一次，否则寻路会撞到"新出现的水"
		grid.free()
		grid = _build_grid(doc, height)
		out["grid"] = grid

	# ⑤ 把地形参数与两张图捕获进 doc
	# ⚠ 必须传 Terrain.**params**（MapParams 实例），不是 Terrain 节点本身 ——
	# 传节点的话 get_property_list() 拿不到那 28 个地形字段，terrain 字典会是空的，
	# 于是存盘的地图丢掉 world_size，重新载入时尺寸退回默认 200m（72 格变 100 格）。
	doc.capture_terrain_from(Terrain.params)

	# ⑥ 校验
	var rep: Dictionary = MapValidator.validate(doc, grid)
	out["doc"] = doc
	out["report"] = rep
	out["text"] = MapValidator.report(rep)
	out["ok"] = bool(rep["ok"])
	if not out["ok"]:
		out["error"] = "校验未通过（%d 个错误）" % int(rep["errors"])
	return out

## 按 doc 的尺寸建一张网格，水域用 Terrain 现算。
static func _build_grid(doc, height: Image):
	var g = GridManagerScript.new()
	g.map_size = Vector2i(int(doc.grid_n), int(doc.grid_n))
	g.cell_size = float(doc.cell_size)
	g.origin = Vector3.ZERO
	# 不用 _init_grid()：它读 Terrain.is_water，而我们可能刚把高度图对称化过，
	# Terrain 的内部图还未刷新，会拿到旧水域。直接按 height 图算，保证一致。
	g.occupied = []
	var n: int = int(doc.grid_n)
	var hw: int = height.get_width() if height != null else 0
	var hh: int = height.get_height() if height != null else 0
	var water_y: float = float(Terrain.params.get("water_level")) if Terrain != null and Terrain.params != null else -2.0
	for x in range(n):
		var col: Array = []
		for z in range(n):
			var val: int = 0
			if hw > 0 and hh > 0:
				var hx: int = clampi(int((float(x) + 0.5) / float(n) * float(hw)), 0, hw - 1)
				var hz: int = clampi(int((float(z) + 0.5) / float(n) * float(hh)), 0, hh - 1)
				if height.get_pixel(hx, hz).r <= water_y:
					val = 3
			col.append(val)
		g.occupied.append(col)
	return g

## 便捷：直接生成并存盘。返回 { ok, map_name, path, text, error }
static func generate_and_save(template: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var MapIO = load("res://scripts/mapformat/MapIO.gd")
	var r: Dictionary = generate(template, opts)
	var out: Dictionary = {"ok": false, "map_name": str(opts.get("map_name", "")),
		"text": r.get("text", ""), "error": str(r.get("error", ""))}
	if not r["ok"]:
		return out
	var doc = r["doc"]
	var images: Dictionary = Terrain.export_images()
	var saved: bool = MapIO.save(doc, images.get("height"), images.get("biome"))
	out["ok"] = saved
	out["map_name"] = str(doc.map_name)
	if not saved:
		out["error"] = "存盘失败"
	if r["grid"] != null and is_instance_valid(r["grid"]):
		r["grid"].free()
	return out
