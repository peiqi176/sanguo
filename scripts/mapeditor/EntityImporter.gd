extends RefCounted
## EntityImporter —— 导入「一个能用的建筑 / 兵种」，而不只是一张贴图（M3-6）
##
## 和 AssetImporter 的分工：
##   · AssetImporter  只管贴图：PNG → assets/sprites/ + asset_map.json
##   · EntityImporter 管玩法数据：往 units.json / buildings.json 里补一条定义
## 导入一个实体 = 两步一起做，否则会出现「调色板里有这行、一点就报未知 id」的半成品。
##
## 为什么不直接改 units.json / buildings.json：
##   那两个是策划表（36 兵种 / 32 建筑），带 _meta、带注释、带手艺平衡；
##   程序化整体重写会把排版和注释冲掉，还会和后续策划改表冲突。
##   所以自建实体单独落 config/custom_units.json / custom_buildings.json，
##   DataLoader 启动时 merge 进内存 —— 想回复原厂状态，删掉这两个文件即可。
##
## 同理：内置 id 不允许被覆盖。撞名直接拒绝，逼你换个名字，
## 免得"我以为在改自己的建筑，其实把官府的 5000 血改成了 300"。

const AssetImporter = preload("res://scripts/mapeditor/AssetImporter.gd")

const KIND_UNIT: String = "unit"
const KIND_BUILDING: String = "building"

const CUSTOM_UNITS_PATH: String = "res://config/custom_units.json"
const CUSTOM_BUILDINGS_PATH: String = "res://config/custom_buildings.json"

## kind → asset_map 里的分类名（贴图挂在哪个分类下）
const ASSET_CAT: Dictionary = {
	KIND_UNIT: "units",
	KIND_BUILDING: "buildings",
}

## kind → 给 UI 用的中文名
const KIND_LABELS: Dictionary = {
	KIND_UNIT: "兵种",
	KIND_BUILDING: "建筑",
}

## 单位可用 category（影响 Unit.gd 的分支：civilian 才能采集/建造）
const UNIT_CATEGORIES: Array = ["civilian", "infantry", "cavalry", "archer", "siege", "navy"]
const UNIT_CATEGORY_LABELS: Dictionary = {
	"civilian": "民夫（可采集/建造）",
	"infantry": "步兵",
	"cavalry": "骑兵",
	"archer": "弓兵",
	"siege": "器械",
	"navy": "水军",
}

## 建筑可用 category
const BUILDING_CATEGORIES: Array = ["production", "governance", "military", "civil", "defense"]
const BUILDING_CATEGORY_LABELS: Dictionary = {
	"production": "生产",
	"governance": "政务",
	"military": "军事",
	"civil": "民生",
	"defense": "防御",
}

## 尺寸上限：和 MapDoc 的 grid_n 无关，纯粹是"再大就不是建筑而是城墙段了"
const MIN_SIZE: int = 1
const MAX_SIZE: int = 8
const MAX_NAME_LEN: int = 16
const MAX_ID_LEN: int = 48

# ---------------------------------------------------------------- 默认定义

## 一个"能立刻用"的兵种默认值。数值取现有 T1 刀兵的水位，
## 不至于导入完就是一份打不动的木头。
static func default_unit_def(display_name: String, category: String = "infantry") -> Dictionary:
	var cat: String = category if UNIT_CATEGORIES.has(category) else "infantry"
	return {
		"name": display_name,
		"category": cat,
		"tier": 1,
		"government_req": 1,
		"hp": 80,
		"atk": 10,
		"def": 4,
		"atk_speed": 1.0,
		"move_speed": 2.6,
		"morale": 60,
		"range": 0.6,
		"pop_cost": 1,
		"cost": {"wood": 20, "gold": 10},
		"train_time": 20,
		# 默认挂在刀兵营：不挂的话它只能在地图编辑器里摆着，
		# 进游戏后没有任何建筑能训练它 —— 那等于只导入了半个人。
		"train_from": ["barracks_sword"],
	}

