extends RefCounted
## MapValidator —— 地图「能不能正常开局」的 7 项硬校验
##
## 为什么必须在生成后跑一遍：生成器是"尽量合理"，不是"保证可用"。
## 用户拿到一张开局就废的图，比拿到一张丑图糟得多。
##
## 每项返回 { "id", "name", "ok", "level", "msg", "data" }
##   level: "error"（必须修，否则不可玩） / "warn"（可玩但明显不合理） / "info"
##
## 全部纯函数，不建场景，headless 直接测。

const SEVERITY_ERROR: String = "error"
const SEVERITY_WARN: String = "warn"
const SEVERITY_INFO: String = "info"

## 起点最小间距（格）。大图用 18，小图按比例缩 ——
## 40 格的小图要求 18 格间距是荒谬的（它自己对角线才 56）。
static func _min_start_dist(doc) -> float:
	var n: int = int(doc.grid_n)
	return clampf(float(n) * 0.22, 8.0, 18.0)

## 「你的资源」半径：只有这么近的资源才算这个起点的家底。
## 更远的是中立争夺点，不该拿来做公平性比较（否则谁离中心近谁"富"）。
static func _res_sphere(doc) -> float:
	var n: int = int(doc.grid_n)
	return clampf(float(n) * 0.30, 10.0, 22.0)

## 起点周围需要的最小空地格数（6×6 的房子 + 几个民居）
const MIN_BASE_CLEAR: int = 20
## 各玩家资源总量的可接受差距（比例）
const MAX_RESOURCE_GAP: float = 0.35

static func _r(id: String, name: String, ok: bool, level: String, msg: String, data: Dictionary = {}) -> Dictionary:
	return {"id": id, "name": name, "ok": ok, "level": level, "msg": msg, "data": data}

## 跑全套。doc 为 MapDoc，grid 为 GridManager（可选，不给就跳过依赖占位的检查）。
## 返回 { "ok": bool, "errors": int, "warns": int, "results": Array }
static func validate(doc, grid = null) -> Dictionary:
	var results: Array = []
	if doc == null:
		results.append(_r("doc", "地图数据存在", false, SEVERITY_ERROR, "doc 为空"))
		return _pack(results)

	results.append(_check_start_count(doc))
	results.append(_check_start_dist(doc))
	results.append(_check_start_standable(doc, grid))
	results.append(_check_base_room(doc, grid))
	results.append(_check_resource_balance(doc))
	results.append(_check_objects_in_bounds(doc))
	results.append(_check_no_overlap(doc))
	return _pack(results)

static func _pack(results: Array) -> Dictionary:
	var errors: int = 0
	var warns: int = 0
	for r in results:
		if bool(r["ok"]):
			continue
		if str(r["level"]) == SEVERITY_ERROR:
			errors += 1
		elif str(r["level"]) == SEVERITY_WARN:
			warns += 1
	return {"ok": errors == 0, "errors": errors, "warns": warns, "results": results}

# ------------------------------------------------------------------ 1 起点数量

static func _check_start_count(doc) -> Dictionary:
	var sp: Array = doc.start_points()
	var n: int = doc.players.size()
	if n == 0:
		return _r("start_count", "起点数量", false, SEVERITY_WARN,
			"地图没有配置玩家（单人沙盘可以忽略）", {"players": 0, "starts": sp.size()})
	if sp.size() < n:
		return _r("start_count", "起点数量", false, SEVERITY_ERROR,
			"%d 个玩家只有 %d 个起点，有玩家会开局无家可归" % [n, sp.size()],
			{"players": n, "starts": sp.size()})
	return _r("start_count", "起点数量", true, SEVERITY_INFO,
		"%d 个玩家 / %d 个起点" % [n, sp.size()], {"players": n, "starts": sp.size()})

# ------------------------------------------------------------------ 2 起点间距

