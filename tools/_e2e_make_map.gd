extends Node
## 端到端测试（第一步）：造一张**带对象**的地图存盘，然后以 custom 模式启动游戏。
##
## 跑法：
##   Godot_v4.7.2-stable_mono_win64_console.exe --headless --path . --quit-after 300 \
##     res://tools/_e2e_make_map.tscn
##
## 期望日志（在 Main 里）：
##   [Main] ✅ 已载入自定义地图 _selftest_e2e（256²，200 m，4 个对象）
##   [Main] 按地图对象铺装：成功 4，失败 0
##
## 这条链路是"地图工坊能不能给游戏供图"的唯一判据：
## 编辑器存 → MapIO 读 → ObjectSpawner 铺 → 实体真的进了场景树。

const MapDoc = preload("res://scripts/mapformat/MapDoc.gd")
const MapIO = preload("res://scripts/mapformat/MapIO.gd")

const TEST_MAP: String = "_selftest_e2e"

func _ready() -> void:
	Terrain.generate(Terrain.default_params())

	var doc = MapDoc.new()
	doc.map_name = TEST_MAP
	doc.cell_size = 2.0
	doc.capture_terrain_from(Terrain.params)

	var n: int = doc.grid_n
	var placed: int = 0

	# 官府 3×3
	var a: Vector2i = _find_land(n, 3)
	if a != Vector2i(-1, -1):
		doc.add_object({"kind": "building", "id": "government", "owner": "shu",
				"grid": [a.x, a.y], "rot": 0})
		placed += 1

	# 两个兵（避开官府的 3×3）
	var b: Vector2i = _find_land(n, 1, a + Vector2i(4, 0))
	if b != Vector2i(-1, -1):
		doc.add_object({"kind": "unit", "id": "sword", "owner": "shu",
				"grid": [b.x, b.y], "rot": 0})
		placed += 1
	var c: Vector2i = _find_land(n, 1, b + Vector2i(1, 0))
	if c != Vector2i(-1, -1):
		doc.add_object({"kind": "unit", "id": "archer", "owner": "shu",
				"grid": [c.x, c.y], "rot": 0})
		placed += 1

	# 一棵树（世界坐标）
	var t: Vector2i = _find_land(n, 1, c + Vector2i(0, 2))
	if t != Vector2i(-1, -1):
		var wx: float = (float(t.x) + 0.5) * doc.cell_size
		var wz: float = (float(t.y) + 0.5) * doc.cell_size
		doc.add_object({"kind": "deco", "id": "tree_1", "pos": [wx, wz], "scale": 1.1})
		placed += 1

	var ok: bool = MapIO.save(doc, Terrain.heightmap_img, Terrain.biome_img)
	print("[E2E] 造图完成：%d 个对象，存盘%s → %s" % [placed, "成功" if ok else "失败", TEST_MAP])
	if not ok:
		get_tree().quit(1)
		return

	# 必须走 game_settings_override：Main._ready 第一件事是 apply_settings()，
	# 它会用 override（或磁盘存档）**无条件覆盖** GameManager.map_mode。
	# 直接给 GameManager.map_mode 赋值会被它冲掉，然后默默跑成 preset。
	GameManager.editor_mode = false
	GameManager.game_settings_override = {
		"map_mode": "custom",
		"map_saved_name": TEST_MAP,
	}
	# 延后一帧再切场景：这里还在 _ready 里，场景树正忙着 add_child，
	# 当场切会报 "Parent node is busy adding/removing children"。
	get_tree().change_scene_to_file.call_deferred("res://scenes/Main.tscn")

## 在网格里找一块 size×size 全陆地的位置；prefer 是"从这里开始找"的提示点
func _find_land(n: int, size: int, prefer: Vector2i = Vector2i(4, 4)) -> Vector2i:
	var start: Vector2i = prefer if prefer.x > 0 and prefer.y > 0 else Vector2i(4, 4)
	# 先试提示点附近，再全图扫
	for radius in range(0, 12):
		for dx in range(-radius, radius + 1):
			for dz in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dz)) != radius:
					continue
				var p: Vector2i = start + Vector2i(dx, dz)
				if _is_all_land(p, size, n):
					return p
	for gx in range(4, n - 4):
		for gz in range(4, n - 4):
			if _is_all_land(Vector2i(gx, gz), size, n):
				return Vector2i(gx, gz)
	return Vector2i(-1, -1)

func _is_all_land(p: Vector2i, size: int, n: int) -> bool:
	if p.x < 0 or p.y < 0 or p.x + size > n or p.y + size > n:
		return false
	for dx in range(size):
		for dz in range(size):
			var wx: float = (float(p.x + dx) + 0.5) * 2.0
			var wz: float = (float(p.y + dz) + 0.5) * 2.0
			if Terrain.is_water(wx, wz):
				return false
	return true
