extends Node3D
## 移动 / 贴地 集成自测
##
## 只检查"能不能算出路径"是不够的 —— 用户看到的症状是"点了不走 / 走起来上下飘"。
## 所以这里真的把 Main 跑起来，给一个兵下移动命令，然后逐物理帧观察它：
##   ① 有没有走到目标附近；
##   ② 每一帧的 y 有没有贴在地形上（不是浮空也不是陷地）；
##   ③ y 有没有单帧跳变（上下抖动的量化指标）。
##
## 用物理帧而不是渲染帧计数：headless 模式下渲染帧跑得飞快，
## 用渲染帧数计时会让"给了 400 帧"实际只过了 0.3 秒，测出来永远不动。

var _pass: int = 0
var _fail: int = 0
var _main = null
var _unit = null
var _target: Vector3 = Vector3.ZERO
var _t: int = 0
var _elapsed: float = 0.0
var _max_dy: float = 0.0
var _last_y: float = 0.0
var _start_dist: float = 0.0
var _ground_err_shown: bool = false

func check(ok: bool, what: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		print("[SELFTEST] ❌ ", what)

func _ready() -> void:
	_main = load("res://scenes/Main.tscn").instantiate()
	add_child(_main)

func _physics_process(delta: float) -> void:
	_t += 1
	if _t < 20:
		return
	if _t == 20:
		_begin()
		return
	if _unit == null or not is_instance_valid(_unit):
		return
	_elapsed += delta
	_look()
	if _elapsed >= 9.0:
		_finish()

func _begin() -> void:
	for n in _main.get_children():
		if n.get("unit_id") == "sword" and str(n.get("faction")) == "shu":
			_unit = n
			break
	if _unit == null:
		check(false, "场景里找不到蜀国剑兵，无法测试")
		_finish()
		return
	var grid = GameManager.grid
	var g0: Vector2i = grid.world_to_grid(_unit.global_position)
	var g1: Vector2i = g0
	# 目标必须是"真的能走到"的格子。
	# 地形加了山脊之后，原来的 (+d,+d) 对角线经常正好落到河对岸，
	# A* 返回空路径 → 单位原地不动，看起来像"寻路挂了"，其实是测试选点不合理。
	for d in range(6, 20):
		for off in [Vector2i(d, d), Vector2i(d, 0), Vector2i(0, d), Vector2i(-d, 0), Vector2i(0, -d)]:
			var cand: Vector2i = g0 + off
			if not (grid.is_in_bounds(cand) and grid.is_walkable(cand)):
				continue
			if GameManager.pathfinder.find_path(g0, cand).size() >= 3:
				g1 = cand
				break
		if g1 != g0:
			break
	_target = grid.grid_to_world(g1)
	_start_dist = Vector2(_unit.global_position.x - _target.x, _unit.global_position.z - _target.z).length()
	_last_y = _unit.global_position.y
	print("[MOVE] 起点 %s → 目标 %s（水平距离 %.1f m）" % [
		str(_unit.global_position), str(_target), _start_dist])
	# 诊断：地形改陡之后单位原地不动过一次，先把"起点/目标能不能走、路径有多长"打出来
	var gm0: Vector2i = grid.world_to_grid(_unit.global_position)
	print("[MOVE] 起点格 %s in_bounds=%s walkable=%s | 目标格 %s walkable=%s | 地形高 %.2f / 目标高 %.2f" % [
		str(gm0), str(grid.is_in_bounds(gm0)), str(grid.is_walkable(gm0)),
		str(g1), str(grid.is_walkable(g1)),
		Terrain.get_height(_unit.global_position.x, _unit.global_position.z),
		Terrain.get_height(_target.x, _target.z)])
	check(_start_dist > 4.0, "测试距离够长（%.1f m > 4 m）" % _start_dist)
	_unit.command_move(_target)
	print("[MOVE] command_move 之后 state=%s path=%s" % [
		str(_unit.get("state")), str(_unit.get("path"))])

func _look() -> void:
	var p: Vector3 = _unit.global_position
	var gh: float = Terrain.get_height(p.x, p.z)
	if absf(p.y - gh) > 0.6 and not _ground_err_shown:
		_ground_err_shown = true
		check(false, "脱离地面：y=%.2f 地面=%.2f（相差 %.2f m）" % [p.y, gh, p.y - gh])
	_max_dy = maxf(_max_dy, absf(p.y - _last_y))
	_last_y = p.y

func _finish() -> void:
	set_physics_process(false)
	var p: Vector3 = _unit.global_position
	var d: float = Vector2(p.x - _target.x, p.z - _target.z).length()
	print("[MOVE] 结束位置 %s，距目标 %.2f m，单帧最大垂直位移 %.3f m" % [str(p), d, _max_dy])
	check(d < 2.5, "走到了目标附近（%.2f m < 2.5 m）" % d)
	check(d < _start_dist - 3.0, "确实前进了（%.1f → %.1f m）" % [_start_dist, d])
	check(_max_dy < 0.35, "垂直方向没有抖动（单帧最大 %.3f m < 0.35）" % _max_dy)
	check(absf(p.y - Terrain.get_height(p.x, p.z)) < 0.2, "终点仍贴在地面")
	print("[SELFTEST] %d 项检查，%d 项失败" % [_pass + _fail, _fail])
	if _fail == 0:
		print("[SELFTEST] ✅ 移动与贴地全部通过")
	else:
		print("[SELFTEST] ❌ 有 %d 项失败" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