static func _check_start_dist(doc) -> Dictionary:
	var sp: Array = doc.start_points()
	var min_d: float = 99999.0
	var worst: Array = []
	for i in range(sp.size()):
		for j in range(i + 1, sp.size()):
			var a: Vector2i = sp[i]
			var b: Vector2i = sp[j]
			var d: float = Vector2(float(a.x - b.x), float(a.y - b.y)).length()
			if d < min_d:
				min_d = d
				worst = [a, b]
	if sp.size() < 2:
		return _r("start_dist", "起点间距", true, SEVERITY_INFO, "少于 2 个起点，无需检查")
	var need: float = _min_start_dist(doc)
	if min_d < need:
		return _r("start_dist", "起点间距", false, SEVERITY_ERROR,
			"最近两家只隔 %.1f 格（要求 ≥ %.0f），开局就贴脸" % [min_d, need],
			{"min_dist": min_d, "pair": worst})
	return _r("start_dist", "起点间距", true, SEVERITY_INFO,
		"最近两家 %.1f 格" % min_d, {"min_dist": min_d})

# ------------------------------------------------------------------ 3 起点可站立

## 建筑占几格。只做粗略推定：官府 3×3，其余 2×2。
## 这里刻意不查 buildings.json —— 校验器要保持"纯逻辑、可单测"，
## 精确足迹由 ObjectSpawner/PlacementGhost 负责，这里只需要判断"谁压在起点上"。
static func _footprint(building_id: String) -> Vector2i:
	if building_id == "government":
		return Vector2i(3, 3)
	return Vector2i(2, 2)

## 压在这格上的建筑归属（没有则空字符串）
static func _building_owner_at(doc, p: Vector2i) -> String:
	for o in doc.objects:
		if typeof(o) != TYPE_DICTIONARY or str(o.get("kind", "")) != "building":
			continue
		if not o.has("grid"):
			continue
		var g: Array = o["grid"]
		var x: int = int(g[0])
		var y: int = int(g[1])
		var sz: Vector2i = _footprint(str(o.get("id", "")))
		if p.x >= x and p.x < x + sz.x and p.y >= y and p.y < y + sz.y:
			return str(o.get("owner", ""))
	return ""

static func _check_start_standable(doc, grid) -> Dictionary:
	var sp: Array = doc.start_points()
	if sp.is_empty():
		return _r("start_stand", "起点可站立", true, SEVERITY_INFO, "无起点，跳过")
	if grid == null:
		# 没有 grid 时用对象占位推断：起点上如果压着**别家**建筑，同样有问题
		for p in sp:
			var ow: String = _building_owner_at(doc, p)
			if ow != "" and ow != _faction_of_start(doc, p):
				return _r("start_stand", "起点可站立", false, SEVERITY_ERROR,
					"起点 %s 上压着 %s 的建筑" % [str(p), ow], {})
		return _r("start_stand", "起点可站立", true, SEVERITY_INFO, "未提供 grid，仅检查建筑归属")
	var bad: Array = []
	for p in sp:
		if not grid.is_in_bounds(p):
			bad.append({"point": p, "why": "超出地图"})
			continue
		if grid.is_walkable(p):
			continue   # 空地，最好
		var occ: int = int(grid.occupied[p.x][p.y])
		if occ == 3:
			bad.append({"point": p, "why": "水域"})
			continue
		# 被建筑占住：如果是本家官府压在上面，那是设计意图（起点=基地锚点），放行
		var owner: String = _building_owner_at(doc, p)
		var mine: String = _faction_of_start(doc, p)
		if owner != "" and (mine == "" or owner == mine):
			continue
		bad.append({"point": p, "why": "被 %s 占用" % (owner if owner != "" else "未知对象")})
	if not bad.is_empty():
		return _r("start_stand", "起点可站立", false, SEVERITY_ERROR,
			"%d 个起点站不住：%s" % [bad.size(), str(bad[0])], {"bad": bad})
	return _r("start_stand", "起点可站立", true, SEVERITY_INFO, "%d 个起点都可用" % sp.size())

static func _faction_of_start(doc, p: Vector2i) -> String:
	for pl in doc.players:
		if typeof(pl) != TYPE_DICTIONARY or not pl.has("start"):
			continue
		var s: Array = pl["start"]
		if int(s[0]) == p.x and int(s[1]) == p.y:
			return str(pl.get("faction", ""))
	return ""

