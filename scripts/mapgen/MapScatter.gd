extends RefCounted
## MapScatter —— 资源 / 树 / 村庄 / 野马的铺设
##
## 公平性靠的是「结构」不是「运气」：
##   每个起点周围用的是**同一张角度表 + 同一组距离**，只是绕着自己的起点转。
##   所以谁的矿在哪，谁的林在哪，几何上完全同构 —— 不需要事后比总量。
##
## 与 MapSymmetric 的分工：
##   MapSymmetric 负责「地形和已有对象整体翻面」；
##   MapScatter 负责「从零铺内容」，它自己已经保证各起点同构，
##   所以调用方可以用对称也可以不用，都不影响公平性。

const ANGLES: Array = [0.0, 45.0, 90.0, 135.0, 180.0, 225.0, 270.0, 315.0]

## 每个起点脚下必备的资源。dist 是格数，count 是份数。
## 数值参考傲世三国：开局两木两粮一石，够撑过第一波。
const DEFAULT_RES_PLAN: Array = [
	{"id": "wood", "amount": 900, "dist": 7, "count": 2},
	{"id": "food", "amount": 1200, "dist": 10, "count": 2},
	{"id": "stone", "amount": 800, "dist": 9, "count": 1},
]

## 起点周围留空半径：这里什么都不撒，否则官府放不下
const KEEP_CLEAR: int = 4

# ---------------------------------------------------------------- 坡度工具

## 半径 r 的搜索偏移。r=0 只返回原地，r>0 返回 8 个方向。
static func _offset_ring(r: int) -> Array:
	if r <= 0:
		return [Vector2i.ZERO]
	return [
		Vector2i(r, 0), Vector2i(-r, 0), Vector2i(0, r), Vector2i(0, -r),
		Vector2i(r, r), Vector2i(-r, r), Vector2i(r, -r), Vector2i(-r, -r),
	]

## 以 grid 坐标 pos 为左上角、size 为范围，量这段平台的最大高差（米）。
## 用来判断"这块地够不够平"，光靠 GridManager 的占位是看不出来的。
static func _relief_of(height: Image, grid, pos: Vector2i, size: Vector2i) -> float:
	if height == null or grid == null:
		return 0.0
	var n: int = int(grid.map_size.x)
	if n <= 0:
		return 0.0
	var hw: int = height.get_width()
	var hh: int = height.get_height()
	var hmin: float = 99999.0
	var hmax: float = -99999.0
	for dx in range(size.x):
		for dz in range(size.y):
			var gx: int = pos.x + dx
			var gz: int = pos.y + dz
			if gx < 0 or gz < 0 or gx >= n or gz >= n:
				continue
			var hx: int = clampi(int((float(gx) + 0.5) / float(n) * float(hw)), 0, hw - 1)
			var hz: int = clampi(int((float(gz) + 0.5) / float(n) * float(hh)), 0, hh - 1)
			var h: float = height.get_pixel(hx, hz).r
			hmin = minf(hmin, h)
			hmax = maxf(hmax, h)
	if hmax < hmin:
		return 0.0
	return hmax - hmin

# ---------------------------------------------------------------- 工具

## 在 center 周围 radius±2 的环上，按 angles 表找可用格。
## 返回实际找到的格（可能少于 count）。
static func _ring_cells(grid, center: Vector2i, radius: int, count: int,
		used: Dictionary, angle_start: int = 0) -> Array:
	var out: Array = []
	if grid == null or count <= 0:
		return out
	var n: int = int(grid.map_size.x)
	for i in range(ANGLES.size() * 2):     # 最多绕两圈，找够为止
		if out.size() >= count:
			break
		var deg: float = float(ANGLES[(angle_start + i) % ANGLES.size()])
		# 第二圈把距离错开一点，避免重叠在同一格
		var r: int = radius + (2 if i >= ANGLES.size() else 0)
		var rad: float = deg_to_rad(deg)
		var p := Vector2i(
			center.x + int(round(cos(rad) * float(r))),
			center.y + int(round(sin(rad) * float(r))))
		p = Vector2i(clampi(p.x, 1, n - 2), clampi(p.y, 1, n - 2))
		var key: String = "%d,%d" % [p.x, p.y]
		if used.has(key):
			continue
		if not grid.is_placeable(p, Vector2i(1, 1)):
			continue
		used[key] = true
		out.append(p)
	return out

