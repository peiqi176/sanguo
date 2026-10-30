extends RefCounted
## AssetImporter —— 把一张外部 PNG 变成「调色板里能直接摆的资产」（M3-1 / M3-2）
##
## 只做三件事，纯函数 + 只碰磁盘，不碰 UI，方便 headless 测试：
##   1. validate()  —— 校验这张图是否具备当 2.5D 精灵的条件，并给出**具体**原因
##   2. import_file() —— 拷进 assets/sprites/ + 写 asset_map.json + 刷 DataLoader 缓存
##   3. category_ids() —— 给 UI 用：某分类下现有的 id 清单
##
## 为什么要「拷进 assets/sprites/」而不是原地引用：
##   导出时只有 res:// 里的资源会被打包，指向桌面某处的路径在别人机器上必然断裂。
##
## 关于 Godot 的导入缓存：
##   刚拷进去的 PNG 还没有 .import / .ctex，`ResourceLoader.exists()` 是 false。
##   DataLoader._load_sprite_texture() 里有一条 Image.load_from_file 兜底，
##   所以导入完**立刻**就能在调色板看到、摆进地图、进游戏 —— 不必重启编辑器。
##   重启一次 Godot 后新图会被正常导入，走的还是同一条代码路径，行为不变。

## 分类 → 缺省 scale（与 asset_map.json 里同分类的常见值对齐）
const DEFAULT_SCALE: Dictionary = {
	"buildings": 1.5,
	"units": 1.2,
	"generals": 1.6,
	"resource_nodes": 1.0,
	"village": 1.8,
	"wild_horse": 1.3,
	"supply_cart": 1.5,
}

## 分类 → 显示名（UI 下拉用）
const CATEGORY_LABELS: Dictionary = {
	"buildings": "建筑",
	"units": "单位",
	"generals": "武将",
	"resource_nodes": "资源点",
	"village": "村庄",
	"wild_horse": "野马",
	"supply_cart": "辎重车",
}

const SPRITE_DIR: String = "res://assets/sprites/"
const ASSET_MAP_PATH: String = "res://config/asset_map.json"

## 校验阈值
const MIN_SIDE: int = 32
const MAX_SIDE: int = 4096
const MAX_PAD_RATIO: float = 0.25       # 底边留白超过 25% → 贴地会浮空
const MIN_CONTENT_RATIO: float = 0.08   # 内容高度占画布不足 8% → 图太小

# ---------------------------------------------------------------- 校验

## 返回 { ok, errors[], warnings[], info{} }
## errors 会阻止导入；warnings 只是提醒，仍然允许导入。
static func validate(path: String) -> Dictionary:
	var errors: Array = []
	var warnings: Array = []
	var info: Dictionary = {}

	if path == "":
		return {"ok": false, "errors": ["没有选择文件"], "warnings": [], "info": {}}

	var abs_path: String = _abs(path)
	if not FileAccess.file_exists(abs_path):
		return {"ok": false, "errors": ["文件不存在：%s" % path], "warnings": [], "info": {}}

	# 1) 能解码吗
	var img: Image = Image.load_from_file(abs_path)
	if img == null or img.is_empty():
		return {"ok": false, "errors": ["无法解码（不是有效 PNG？）：%s" % path], "warnings": [], "info": {}}

	var w: int = img.get_width()
	var h: int = img.get_height()
	info["width"] = w
	info["height"] = h
	info["size_label"] = "%d × %d" % [w, h]

	# 2) 尺寸
	if w < MIN_SIDE or h < MIN_SIDE:
		errors.append("尺寸太小：%d×%d（最短边至少 %d）" % [w, h, MIN_SIDE])
	if w > MAX_SIDE or h > MAX_SIDE:
		errors.append("尺寸太大：%d×%d（最长边上限 %d）" % [w, h, MAX_SIDE])
	if w != h:
		warnings.append("不是正方形（%d×%d）。建筑按 1:1 画布设计，非正方形会左右不对称" % [w, h])

	# 3) 透明通道 —— 2.5D 精灵必须有透明底，否则会变成一块实心方板挡住所���
	if not img.detect_alpha() or img.detect_alpha() == Image.ALPHA_NONE:
		warnings.append("没有透明通道。2.5D 摆进场景会显示成实心方板，强烈建议用透明底 PNG")

	# 4) 内容包围盒（alpha 非空范围）
	var rect: Rect2i = img.get_used_rect()
	info["content"] = rect
	info["content_label"] = "x%d~%d, y%d~%d" % [rect.position.x, rect.end.x, rect.position.y, rect.end.y]
	if rect.size.x <= 0 or rect.size.y <= 0:
		errors.append("整张图完全透明，没有任何可见内容")
		return {"ok": false, "errors": errors, "warnings": warnings, "info": info}

	# 5) 底边留白 —— 这是"贴地会浮空"的直接原因
	var pad_px: int = h - rect.end.y
	var pad_ratio: float = float(pad_px) / float(h)
	info["pad_px"] = pad_px
	info["pad_ratio"] = pad_ratio
	if pad_ratio > MAX_PAD_RATIO:
		warnings.append("底边留白 %.0f%%（%d 像素）。游戏会自动把内容底边贴到地面，但留白这么大通常意味着画歪了或底部带了多余投影" % [pad_ratio * 100.0, pad_px])

	# 6) 内容太小
	var content_ratio: float = float(rect.size.y) / float(h)
	info["content_ratio"] = content_ratio
	if content_ratio < MIN_CONTENT_RATIO:
		warnings.append("内容只占画布高度 %.0f%%，进游戏会显得很小（建议撑满画布 60% 以上）" % [content_ratio * 100.0])

	return {"ok": errors.is_empty(), "errors": errors, "warnings": warnings, "info": info}