# ------------------------------------------------------------------ 4 基地空地

static func _check_base_room(doc, grid) -> Dictionary:
	var sp: Array = doc.start_points()
	if sp.is_empty() or grid == null:
		return _r("base_room", "基地空地", true, SEVERITY_INFO, "无起点或无 grid，跳过")
	var bad: Array = []
	for p in sp:
		var ok: int = 0
		# 官府是 3×3（约），再留一圈给民居 → 6 格半径内数可建格
		for dy in range(-6, 7):
			for dx in range(-6, 7):
				if absi(dx) + absi(dy) > 8:
					continue
				var q: Vector2i = p + Vector2i(dx, dy)
				if grid.is_in_bounds(q) and grid.is_placeable(q, Vector2i(1, 1)):
					ok += 1
		if ok < MIN_BASE_CLEAR:
			bad.append({"point": p, "clear": ok})
	if not bad.is_empty():
		return _r("base_room", "基地空地", false, SEVERITY_WARN,
			"%d 个起点周围空地不足（最少 %d 格，实际 %d）" % [
				bad.size(), MIN_BASE_CLEAR, int(bad[0]["clear"])], {"bad": bad})
	return _r("base_room", "基地空地", true, SEVERITY_INFO, "每个起点周围空地都够")

# ------------------------------------------------------------------ 5 资源均衡

static func _check_resource_balance(doc) -> Dictionary:
	var sp: Array = doc.start_points()
	# 收集资源点
	var res: Array = []
	for o in doc.objects:
		if typeof(o) == TYPE_DICTIONARY and str(o.get("kind", "")) == "resource" and o.has("grid"):
			res.append(o)
	if res.is_empty():
		return _r("res_balance", "资源均衡", false, SEVERITY_WARN, "地图上没有资源点，无法发展", {})
	if sp.size() < 2:
		return _r("res_balance", "资源均衡", true, SEVERITY_INFO,
			"%d 个资源点，单起点无需比较" % res.size(), {"resources": res.size()})

	# 每个起点"家底"：只算 _res_sphere 半径内的资源。
	# 更远的是中立争夺点（往往在地图正中、两家等距），
	# 拿它做"谁更富"的比较没有意义 —— 之前就是这么误报的。
	var sphere: float = _res_sphere(doc)
	var totals: Array = []
	var neutral: int = 0
	for i in range(sp.size()):
		totals.append(0)
	for o in res:
		var g: Array = o["grid"]
		var rp := Vector2i(int(g[0]), int(g[1]))
		var best_i: int = -1
		var best_d: float = 99999.0
		for i in range(sp.size()):
			var d: float = Vector2(float(rp.x - sp[i].x), float(rp.y - sp[i].y)).length()
			if d < best_d:
				best_d = d
				best_i = i
		if best_i < 0:
			continue
		if best_d > sphere:
			neutral += 1        # 中立资源，不计入任何一方
			continue
		totals[best_i] += maxi(int(o.get("amount", 1)), 1)

	# 有玩家一个专属资源都没有 → 比"差距大"更严重
	for i in range(totals.size()):
		if int(totals[i]) == 0:
			return _r("res_balance", "资源均衡", false, SEVERITY_ERROR,
				"玩家 %d 的起点 %.0f 格内没有任何资源，无法开局" % [i, sphere],
				{"totals": totals, "neutral": neutral})

	var tmin: int = 99999999
	var tmax: int = -1
	var sum: int = 0
	for t in totals:
		tmin = mini(tmin, int(t))
		tmax = maxi(tmax, int(t))
		sum += int(t)
	if sum == 0:
		return _r("res_balance", "资源均衡", false, SEVERITY_WARN, "资源总量为 0", {})
	var gap: float = float(tmax - tmin) / float(maxi(tmax, 1))
	if gap > MAX_RESOURCE_GAP:
		return _r("res_balance", "资源均衡", false, SEVERITY_WARN,
			"各玩家资源差 %.0f%%（上限 %.0f%%），最少 %d / 最多 %d" % [
				gap * 100.0, MAX_RESOURCE_GAP * 100.0, tmin, tmax],
			{"totals": totals, "gap": gap})
	return _r("res_balance", "资源均衡", true, SEVERITY_INFO,
		"各玩家专属资源差 %.0f%%（另有 %d 个中立资源点）" % [gap * 100.0, neutral],
		{"totals": totals, "gap": gap, "neutral": neutral})

