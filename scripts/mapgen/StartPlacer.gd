extends RefCounted
## StartPlacer —— 给每个玩家挑一个"公平且好开局"的出生点
##
## 为什么不能随便撒：
##   ① 落在水里/悬崖上 → 开局就废；
##   ② 周围空地太小 → 官府放不下，玩家一进来就"无法放置"；
##   ③ 两个玩家挨太近 → 30 秒就打起来，不是 RTS 是格斗；
##   ④ 资源分布悬殊 → 有人三矿有人无矿，不用打都知道结果。
##
## 所以用「候选点打分 + 贪心取最大间距」两步。全部是纯函数，
## 只依赖 grid（通行/占位）和高度图（平坦度），可在 headless 里直接测。

const DEFAULT_MIN_DIST: int = 28      # 两个起点最小格距（84 格地图上约 1/3 对角线）
const CANDIDATE_STEP: int = 3         # 候选点采样步长，越小越慢越准
const BASE_CLEAR_RADIUS: int = 5      # 起点周围需要这么多格的空地（放得下官府+民居）
const EDGE_MARGIN: int = 8            # 离地图边至少这么远，否则镜头贴边很难受

## 单点评估。返回分数（越大越好），以及各项分解，便于校验器/向导展示。
## resource_cells: 已知资源点格坐标数组（由调用方从 doc.objects 里筛 "resource" 得来）。
static func score_point(grid, height: Image, p: Vector2i, resource_cells: Array = []) -> Dictionary:
	var n: int = int(grid.map_size.x)
	var detail: Dictionary = {
		"point": p, "score": 0.0,
		"flat": 0.0, "clear": 0.0, "water": 0.0, "edge": 0.0, "res": 0.0,
	}

	# ① 边缘惩罚：越靠边越差（软性，不直接否决）
	var d_edge: int = mini(mini(p.x, n - 1 - p.x), mini(p.y, n - 1 - p.y))
	if d_edge < EDGE_MARGIN:
		detail["edge"] = -float(EDGE_MARGIN - d_edge) * 6.0

	# ② 平坦度：以 p 为中心 9×9 采样，标准差越小越好
	if height != null:
		var hs: Array = []
		var px_per_cell: float = float(height.get_width()) / float(n)
		for dy in range(-4, 5):
			for dx in range(-4, 5):
				var q: Vector2i = p + Vector2i(dx, dy)
				if q.x < 0 or q.y < 0 or q.x >= n or q.y >= n:
					continue
				var hx: int = clampi(int((float(q.x) + 0.5) * px_per_cell), 0, height.get_width() - 1)
				var hy: int = clampi(int((float(q.y) + 0.5) * px_per_cell), 0, height.get_height() - 1)
				hs.append(height.get_pixel(hx, hy).r)
		if hs.size() > 1:
			var mean: float = 0.0
			for v in hs:
				mean += float(v)
			mean /= float(hs.size())
			var var_sum: float = 0.0
			var hmin: float = 99999.0
			var hmax: float = -99999.0
			for v in hs:
				var dv: float = float(v) - mean
				var_sum += dv * dv
				hmin = minf(hmin, float(v))
				hmax = maxf(hmax, float(v))
			var sd: float = sqrt(var_sum / float(hs.size()))
			# 标准差 0m → 满分 40；每 1m 起伏扣 8 分，扣到 -40 为止
			detail["flat"] = clampf(40.0 - sd * 8.0, -40.0, 40.0)
			# ★ 光看标准差不够：河岸那种"一边平地一边 10m 悬崖"的布局，
			# 标准差可能只有 3m（平均下来不离谱），但官府放上去一半悬空。
			# 所以额外看 9×9 内的总高差，超过 3m 就重罚。
			var relief: float = hmax - hmin
			detail["relief"] = relief
			if relief > 3.0:
				detail["flat"] = float(detail["flat"]) - (relief - 3.0) * 9.0
		detail["height"] = float(hs[hs.size() / 2]) if hs.size() > 0 else 0.0

	# ③ 空地率：以 p 为中心 BASE_CLEAR_RADIUS 半径内可建格占比
	var total: int = 0
	var ok: int = 0
	var water: int = 0
	for dy in range(-BASE_CLEAR_RADIUS, BASE_CLEAR_RADIUS + 1):
		for dx in range(-BASE_CLEAR_RADIUS, BASE_CLEAR_RADIUS + 1):
			# 菱形（曼哈顿距离）采样：四个角对开局没意义，还容易误判成"空地少"
			if absi(dx) + absi(dy) > BASE_CLEAR_RADIUS + 2:
				continue
			var q2: Vector2i = p + Vector2i(dx, dy)
			total += 1
			if not grid.is_in_bounds(q2):
				water += 1
				continue
			if grid.is_placeable(q2, Vector2i(1, 1)):
				ok += 1
			elif int(grid.occupied[q2.x][q2.y]) == 3:
				water += 1   # 3 = 水域（GridManager 约定）
	var ratio: float = float(ok) / float(maxi(total, 1))
	detail["clear"] = ratio * 45.0
	# 起点正下方必须站得住，否则直接判死（返回大负数）
	if grid.is_in_bounds(p) and not grid.is_walkable(p):
		detail["score"] = -9999.0
		detail["fatal"] = "起点不可通行"
		return detail
	if ratio < 0.55:
		detail["fatal"] = "周围空地不足（%.0f%%）" % (ratio * 100.0)
		detail["score"] = -9999.0
		return detail
	detail["water"] = -float(water) * 1.5

	# ④ 资源邻近度：最近的资源点距离，越近越好（0 格=15 分，每格 -0.5）
	detail["res"] = _resource_score(p, resource_cells)

	detail["score"] = float(detail["flat"]) + float(detail["clear"]) \
		+ float(detail["water"]) + float(detail["edge"]) + float(detail["res"])
	return detail


