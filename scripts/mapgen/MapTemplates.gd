extends RefCounted
## MapTemplates —— 5 套开箱可玩的地图模板
##
## 模板只负责「参数」，不负责「生成」：
##   地形参数写进 MapParams，起点与内容交给 StartPlacer / MapScatter。
##   这样模板可以只改数值、不动逻辑 —— 加第 6 套模板不需要碰生成管线。
##
## 每套都带对称模式，因为 RTS 的公平性只有两种来源：
##   「结构性对称」或者「数值上近似」。这里统一选前者。

const MapSymmetric = preload("res://scripts/mapgen/MapSymmetric.gd")
const MapScatter = preload("res://scripts/mapgen/MapScatter.gd")
const StartPlacer = preload("res://scripts/mapgen/StartPlacer.gd")

const TEMPLATES: Array = [
	{
		"id": "three_kingdoms",
		"name": "三分天下",
		"desc": "三方鼎立的中原大地。河流横贯，各自腹地开阔，中路的富矿是唯一的死斗点。",
		"players": 3,
		"grid_n": 96,
		"cell_size": 2.0,
		"symmetry": MapSymmetric.Mode.POINT,
		"min_start_dist": 30,
		"terrain": {
			"seed": 20261024, "max_height": 16.0, "water_level": -2.0,
			"noise_frequency": 0.017, "noise_octaves": 5,
			"base_height": 0.16, "height_scale": 0.05,
			"river_count": 1, "river_width": 7.0, "river_depth": 0.85,
			"lake_count": 1, "lake_radius": 18.0,
			"forest_density": 1.0, "stone_density": 1.0,
		},
		"scatter": {"neutral_resources": 6, "villages": 3, "horses": 4},
	},
	{
		"id": "two_kingdoms",
		"name": "双雄争霸",
		"desc": "隔河对峙的经典 1v1。地形镜像对称，比的是运营不是运气。",
		"players": 2,
		"grid_n": 84,
		"cell_size": 2.0,
		"symmetry": MapSymmetric.Mode.MIRROR_Z,
		"min_start_dist": 36,
		"terrain": {
			"seed": 777001, "max_height": 15.0, "water_level": -2.0,
			"noise_frequency": 0.019, "noise_octaves": 5,
			"base_height": 0.14, "height_scale": 0.05,
			"river_count": 1, "river_width": 9.0, "river_depth": 0.95,
			"lake_count": 0,
			"forest_density": 1.1, "stone_density": 0.9,
		},
		"scatter": {"neutral_resources": 4, "villages": 2, "horses": 3},
	},
	{
		"id": "four_warlords",
		"name": "四方割据",
		"desc": "四家分踞四角的旋转对称图。中盘是四条通向中心的走廊，谁卡住路口谁赢。",
		"players": 4,
		"grid_n": 100,
		"cell_size": 2.0,
		"symmetry": MapSymmetric.Mode.ROTATE_90,
		"min_start_dist": 34,
		"terrain": {
			"seed": 409600, "max_height": 18.0, "water_level": -2.0,
			"noise_frequency": 0.016, "noise_octaves": 6,
			"base_height": 0.15, "height_scale": 0.06,
			"river_count": 2, "river_width": 6.0, "river_depth": 0.8,
			"lake_count": 2, "lake_radius": 14.0,
			"forest_density": 0.9, "stone_density": 1.2,
		},
		"scatter": {"neutral_resources": 8, "villages": 4, "horses": 6},
	},
	{
		"id": "central_prize",
		"name": "中原逐鹿",
		"desc": "两家的距离被刻意拉近，中央放一座超量富矿。要么抢矿，要么偷家。",
		"players": 2,
		"grid_n": 88,
		"cell_size": 2.0,
		"symmetry": MapSymmetric.Mode.POINT,
		"min_start_dist": 28,
		"terrain": {
			"seed": 20260808, "max_height": 14.0, "water_level": -2.0,
			"noise_frequency": 0.020, "noise_octaves": 4,
			"base_height": 0.18, "height_scale": 0.05,
			"river_count": 1, "river_width": 5.0, "river_depth": 0.7,
			"lake_count": 0,
			"forest_density": 0.8, "stone_density": 1.0,
		},
		"scatter": {"neutral_resources": 10, "villages": 2, "horses": 2},
	},
	{
		"id": "warlord_rush",
		"name": "群雄并起",
		"desc": "8 人小图快攻。资源紧、距离近，5 分钟内必接战。练微操用的。",
		"players": 8,
		"grid_n": 76,
		"cell_size": 2.0,
		"symmetry": MapSymmetric.Mode.ROTATE_90,
		"min_start_dist": 20,
		"terrain": {
			"seed": 888888, "max_height": 12.0, "water_level": -2.0,
			"noise_frequency": 0.022, "noise_octaves": 4,
			"base_height": 0.20, "height_scale": 0.05,
			"river_count": 0, "river_width": 5.0, "river_depth": 0.6,
			"lake_count": 1, "lake_radius": 10.0,
			"forest_density": 0.7, "stone_density": 1.3,
		},
		"scatter": {"neutral_resources": 6, "villages": 1, "horses": 4},
	},
]