# ------------------------------------------------------------------ 6 对象在界内

static func _check_objects_in_bounds(doc) -> Dictionary:
	var n: int = int(doc.grid_n)
	var cs: float = float(doc.cell_size)
	var bad: Array = []
	for o in doc.objects:
		if typeof(o) != TYPE_DICTIONARY:
			bad.append({"obj": "(非法类型)", "why": "不是字典"})
			continue
		if o.has("grid"):
			var g: Array = o["grid"]
			if g.size() < 2:
				bad.append({"obj": str(o.get("id", "?")), "why": "grid 字段残缺"})
				continue
			var x: int = int(g[0])
			var y: int = int(g[1])
			if x < 0 or y < 0 or x >= n or y >= n:
				bad.append({"obj": str(o.get("id", "?")), "grid": [x, y], "why": "超出 %dx%d" % [n, n]})
		elif o.has("pos"):
			var pos: Array = o["pos"]
			if pos.size() < 2:
				bad.append({"obj": str(o.get("id", "?")), "why": "pos 字段残缺"})
				continue
			var wx: float = float(pos[0])
			var wz: float = float(pos[1])
			if wx < 0.0 or wz < 0.0 or wx > float(n) * cs or wz > float(n) * cs:
				bad.append({"obj": str(o.get("id", "?")), "pos": [wx, wz], "why": "超出世界范围"})
	if not bad.is_empty():
		return _r("in_bounds", "对象在地图内", false, SEVERITY_ERROR,
			"%d 个对象跑到地图外：%s" % [bad.size(), str(bad[0])], {"bad": bad})
	return _r("in_bounds", "对象在地图内", true, SEVERITY_INFO,
		"%d 个对象都在范围内" % doc.objects.size())

# ------------------------------------------------------------------ 7 实体不重叠

static func _check_no_overlap(doc) -> Dictionary:
	# 只查"格对齐的实体"（建筑/资源/村庄），装饰与单位允许叠放
	var occupied: Dictionary = {}
	var bad: Array = []
	for o in doc.objects:
		if typeof(o) != TYPE_DICTIONARY or not o.has("grid"):
			continue
		var kind: String = str(o.get("kind", ""))
		if kind != "building" and kind != "resource" and kind != "village":
			continue
		var g: Array = o["grid"]
		var key: String = "%d,%d" % [int(g[0]), int(g[1])]
		if occupied.has(key):
			bad.append({"first": occupied[key], "second": str(o.get("id", "?")), "grid": key})
		else:
			occupied[key] = str(o.get("id", "?"))
	if not bad.is_empty():
		return _r("overlap", "实体不重叠", false, SEVERITY_WARN,
			"%d 处格子被两个实体同时占用（第一个：%s）" % [bad.size(), str(bad[0])], {"bad": bad})
	return _r("overlap", "实体不重叠", true, SEVERITY_INFO, "无实体重叠")

# ------------------------------------------------------------------ 报告

## 把结果拼成一段人能读的文字，给向导/控制台用
static func report(rep: Dictionary) -> String:
	var lines: Array = []
	lines.append("地图校验：%s（错误 %d / 警告 %d）" % [
		"✅ 通过" if bool(rep.get("ok", false)) else "❌ 不通过",
		int(rep.get("errors", 0)), int(rep.get("warns", 0))])
	for r in rep.get("results", []):
		var mark: String = "✅"
		if not bool(r["ok"]):
			mark = "❌" if str(r["level"]) == SEVERITY_ERROR else "⚠️"
		lines.append("  %s %s：%s" % [mark, str(r["name"]), str(r["msg"])])
	return "\n".join(lines)
