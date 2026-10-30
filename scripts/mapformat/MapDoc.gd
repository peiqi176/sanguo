extends Resource
## MapDoc —— 地图数据模型（地图工坊的唯一事实源 / single source of truth）
##
## 两条设计约束，改动前先读：
##
## ① 不用 class_name，一律 preload 引用。
##    本项目在 headless / 新克隆仓库下踩过「.godot 全局类缓存尚未生成 → class_name 解析失败」
##    的坑，TerrainMaterial 已经因此改回 preload。这里保持同一规矩。
##
## ② MapDoc 不持有 Image。
##    地形图始终活在 Terrain autoload 里（编辑器改高度 = 直接改 Terrain.heightmap_img）。
##    如果 MapDoc 也存一份 Image，就会出现两个真相，谁先谁后说不清、存盘时不知道该信谁。
##    所以：MapDoc 只管「元数据 + 对象层 + 区域 + 玩家 + 触发器」，
##          图由 MapIO 在保存时从 Terrain 取、读取时塞回 Terrain。
##
## 坐标约定：一切以 grid（Vector2i）为准，世界坐标由 GridManager.grid_to_world() 派生。
## 这样改了地形之后建筑还站在原地（重新算一次世界 Y 即可），不会出现"房子飘在空中"。

## 当前格式版本。改结构时 +1，并在 MapIO._migrate() 里加一级升级。
const VERSION: int = 1

## 文件标记。MapIO 靠它把「工坊地图」和「MapSaveManager 的老参数图」区分开，
## 两者都住在 user://maps/ 下，格式互不兼容，混读会得到"点进去打不开"的幽灵条目。
const KIND: String = "mapforge"

# --- 身份 ---
var version: int = VERSION
var kind: String = KIND
var map_name: String = "未命名地图"
var author: String = ""
var desc: String = ""
var created: String = ""
var modified: String = ""

# --- 网格与世界 ---
## 一条必须守住的契约：world_size() == grid_n * cell_size
## n=84/120/168，cell=2.0 → 168/240/336
var grid_n: int = 100
var cell_size: float = 2.0

# --- 图尺寸（独立于 grid，不要混为一谈）---
var heightmap_size: int = 256
var biome_size: int = 256

# --- 地形参数字典（MapParams 的全部脚本变量，保留"从这套参数再生成"的能力）---
var terrain: Dictionary = {}

# --- 内容层 ---
var objects: Array = []      # Array[Dictionary]，见下方 SCHEMA 注释
var regions: Array = []
var players: Array = []
var triggers: Array = []
var settings: Dictionary = {}

## objects[] 单条结构（所有 kind 共用一个 schema，只为可读性分字段）：
##   { "kind":"building", "id":"government", "owner":"wei", "grid":[132,24], "rot":0 }
##   { "kind":"unit",     "id":"sword",      "owner":"wei", "grid":[128,20], "rot":180 }
##   { "kind":"resource", "id":"wood",       "grid":[120,18], "amount":900 }
##   { "kind":"resource", "id":"iron",       "grid":[96,12],  "amount":99999, "is_mine":true }
##   { "kind":"village",  "id":"village_0",  "grid":[80,80],  "props":{"is_city":false} }
##   { "kind":"horse",    "id":"chitu",      "grid":[60,90] }
##   { "kind":"deco",     "id":"tree_2",     "pos":[210.5,133.0], "scale":1.2, "rot":0 }
##
## deco 用世界坐标 pos（装饰允许非格对齐、允许叠放），其余全部用 grid。

# ---------------------------------------------------------------- 派生值

func world_size() -> float:
	return float(grid_n) * cell_size

func grid_size() -> Vector2i:
	return Vector2i(grid_n, grid_n)

func start_points() -> Array:
	var out: Array = []
	for p in players:
		if typeof(p) == TYPE_DICTIONARY and p.has("start"):
			var s = p["start"]
			if typeof(s) == TYPE_ARRAY and s.size() >= 2:
				out.append(Vector2i(int(s[0]), int(s[1])))
	return out

func count_by_kind(k: String) -> int:
	var n: int = 0
	for o in objects:
		if typeof(o) == TYPE_DICTIONARY and str(o.get("kind", "")) == k:
			n += 1
	return n

# ---------------------------------------------------------------- 序列化

func to_dict() -> Dictionary:
	return {
		"version": version,
		"kind": kind,
		"name": map_name,
		"author": author,
		"desc": desc,
		"created": created,
		"modified": modified,
		"grid": {"n": grid_n, "cell_size": cell_size},
		"heightmap_size": heightmap_size,
		"biome_size": biome_size,
		"terrain": terrain.duplicate(true),
		"objects": objects.duplicate(true),
		"regions": regions.duplicate(true),
		"players": players.duplicate(true),
		"triggers": triggers.duplicate(true),
		"settings": settings.duplicate(true),
	}