## 全图随机找格（用于树/中立村庄）。避开 used 和起点空区。
static func _random_cells(grid, count: int, used: Dictionary, rng: RandomNumberGenerator,
		starts: Array, min_start_dist: int) -> Array:
	var out: Array = []
	if grid == null or count <= 0:
		return out
	var n: int = int(grid.map_size.x)
	var tries: int = 0
	var max_tries: int = count * 40
	while out.size() < count and tries < max_tries:
		tries += 1
		var p := Vector2i(rng.randi_range(1, n - 2), rng.randi_range(1, n - 2))
		var key: String = "%d,%d" % [p.x, p.y]
		if used.has(key):
			continue
		if not grid.is_placeable(p, Vector2i(1, 1)):
			continue
		var too_close: bool = false
		for s in starts:
			var sp: Vector2i = s
			if Vector2(float(p.x - sp.x), float(p.y - sp.y)).length() < float(min_start_dist):
				too_close = true
				break
		if too_close:
			continue
		used[key] = true
		out.append(p)
	return out

# ---------------------------------------------------------------- 主入口

## 一次铺完。doc.objects 就地追加，返回统计：
## { "resources": n, "neutral_resources": n, "trees": n, "decos": n, "villages": n, "horses": n }
##
## opts（全部可选）：
##   res_plan:         覆盖 DEFAULT_RES_PLAN
##   neutral_resources: 中立富矿数量（草图中路/角落的争夺点），默认 4
##   trees:            树的数量，默认按地图面积算（每 100 格 1.2 棵）
##   rocks:            石头装饰数量
##   villages:         中立村庄数量，默认 2
##   horses:           野马数量，默认 4
##   seed:             随机种子，默认 20261024
##   keep_clear:       起点空区半径，默认 KEEP_CLEAR
static func scatter_all(doc, grid, starts: Array, opts: Dictionary = {}) -> Dictionary:
	var stats: Dictionary = {"resources": 0, "neutral_resources": 0, "trees": 0,
		"decos": 0, "villages": 0, "horses": 0}
	if doc == null or grid == null:
		return stats

	var rng := RandomNumberGenerator.new()
	rng.seed = int(opts.get("seed", 20261024))
	var keep_clear: int = int(opts.get("keep_clear", KEEP_CLEAR))
	var res_plan: Array = opts.get("res_plan", DEFAULT_RES_PLAN)
	var n: int = int(grid.map_size.x)

	# used 记录已占用的格，避免资源点互相叠、避免压到已有建筑
	var used: Dictionary = {}
	for o in doc.objects:
		if typeof(o) == TYPE_DICTIONARY and o.has("grid"):
			var g: Array = o["grid"]
			used["%d,%d" % [int(g[0]), int(g[1])]] = true

	# 起点空区也占掉（资源不该撒在官府脚下）
	var start_pts: Array = []
	for s in starts:
		var sp: Vector2i = s if s is Vector2i else Vector2i(int(s[0]), int(s[1]))
		start_pts.append(sp)
		for dy in range(-keep_clear, keep_clear + 1):
			for dx in range(-keep_clear, keep_clear + 1):
				if absi(dx) + absi(dy) > keep_clear:
					continue
				used["%d,%d" % [sp.x + dx, sp.y + dy]] = true

	# ① 每个起点周围同构的一圈资源
	for si in range(start_pts.size()):
		var sp2: Vector2i = start_pts[si]
		var angle_idx: int = 0
		for item in res_plan:
			var cnt: int = int(item.get("count", 1))
			var cells: Array = _ring_cells(grid, sp2, int(item.get("dist", 8)), cnt, used, angle_idx)
			angle_idx += cnt
			for c in cells:
				doc.add_object({
					"kind": "resource",
					"id": str(item.get("id", "wood")),
					"grid": [c.x, c.y],
					"amount": int(item.get("amount", 900)),
				})
				stats["resources"] = int(stats["resources"]) + 1

	# ② 中立富矿：只放地图正中的小环。
	#
	# 为什么必须"正中 + 小半径"：中立矿是争夺点，它到各家的距离必须近似相等，
	# 否则就是先天倾斜。实测放 r=7 的环上时，(35,35) 那个矿到一家 19.8 格、
	# 到另一家 34 格 —— 直接决定胜负。压到 r≤2 后各方向距离差 < 10%。
	var neutral_cnt: int = int(opts.get("neutral_resources", 4))
	if neutral_cnt > 0:
		var center := Vector2i(n / 2, n / 2)
		var types: Array = ["wood", "food", "stone"]
		var got: Array = _ring_cells(grid, center, 2, mini(neutral_cnt, 8), used, 0)
		for i in range(got.size()):
			var c2: Vector2i = got[i]
			doc.add_object({
				"kind": "resource",
				"id": str(types[i % types.size()]),
				"grid": [c2.x, c2.y],
				"amount": 9999,     # 富矿：够打满全场
			})
			stats["neutral_resources"] = int(stats["neutral_resources"]) + 1

	# ③ 树（纯装饰，成片撒，不影响平衡）
	var tree_cnt: int = int(opts.get("trees", int(float(n * n) / 100.0 * 1.2)))
	if tree_cnt > 0:
		var tcells: Array = _random_cells(grid, tree_cnt, used, rng, start_pts, keep_clear + 3)
		for i in range(tcells.size()):
			var c3: Vector2i = tcells[i]
			var cs: float = float(doc.cell_size)
			doc.add_object({
				"kind": "deco",
				"id": "tree_%d" % (i % 4),
				"pos": [(float(c3.x) + 0.5) * cs, (float(c3.y) + 0.5) * cs],
				"scale": 0.9 + fmod(float(c3.x * 7 + c3.y * 13), 6.0) * 0.1,
				"rot": 0,
			})
			stats["trees"] = int(stats["trees"]) + 1

	# ④ 石头装饰
	var rock_cnt: int = int(opts.get("rocks", maxi(4, n / 10)))
	if rock_cnt > 0:
		var rcells: Array = _random_cells(grid, rock_cnt, used, rng, start_pts, keep_clear + 2)
		for c4 in rcells:
			var cs2: float = float(doc.cell_size)
			doc.add_object({
				"kind": "deco", "id": "rock",
				"pos": [(float(c4.x) + 0.5) * cs2, (float(c4.y) + 0.5) * cs2],
				"scale": 1.0, "rot": 0,
			})
			stats["decos"] = int(stats["decos"]) + 1

	# ⑤ 中立村庄（占领点）
	var village_cnt: int = int(opts.get("villages", 2))
	if village_cnt > 0:
		var vcells: Array = _random_cells(grid, village_cnt, used, rng, start_pts, maxi(12, n / 4))
		for i2 in range(vcells.size()):
			var c5: Vector2i = vcells[i2]
			doc.add_object({
				"kind": "village", "id": "village_%d" % i2,
				"grid": [c5.x, c5.y],
				"props": {"is_city": false},
			})
			stats["villages"] = int(stats["villages"]) + 1

	# ⑥ 野马
	var horse_cnt: int = int(opts.get("horses", 4))
	if horse_cnt > 0:
		var horses_types: Array = ["white", "red", "chitu", "dilu"]
		var hcells: Array = _random_cells(grid, horse_cnt, used, rng, start_pts, keep_clear + 2)
		for i3 in range(hcells.size()):
			var c6: Vector2i = hcells[i3]
			doc.add_object({
				"kind": "horse",
				"id": str(horses_types[i3 % horses_types.size()]),
				"grid": [c6.x, c6.y],
			})
			stats["horses"] = int(stats["horses"]) + 1

	doc.touch()
	return stats

