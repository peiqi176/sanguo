extends Node3D
## 寻路自测：8 方向 / 防切角 / 视线拉直 / 无障碍物时走直线
##
## 为什么要单独测：寻路是"看起来没坏其实错了"的典型 ——
## 4 方向时路径永远能通，只是走成楼梯；没有断言就永远发现不了。

const Pathfinder = preload("res://scripts/core/Pathfinder.gd")

var _pass: int = 0
var _fail: int = 0

func check(ok: bool, what: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		print("[SELFTEST] ❌ ", what)

func _make_grid(n: int) -> Node:
	# 注意：不能调 g._init_grid()，它会按 Terrain.is_water 把水格标成 3。
	# 测试网格坐标 (0..n) 落在世界的哪个角落、是水是陆，完全取决于地形种子，
	# 会让寻路测试时通时不通。这里手工铺一张全空图，把地形变量隔离掉。
	var g = load("res://scripts/core/GridManager.gd").new()
	g.map_size = Vector2i(n, n)
	g.origin = Vector3.ZERO
	g.cell_size = 2.0
	g.occupied = []
	for x in range(n):
		var col: Array = []
		for y in range(n):
			col.append(0)
		g.occupied.append(col)
	return g

## 把一条横墙打上，中间留一个缺口
func _wall(g, y: int, gap_x: int) -> void:
	for x in range(g.map_size.x):
		if x == gap_x:
			continue
		g.occupied[x][y] = 1

func _path_len(path: Array) -> float:
	var t: float = 0.0
	for i in range(1, path.size()):
		t += Vector2(path[i] - path[i - 1]).length()
	return t

## 路径的每一段是否蹭到障碍格（每 0.1 格采样一次，足够密）
func _path_hits(g, path: Array) -> bool:
	for i in range(1, path.size()):
		var a: Vector2 = Vector2(path[i - 1])
		var b: Vector2 = Vector2(path[i])
		var steps: int = int(ceil(a.distance_to(b) * 10.0))
		for s in range(steps + 1):
			var p: Vector2 = a.lerp(b, float(s) / float(maxi(steps, 1)))
			var c: Vector2i = Vector2i(int(round(p.x)), int(round(p.y)))
			if c.x < 0 or c.y < 0 or c.x >= g.map_size.x or c.y >= g.map_size.y:
				return true
			if g.occupied[c.x][c.y] != 0:
				return true
	return false

func _ready() -> void:
	var pf = Pathfinder.new()

	# ---------- 1) 空旷地：必须走对角，而不是楼梯 ----------
	var g = _make_grid(24)
	GameManager.grid = g
	var p1: Array = pf.find_path(Vector2i(1, 1), Vector2i(22, 22))
	check(p1.size() > 0, "空地图能找到路径")
	var straight: float = Vector2(21, 21).length()
	check(_path_len(p1) <= straight * 1.15,
		"路径长度 %.1f 接近直线 %.1f（4 方向会是 42）" % [_path_len(p1), straight])
	check(p1.size() <= 4, "路径被拉直成 ≤4 个拐点（实际 %d）" % p1.size())

	# ---------- 2) 穿墙必须走缺口 ----------
	g = _make_grid(24)
	_wall(g, 12, 3)
	GameManager.grid = g
	var p2: Array = pf.find_path(Vector2i(3, 2), Vector2i(3, 22))
	check(p2.size() > 0, "有墙也能通（缺口在 x=3）")
	check(not _path_hits(g, p2), "路径的任何一段都没有穿墙")
	var crosses_wall_row: bool = false
	for i in range(1, p2.size()):
		if (p2[i - 1].y < 12) != (p2[i].y < 12):
			crosses_wall_row = true
	check(crosses_wall_row, "路径确实跨过了墙所在那一行")

	# ---------- 3) 防切角：两格斜挨着不能从缝里挤过去 ----------
	g = _make_grid(12)
	# 造一个"斜角缝"： (5,4) 和 (4,5) 是障碍，从 (4,4) 到 (5,5) 只能绕
	g.occupied[4][4] = 1   # x=4,y=4
	g.occupied[5][5] = 1   # x=5,y=5
	GameManager.grid = g
	var p3: Array = pf.find_path(Vector2i(5, 4), Vector2i(4, 5))
	# 起点 (5,4) 与终点 (4,5) 都是空格，但彼此斜向相邻的两个正交格全是障碍
	check(p3.size() > 0, "斜角缝仍能迂回抵达")
	check(p3.size() > 2, "斜角缝没有被直接斜穿（拐点数 %d > 2）" % p3.size())

	# ---------- 4) 目标不可行走 → 自动落到最近可行走格 ----------
	g = _make_grid(16)
	g.occupied[8][8] = 1
	GameManager.grid = g
	var p4: Array = pf.find_path(Vector2i(1, 1), Vector2i(8, 8))
	check(p4.size() > 0, "目标被占时能落到旁边并给出路径")
	check(p4[p4.size() - 1] != Vector2i(8, 8), "终点不是被占格")

	# ---------- 5) 缓存命中 ----------
	var p5: Array = pf.find_path(Vector2i(1, 1), Vector2i(8, 8))
	check(p5.size() == p4.size(), "同一查询命中缓存，结果一致")

	# ---------- 6) 越界立即失败（不崩、不卡） ----------
	var p6: Array = pf.find_path(Vector2i(-5, 0), Vector2i(999, 999))
	check(p6.size() == 0, "越界返回空数组而不是崩")

	print("[SELFTEST] %d 项检查，%d 项失败" % [_pass + _fail, _fail])
	if _fail == 0:
		print("[SELFTEST] ✅ 寻路全部通过")
	else:
		print("[SELFTEST] ❌ 有 %d 项失败" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
