extends Node3D
## 建造 + 野马贴地 集成自测
##
## 这两条都是"点了没反应 / 看着在飘"的问题，光看代码看不出来：
##   · 建造：`command_build()` 里调了一个不存在的方法（is_passable），
##     运行时抛错中断 → 农夫永远不会去工地 → 建筑永远 0%。
##   · 野马：`_wander()` 只改 x/z，y 一直是出生高度 → 山坡上飞天或入地。
## 所以这里真跑 Main，真下单，真跑 10 秒物理，然后量结果。

var _pass: int = 0
var _fail: int = 0
var _main = null
var _t: int = 0
var _elapsed: float = 0.0
var _site = null
var _n0: int = 0
var _horses: Array = []

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
	_elapsed += delta
	if _elapsed >= 10.0:
		_finish()

func _begin() -> void:
	var g = GameManager.grid
	_n0 = GameManager.all_buildings.size()
	_horses = GameManager.wild_horses.duplicate()

	# 找一块离蜀国官府 6~16 格的可建空地
	var gov = null
	for b in GameManager.all_buildings:
		if b.get("building_id") == "government" and str(b.get("faction")) == GameManager.player_faction:
			gov = b
			break
	check(gov != null, "找到玩家的官府")
	if gov == null:
		_finish()
		return
	var home: Vector2i = g.world_to_grid(gov.global_position)
	var pick = null
	for r in range(4, 17):
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if absi(dx) != r and absi(dz) != r:
					continue
				var p: Vector2i = home + Vector2i(dx, dz)
				if g.is_placeable(p, Vector2i(2, 2)):
					pick = p
					break
			if pick != null:
				break
		if pick != null:
			break
	check(pick != null, "官府附近能找到 2x2 空地")
	if pick == null:
		_finish()
		return

	var wp: Vector3 = g.grid_to_world(pick)
	_main.start_build_mode("house")
	check(_main._build_mode == "house", "成功进入建造模式")
	_main._place_building("house", wp)
	check(GameManager.all_buildings.size() == _n0 + 1,
		"点下去后确实多了一栋建筑（%d → %d）" % [_n0, GameManager.all_buildings.size()])
	# 找到刚放下的那栋（进度未满的房子）
	for b in GameManager.all_buildings:
		if b.get("building_id") == "house" and float(b.get("build_progress")) < 0.999:
			_site = b
			break
	check(_site != null, "新房子处于「建造中」状态")

func _finish() -> void:
	set_physics_process(false)
	if _site != null and is_instance_valid(_site):
		var prog: float = float(_site.get("build_progress"))
		# 注意：真实字段名是私有的 _builders（不是 current_builders）
		var bl: Array = _site.get("_builders")
		var alive: int = 0
		for b in bl:
			if b != null and is_instance_valid(b):
				alive += 1
		print("[BUILD] 10 秒后进度 = %.1f%%  建造者 = %d/%d  base_build_time = %.1fs" % [
			prog * 100.0, alive, int(_site.get("max_builders")),
			float(_site.get("base_build_time"))])
		check(prog > 0.02, "农夫确实在工地干活（进度 %.1f%% > 2%%）" % (prog * 100.0))
	else:
		check(false, "没有拿到建造中的房子")

	# 野马贴地
	var worst: float = 0.0
	for h in _horses:
		if is_instance_valid(h):
			var gh: float = Terrain.get_height(h.global_position.x, h.global_position.z)
			worst = maxf(worst, absf(h.global_position.y - gh))
	print("[HORSE] %d 匹野马，最大离地误差 %.3f m" % [_horses.size(), worst])
	if _horses.size() > 0:
		check(worst < 0.35, "野马全部贴着地面（最大误差 %.3f m < 0.35）" % worst)
	else:
		print("[HORSE] 本局没有野马，跳过")

	print("[SELFTEST] %d 项检查，%d 项失败" % [_pass + _fail, _fail])
	if _fail == 0:
		print("[SELFTEST] ✅ 建造与野马贴地全部通过")
	else:
		print("[SELFTEST] ❌ 有 %d 项失败" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