## 给每个玩家铺开局基地：官府 + 民居 + 若干农夫/士兵。
## 这一步必须放在 scatter 之后（基地要压在资源圈内侧的空地上）。
##
## height 传进来是为了判坡度。只靠 grid.is_placeable 不够 ——
## 它只知道"这格没被占/不是水"，不知道"这格离悬崖一米"。
## 实拍见过官府一半悬在河岸峭壁上，就是因为只查了占位。
static func place_start_bases(doc, grid, starts: Array, opts: Dictionary = {}, height: Image = null) -> Dictionary:
	var stats: Dictionary = {"bases": 0, "buildings": 0, "units": 0}
	if doc == null or grid == null:
		return stats
	var facades: Array = opts.get("factions", ["shu", "wei", "wu", "qun"])
	var unit_mix: Array = opts.get("units", ["peasant", "peasant", "sword", "archer"])
	var max_relief: float = float(opts.get("base_max_relief", 2.6))

	for i in range(starts.size()):
		var sp: Vector2i = starts[i] if starts[i] is Vector2i else Vector2i(int(starts[i][0]), int(starts[i][1]))
		var faction: String = str(facades[i % facades.size()])
		# 官府按 3×3 放，左上角对齐到起点左上方 1 格（让起点落在建筑中心）
		var gx: int = clampi(sp.x - 1, 0, int(grid.map_size.x) - 3)
		var gy: int = clampi(sp.y - 1, 0, int(grid.map_size.y) - 3)
		# 由近到远搜：先在原地试（5×5 留 1 格边），再螺旋往外找，
		# 每一步都要求"能放 + 平台够平"。找不到才退回只在原地的 3×3。
		var placed_pos: Vector2i = Vector2i(-1, -1)
		var radius_try: Array = [0, 1, 2, 3, 4, 5, 6, 7, 8]
		# 由严到宽：先找 7×7 平台（离水/崖 2 格），再 5×5，最后 3×3。
		# 只找 5×5 时官府常常紧贴河岸 —— 地块本身是平的，但视觉上像挂在崖边。
		for margin in [2, 1, 0]:
			var need: Vector2i = Vector2i(3 + margin * 2, 3 + margin * 2)
			var probe_off := Vector2i(margin, margin)
			for r in radius_try:
				if placed_pos.x >= 0:
					break
				# 环上按 8 个方向试（比全遍历快，也够用）
				for d in _offset_ring(r):
					var try_pos: Vector2i = Vector2i(gx + d.x, gy + d.y)
					if try_pos.x < 0 or try_pos.y < 0:
						continue
					if try_pos.x + 3 > int(grid.map_size.x) or try_pos.y + 3 > int(grid.map_size.y):
						continue
					if not grid.is_placeable(try_pos - probe_off, need):
						continue
					if height != null and margin >= 1:
						# 平台范围是 try_pos 往外扩 margin 格，所以要按 probe_off 回退
						if _relief_of(height, grid, try_pos - probe_off, need) > max_relief:
							continue
					placed_pos = try_pos
					break
			if placed_pos.x >= 0:
				break
		if placed_pos.x < 0:
			continue   # 实在放不下，跳过这个玩家（校验器会报出来）
		gx = placed_pos.x
		gy = placed_pos.y
		if height != null:
			print("[SCATTER] 起点 %s → 官府 %s（挪了 %s，5×5 高差 %.2f m，阈值 %.1f）" % [
				str(sp), str(Vector2i(gx, gy)), str(Vector2i(gx - (sp.x - 1), gy - (sp.y - 1))),
				_relief_of(height, grid, Vector2i(gx - 2, gy - 2), Vector2i(7, 7)), max_relief])
		doc.add_object({"kind": "building", "id": "government", "owner": faction, "grid": [gx, gy]})
		stats["buildings"] = int(stats["buildings"]) + 1
		grid.set_occupied(Vector2i(gx, gy), Vector2i(3, 3), 1)

		# 民居：官府右侧两间
		for k2 in range(2):
			var hx: int = gx + 4 + k2 * 2
			if grid.is_placeable(Vector2i(hx, gy), Vector2i(2, 2)):
				doc.add_object({"kind": "building", "id": "house", "owner": faction, "grid": [hx, gy]})
				stats["buildings"] = int(stats["buildings"]) + 1
				grid.set_occupied(Vector2i(hx, gy), Vector2i(2, 2), 1)

		# 开局单位：在官府下方排一列
		for u in range(unit_mix.size()):
			var ux: int = gx + u % 3
			var uy: int = gy + 4 + int(u / 3)
			if not grid.is_in_bounds(Vector2i(ux, uy)):
				continue
			doc.add_object({
				"kind": "unit", "id": str(unit_mix[u]), "owner": faction,
				"grid": [ux, uy], "rot": 180,
			})
			stats["units"] = int(stats["units"]) + 1

		stats["bases"] = int(stats["bases"]) + 1
	doc.touch()
	return stats