## 全部模板（浅拷贝，调用方改不动原始常量）
static func list() -> Array:
	var out: Array = []
	for t in TEMPLATES:
		out.append(t.duplicate(true))
	return out

static func template_def(id: String) -> Dictionary:
	for t in TEMPLATES:
		if str(t.get("id", "")) == id:
			return t.duplicate(true)
	return {}

static func default_template() -> Dictionary:
	return TEMPLATES[0].duplicate(true)

## 把模板的地形参数写进 MapParams 实例。只覆盖模板里出现过的字段，
## 其余保持用户原值 —— 否则模板会悄悄清掉用户手调过的参数。
static func apply_terrain_params(template: Dictionary, params) -> int:
	if params == null:
		return 0
	var t: Dictionary = template.get("terrain", {})
	var applied: int = 0
	for k in t.keys():
		if k in params:
			params.set(str(k), t[k])
			applied += 1
	var g: int = int(template.get("grid_n", 0))
	if g > 0 and "world_size" in params:
		# world_size 必须等于 grid_n * cell_size，这条契约不能破
		params.set("world_size", float(g) * float(template.get("cell_size", 2.0)))
		applied += 1
	return applied

## 只生成"内容层"（起点 + 资源 + 装饰 + 开局基地），不碰地形。
## 地形由调用方（向导）先按 apply_terrain_params 重新生成。
##
## 返回 { "starts": [...], "scatter": {...}, "bases": {...} }
static func generate_content(doc, grid, height: Image, template: Dictionary,
		opts: Dictionary = {}) -> Dictionary:
	var out: Dictionary = {"starts": [], "scatter": {}, "bases": {}}
	if doc == null or grid == null:
		return out

	var n_players: int = int(template.get("players", 2))
	var min_dist: int = int(template.get("min_start_dist", 28))
	var mode: int = int(template.get("symmetry", MapSymmetric.Mode.POINT))

	# 先丢掉上一次生成的玩家与内容层，避免叠加
	doc.players = []
	var keep: Array = []
	for o in doc.objects:
		# 保留用户手摆的装饰（deco），其余重新生成
		if typeof(o) == TYPE_DICTIONARY and str(o.get("kind", "")) == "deco":
			keep.append(o)
	doc.objects = keep

	# ★ 用对称选点：只挑基点，其余由轨道翻出来。
	# 独立挑 N 个点看起来更灵活，但会让地图正中的中立富矿到各家距离不等。
	var starts: Array = StartPlacer.pick_symmetric(grid, height, n_players, mode, min_dist, [])
	if starts.size() < n_players:
		out["error"] = "只找到 %d 个合格起点（需要 %d），建议放宽最小间距或调整地形" % [
			starts.size(), n_players]
	# 写进 doc.players
	for s in starts:
		doc.set_player(int(s["slot"]), {
			"slot": int(s["slot"]),
			"faction": str(["shu", "wei", "wu", "qun"][int(s["slot"]) % 4]),
			"start": s["start"],
		})
	out["starts"] = starts

	var start_pts: Array = []
	for s2 in starts:
		start_pts.append(Vector2i(int(s2["start"][0]), int(s2["start"][1])))

	# 先摆基地，再撒资源 —— 反过来会让资源占掉官府的位置
	var base_opts: Dictionary = opts.duplicate(true)
	base_opts["factions"] = ["shu", "wei", "wu", "qun"]
	out["bases"] = MapScatter.place_start_bases(doc, grid, start_pts, base_opts, height)

	var sc_opts: Dictionary = template.get("scatter", {}).duplicate(true)
	for k in opts.keys():
		sc_opts[k] = opts[k]
	out["scatter"] = MapScatter.scatter_all(doc, grid, start_pts, sc_opts)

	# 按模板的对称模式把刚生成的内容翻一遍，保证两侧完全一致。
	# 注意：起点本身已经由 pick_symmetric 对称好了，这里补的是
	# 资源/建筑/装饰这些"跟着起点走但排布随机"的东西。
	if mode >= 0:
		var owner_map: Dictionary = {}
		# 点对称/镜像时 0↔1 对调最自然（shu 的镜像归 wei）
		owner_map["shu"] = "wei"
		owner_map["wei"] = "shu"
		MapSymmetric.apply_objects(doc, mode, owner_map, ["unit"])
	out["symmetry"] = mode
	doc.touch()
	return out
