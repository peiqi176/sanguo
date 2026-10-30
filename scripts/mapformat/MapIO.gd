extends RefCounted
## MapIO —— 地图文件的唯一读写入口（磁盘格式的全部知识都在这里）
##
## 磁盘布局（开发期用目录；发布期可 pack 成 .sgmap，本质是 zip）：
##   user://maps/<地图名>/
##   ├── map.json            # 元数据 + 对象/区域/玩家/触发器（人可读、可 diff）
##   ├── height.raw          # int32 w | int32 h | float32[w*h]  —— 无损、零编解码依赖
##   ├── height_preview.png  # 8bit 灰度预览（调试/缩略图候选）
##   ├── biome.png           # RGBA8 群系权重：R=森林 G=土地 B=石板 A=保留
##   ├── splat.png           # RGBA8 人工拼图层：R=沙地 G=泥土 B=岩石 A=森林地被（可缺省）
##   └── thumbnail.png       # 小地图快照（选图界面用，P7 生成）
##
## ⚠️ user://maps/ 是共享目录，MapSaveManager 的老参数图也住在这里（params.json + biome.png）。
##    两者格式互不兼容，所以：
##      · 工坊地图一定带 "kind": "mapforge" 且一定有 map.json
##      · 老参数图只有 params.json，没有 map.json
##    list_maps() 两种都列，但用 legacy 字段区分，绝不混读。
##
## 另一条规矩：本类不依赖 Terrain。图由调用方传进来 / 传出去，
## 这样它能在 headless 测试里单独跑，不需要 autoload 就绪。

const MapDoc = preload("res://scripts/mapformat/MapDoc.gd")

const MAP_ROOT: String = "user://maps/"

## 一张地图目录里所有可能出现的文件名（pack 按这个顺序收集）
const MAP_FILES: Array[String] = [
	"map.json", "height.raw", "biome.png", "height_preview.png", "thumbnail.png", "splat.png", "splat2.png",
]

# ---------------------------------------------------------------- 保存

## 保存一张地图。height / biome / splat / splat2 传 null 则保留磁盘上的旧图（只改元数据时用）。
static func save(doc, height: Image, biome: Image, splat: Image = null, splat2: Image = null) -> bool:
	if doc == null:
		push_error("[MapIO] save: doc 为 null")
		return false

	var nm: String = sanitize_name(str(doc.map_name))
	if nm == "":
		nm = "未命名地图"
	doc.map_name = nm

	var dir: String = MAP_ROOT + nm + "/"
	var err: int = DirAccess.make_dir_recursive_absolute(dir)
	if err != OK:
		push_error("[MapIO] 无法创建目录 %s (err=%d)" % [dir, err])
		return false

	if height != null:
		if not _write_height(dir + "height.raw", height):
			return false
		doc.heightmap_size = height.get_width()
		_write_height_preview(dir + "height_preview.png", height)

	if biome != null:
		if biome.save_png(dir + "biome.png") != OK:
			push_warning("[MapIO] 群系图写入失败：" + dir + "biome.png")
		doc.biome_size = biome.get_width()

	if splat != null:
		# 拼图层存 PNG：RGBA8 无损，人也能用看图软件打开检查（排查"刷的东西存丢了"很有用）。
		# 全空（一次都没刷）时直接删掉旧文件，别让磁盘上留一张全透明 PNG 增加歧义。
		if _is_splat_empty(splat):
			var da: DirAccess = DirAccess.open(dir)
			if da != null and da.file_exists("splat.png"):
				da.remove("splat.png")
		elif splat.save_png(dir + "splat.png") != OK:
			push_warning("[MapIO] 拼图层写入失败：" + dir + "splat.png")

	# 第二张拼图（石板路/土路）。老地图没有这个文件 = 正常，读档时用空图。
	if splat2 != null:
		if _is_splat_empty(splat2):
			var da2: DirAccess = DirAccess.open(dir)
			if da2 != null and da2.file_exists("splat2.png"):
				da2.remove("splat2.png")
		elif splat2.save_png(dir + "splat2.png") != OK:
			push_warning("[MapIO] 道路层写入失败：" + dir + "splat2.png")

	doc.touch()
	var jf: FileAccess = FileAccess.open(dir + "map.json", FileAccess.WRITE)
	if jf == null:
		push_error("[MapIO] 无法写入 map.json：" + dir)
		return false
	jf.store_string(JSON.stringify(doc.to_dict(), "\t"))
	jf.close()
	return true