## 建筑默认值。size=2×2、600 血、25 秒，和"作坊"一档。
static func default_building_def(display_name: String, size: Vector2i = Vector2i(2, 2),
		category: String = "production") -> Dictionary:
	var cat: String = category if BUILDING_CATEGORIES.has(category) else "production"
	return {
		"name": display_name,
		"category": cat,
		"government_req": 1,
		"hp": 600,
		"size": [clampi(size.x, MIN_SIZE, MAX_SIZE), clampi(size.y, MIN_SIZE, MAX_SIZE)],
		"cost": {"wood": 120},
		"build_time": 25,
		"pop_provide": 0,
	}

static func default_def(kind: String, display_name: String) -> Dictionary:
	if kind == KIND_BUILDING:
		return default_building_def(display_name)
	return default_unit_def(display_name)

# ---------------------------------------------------------------- 校验

## 返回 { ok, errors[], warnings[] }。errors 非空 → 不许导入。
## 只看"这条定义进游戏会不会出错"，不管美术（美术由 AssetImporter.validate 管）。
static func validate(kind: String, entity_id: String, def: Dictionary) -> Dictionary:
	var errors: Array = []
	var warnings: Array = []

	if kind != KIND_UNIT and kind != KIND_BUILDING:
		return {"ok": false, "errors": ["未知类型：%s（只能是 unit / building）" % kind], "warnings": []}

	var id_err: String = check_id(kind, entity_id)
	if id_err != "":
		errors.append(id_err)

	var nm: String = str(def.get("name", "")).strip_edges()
	if nm == "":
		errors.append("名字不能为空（调色板和建造菜单上显示的就是它）")
	elif nm.length() > MAX_NAME_LEN:
		errors.append("名字太长（最多 %d 个字）" % MAX_NAME_LEN)

	if kind == KIND_BUILDING:
		var size = def.get("size", [2, 2])
		if typeof(size) != TYPE_ARRAY or (size as Array).size() < 2:
			errors.append("尺寸格式不对（应为 [宽, 深]）")
		else:
			var sx: int = int(size[0])
			var sy: int = int(size[1])
			if sx < MIN_SIZE or sy < MIN_SIZE or sx > MAX_SIZE or sy > MAX_SIZE:
				errors.append("尺寸 %d×%d 超范围（每边 %d~%d 格）" % [sx, sy, MIN_SIZE, MAX_SIZE])
			elif sx * sy > 36:
				warnings.append("占地 %d×%d = %d 格，大地图上很容易放不下" % [sx, sy, sx * sy])
		if float(def.get("build_time", 0)) < 0.0:
			errors.append("建造时间不能是负数")
		if float(def.get("hp", 0)) <= 0.0:
			errors.append("血量必须大于 0")
	else:
		var cat: String = str(def.get("category", ""))
		if not UNIT_CATEGORIES.has(cat):
			errors.append("兵种类别「%s」不认识（可选：%s）" % [cat, ", ".join(PackedStringArray(UNIT_CATEGORIES))])
		if float(def.get("hp", 0)) <= 0.0:
			errors.append("血量必须大于 0")
		if float(def.get("move_speed", 0)) <= 0.0:
			errors.append("移动速度必须大于 0（否则单位永远走不到目标点）")
		if float(def.get("train_time", 0)) < 0.0:
			errors.append("训练时间不能是负数")
		if float(def.get("atk", 0)) < 0.0:
			errors.append("攻击力不能是负数")
		if float(def.get("range", 0)) < 0.0:
			errors.append("射程不能是负数")
		var tf = def.get("train_from", [])
		if typeof(tf) == TYPE_ARRAY:
			for bid in (tf as Array):
				if DataLoader.get_building_def(str(bid)).is_empty():
					errors.append("训练建筑「%s」不存在" % str(bid))
		elif typeof(tf) != TYPE_NIL:
			errors.append("train_from 应该是建筑 id 数组")

	var cost = def.get("cost", {})
	if typeof(cost) != TYPE_DICTIONARY:
		errors.append("造价格式不对（应为 {资源: 数量}）")
	elif not (cost as Dictionary).is_empty():
		for k in (cost as Dictionary).keys():
			if not ["wood", "food", "gold", "iron", "stone"].has(str(k)):
				warnings.append("造价里的资源「%s」游戏并不存在，会被忽略" % str(k))
			if float((cost as Dictionary)[k]) < 0.0:
				errors.append("造价「%s」不能是负数" % str(k))

	return {"ok": errors.is_empty(), "errors": errors, "warnings": warnings}