# ---------------------------------------------------------------- 导入

## 把 src_path 注册成 category/entity_id 的贴图。
##   src_path     原始文件（可在 res:// 之外，比如桌面）
##   category     buildings / units / generals / ...
##   entity_id    实体 id（如 "warehouse"），必须非空
##   scaled       Sprite3D.scale
##   keep_name    为 true 时沿用原文件名，否则用 entity_id + 扩展名
## 返回 { ok, message, sprite }
static func import_file(src_path: String, category: String, entity_id: String,
		scaled: float = -1.0, keep_name: bool = false) -> Dictionary:
	var v: Dictionary = validate(src_path)
	if not bool(v.get("ok", false)):
		return {"ok": false, "message": "校验未通过：" + "；".join(PackedStringArray(v["errors"])), "sprite": ""}

	if category == "" or entity_id.strip_edges() == "":
		return {"ok": false, "message": "分类和实体 id 都不能为空", "sprite": ""}
	if not DEFAULT_SCALE.has(category):
		return {"ok": false, "message": "未知分类：%s" % category, "sprite": ""}
	var id_err: String = _check_id(entity_id)
	if id_err != "":
		return {"ok": false, "message": id_err, "sprite": ""}

	var src_abs: String = _abs(src_path)
	var ext: String = src_abs.get_extension().to_lower()
	if ext == "":
		ext = "png"
	if ext != "png":
		return {"ok": false, "message": "目前只支持 PNG（给的是 .%s）。请先转换格式" % ext, "sprite": ""}

	var file_name: String = _sanitize(src_abs.get_file()) if keep_name else "%s.%s" % [entity_id, ext]
	var dst_rel: String = SPRITE_DIR + file_name
	var dst_abs: String = _abs(dst_rel)

	# 已经在目标位置的图（比如"未注册图"点进来注册）不需要拷
	# 目标已存在时直接覆盖：文件名由实体 id 派生，同 id 再导入的语义就是"换一张图"，
	# 这里报错拦下来只会让人以为失败了。
	if src_abs != dst_abs:
		if FileAccess.file_exists(dst_abs):
			var rm: int = DirAccess.remove_absolute(dst_abs)
			if rm != OK and rm != ERR_FILE_NOT_FOUND:
				return {"ok": false, "message": "旧文件删不掉（错误码 %d）：%s" % [rm, dst_rel], "sprite": ""}
		var err: int = DirAccess.copy_absolute(src_abs, dst_abs)
		if err != OK:
			return {"ok": false, "message": "拷贝失败（错误码 %d）：%s" % [err, dst_rel], "sprite": ""}

	# 写映射表
	var doc: Dictionary = _read_asset_map()
	if doc.is_empty():
		return {"ok": false, "message": "读不到 config/asset_map.json", "sprite": ""}
	var block = doc.get(category, {})
	if typeof(block) != TYPE_DICTIONARY:
		block = {}
	var is_new_id: bool = not (block as Dictionary).has(entity_id)
	(block as Dictionary)[entity_id] = {
		"sprite": file_name,
		"scale": float(scaled) if scaled > 0.0 else float(DEFAULT_SCALE.get(category, 1.0)),
		"offset_y": 0,
		"content_pad": snappedf(float(v["info"].get("pad_ratio", 0.0)), 0.0001),
	}
	doc[category] = block

	if not _write_asset_map(doc):
		return {"ok": false, "message": "写不动 config/asset_map.json（目录只读？）", "sprite": ""}

	# 关键一步：让 DataLoader 立刻重读，否则新图会被旧的"找不到/坏图"结论挡住
	DataLoader.reload_asset_map()

	var action: String = "新增" if is_new_id else "覆盖"
	return {
		"ok": true,
		"message": "%s %s/%s → %s（scale %.2f，底边留白 %.1f%%）" % [
			action, category, entity_id, file_name,
			float(DEFAULT_SCALE.get(category, 1.0)) if scaled <= 0.0 else scaled,
			float(v["info"].get("pad_ratio", 0.0)) * 100.0,
		],
		"sprite": file_name,
	}