## 拼图层是不是一次都没刷过（四个通道全 0）。
## 稀疏采样就够：手刷过一笔，笔刷半径内必然有大量非零像素，
## 而且这里会在每次存盘时跑一遍，200 万像素全扫会拖慢保存。
static func _is_splat_empty(img: Image) -> bool:
	if img == null:
		return true
	var sz_x: int = img.get_width()
	var sz_y: int = img.get_height()
	for py in range(0, sz_y, 3):
		for px in range(0, sz_x, 3):
			var c: Color = img.get_pixel(px, py)
			if c.r + c.g + c.b + c.a > 0.004:
				return false
	return true

# ---------------------------------------------------------------- 读取

## 返回 { "doc": MapDoc, "height": Image|null, "biome": Image|null, "dir": String }
## 失败返回 {}（调用方据此退回程序生成）。
static func load_map(map_name: String) -> Dictionary:
	var nm: String = sanitize_name(map_name)
	var dir: String = MAP_ROOT + nm + "/"
	if not FileAccess.file_exists(dir + "map.json"):
		return {}

	var txt: String = FileAccess.get_file_as_string(dir + "map.json")
	var parsed = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("[MapIO] map.json 解析失败：" + dir)
		return {}

	var d: Dictionary = _migrate(parsed)
	var doc = MapDoc.new()
	if not doc.from_dict(d):
		push_error("[MapIO] map.json 不是工坊地图（kind 不匹配）：" + dir)
		return {}

	var hi: Image = _read_height(dir + "height.raw")
	if hi == null:
		push_warning("[MapIO] 缺少 height.raw，地形需要重新生成：" + dir)

	var bi: Image = null
	if FileAccess.file_exists(dir + "biome.png"):
		bi = Image.load_from_file(dir + "biome.png")

	# 拼图层（人工笔刷）。缺文件 = 这张图从来没刷过，返回 null 让 Terrain 用空图。
	var si: Image = null
	if FileAccess.file_exists(dir + "splat.png"):
		si = Image.load_from_file(dir + "splat.png")
		if si != null and si.get_format() != Image.FORMAT_RGBA8:
			si.convert(Image.FORMAT_RGBA8)

	# 第二张拼图（石板路/土路）。缺文件 = 老地图，用空图。
	var si2: Image = null
	if FileAccess.file_exists(dir + "splat2.png"):
		si2 = Image.load_from_file(dir + "splat2.png")
		if si2 != null and si2.get_format() != Image.FORMAT_RGBA8:
			si2.convert(Image.FORMAT_RGBA8)

	return {"doc": doc, "height": hi, "biome": bi, "splat": si, "splat2": si2, "dir": dir}

## 只读 map.json 取列表用的轻量信息，不碰高度图。
## 返回 {} 表示这不是工坊地图（可能是 legacy 参数图，交给 _peek_legacy）。
static func peek(map_name: String) -> Dictionary:
	var nm: String = sanitize_name(map_name)
	var dir: String = MAP_ROOT + nm + "/"
	if not FileAccess.file_exists(dir + "map.json"):
		return _peek_legacy(nm)
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(dir + "map.json"))
	if typeof(parsed) != TYPE_DICTIONARY:
		return _peek_legacy(nm)
	var d: Dictionary = parsed

	var g = d.get("grid", {})
	var n: int = int((g as Dictionary).get("n", 0)) if typeof(g) == TYPE_DICTIONARY else 0
	var cell: float = float((g as Dictionary).get("cell_size", 2.0)) if typeof(g) == TYPE_DICTIONARY else 2.0
	var objs = d.get("objects", [])
	var mtime: int = FileAccess.get_modified_time(dir + "map.json")

	return {
		"name": str(d.get("name", nm)),
		"kind": str(d.get("kind", "")),
		"desc": str(d.get("desc", "")),
		"author": str(d.get("author", "")),
		"grid_n": n,
		"cell_size": cell,
		"world_size": float(n) * cell,
		"object_count": (objs as Array).size() if typeof(objs) == TYPE_ARRAY else 0,
		"modified": str(d.get("modified", "")),
		"mtime": mtime,
		"legacy": false,
		"has_height": FileAccess.file_exists(dir + "height.raw"),
		"has_thumb": FileAccess.file_exists(dir + "thumbnail.png"),
	}

## legacy = MapSaveManager 的老参数图（只有 params.json）
static func _peek_legacy(nm: String) -> Dictionary:
	var dir: String = MAP_ROOT + nm + "/"
	if not FileAccess.file_exists(dir + "params.json"):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(dir + "params.json"))
	var ws: float = 0.0
	var seed_v: int = 0
	if typeof(parsed) == TYPE_DICTIONARY:
		ws = float((parsed as Dictionary).get("world_size", 0.0))
		seed_v = int((parsed as Dictionary).get("seed", 0))
	return {
		"name": nm,
		"kind": "legacy_params",
		"desc": "参数图（无高度图，进游戏时按 seed 重新生成）",
		"author": "",
		"grid_n": int(round(ws / 2.0)),
		"cell_size": 2.0,
		"world_size": ws,
		"object_count": 0,
		"modified": "",
		"mtime": FileAccess.get_modified_time(dir + "params.json"),
		"legacy": true,
		"has_height": false,
		"has_thumb": false,
	}