## 就地赋值。返回 false 表示这份 dict 不是工坊地图（调用方应走 legacy 分支）。
##
## 所有数字都显式 int()/float() 转换：JSON 解析出来的整数在不同版本里
## 可能是 int 也可能是 float，不显式转的话 grid_n 会在 "168" 和 "168.0" 之间飘。
func from_dict(d: Dictionary) -> bool:
	if typeof(d) != TYPE_DICTIONARY:
		return false

	# kind 缺失视作早期工坊图（那时还没有这个字段），但仍要能和老参数图区分：
	# 老参数图有 "params.json" 而没有 map.json，压根不会走到这里。
	var k: String = str(d.get("kind", KIND))
	if k != KIND:
		return false

	version = int(d.get("version", 1))
	kind = k
	map_name = str(d.get("name", d.get("map_name", "未命名地图")))
	author = str(d.get("author", ""))
	desc = str(d.get("desc", ""))
	created = str(d.get("created", ""))
	modified = str(d.get("modified", ""))

	var g = d.get("grid", {})
	if typeof(g) == TYPE_DICTIONARY:
		grid_n = int(g.get("n", grid_n))
		cell_size = float(g.get("cell_size", cell_size))

	heightmap_size = int(d.get("heightmap_size", heightmap_size))
	biome_size = int(d.get("biome_size", biome_size))

	var t = d.get("terrain", {})
	if typeof(t) == TYPE_DICTIONARY:
		terrain = (t as Dictionary).duplicate(true)

	objects = _as_array(d.get("objects", []))
	regions = _as_array(d.get("regions", []))
	players = _as_array(d.get("players", []))
	triggers = _as_array(d.get("triggers", []))

	var s = d.get("settings", {})
	if typeof(s) == TYPE_DICTIONARY:
		settings = (s as Dictionary).duplicate(true)

	return true

func _as_array(v) -> Array:
	if typeof(v) == TYPE_ARRAY:
		return (v as Array).duplicate(true)
	return []

func clone():
	var c = get_script().new()
	c.from_dict(to_dict())
	return c

func touch() -> void:
	modified = Time.get_datetime_string_from_system(false, true)

# ---------------------------------------------------------------- 地形参数桥

## 从 MapParams 对象抓取全部脚本变量到 terrain 字典。
## 不硬编码 28 个字段名 —— 以后 MapParams 加字段会自动跟上，不会漏。
func capture_terrain_from(p) -> void:
	terrain.clear()
	if p == null:
		return
	for prop in p.get_property_list():
		if not (int(prop.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		terrain[prop.name] = p.get(prop.name)
	# 顺带把图尺寸同步过来（MapParams 里也有这两个字段）
	if terrain.has("heightmap_size"):
		heightmap_size = int(terrain["heightmap_size"])
	if terrain.has("biome_size"):
		biome_size = int(terrain["biome_size"])
	if terrain.has("world_size"):
		var ws: float = float(terrain["world_size"])
		if ws > 0.0 and cell_size > 0.0:
			grid_n = int(round(ws / cell_size))

## 把 terrain 字典写回 MapParams 对象（读档后重建地形用）。
## 按属性声明类型转换，避免 int 属性收到 float 时出现隐式截断警告。
func apply_terrain_to(p) -> void:
	if p == null:
		return
	for prop in p.get_property_list():
		if not (int(prop.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		if not terrain.has(prop.name):
			continue
		var v = terrain[prop.name]
		match int(prop.type):
			TYPE_INT:
				p.set(prop.name, int(v))
			TYPE_FLOAT:
				p.set(prop.name, float(v))
			_:
				p.set(prop.name, v)

# ---------------------------------------------------------------- 对象层

func add_object(o: Dictionary) -> int:
	objects.append(o)
	touch()
	return objects.size() - 1

## 返回被删除的对象（撤销/剪贴板要用）
func remove_object(idx: int) -> Dictionary:
	if idx < 0 or idx >= objects.size():
		return {}
	var o = objects[idx]
	objects.remove_at(idx)
	touch()
	if typeof(o) == TYPE_DICTIONARY:
		return o
	return {}

func replace_object(idx: int, o: Dictionary) -> void:
	if idx < 0 or idx >= objects.size():
		return
	objects[idx] = o
	touch()

func get_object(idx: int) -> Dictionary:
	if idx < 0 or idx >= objects.size():
		return {}
	var o = objects[idx]
	if typeof(o) == TYPE_DICTIONARY:
		return o
	return {}

## 命中测试用的对象 id（调试/校验用）
func object_ids_by_kind(k: String) -> Array:
	var out: Array = []
	for o in objects:
		if typeof(o) == TYPE_DICTIONARY and str(o.get("kind", "")) == k:
			out.append(str(o.get("id", "")))
	return out

# ---------------------------------------------------------------- 玩家层

func get_player(slot: int) -> Dictionary:
	for p in players:
		if typeof(p) == TYPE_DICTIONARY and int(p.get("slot", -1)) == slot:
			return p
	return {}

func set_player(slot: int, p: Dictionary) -> void:
	p["slot"] = slot
	for i in range(players.size()):
		var cur = players[i]
		if typeof(cur) == TYPE_DICTIONARY and int(cur.get("slot", -1)) == slot:
			players[i] = p
			touch()
			return
	players.append(p)
	touch()

func remove_player(slot: int) -> void:
	for i in range(players.size()):
		var cur = players[i]
		if typeof(cur) == TYPE_DICTIONARY and int(cur.get("slot", -1)) == slot:
			players.remove_at(i)
			touch()
			return