## 资源邻近度。不给资源列表就返回 0（不影响选址主逻辑）。
static func _resource_score(p: Vector2i, resource_cells: Array) -> float:
	if resource_cells.is_empty():
		return 0.0
	var best: float = 9999.0
	for c in resource_cells:
		var cx: int = 0
		var cy: int = 0
		if c is Vector2i:
			cx = c.x
			cy = c.y
		elif typeof(c) == TYPE_ARRAY and c.size() >= 2:
			cx = int(c[0])
			cy = int(c[1])
		else:
			continue
		var d: float = Vector2(float(p.x - cx), float(p.y - cy)).length()
		best = minf(best, d)
	return clampf(15.0 - best * 0.5, 0.0, 15.0)

## 主入口：挑 n 个起点。
##
## resource_cells: 资源点格坐标，用于"离资源近"加分。可选。
## min_dist: 两个起点最小格距；传 0 用默认值。
## 返回 [{ "slot": i, "start": [x,y], "score": float, "detail": {...} }, ...]
## 选不满时返回长度 < n 的数组（调用方应当校验）。
static func pick(grid, height: Image, n: int, min_dist: int = 0, resource_cells: Array = []) -> Array:
	var out: Array = []
	if grid == null or n <= 0:
		return out
	var n_cells: int = int(grid.map_size.x)
	if min_dist <= 0:
		# 按地图大小自动定：84 格图约 28 格，小图按比例缩
		min_dist = maxi(12, int(float(n_cells) * 0.33))

	# 1) 采候选点并打分
	var cands: Array = []
	var step: int = CANDIDATE_STEP if n_cells >= 60 else 2
	for y in range(EDGE_MARGIN, n_cells - EDGE_MARGIN, step):
		for x in range(EDGE_MARGIN, n_cells - EDGE_MARGIN, step):
			var p := Vector2i(x, y)
			if not grid.is_walkable(p):
				continue
			var s: Dictionary = score_point(grid, height, p, resource_cells)
			if float(s.get("score", -9999.0)) <= -9000.0:
				continue
			cands.append(s)
	if cands.is_empty():
		return out

	# 2) 分数降序
	cands.sort_custom(func(a, b): return float(a["score"]) > float(b["score"]))

	# 3) 贪心：每次取当前最高分且离已选够远的
	for c in cands:
		if out.size() >= n:
			break
		var p: Vector2i = c["point"]
		var far_enough: bool = true
		for chosen in out:
			var q: Vector2i = chosen["point"]
			# 环形距离：地图左右边缘在视觉上是连着的，但 RTS 不连通，用直线即可
			if Vector2(float(p.x - q.x), float(p.y - q.y)).length() < float(min_dist):
				far_enough = false
				break
		if not far_enough:
			continue
		out.append(c)

	# 4) 装成玩家格式
	var result: Array = []
	for i in range(out.size()):
		var c2: Dictionary = out[i]
		result.append({
			"slot": i,
			"start": [int(c2["point"].x), int(c2["point"].y)],
			"score": float(c2["score"]),
			"detail": c2,
		})
	return result