## id 合法性（含撞名检查）。返回空串表示通过。
static func check_id(kind: String, entity_id: String) -> String:
	var id: String = entity_id.strip_edges()
	if id == "":
		return "实体 id 不能为空"
	if id.length() > MAX_ID_LEN:
		return "实体 id 太长（最多 %d 字符）" % MAX_ID_LEN
	var re: RegEx = RegEx.new()
	re.compile("^[a-z][a-z0-9_]*$")
	if re.search(id) == null:
		return "实体 id 只能用小写字母/数字/下划线，且不能以数字开头（现在是「%s」）" % id
	if is_builtin(kind, id):
		return "「%s」是内置%s的 id，不能覆盖。换一个名字（比如 %s_2）" % [
			id, str(KIND_LABELS.get(kind, kind)), id]
	return ""

# ---------------------------------------------------------------- 导入

## 完整导入：贴图 + 玩法定义。
##   src_png     原始 PNG（可以在 res:// 之外，比如桌面）
##   kind        unit / building
##   entity_id   实体 id（也是文件名、调色板里的 key）
##   def         玩法定义（见 default_*_def()）
##   sprite_scale Sprite3D.scale；<=0 用该分类缺省值
## 返回 { ok, message, errors[], sprite }
static func import_entity(src_png: String, kind: String, entity_id: String,
		def: Dictionary, sprite_scale: float = -1.0) -> Dictionary:
	if kind != KIND_UNIT and kind != KIND_BUILDING:
		return {"ok": false, "message": "未知类型：%s" % kind, "errors": [], "sprite": ""}
	var id: String = entity_id.strip_edges()

	var v: Dictionary = validate(kind, id, def)
	if not bool(v.get("ok", false)):
		var errs: Array = v.get("errors", [])
		return {
			"ok": false,
			"message": "定义有问题：" + "；".join(PackedStringArray(errs)),
			"errors": errs,
			"sprite": "",
		}

	# ① 贴图（AssetImporter 自己会做图片校验，不合格直接中止）
	var asset_cat: String = str(ASSET_CAT[kind])
	var res: Dictionary = AssetImporter.import_file(src_png, asset_cat, id, sprite_scale, false)
	if not bool(res.get("ok", false)):
		return {"ok": false, "message": str(res.get("message", "贴图导入失败")), "errors": [], "sprite": ""}

	# ② 玩法定义
	var clean: Dictionary = _sanitize_def(kind, id, def)
	var store: Dictionary = _read_store(kind)
	var block = store.get(_container_key(kind), {})
	if typeof(block) != TYPE_DICTIONARY:
		block = {}
	var existed: bool = (block as Dictionary).has(id)
	(block as Dictionary)[id] = clean
	store[_container_key(kind)] = block
	if not _write_store(kind, store):
		# 定义写不进去就别说成功 —— 只留一张贴图的半成品比彻底失败更难查
		return {"ok": false, "message": "写不动 %s（目录只读？）" % _store_path(kind), "errors": [], "sprite": ""}

	DataLoader.reload_entities()

	return {
		"ok": true,
		"message": "%s%s「%s」(%s)：%s" % [
			"覆盖" if existed else "新增", str(KIND_LABELS.get(kind, kind)),
			str(clean.get("name", id)), id, str(res.get("message", "")),
		],
		"errors": [],
		"sprite": str(res.get("sprite", "")),
	}