# ---------------------------------------------------------------- 列表 / 管理

## 列出 user://maps/ 下所有可识别的地图，按修改时间倒序（最新的排最前）。
static func list_maps() -> Array:
	var out: Array = []
	var dir: DirAccess = DirAccess.open(MAP_ROOT)
	if dir == null:
		return out
	dir.list_dir_begin()
	var n: String = dir.get_next()
	while n != "":
		if n != "." and n != ".." and dir.current_is_dir():
			var info: Dictionary = peek(n)
			if not info.is_empty():
				out.append(info)
		n = dir.get_next()
	dir.list_dir_end()
	out.sort_custom(func(a, b): return int(a.get("mtime", 0)) > int(b.get("mtime", 0)))
	return out

static func exists(map_name: String) -> bool:
	var nm: String = sanitize_name(map_name)
	return nm != "" and FileAccess.file_exists(MAP_ROOT + nm + "/map.json")

## 只删工坊地图。故意不删 legacy 参数图 —— 那是 MapSaveManager 的地盘。
static func delete_map(map_name: String) -> bool:
	var nm: String = sanitize_name(map_name)
	if not exists(nm):
		push_warning("[MapIO] delete_map: 不是工坊地图，拒绝删除：" + nm)
		return false
	return _remove_dir_recursive(MAP_ROOT + nm + "/")

static func duplicate_map(src: String, dst: String) -> bool:
	var src_nm: String = sanitize_name(src)
	if not exists(src_nm):
		return false
	var dst_nm: String = _unique_name(sanitize_name(dst))
	var src_dir: String = MAP_ROOT + src_nm + "/"
	var dst_dir: String = MAP_ROOT + dst_nm + "/"
	if DirAccess.make_dir_recursive_absolute(dst_dir) != OK:
		return false

	for fn in MAP_FILES:
		if FileAccess.file_exists(src_dir + fn):
			var bytes: PackedByteArray = FileAccess.get_file_as_bytes(src_dir + fn)
			var wf: FileAccess = FileAccess.open(dst_dir + fn, FileAccess.WRITE)
			if wf != null:
				wf.store_buffer(bytes)
				wf.close()

	# 改名：json 里的 name 也要跟着变，否则列表里两个同名条目
	var loaded: Dictionary = load_map(dst_nm)
	if not loaded.is_empty():
		var doc = loaded["doc"]
		doc.map_name = dst_nm
		save(doc, null, null)
	return true

# ---------------------------------------------------------------- 打包 / 导入

## 打包成 .sgmap（就是 zip）。out_abs_path 建议用绝对路径。
static func pack(map_name: String, out_abs_path: String) -> bool:
	var nm: String = sanitize_name(map_name)
	if not exists(nm):
		return false
	var dir: String = MAP_ROOT + nm + "/"
	var packer: ZIPPacker = ZIPPacker.new()
	if packer.open(out_abs_path) != OK:
		push_error("[MapIO] 无法创建压缩包：" + out_abs_path)
		return false
	for fn in MAP_FILES:
		if not FileAccess.file_exists(dir + fn):
			continue
		packer.start_file(fn)
		packer.write_file(FileAccess.get_file_as_bytes(dir + fn))
		packer.close_file()
	packer.close()
	return true

