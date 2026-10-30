extends Node
## 闭环自测：一键生成 → 存盘 → 以 custom 模式重启 Main → 建筑真的进了场景
##
## 验证的是"生成的地图能不能玩"，不是"数据写对没写对"。
## 前面几套测的都是 doc 层面；这一套走的是玩家真实路径：
##   MapGenService.generate_and_save()  →  GameManager.map_mode = "custom"
##   →  Main._apply_map_mode()  →  MapIO.load_map()  →  _spawn_from_doc()
##
## 只要这条链上任何一环断了（文件名不一致、doc 没存 objects、
## custom 分支读不到图、spawn 时 grid 尺寸不匹配），建筑数就会是 0。

const MapTemplates = preload("res://scripts/mapgen/MapTemplates.gd")
const MapGenService = preload("res://scripts/mapgen/MapGenService.gd")
const MapIO = preload("res://scripts/mapformat/MapIO.gd")

const MAP_NAME: String = "_selftest_playable"

var _pass: int = 0
var _fail: int = 0
var _t: int = 0
var _main = null

func check(ok: bool, what: String) -> void:
	if ok:
		_pass += 1
		print("[PLAYABLE] ✅ ", what)
	else:
		_fail += 1
		print("[PLAYABLE] ❌ ", what)

func _ready() -> void:
	# ① 先造一张图并落盘（这一步不需要 Main 在场）
	var tpl: Dictionary = MapTemplates.template_def("two_kingdoms")
	tpl["grid_n"] = 72
	tpl["min_start_dist"] = 20
	tpl["players"] = 2
	var gen: Dictionary = MapGenService.generate_and_save(tpl, {
		"map_name": MAP_NAME, "heightmap_size": 128, "biome_size": 128,
	})
	print("[PLAYABLE] 生成：ok=%s error=%s map=%s" % [
		str(gen["ok"]), str(gen["error"]), str(gen["map_name"])])
	check(bool(gen["ok"]), "生成并成功存盘")
	check(MapIO.exists(MAP_NAME), "地图文件确实在 user://maps/ 下")
	# 诊断：盘上的 doc 到底记了什么尺寸
	var probe: Dictionary = MapIO.load_map(MAP_NAME)
	if not probe.is_empty():
		var pd = probe["doc"]
		print("[PLAYABLE] 盘上 doc：grid_n=%d cell_size=%.1f world_size()=%.1f terrain.world_size=%s" % [
			pd.grid_n, pd.cell_size, pd.world_size(), str(pd.terrain.get("world_size", "缺失"))])

	# ② 用 custom 模式起 Main —— 走的就是玩家点「试玩」时的同一条路
	GameManager.game_settings_override = {
		"map_mode": "custom",
		"map_saved_name": MAP_NAME,
	}
	GameManager.apply_settings()
	check(GameManager.map_mode == "custom", "GameManager 切到 custom 模式")
	_main = load("res://scenes/Main.tscn").instantiate()
	add_child(_main)

func _process(_d: float) -> void:
	_t += 1
	if _t < 40:
		return
	set_process(false)
	_verify()

func _verify() -> void:
	var nb: int = 0
	var nu: int = 0
	var nr: int = 0
	for c in _main.get_children():
		if c.get("building_id") != null:
			nb += 1
		elif c.get("unit_id") != null:
			nu += 1
		elif c.get("resource_id") != null or c.get("node_type") != null:
			nr += 1
	print("[PLAYABLE] 场景实体：建筑 %d / 单位 %d / 资源 %d" % [nb, nu, nr])
	check(nb > 0, "自定义地图的建筑进了场景（%d 栋）" % nb)
	check(nu > 0, "自定义地图的单位进了场景（%d 个）" % nu)
	check(_main.grid.map_size.x == 72, "网格尺寸跟随地图（%d）" % _main.grid.map_size.x)

	# 建筑必须站在地面上，不能埋进山里
	var worst_sink: float = 0.0
	for c in _main.get_children():
		if c.get("building_id") == null:
			continue
		var gp: Vector3 = (c as Node3D).global_position
		var gh: float = Terrain.get_height(gp.x, gp.z)
		worst_sink = maxf(worst_sink, absf(gp.y - gh))
	check(worst_sink < 2.0, "建筑离地误差 %.2f m < 2.0" % worst_sink)

	# 清场：别把测试地图留在用户目录里
	MapIO.delete_map(MAP_NAME)
	check(not MapIO.exists(MAP_NAME), "测试地图已清理")

	print("[SELFTEST] %d 项检查，%d 项失败" % [_pass + _fail, _fail])
	if _fail == 0:
		print("[SELFTEST] ✅ 生成地图可玩性闭环通过")
	else:
		print("[SELFTEST] ❌ 有 %d 项失败" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