# ---------------------------------------------------------------- 卸载

## 从 asset_map.json 里摘掉某条映射（EntityImporter 删实体时用）。
## 只删映射，**不删 PNG 文件** —— 图还在 assets/sprites/ 里，会落到调色板的「未注册」分组，
## 想复用或想重新挂到别的实体上都不用重新导一遍。
static func remove_entry(category: String, entity_id: String) -> bool:
	var doc: Dictionary = _read_asset_map()
	if doc.is_empty():
		return false
	var block = doc.get(category, null)
	if typeof(block) != TYPE_DICTIONARY or not (block as Dictionary).has(entity_id):
		return false
	(block as Dictionary).erase(entity_id)
	if not _write_asset_map(doc):
		return false
	DataLoader.reload_asset_map()
	return true

# ---------------------------------------------------------------- UI 辅助

static func category_ids(category: String) -> Array:
	var doc: Dictionary = _read_asset_map()
	var block = doc.get(category, {})
	var out: Array = []
	if typeof(block) == TYPE_DICTIONARY:
		for k in block.keys():
			var adef = block[k]
			if typeof(adef) == TYPE_DICTIONARY and adef.has("sprite"):
				out.append(str(k))
	out.sort()
	return out

## 某个文件是否已被任何分类引用（用来判断"未注册图"）
static func is_registered(sprite_file: String) -> bool:
	var doc: Dictionary = _read_asset_map()
	for cat in doc.keys():
		var block = doc[cat]
		if typeof(block) != TYPE_DICTIONARY:
			continue
		for eid in block.keys():
			var adef = block[eid]
			if typeof(adef) == TYPE_DICTIONARY and str(adef.get("sprite", "")) == sprite_file:
				return true
	return false

## assets/sprites/ 下所有未被映射的 PNG（调色板"未注册"分组用）
static func orphan_files() -> Array:
	var dir: DirAccess = DirAccess.open(SPRITE_DIR)
	if dir == null:
		return []
	var out: Array = []
	for f in dir.get_files():
		if f.to_lower().ends_with(".png") and not is_registered(f):
			out.append(f)
	out.sort()
	return out

# ---------------------------------------------------------------- 内部

static func _read_asset_map() -> Dictionary:
	if not FileAccess.file_exists(ASSET_MAP_PATH):
		return {}
	var f: FileAccess = FileAccess.open(ASSET_MAP_PATH, FileAccess.READ)
	if f == null:
		return {}
	var text: String = f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed

static func _write_asset_map(doc: Dictionary) -> bool:
	var f: FileAccess = FileAccess.open(ASSET_MAP_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(doc, "  ") + "\n")
	f.close()
	return true

## 实体 id 只允许小写字母/数字/下划线，避免和 JSON key、文件名、URL 打架
static func _check_id(id: String) -> String:
	if id.length() > 48:
		return "实体 id 太长（最多 48 字符）"
	var re: RegEx = RegEx.new()
	re.compile("^[a-z0-9_]+$")
	if re.search(id) == null:
		return "实体 id 只能用小写字母、数字、下划线（现在是「%s」）" % id
	return ""

static func _sanitize(file_name: String) -> String:
	var re: RegEx = RegEx.new()
	re.compile("[^A-Za-z0-9_.-]")
	return re.sub(file_name, "_", true)

static func _abs(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	return path