## 导入 .sgmap，返回落地后的地图名（重名会自动加后缀）。失败返回 ""。
static func unpack(zip_abs_path: String) -> String:
	var reader: ZIPReader = ZIPReader.new()
	if reader.open(zip_abs_path) != OK:
		push_error("[MapIO] 无法打开压缩包：" + zip_abs_path)
		return ""
	var files: PackedStringArray = reader.get_files()
	if not files.has("map.json"):
		push_error("[MapIO] 压缩包里没有 map.json，不是合法地图包")
		reader.close()
		return ""

	var parsed = JSON.parse_string(reader.read_file("map.json").get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		reader.close()
		return ""
	if str((parsed as Dictionary).get("kind", "")) != MapDoc.KIND:
		reader.close()
		push_error("[MapIO] 压缩包不是工坊地图（kind 不匹配）")
		return ""

	var nm: String = _unique_name(sanitize_name(str((parsed as Dictionary).get("name", "导入地图"))))
	var dir: String = MAP_ROOT + nm + "/"
	if DirAccess.make_dir_recursive_absolute(dir) != OK:
		reader.close()
		return ""

	for fn in files:
		# 防 zip slip：只接受纯文件名，拒绝 ../ 和目录
		if fn.contains("..") or fn.contains("/") or fn.contains("\\"):
			continue
		if not MAP_FILES.has(fn):
			continue
		var wf: FileAccess = FileAccess.open(dir + fn, FileAccess.WRITE)
		if wf == null:
			continue
		wf.store_buffer(reader.read_file(fn))
		wf.close()
	reader.close()

	# json 里的 name 要对上目录名
	var loaded: Dictionary = load_map(nm)
	if not loaded.is_empty():
		var doc = loaded["doc"]
		doc.map_name = nm
		save(doc, null, null)
	return nm

# ---------------------------------------------------------------- 高度图编解码

## int32 w | int32 h | float32[w*h]
static func _write_height(path: String, img: Image) -> bool:
	if img == null:
		return false
	var src: Image = img
	if src.get_format() != Image.FORMAT_RF:
		# 调用方传了 RGBA8 之类时，先转 RF，否则写出来是整个字节流错位
		src = img.duplicate()
		src.convert(Image.FORMAT_RF)

	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("[MapIO] 无法写入 " + path)
		return false
	f.store_32(src.get_width())
	f.store_32(src.get_height())
	f.store_buffer(src.get_data())
	f.close()
	return true

static func _read_height(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var w: int = f.get_32()
	var h: int = f.get_32()
	# 明显损坏/恶意尺寸直接拒绝，避免 get_buffer 申请天文数字内存
	if w <= 0 or h <= 0 or w > 8192 or h > 8192:
		f.close()
		push_error("[MapIO] height.raw 尺寸异常 %dx%d" % [w, h])
		return null
	var need: int = w * h * 4
	var buf: PackedByteArray = f.get_buffer(need)
	f.close()
	if buf.size() != need:
		push_error("[MapIO] height.raw 数据不足：期望 %d 实得 %d" % [need, buf.size()])
		return null
	return Image.create_from_data(w, h, false, Image.FORMAT_RF, buf)

## 8bit 灰度预览。注意 RF 直接转 RGBA8 会把 0.0~1.0 映射到 0~255，正是我们要的效果。
static func _write_height_preview(path: String, img: Image) -> void:
	var prev: Image = img.duplicate()
	prev.convert(Image.FORMAT_RGBA8)
	prev.save_png(path)

# ---------------------------------------------------------------- 版本迁移

static func _migrate(d: Dictionary) -> Dictionary:
	var v: int = int(d.get("version", 1))
	if v > MapDoc.VERSION:
		push_warning("[MapIO] 地图版本 %d 高于当前支持 %d，可能有字段读不出来" % [v, MapDoc.VERSION])
		return d
	# 目前只有 v1，没有历史版本需要迁移。以后加在这里：
	#   if v < 2:
	#       d = _migrate_v1_to_v2(d)
	#       v = 2
	d["version"] = v
	return d

# ---------------------------------------------------------------- 名字处理

## 去掉文件系统非法字符 + 首尾空白/点。中文保留（Windows 完全支持）。
static func sanitize_name(raw: String) -> String:
	var s: String = raw.strip_edges()
	for ch in ["\\", "/", ":", "*", "?", "\"", "<", ">", "|"]:
		s = s.replace(ch, "_")
	s = s.replace("..", "_")
	while s.begins_with("."):
		s = s.substr(1)
	while s.ends_with("."):
		s = s.substr(0, s.length() - 1)
	return s.strip_edges()

static func _unique_name(base: String) -> String:
	if base == "":
		base = "未命名地图"
	if not exists(base) and not FileAccess.file_exists(MAP_ROOT + base + "/params.json"):
		return base
	for i in range(2, 1000):
		var cand: String = "%s_%d" % [base, i]
		if not exists(cand) and not FileAccess.file_exists(MAP_ROOT + cand + "/params.json"):
			return cand
	return base + "_" + str(Time.get_unix_time_from_system())

static func _remove_dir_recursive(dir_path: String) -> bool:
	var d: DirAccess = DirAccess.open(dir_path)
	if d == null:
		return false
	d.list_dir_begin()
	var n: String = d.get_next()
	while n != "":
		if n != "." and n != "..":
			if d.current_is_dir():
				_remove_dir_recursive(dir_path + n + "/")
			else:
				d.remove(n)
		n = d.get_next()
	d.list_dir_end()
	return DirAccess.remove_absolute(dir_path) == OK