## 删除自建实体：定义 + 贴图映射一起摘掉，PNG 文件保留（落到「未注册」分组）。
## 内置实体拒绝删除（它们在 units.json / buildings.json 里，这里动不了）。
static func remove_entity(kind: String, entity_id: String) -> Dictionary:
	if is_builtin(kind, entity_id):
		return {"ok": false, "message": "「%s」是内置%s，不能删" % [entity_id, str(KIND_LABELS.get(kind, kind))]}
	var store: Dictionary = _read_store(kind)
	var key: String = _container_key(kind)
	var block = store.get(key, {})
	if typeof(block) != TYPE_DICTIONARY or not (block as Dictionary).has(entity_id):
		return {"ok": false, "message": "「%s」不是自建%s，没东西可删" % [entity_id, str(KIND_LABELS.get(kind, kind))]}
	(block as Dictionary).erase(entity_id)
	store[key] = block
	if not _write_store(kind, store):
		return {"ok": false, "message": "写不动 %s" % _store_path(kind)}
	AssetImporter.remove_entry(str(ASSET_CAT[kind]), entity_id)
	DataLoader.reload_entities()
	return {"ok": true, "message": "已删除 %s（贴图文件保留，可在「未注册」里找回）" % entity_id}

# ---------------------------------------------------------------- 查询

static func is_builtin(kind: String, entity_id: String) -> bool:
	if kind == KIND_UNIT:
		return not DataLoader.get_unit_def(entity_id).is_empty() and not is_custom(kind, entity_id)
	return not DataLoader.get_building_def(entity_id).is_empty() and not is_custom(kind, entity_id)

## 是否为自建实体（在 custom_*.json 里）
static func is_custom(kind: String, entity_id: String) -> bool:
	var store: Dictionary = _read_store(kind)
	var block = store.get(_container_key(kind), {})
	if typeof(block) != TYPE_DICTIONARY:
		return false
	return (block as Dictionary).has(entity_id)

static func custom_ids(kind: String) -> Array:
	var store: Dictionary = _read_store(kind)
	var block = store.get(_container_key(kind), {})
	var out: Array = []
	if typeof(block) == TYPE_DICTIONARY:
		out = (block as Dictionary).keys()
	out.sort()
	return out

## UI 里"自动取个没被占用的 id"用：base → base_2 → base_3 …
static func next_free_id(kind: String, base: String) -> String:
	var root: String = _sanitize_id(base)
	if root == "":
		root = "custom_" + ("unit" if kind == KIND_UNIT else "building")
	if check_id(kind, root) == "" and not is_custom(kind, root):
		return root
	for i in range(2, 100):
		var cand: String = "%s_%d" % [root, i]
		if check_id(kind, cand) == "" and not is_custom(kind, cand):
			return cand
	return "%s_%d" % [root, Time.get_ticks_msec()]

# ---------------------------------------------------------------- 内部

static func _store_path(kind: String) -> String:
	return CUSTOM_UNITS_PATH if kind == KIND_UNIT else CUSTOM_BUILDINGS_PATH

static func _container_key(kind: String) -> String:
	return "units" if kind == KIND_UNIT else "buildings"

