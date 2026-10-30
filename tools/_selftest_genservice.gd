extends Node3D
## MapGenService 端到端自测：真 Terrain + 真生成 + 真存盘 + 真读回
##
## 前面 _selftest_mapgen 测的是"零件对不对"，这套测的是"整条流水线通不通"：
## 模板 → 地形重生成 → 对称化 → 起点 → 铺内容 → 校验 → 存盘 → 读回。
##
## 为什么必须真跑：这条链上每一步都会改全局状态（Terrain.heightmap_img 是引用，
## ImageTexture 是拷贝，GridManager 是新建节点），任何一环漏刷新都不会报错，
## 只会静静地生成一张"屏幕上和硬盘里不一样"的地图。

const MapDoc = preload("res://scripts/mapformat/MapDoc.gd")
const MapIO = preload("res://scripts/mapformat/MapIO.gd")
const MapTemplates = preload("res://scripts/mapgen/MapTemplates.gd")
const MapSymmetric = preload("res://scripts/mapgen/MapSymmetric.gd")
const MapValidator = preload("res://scripts/mapgen/MapValidator.gd")
const MapGenService = preload("res://scripts/mapgen/MapGenService.gd")

var _pass: int = 0
var _fail: int = 0
var _t: int = 0
var _main = null

func check(ok: bool, what: String) -> void:
	if ok:
		_pass += 1
		print("[GENSVC] ✅ ", what)
	else:
		_fail += 1
		print("[GENSVC] ❌ ", what)

func _ready() -> void:
	_main = load("res://scenes/Main.tscn").instantiate()
	add_child(_main)

func _process(_d: float) -> void:
	_t += 1
	if _t < 30:
		return
	set_process(false)
	_run()
	print("[SELFTEST] %d 项检查，%d 项失败" % [_pass + _fail, _fail])
	if _fail == 0:
		print("[SELFTEST] ✅ 一键生成管线端到端通过")
	else:
		print("[SELFTEST] ❌ 有 %d 项失败" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)

func _run() -> void:
	# 用「双雄争霸」：2 人镜像图，逻辑最简单，出问题最容易定位
	var tpl: Dictionary = MapTemplates.template_def("two_kingdoms")
	check(not tpl.is_empty(), "取到模板 two_kingdoms")
	tpl["grid_n"] = 72
	tpl["min_start_dist"] = 20
	tpl["players"] = 2

	var r: Dictionary = MapGenService.generate(tpl, {
		"map_name": "_selftest_gen",
		"heightmap_size": 128,     # 测速：128 比 256 快 4 倍，逻辑完全一样
		"biome_size": 128,
	})
	print("[GENSVC] 生成结果：ok=%s  error=%s" % [str(r["ok"]), str(r["error"])])
	if not str(r["text"]).is_empty():
		print(r["text"])

	var doc = r["doc"]
	var grid = r["grid"]
	check(doc != null, "产出了 MapDoc")
	check(grid != null, "产出了网格")
	check(str(r["error"]).is_empty() or bool(r["ok"]), "无致命错误（%s）" % str(r["error"]))
	if doc == null:
		return

	# ① 尺寸契约：world_size == grid_n × cell_size
	check(absf(doc.world_size() - float(doc.grid_n) * doc.cell_size) < 0.01,
		"world_size = %d × %.1f = %.1f（实际 %.1f）" % [
			doc.grid_n, doc.cell_size, float(doc.grid_n) * doc.cell_size, doc.world_size()])
	check(Terrain.params.get("world_size") != null
		and absf(float(Terrain.params.get("world_size")) - doc.world_size()) < 0.01,
		"Terrain.params.world_size 与 doc 对齐（%.1f）" % doc.world_size())

	# ② 起点
	check(doc.players.size() == 2, "写入 2 个玩家（实际 %d）" % doc.players.size())
	var sp: Array = doc.start_points()
	check(sp.size() == 2, "2 个起点（实际 %d）" % sp.size())
	if sp.size() == 2:
		var d: float = Vector2(float(sp[0].x - sp[1].x), float(sp[0].y - sp[1].y)).length()
		check(d >= 20.0, "起点间距 %.1f ≥ 20" % d)
		# 镜像模式下两点必须互为镜像（这是公平性的几何保证）
		var mode: int = int(tpl.get("symmetry", 0))
		check(sp[1] == MapSymmetric.mirror(sp[0], doc.grid_n, mode),
			"起点严格对称 %s ↔ %s" % [str(sp[0]), str(sp[1])])

	# ③ 内容
	check(doc.count_by_kind("building") >= 4, "有建筑（%d 栋）" % doc.count_by_kind("building"))
	check(doc.count_by_kind("resource") >= 8, "有资源点（%d 个）" % doc.count_by_kind("resource"))
	check(doc.count_by_kind("unit") >= 4, "有开局单位（%d 个）" % doc.count_by_kind("unit"))
	check(doc.count_by_kind("deco") > 0, "有装饰（%d 个）" % doc.count_by_kind("deco"))

	# ④ 地形真的对称了（高度图逐点验证，这是"对称化有没有落到图上"的唯一证据）
	var imgs: Dictionary = Terrain.export_images()
	var h: Image = imgs.get("height", null)
	check(h != null, "拿到高度图")
	if h != null:
		var mode2: int = int(tpl.get("symmetry", 0))
		var worst: float = 0.0
		var n: int = h.get_width()
		var step: int = maxi(1, n / 48)      # 抽样 48×48，够发现不对称
		for y in range(0, n, step):
			for x in range(0, n, step):
				var src: Vector2i = MapSymmetric.primary_of(Vector2i(x, y), n, n, mode2)
				worst = maxf(worst, absf(h.get_pixel(x, y).r - h.get_pixel(src.x, src.y).r))
		check(worst < 0.001, "高度图已对称化，抽样最大差 %.6f m" % worst)
		check(Terrain.heightmap_tex != null, "纹理已刷新（不刷新会画面与存档不一致）")

	# ⑤ 校验
	var rep: Dictionary = r["report"]
	check(rep.get("results", []).size() == 7, "跑满 7 项校验")
	check(bool(rep["ok"]), "校验通过（错误 %d / 警告 %d）" % [int(rep["errors"]), int(rep["warns"])])

	# ⑥ 存盘 + 读回
	var saved: bool = MapIO.save(doc, h, imgs.get("biome", null))
	check(saved, "存盘成功")
	if saved:
		var back: Dictionary = MapIO.load_map(doc.map_name)
		check(not back.is_empty(), "能读回地图")
		if not back.is_empty():
			var d2 = back["doc"]
			check(d2.grid_n == doc.grid_n, "读回 grid_n 一致（%d）" % d2.grid_n)
			check(d2.objects.size() == doc.objects.size(),
				"读回对象数一致（%d == %d）" % [d2.objects.size(), doc.objects.size()])
			check(d2.players.size() == doc.players.size(),
				"读回玩家数一致（%d）" % d2.players.size())
			var bh: Image = back.get("height", null)
			check(bh != null and bh.get_width() == h.get_width(),
				"读回高度图分辨率一致")
		# 清理，别污染用户的 user://maps
		MapIO.delete_map(doc.map_name)
		check(not MapIO.exists(doc.map_name), "测试地图已清理")

	if grid != null and is_instance_valid(grid):
		grid.free()
