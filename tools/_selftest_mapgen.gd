extends Node3D
## M4 生成器三件套自测：MapSymmetric / StartPlacer / MapValidator
##
## 为什么这套必须存在：这三个模块的输出直接决定"能不能开局"，
## 而它们的共同特点是「看起来对、实际全错」——对称差 1 格、起点少 1 个、
## 校验漏报一项，都不会崩，只会让玩家玩到一张废图。
## 所以每条都做数值断言，不靠肉眼。

const MapDoc = preload("res://scripts/mapformat/MapDoc.gd")
const MapSymmetric = preload("res://scripts/mapgen/MapSymmetric.gd")
const StartPlacer = preload("res://scripts/mapgen/StartPlacer.gd")
const MapValidator = preload("res://scripts/mapgen/MapValidator.gd")
const MapScatter = preload("res://scripts/mapgen/MapScatter.gd")
const MapTemplates = preload("res://scripts/mapgen/MapTemplates.gd")
const GridManagerScript = preload("res://scripts/core/GridManager.gd")

var _pass: int = 0
var _fail: int = 0
var _grid = null

func check(ok: bool, what: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		print("[MAPGEN] ❌ ", what)

func _ready() -> void:
	_make_grid()
	_test_mirror_math()
	_test_height_symmetry()
	_test_object_symmetry()
	_test_start_placer()
	_test_validator_good()
	_test_validator_bad()
	_test_scatter_fairness()
	_test_templates_end_to_end()
	print("[SELFTEST] %d 项检查，%d 项失败" % [_pass + _fail, _fail])
	if _fail == 0:
		print("[SELFTEST] ✅ 地图生成器全套通过")
	else:
		print("[SELFTEST] ❌ 有 %d 项失败" % _fail)
	if _grid != null and is_instance_valid(_grid):
		_grid.free()
	get_tree().quit(1 if _fail > 0 else 0)

## 手搓一个 40×40 纯空地网格。
## 不走 GridManager._init_grid()：那个会去问 Terrain.is_water()，
## 单元测试不该被全局地形状态牵着走。
func _make_grid() -> void:
	_grid = GridManagerScript.new()
	_grid.map_size = Vector2i(40, 40)
	_grid.cell_size = 2.0
	_grid.occupied = []
	for x in range(40):
		var col: Array = []
		for z in range(40):
			col.append(0)
		_grid.occupied.append(col)
	# 在中间挖一条水域竖带 x=19..20，用来测"起点避开水面"
	for z in range(40):
		for x in range(19, 21):
			_grid.occupied[x][z] = 3

# ------------------------------------------------------------------ 1 镜像公式

func _test_mirror_math() -> void:
	var n: int = 8
	check(MapSymmetric.mirror(Vector2i(0, 0), n, MapSymmetric.Mode.POINT) == Vector2i(7, 7),
		"点对称 (0,0)→(7,7)")
	check(MapSymmetric.mirror(Vector2i(0, 0), n, MapSymmetric.Mode.MIRROR_X) == Vector2i(0, 7),
		"X 轴镜像 (0,0)→(0,7)")
	check(MapSymmetric.mirror(Vector2i(0, 0), n, MapSymmetric.Mode.MIRROR_Z) == Vector2i(7, 0),
		"Z 轴镜像 (0,0)→(7,0)")
	check(MapSymmetric.mirror(Vector2i(2, 5), n, MapSymmetric.Mode.ROTATE_90) == Vector2i(5, 5),
		"旋转 90° (2,5)→(5,5)")
	# 镜像的阶：点对称/两种镜像 = 2 阶（做两次回原点）；旋转 90° = 4 阶
	var ok_inv: bool = true
	for m in range(4):
		var order: int = 4 if m == MapSymmetric.Mode.ROTATE_90 else 2
		for x in range(n):
			for y in range(n):
				var p := Vector2i(x, y)
				var q := p
				for _i in range(order):
					q = MapSymmetric.mirror(q, n, m)
				if q != p:
					ok_inv = false
	check(ok_inv, "镜像按各自阶数（2/4 阶）作用后回到原点")
	# 主侧判定：每条轨道上恰好一个点 is_primary
	var pair_ok: bool = true
	for m in range(4):
		for x in range(n):
			for y in range(n):
				var p2 := Vector2i(x, y)
				var orb: Array = MapSymmetric.orbit(p2, n, n, m)
				var cnt: int = 0
				for q2 in orb:
					if MapSymmetric.is_primary(q2, n, n, m):
						cnt += 1
				if cnt != 1:
					pair_ok = false
	check(pair_ok, "每条对称轨道里恰好一个点被判定为主侧")

# ------------------------------------------------------------------ 2 高度图对称

func _test_height_symmetry() -> void:
	for m in range(4):
		var img: Image = _make_bumpy(64, 64)
		var touched: int = MapSymmetric.apply_height(img, m)
		check(touched > 0, "%s：改写了 %d 个像素" % [MapSymmetric.mode_name(m), touched])
		# 严格检查：同一轨道上的点 r 通道完全相等
		var worst: float = 0.0
		for y in range(64):
			for x in range(64):
				var src: Vector2i = MapSymmetric.primary_of(Vector2i(x, y), 64, 64, m)
				var d: float = absf(img.get_pixel(x, y).r - img.get_pixel(src.x, src.y).r)
				worst = maxf(worst, d)
		check(worst < 0.0001, "%s：对称后最大高度差 %.6f m" % [MapSymmetric.mode_name(m), worst])

## 造一张有起伏的高度图（正弦 + 随机，保证左右不天然对称）
func _make_bumpy(w: int, h: int) -> Image:
	var img: Image = Image.create(w, h, false, Image.FORMAT_RF)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for y in range(h):
		for x in range(w):
			var v: float = sin(float(x) * 0.21) * 1.7 + cos(float(y) * 0.13) * 1.1
			v += rng.randf_range(-0.4, 0.4)
			img.set_pixel(x, y, Color(v, 0.0, 0.0, 1.0))
	return img

# ------------------------------------------------------------------ 3 对象对称

func _test_object_symmetry() -> void:
	var doc = MapDoc.new()
	doc.grid_n = 20
	doc.cell_size = 2.0
	# 3 个非中线对象 + 1 个中线对象（中线的不该被复制）
	doc.add_object({"kind": "building", "id": "government", "owner": "wei", "grid": [2, 3]})
	doc.add_object({"kind": "unit", "id": "sword", "owner": "wei", "grid": [4, 5]})
	doc.add_object({"kind": "resource", "id": "wood", "grid": [1, 7], "amount": 900})
	doc.add_object({"kind": "resource", "id": "iron", "grid": [9, 9], "amount": 500})
	var n0: int = doc.objects.size()
	var added: Array = MapSymmetric.apply_objects(doc, MapSymmetric.Mode.POINT,
		{"wei": "shu"}, ["deco"])
	check(added.size() == 4, "4 个对象镜像出 4 个副本（实际 %d）" % added.size())
	check(doc.objects.size() == n0 + 4, "对象总数 %d → %d" % [n0, doc.objects.size()])
	# 中线对象 (9,9) 在 20 格里点对称 → (10,10)，不是自身，所以也会被复制
	var has_shu: bool = false
	var iron_cnt: int = 0
	for o in doc.objects:
		if str(o.get("owner", "")) == "shu":
			has_shu = true
		if str(o.get("id", "")) == "iron":
			iron_cnt += 1
	check(has_shu, "owner_map 生效（wei 的副本归 shu）")
	check(iron_cnt == 2, "资源点也被复制，保证双方资源量一致（iron %d 个）" % iron_cnt)
	# 资源 amount 必须跟着复制，否则"看着对称实际不公平"
	for o in doc.objects:
		if str(o.get("id", "")) == "wood":
			check(int(o.get("amount", 0)) == 900, "资源量随副本一起复制（amount=900）")
			break

	# 装饰走世界坐标，也要能镜像
	var doc2 = MapDoc.new()
	doc2.grid_n = 20
	doc2.cell_size = 2.0
	doc2.add_object({"kind": "deco", "id": "tree_2", "pos": [5.0, 9.0], "scale": 1.2, "rot": 0})
	var added2: Array = MapSymmetric.apply_objects(doc2, MapSymmetric.Mode.POINT)
	check(added2.size() == 1, "装饰能被镜像（%d 个）" % added2.size())
	if added2.size() == 1:
		# 格 (2,4) 点对称 → (17,15)，中心 → 世界 (35.0, 31.0)
		var pos: Array = added2[0]["pos"]
		check(absf(float(pos[0]) - 35.0) < 0.01 and absf(float(pos[1]) - 31.0) < 0.01,
			"装饰镜像位置正确 (35.0, 31.0)，实际 %s" % str(pos))

# ------------------------------------------------------------------ 4 起点选址

func _test_start_placer() -> void:
	var img: Image = _make_bumpy(64, 64)
	# 给一点资源点，测资源加权不炸
	var res_cells: Array = [Vector2i(10, 10), Vector2i(30, 30)]
	var picked: Array = StartPlacer.pick(_grid, img, 2, 14, res_cells)
	check(picked.size() == 2, "40×40 图上选出 2 个起点（实际 %d）" % picked.size())
	if picked.size() == 2:
		var a := Vector2i(picked[0]["start"][0], picked[0]["start"][1])
		var b := Vector2i(picked[1]["start"][0], picked[1]["start"][1])
		var d: float = Vector2(float(a.x - b.x), float(a.y - b.y)).length()
		check(d >= 14.0, "两起点间距 %.1f ≥ 14" % d)
		check(_grid.is_walkable(a), "起点 A %s 可站立" % str(a))
		check(_grid.is_walkable(b), "起点 B %s 可站立" % str(b))
		# 不能落在中间那条水带里
		check(a.x < 19 or a.x > 20, "起点 A 避开水域（x=%d）" % a.x)
		check(b.x < 19 or b.x > 20, "起点 B 避开水域（x=%d）" % b.x)
		check(float(picked[0]["score"]) >= float(picked[1]["score"]),
			"结果按分数降序（%.1f ≥ %.1f）" % [float(picked[0]["score"]), float(picked[1]["score"])])

	# 4 个玩家：40×40 上间距要求 14 很紧，验证能选满或至少不崩
	var picked4: Array = StartPlacer.pick(_grid, img, 4, 12, res_cells)
	check(picked4.size() >= 2, "4 玩家请求至少选出 2 个（实际 %d）" % picked4.size())
	var all_far: bool = true
	for i in range(picked4.size()):
		for j in range(i + 1, picked4.size()):
			var p := Vector2i(picked4[i]["start"][0], picked4[i]["start"][1])
			var q := Vector2i(picked4[j]["start"][0], picked4[j]["start"][1])
			if Vector2(float(p.x - q.x), float(p.y - q.y)).length() < 12.0:
				all_far = false
	check(all_far, "多起点之间都满足最小间距")

# ------------------------------------------------------------------ 5 校验：合法图

func _test_validator_good() -> void:
	var doc = _make_good_doc()
	var rep: Dictionary = MapValidator.validate(doc, _grid)
	check(bool(rep["ok"]), "合法地图校验通过（错误 %d）" % int(rep["errors"]))
	check(rep["results"].size() == 7, "跑满 7 项检查（实际 %d）" % rep["results"].size())
	# 打印一次报告，方便人工扫一眼
	print("[MAPGEN] 合法图报告：\n" + MapValidator.report(rep))

func _make_good_doc():
	var doc = MapDoc.new()
	doc.map_name = "validator_good"
	doc.grid_n = 40
	doc.cell_size = 2.0
	# 两个起点，间距 24 格，都在空地上，避开中间水带
	doc.set_player(0, {"slot": 0, "faction": "shu", "start": [6, 6]})
	doc.set_player(1, {"slot": 1, "faction": "wei", "start": [30, 30]})
	# 每人两个资源点，各自附近 → 资源均衡
	doc.add_object({"kind": "resource", "id": "wood", "grid": [8, 8], "amount": 900})
	doc.add_object({"kind": "resource", "id": "iron", "grid": [10, 5], "amount": 800})
	doc.add_object({"kind": "resource", "id": "wood", "grid": [32, 32], "amount": 900})
	doc.add_object({"kind": "resource", "id": "iron", "grid": [30, 28], "amount": 800})
	doc.add_object({"kind": "building", "id": "government", "owner": "shu", "grid": [5, 5]})
	doc.add_object({"kind": "building", "id": "government", "owner": "wei", "grid": [29, 29]})
	return doc

# ------------------------------------------------------------------ 6 校验：坏图逐项报错

func _test_validator_bad() -> void:
	# ① 起点贴脸
	var d1 = _make_good_doc()
	d1.set_player(1, {"slot": 1, "faction": "wei", "start": [10, 10]})
	var r1: Dictionary = MapValidator.validate(d1, _grid)
	check(_has_failed(r1, "start_dist"), "起点贴脸时 start_dist 报错")

	# ② 起点数量不足
	var d2 = _make_good_doc()
	d2.set_player(2, {"slot": 2, "faction": "wu"})   # 第 3 个玩家没有 start
	var r2: Dictionary = MapValidator.validate(d2, _grid)
	check(_has_failed(r2, "start_count"), "玩家比起点多时 start_count 报错")

	# ③ 起点落在水里
	var d3 = _make_good_doc()
	d3.set_player(0, {"slot": 0, "faction": "shu", "start": [19, 20]})
	var r3: Dictionary = MapValidator.validate(d3, _grid)
	check(_has_failed(r3, "start_stand"), "起点在水里时 start_stand 报错")

	# ④ 对象越界
	var d4 = _make_good_doc()
	d4.add_object({"kind": "building", "id": "house", "grid": [999, 3]})
	var r4: Dictionary = MapValidator.validate(d4, _grid)
	check(_has_failed(r4, "in_bounds"), "对象越界时 in_bounds 报错")

	# ⑤ 没有资源
	var d5 = _make_good_doc()
	var kept: Array = []
	for o in d5.objects:
		if str(o.get("kind", "")) != "resource":
			kept.append(o)
	d5.objects = kept
	var r5: Dictionary = MapValidator.validate(d5, _grid)
	check(_has_failed(r5, "res_balance"), "无资源点时 res_balance 报警告")

	# ⑥ 资源严重不均：全堆在 shu 家门口
	var d6 = _make_good_doc()
	d6.objects = []
	d6.add_object({"kind": "resource", "id": "wood", "grid": [7, 7], "amount": 9000})
	d6.add_object({"kind": "resource", "id": "wood", "grid": [8, 6], "amount": 9000})
	var r6: Dictionary = MapValidator.validate(d6, _grid)
	check(_has_failed(r6, "res_balance"), "资源全在一家附近时 res_balance 报警告")

	# ⑦ 实体重叠
	var d7 = _make_good_doc()
	d7.add_object({"kind": "building", "id": "house", "grid": [5, 5]})   # 和官府同格
	var r7: Dictionary = MapValidator.validate(d7, _grid)
	check(_has_failed(r7, "overlap"), "建筑叠在同一格时 overlap 报警告")

	# ⑧ doc 为空
	var r8: Dictionary = MapValidator.validate(null, _grid)
	check(not bool(r8["ok"]), "doc 为空时整体不通过")

func _has_failed(rep: Dictionary, id: String) -> bool:
	for r in rep.get("results", []):
		if str(r["id"]) == id:
			return not bool(r["ok"])
	return false

# ------------------------------------------------------------------ 7 铺设公平性

func _test_scatter_fairness() -> void:
	# 60×60 上跑：小图里中立富矿必然落进某家的专属半径，测不出问题
	var g = _fresh_grid(60, 60)
	var doc = MapDoc.new()
	doc.grid_n = 60
	doc.cell_size = 2.0
	var starts: Array = [Vector2i(10, 10), Vector2i(49, 49)]
	var stats: Dictionary = MapScatter.scatter_all(doc, g, starts, {
		"neutral_resources": 2, "trees": 20, "villages": 1, "horses": 2, "seed": 12345,
	})
	check(int(stats["resources"]) == 10, "两个起点各 5 个资源点，共 10（实际 %d）" % int(stats["resources"]))
	check(int(stats["trees"]) == 20, "树铺了 20 棵（实际 %d）" % int(stats["trees"]))
	check(doc.count_by_kind("resource") == 10 + 2, "资源点总数含中立富矿 = 12（实际 %d）" % doc.count_by_kind("resource"))

	# 公平性：只比"专属家底"（起点 20 格内的资源）。
	# 地图正中的中立富矿对两家近似等距，算进来只会让"最近起点归属"决定结果，
	# 那是测量误差不是真实差距。
	var sphere: float = 20.0
	var totals: Array = [0, 0]
	var counted: int = 0
	for o in doc.objects:
		if str(o.get("kind", "")) != "resource":
			continue
		var gg: Array = o["grid"]
		var p := Vector2i(int(gg[0]), int(gg[1]))
		var d0: float = Vector2(float(p.x - 10), float(p.y - 10)).length()
		var d1: float = Vector2(float(p.x - 49), float(p.y - 49)).length()
		var near: float = minf(d0, d1)
		if near > sphere:
			continue   # 中立资源，不计入
		totals[0 if d0 <= d1 else 1] += int(o.get("amount", 1))
		counted += 1
	check(counted == 10, "两个起点 20 格内共 10 个专属资源（实际 %d）" % counted)
	var gap_ratio: float = absf(float(totals[0] - totals[1])) / float(maxi(maxi(totals[0], totals[1]), 1))
	check(gap_ratio <= 0.05, "两家专属资源完全同构，差 %.0f%% ≤ 5%%（shu %d / wei %d）" % [
		gap_ratio * 100.0, totals[0], totals[1]])

	# 资源不能压在起点脚下（空区半径 4）
	var too_close: bool = false
	for o2 in doc.objects:
		if str(o2.get("kind", "")) != "resource":
			continue
		var g2: Array = o2["grid"]
		var p2 := Vector2i(int(g2[0]), int(g2[1]))
		for s in starts:
			if absi(p2.x - s.x) + absi(p2.y - s.y) <= 2:
				too_close = true
	check(not too_close, "资源没撒在起点脚下（空区生效）")

	# 基地铺设：官府必须真的放下去
	var doc2 = MapDoc.new()
	doc2.grid_n = 60
	doc2.cell_size = 2.0
	var g2b = _fresh_grid(60, 60)
	var base_stats: Dictionary = MapScatter.place_start_bases(doc2, g2b, [Vector2i(15, 15), Vector2i(45, 45)], {})
	check(int(base_stats["bases"]) == 2, "两个基地都放下了（%d）" % int(base_stats["bases"]))
	check(doc2.count_by_kind("building") == 6, "每基地 1 官府 + 2 民居 = 6 栋（实际 %d）" % doc2.count_by_kind("building"))
	check(doc2.count_by_kind("unit") == 8, "每基地 4 个开局单位 = 8（实际 %d）" % doc2.count_by_kind("unit"))
	g2b.free()
	g.free()

	# 对称选点：2 人点对称，两点必须互为镜像
	var g3 = _fresh_grid(60, 60)
	var img3: Image = _make_bumpy(80, 80)
	var sym2: Array = StartPlacer.pick_symmetric(g3, img3, 2, MapSymmetric.Mode.POINT, 20, [])
	check(sym2.size() == 2, "对称选点给出 2 个起点（实际 %d）" % sym2.size())
	if sym2.size() == 2:
		var a := Vector2i(int(sym2[0]["start"][0]), int(sym2[0]["start"][1]))
		var b := Vector2i(int(sym2[1]["start"][0]), int(sym2[1]["start"][1]))
		check(b == MapSymmetric.mirror(a, 60, MapSymmetric.Mode.POINT),
			"两个起点严格互为点对称 %s ↔ %s" % [str(a), str(b)])
	# 4 人旋转对称：四个点必须在同一条 4 阶轨道上
	var sym4: Array = StartPlacer.pick_symmetric(g3, img3, 4, MapSymmetric.Mode.ROTATE_90, 14, [])
	check(sym4.size() == 4, "旋转对称给出 4 个起点（实际 %d）" % sym4.size())
	if sym4.size() == 4:
		var a4 := Vector2i(int(sym4[0]["start"][0]), int(sym4[0]["start"][1]))
		var orb: Array = MapSymmetric.orbit(a4, 60, 60, MapSymmetric.Mode.ROTATE_90)
		var all_in: bool = true
		for s4 in sym4:
			var q := Vector2i(int(s4["start"][0]), int(s4["start"][1]))
			if not orb.has(q):
				all_in = false
		check(all_in, "四个起点同属一条旋转轨道（几何上完全等价）")
	g3.free()

func _fresh_grid(w: int, h: int):
	var g = GridManagerScript.new()
	g.map_size = Vector2i(w, h)
	g.cell_size = 2.0
	g.occupied = []
	for x in range(w):
		var col: Array = []
		for z in range(h):
			col.append(0)
		g.occupied.append(col)
	return g

# ------------------------------------------------------------------ 8 模板端到端

func _test_templates_end_to_end() -> void:
	var all: Array = MapTemplates.list()
	check(all.size() == 5, "内置 5 套模板（实际 %d）" % all.size())
	var ids: Dictionary = {}
	for t in all:
		ids[str(t.get("id", ""))] = true
		check(int(t.get("players", 0)) >= 2, "%s 至少 2 名玩家" % str(t.get("name", "?")))
		check(t.has("terrain") and t.has("scatter"), "%s 同时带地形与铺设参数" % str(t.get("name", "?")))
		check(t.get("symmetry") != null, "%s 指定了对称模式" % str(t.get("name", "?")))
	check(ids.size() == 5, "5 套模板 id 互不重复")

	# 拿一套真正跑一遍：2 人镜像图，用接近真实尺寸的 76×76
	var tpl: Dictionary = MapTemplates.template_def("two_kingdoms")
	check(not tpl.is_empty(), "能按 id 取到 two_kingdoms")
	tpl["grid_n"] = 76
	tpl["min_start_dist"] = 20
	tpl["players"] = 2

	var g = _fresh_grid(76, 76)
	var doc = MapDoc.new()
	doc.grid_n = 76
	doc.cell_size = 2.0
	var img: Image = _make_bumpy(96, 96)
	var res: Dictionary = MapTemplates.generate_content(doc, g, img, tpl, {"trees": 15})
	check(int(res["starts"].size()) == 2, "模板生成 2 个起点（实际 %d）" % int(res["starts"].size()))
	check(doc.players.size() == 2, "doc.players 写了 2 条（实际 %d）" % doc.players.size())
	check(doc.count_by_kind("building") >= 4, "生成了建筑（%d 栋）" % doc.count_by_kind("building"))
	check(doc.count_by_kind("resource") > 0, "生成了资源点（%d 个）" % doc.count_by_kind("resource"))

	# 生成出来的图必须能过校验（起码头两项不能报 error）
	var rep: Dictionary = MapValidator.validate(doc, g)
	print("[MAPGEN] 模板 two_kingdoms 端到端报告：\n" + MapValidator.report(rep))
	check(bool(rep["ok"]), "模板生成的图通过校验（错误 %d）" % int(rep["errors"]))
	g.free()

	# apply_terrain_params 只覆盖模板声明过的字段
	var P = load("res://scripts/core/MapParams.gd").new()
	P.set("noise_octaves", 9)
	var applied: int = MapTemplates.apply_terrain_params(tpl, P)
	check(applied > 0, "地形参数写入了 %d 项" % applied)
	check(int(P.get("noise_octaves")) == 5, "模板覆盖了 noise_octaves（9→5，实际 %d）" % int(P.get("noise_octaves")))
	check(absf(float(P.get("world_size")) - 152.0) < 0.01,
		"world_size = grid_n × cell_size = 152（实际 %.1f）" % float(P.get("world_size")))
	P = null