## 只保留认识且有意义的字段，顺手把数值类型规范一遍。
## 为什么要白名单：UI 上传进来的字段名写错一个字母，就会变成"看上去导入成功、
## 但那个属性永远是默认值"。与其静默吞掉，不如在这里就按定义裁剪。
static func _sanitize_def(kind: String, entity_id: String, def: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	out["name"] = str(def.get("name", entity_id)).strip_edges()
	out["category"] = str(def.get("category", "infantry" if kind == KIND_UNIT else "production"))
	out["government_req"] = int(def.get("government_req", 1))
	out["hp"] = float(def.get("hp", 80.0 if kind == KIND_UNIT else 600.0))
	var cost: Dictionary = {}
	var raw_cost = def.get("cost", {})
	if typeof(raw_cost) == TYPE_DICTIONARY:
		for k in (raw_cost as Dictionary).keys():
			if ["wood", "food", "gold", "iron", "stone"].has(str(k)):
				cost[str(k)] = int(round(float((raw_cost as Dictionary)[k])))
	out["cost"] = cost
	# 标记来源，方便以后在策划表里一眼区分"这是编辑器导入的"
	out["custom"] = true

	if kind == KIND_BUILDING:
		var size = def.get("size", [2, 2])
		var sx: int = 2
		var sy: int = 2
		if typeof(size) == TYPE_ARRAY and (size as Array).size() >= 2:
			sx = clampi(int(size[0]), MIN_SIZE, MAX_SIZE)
			sy = clampi(int(size[1]), MIN_SIZE, MAX_SIZE)
		out["size"] = [sx, sy]
		out["build_time"] = float(def.get("build_time", 25.0))
		out["pop_provide"] = int(def.get("pop_provide", 0))
	else:
		out["tier"] = int(def.get("tier", 1))
		out["atk"] = float(def.get("atk", 10.0))
		out["def"] = float(def.get("def", 4.0))
		out["atk_speed"] = float(def.get("atk_speed", 1.0))
		out["move_speed"] = float(def.get("move_speed", 2.6))
		out["morale"] = float(def.get("morale", 60.0))
		out["range"] = float(def.get("range", 0.6))
		out["pop_cost"] = int(def.get("pop_cost", 1))
		out["train_time"] = float(def.get("train_time", 20.0))
		var tf: Array = []
		var raw_tf = def.get("train_from", [])
		if typeof(raw_tf) == TYPE_ARRAY:
			for bid in (raw_tf as Array):
				var sid: String = str(bid)
				# 只收真实存在、且本来就带训练列表的建筑 ——
				# 挂到"官府"这种没有 trains 的建筑上，Building.gd 也不会列它，
				# 存进去只会变成一条永远不生效的配置。
				var bd: Dictionary = DataLoader.get_building_def(sid)
				if bd.is_empty():
					continue
				if typeof(bd.get("trains", null)) != TYPE_ARRAY and not is_custom(KIND_BUILDING, sid):
					continue
				if not tf.has(sid):
					tf.append(sid)
		out["train_from"] = tf
	return out

## UI 用：哪些建筑可以挂"训练新兵种"。
## 只列本来就有 trains 的（兵营/器械房/船厂…），没有 trains 的建筑挂上去也不生效。
static func trainable_buildings() -> Array:
	var out: Array = []
	var all: Dictionary = DataLoader.buildings.get("buildings", {})
	for bid in all.keys():
		var bd = all[bid]
		if typeof(bd) != TYPE_DICTIONARY:
			continue
		if typeof(bd.get("trains", null)) == TYPE_ARRAY:
			out.append({"id": str(bid), "name": str(bd.get("name", bid))})
	out.sort_custom(func(a, b): return str(a["name"]) < str(b["name"]))
	return out

static func _read_store(kind: String) -> Dictionary:
	var path: String = _store_path(kind)
	if not FileAccess.file_exists(path):
		return {
			"_meta": {
				"note": "编辑器「导入%s」生成的自建实体。内置实体在 %s，不要往这里抄。" % [
					str(KIND_LABELS.get(kind, kind)),
					"units.json" if kind == KIND_UNIT else "buildings.json",
				],
			},
		}
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text: String = f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("[EntityImporter] %s 解析失败，当作空表处理" % path)
		return {}
	return parsed

static func _write_store(kind: String, store: Dictionary) -> bool:
	var f: FileAccess = FileAccess.open(_store_path(kind), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(store, "  ") + "\n")
	f.close()
	return true

static func _sanitize_id(raw: String) -> String:
	var re: RegEx = RegEx.new()
	re.compile("[^a-z0-9_]")
	var s: String = re.sub(raw.strip_edges().to_lower(), "_", true)
	# 去掉开头的非字母
	while s.length() > 0 and not (s[0] >= "a" and s[0] <= "z"):
		s = s.substr(1)
	return s