# ------------------------------------------------------------------ 对称选点

## 对称选点：**只选基点，其余由对称轨道生成**。
##
## 为什么必须是这个顺序：
##   独立选 N 个点（哪怕都合格）也不保证它们关于地图中心对称，
##   而地图正中的中立富矿到各家距离就会不等 —— 实测两边差 80%。
##   RTS 地图的标准做法是"选一半，翻面"。
##
## mode 用 MapSymmetric.Mode 的枚举值：0/1/2 是 2 阶，3（ROTATE_90）是 4 阶。
static func pick_symmetric(grid, height: Image, n_players: int, mode: int,
		min_dist: int = 0, resource_cells: Array = []) -> Array:
	if grid == null or n_players <= 0:
		return []
	var n: int = int(grid.map_size.x)
	var order: int = 4 if mode == 3 else 2
	var n_base: int = int(ceil(float(n_players) / float(order)))
	# 基点之间要更远：同一条 4 阶轨道会把间距放大，但不同轨道之间不会，
	# 所以基点间距按 min_dist 再放宽 1.15 倍，避免展开后贴脸。
	var base_dist: int = int(float(min_dist) * 1.15) if min_dist > 0 else 0
	# 多要一批候选：轨道内间距不合格的基点会被筛掉，只取 n_base 个不够用。
	var cands: Array = pick(grid, height, maxi(n_base * 4, 8), base_dist, resource_cells)

	# 逐个试基点：把它的整条轨道展开，检查
	#   ① 轨道内部任意两点间距 ≥ min_dist
	#      （镜像模式下这等价于"基点离中线至少 min_dist/2"，实测 (44,53)
	#        镜像成 (27,53) 只有 17 格 —— 光看基点间距 23 是看不出来的）
	#   ② 与已选中的轨道也不撞
	var groups: Array = []
	for b in cands:
		if groups.size() >= n_base:
			break
		var p0 := Vector2i(int(b["start"][0]), int(b["start"][1]))
		var orb0: Array = _orbit(p0, n, mode)
		var ok: bool = true
		for i in range(orb0.size()):
			for j in range(i + 1, orb0.size()):
				var dd: float = Vector2(float(orb0[i].x - orb0[j].x),
					float(orb0[i].y - orb0[j].y)).length()
				if dd < float(min_dist):
					ok = false
		if ok:
			for g in groups:
				for q1 in g["orb"]:
					for q2 in orb0:
						var d2: float = Vector2(float(q1.x - q2.x), float(q1.y - q2.y)).length()
						if d2 < float(min_dist):
							ok = false
		if ok:
			groups.append({"base": p0, "orb": orb0, "score": float(b["score"]), "detail": b["detail"]})

	var out: Array = []
	var seen: Dictionary = {}
	for grp in groups:
		for q in grp["orb"]:
			var key: String = "%d,%d" % [q.x, q.y]
			if seen.has(key):
				continue
			seen[key] = true
			out.append({
				"slot": out.size(),
				"start": [q.x, q.y],
				"score": float(grp["score"]),
				"detail": grp["detail"],
				"base": [grp["base"].x, grp["base"].y],
			})
			if out.size() >= n_players:
				break
		if out.size() >= n_players:
			break
	return out

## 本地复制一份轨道计算，避免 StartPlacer 反向依赖 MapSymmetric
static func _orbit(p: Vector2i, n: int, mode: int) -> Array:
	var out: Array = [p]
	var q: Vector2i = p
	for i in range(3):
		match mode:
			0: q = Vector2i(n - 1 - q.x, n - 1 - q.y)
			1: q = Vector2i(q.x, n - 1 - q.y)
			2: q = Vector2i(n - 1 - q.x, q.y)
			3: q = Vector2i(q.y, n - 1 - q.x)
			_: return out
		if out.has(q):
			break
		out.append(q)
	return out
