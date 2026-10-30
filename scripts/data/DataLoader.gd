extends Node
## 数据加载器 — 统一加载 config/ 下的 JSON 配置文件
## 所有游戏数据集中在 config/，便于 AI 改数平衡

var units: Dictionary = {}
var buildings: Dictionary = {}
var generals: Dictionary = {}
var tech: Dictionary = {}
var factions: Dictionary = {}
var combat: Dictionary = {}
var logistics: Dictionary = {}
var diplomacy: Dictionary = {}
var seasons: Dictionary = {}
var asset_map: Dictionary = {}
var maps: Dictionary = {}
var game_settings: Dictionary = {}
var tech_elite: Dictionary = {}
var attack_ranges: Dictionary = {}
var relics: Dictionary = {}

var level_curve: Dictionary = {}
var veteran_bonus: Dictionary = {}

# 坏图检测缓存：key = sprite 文件名, value = true(可用) / false(坏图)
var _sprite_usable_cache: Dictionary = {}
# 贴图内容包围盒缓存：key = sprite 文件名, value = Rect2i（alpha 非空的像素范围）
# 用途：算「底边留白」，让每张图的脚底/屋基都能精确落在地面上。
var _sprite_rect_cache: Dictionary = {}
# 未经 Godot 导入的 PNG 的运行时纹理缓存：key = 资源路径, value = ImageTexture
# 只给 AssetImporter 刚拷进来、还没有 .import 文件的新图用。
var _unimported_tex_cache: Dictionary = {}

func _ready() -> void:
	_load_all()

func _load_all() -> void:
	units = _load_json("res://config/units.json")
	buildings = _load_json("res://config/buildings.json")
	generals = _load_json("res://config/generals.json")
	tech = _load_json("res://config/tech.json")
	factions = _load_json("res://config/factions.json")
	combat = _load_json("res://config/combat.json")
	logistics = _load_json("res://config/logistics.json")
	diplomacy = _load_json("res://config/diplomacy.json")
	seasons = _load_json("res://config/seasons.json")
	asset_map = _load_json("res://config/asset_map.json")
	maps = _load_json("res://config/maps.json")
	game_settings = _load_json("res://config/game_settings.json")
	tech_elite = _load_json("res://config/tech_elite.json")
	attack_ranges = _load_json("res://config/attack_ranges.json")
	relics = _load_json("res://config/relics.json")
	_apply_unit_ranges()
	_merge_custom_entities()
	_inject_train_from()
	_apply_units_meta()
	print("[DataLoader] 全部配置加载完成（含自建兵种 %d / 自建建筑 %d）" % [
		custom_unit_ids.size(), custom_building_ids.size()])

## 自建实体（编辑器「导入兵种 / 导入建筑」写出来的）单独存在 custom_*.json 里，
## 启动时 merge 进内存 —— 策划表 units.json / buildings.json 一个字节都不动。
## 这两个文件不存在是完全正常的（原厂状态），不要报警。
const CUSTOM_UNITS_PATH: String = "res://config/custom_units.json"
const CUSTOM_BUILDINGS_PATH: String = "res://config/custom_buildings.json"

var custom_unit_ids: Array = []
var custom_building_ids: Array = []

## ⚔ 攻击范围总表覆盖：config/attack_ranges.json 是唯一调参入口，
## 启动时把 unit_ranges 写进 units 内存副本（units.json 的 range 只作兜底）。
func _apply_unit_ranges() -> void:
	var ur: Dictionary = attack_ranges.get("unit_ranges", {})
	if ur.is_empty() or not units.has("units"):
		return
	for uid in ur.keys():
		if units["units"].has(uid):
			units["units"][uid]["range"] = float(ur[uid])

## 武将攻击范围：by_general > by_class > default
func get_general_attack_range(gid: String, cls: String) -> float:
	var gr: Dictionary = attack_ranges.get("general_ranges", {})
	if gr.is_empty():
		return 1.0
	var byg: Dictionary = gr.get("by_general", {})
	if byg.has(gid):
		return float(byg[gid])
	var byc: Dictionary = gr.get("by_class", {})
	return float(byc.get(cls, gr.get("default", 1.0)))

## 武将骑马攻击范围加成（封顶 general_ranges.max）
func get_general_mounted_range_bonus() -> float:
	var gr: Dictionary = attack_ranges.get("general_ranges", {})
	return float(gr.get("mounted_bonus", 0.2))

func get_general_range_cap() -> float:
	var gr: Dictionary = attack_ranges.get("general_ranges", {})
	return float(gr.get("max", 3.0))

func _merge_custom_entities() -> void:
	custom_unit_ids = _merge_one(CUSTOM_UNITS_PATH, "units", units)
	custom_building_ids = _merge_one(CUSTOM_BUILDINGS_PATH, "buildings", buildings)

## 把 path 里的 [key] 块合并进 target[key]，返回合并进来的 id 列表。
func _merge_one(path: String, key: String, target: Dictionary) -> Array:
	var ids: Array = []
	if not FileAccess.file_exists(path):
		return ids
	var src: Dictionary = _load_json(path)
	var block = src.get(key, {})
	if typeof(block) != TYPE_DICTIONARY:
		return ids
	if not target.has(key) or typeof(target[key]) != TYPE_DICTIONARY:
		target[key] = {}
	for k in (block as Dictionary).keys():
		# 内置同名以内置为准：EntityImporter 已经拦了撞名，这里是最后一道保险
		if (target[key] as Dictionary).has(k):
			push_warning("[DataLoader] 自建实体 %s:%s 与内置撞名，已忽略" % [key, k])
			continue
		(target[key] as Dictionary)[k] = (block as Dictionary)[k]
		ids.append(str(k))
	ids.sort()
	return ids

func _apply_units_meta() -> void:
	if units.has("level_curve"):
		level_curve = units["level_curve"]
	if units.has("veteran_bonus"):
		veteran_bonus = units["veteran_bonus"]

## 把自建兵种的 train_from 注入到对应建筑的 trains 里（**只在内存里**）。
##
## 为什么要注入：Building.gd 列训练按钮读的是建筑自己的 def.trains，
## 而建筑表是内置的 buildings.json —— 往里面写等于改策划表。
## 在内存副本上追加一个 id，效果和"策划把它加进兵营"完全一致，
## 但磁盘上 buildings.json 一个字节都没动，删掉自建军种后自动消失。
##
## 顺带说明：units/buildings 每次 reload 都是从磁盘重新 _load_json 出来的新字典，
## 所以这里不用担心重复追加（不会越 reload 越多）。
func _inject_train_from() -> void:
	if custom_unit_ids.is_empty():
		return
	var umap: Dictionary = units.get("units", {})
	var bmap: Dictionary = buildings.get("buildings", {})
	for uid in custom_unit_ids:
		var ud = umap.get(uid, null)
		if typeof(ud) != TYPE_DICTIONARY:
			continue
		var tf = (ud as Dictionary).get("train_from", [])
		if typeof(tf) != TYPE_ARRAY:
			continue
		for bid in (tf as Array):
			var bd = bmap.get(str(bid), null)
			if typeof(bd) != TYPE_DICTIONARY:
				continue
			if typeof((bd as Dictionary).get("trains", null)) != TYPE_ARRAY:
				(bd as Dictionary)["trains"] = []
			var trains: Array = (bd as Dictionary)["trains"]
			if not trains.has(uid):
				trains.append(uid)

## 编辑器导入/删除自建实体之后必须调这个：
## 重读 units/buildings + 重新合并 custom + 重设 level_curve，
## 否则新兵种在本进程里查 get_unit_def() 还是空，调色板点它会报「未知 id」。
func reload_entities() -> void:
	units = _load_json("res://config/units.json")
	buildings = _load_json("res://config/buildings.json")
	_merge_custom_entities()
	_inject_train_from()
	_apply_units_meta()
	print("[DataLoader] 实体表已重载（兵种 %d / 建筑 %d，其中自建 %d / %d）" % [
		(units.get("units", {}) as Dictionary).size(),
		(buildings.get("buildings", {}) as Dictionary).size(),
		custom_unit_ids.size(), custom_building_ids.size()])

func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("[DataLoader] 找不到配置文件: %s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("[DataLoader] JSON 解析失败: %s" % path)
		return {}
	return parsed

## AssetImporter 写回 asset_map.json 之后必须调这个：
## 重读映射表 + 清空三类缓存（可用性 / 内容包围盒 / 未导入纹理），
## 否则新导入的图会被旧的"坏图"或"找不到"结论挡住，看着像导入失败。
func reload_asset_map() -> void:
	asset_map = _load_json("res://config/asset_map.json")
	_sprite_usable_cache.clear()
	_sprite_rect_cache.clear()
	_unimported_tex_cache.clear()
	print("[DataLoader] asset_map 已重载（%d 个分类）" % asset_map.size())

func get_unit_def(unit_id: String) -> Dictionary:
	if units.has("units") and units["units"].has(unit_id):
		return units["units"][unit_id]
	return {}

func get_building_def(building_id: String) -> Dictionary:
	if buildings.has("buildings") and buildings["buildings"].has(building_id):
		return buildings["buildings"][building_id]
	return {}

func get_relic_def(relic_id: String) -> Dictionary:
	if relics.has("relics") and relics["relics"].has(relic_id):
		return relics["relics"][relic_id]
	return {}

func get_general_def(general_id: String) -> Dictionary:
	if generals.has("generals") and generals["generals"].has(general_id):
		return generals["generals"][general_id]
	# generals.json 实际是 general_pool 数组结构（此前只查 "generals" 字典，
	# 导致武将四维属性一直没生效、所有武将都走旧版 fallback 数值）
	for g in generals.get("general_pool", []):
		if str(g.get("id", "")) == general_id:
			return g
	return {}

func get_faction_def(faction_id: String) -> Dictionary:
	if factions.has("factions") and factions["factions"].has(faction_id):
		return factions["factions"][faction_id]
	return {}

## 技能 id -> 显示名（通用技能 / 武将技 / 带兵被动 三处合并，首次调用时建索引）
var _skill_name_cache: Dictionary = {}

func get_skill_name(skill_id: String) -> String:
	if _skill_name_cache.is_empty():
		for key in ["common_skills", "unique_skills"]:
			for s in generals.get(key, {}).get("skills", []):
				_skill_name_cache[str(s.get("id", ""))] = str(s.get("name", ""))
		for pid in generals.get("passive_pool", {}).keys():
			if pid.begins_with("_"):
				continue
			_skill_name_cache[str(pid)] = str(generals["passive_pool"][pid].get("name", ""))
	return str(_skill_name_cache.get(skill_id, skill_id))

## 武将类型 -> 中文名（猛将/防御/进攻型/谋臣/异人）
func get_class_name(class_id: String) -> String:
	var c: Dictionary = generals.get("classes", {}).get(class_id, {})
	return str(c.get("name", class_id))

func get_asset_def(category: String, entity_id: String) -> Dictionary:
	if asset_map.has(category):
		var cat: Dictionary = asset_map[category]
		if cat.has(entity_id):
			return cat[entity_id]
		if cat.has("default"):
			return cat["default"]
	return {}

## 贴图统一放在这个目录（AssetImporter 写文件、调色板列出「未注册图」都依赖它）
const SPRITE_DIR: String = "res://assets/sprites/"

## 按文件路径直接取纹理（调色板的「未注册」分组、导入窗口预览用）。
## 有 Godot 导入缓存就走缓存，没有就运行时解码 —— 见 _load_sprite_texture 的说明。
func load_texture_file(path: String) -> Texture2D:
	return _load_sprite_texture(path)

func get_sprite_texture(category: String, entity_id: String) -> Texture2D:
	# 资源加载：游戏在编辑器或导出后运行时，PNG 已由 Godot 正常导入，
	# 直接走下面的真实加载逻辑（含坏图检测与 fallback）。
	# 注意：不要再在函数开头硬性 `return null` —— 那会让 asset_map.json 里所有
	# 映射与 assets/sprites/ 下的贴图全部失效（历史遗留的 headless 临时 workaround）。
	# 找不到纹理或判定为坏图时，下方代码已自行返回 null 让调用方走 fallback mesh，不会崩溃。
	var adef: Dictionary = get_asset_def(category, entity_id)
	if adef.is_empty():
		return null
	var sprite_file: String = adef.get("sprite", "")
	if sprite_file == "":
		return null
	# 优先根目录（我们的 PNG 全在这里）
	# ⚠ 判定不能只看 ResourceLoader.exists()：AssetImporter 刚拷进来的 PNG 还没有
	# .import/.ctex，ResourceLoader 会说"不存在"，于是一路掉到 category 子目录去，
	# 结果必然找不到 —— 表现就是"导入成功了，但调色板里还是方块"。
	# 必须同时看原始文件是否存在。
	var tex_path: String = "res://assets/sprites/" + sprite_file
	if not ResourceLoader.exists(tex_path) and not FileAccess.file_exists(tex_path):
		# 再试带 category 子目录
		tex_path = "res://assets/sprites/" + category + "/" + sprite_file

	# 坏图缓存命中：已判定为坏图 → 返回 null，让调用方走 fallback mesh
	if _sprite_usable_cache.has(sprite_file):
		if _sprite_usable_cache[sprite_file]:
			return _load_sprite_texture(tex_path)
		return null

	var tex: Texture2D = _load_sprite_texture(tex_path)
	if tex == null:
		print("[DataLoader] ❌ 找不到 %s → %s (尝试过: 根目录, %s/)" % [entity_id, sprite_file, category])
		_sprite_usable_cache[sprite_file] = false
		return null
	# 坏图检测 + 内容包围盒，一次算好两处用。
	# 用 Image.get_used_rect() 取代"隔 2 像素抽样统计不透明占比"：
	#   · get_used_rect() 是 C++ 实现，比 26 万次 GDScript get_pixel 快两个数量级；
	#   · 抽样会漏掉极细的内容（细长旗杆、栏杆），包围盒不会。
	# 这个 Rect2i 就是"贴图内容真正占了画布哪一块"，M3 的贴地高度全指望它。
	var img: Image = tex.get_image()
	var rect: Rect2i = Rect2i(0, 0, tex.get_width(), tex.get_height())
	if img != null:
		if img.is_compressed():
			img.decompress()
		rect = img.get_used_rect()
	var canvas_area: int = maxi(tex.get_width() * tex.get_height(), 1)
	if rect.size.x <= 0 or rect.size.y <= 0:
		print("[DataLoader] ⚠ %s 全透明 → 判定坏图，%s 走 fallback mesh" % [sprite_file, entity_id])
		_sprite_usable_cache[sprite_file] = false
		return null
	# 可视面积占比过低也算坏图：防止"只剩一个噪点"的残帧被当成正常贴图。
	# 阈值 0.2%，远低于正常单位图（内容通常占画布 10%~60%），不会误杀。
	var area_ratio: float = float(rect.size.x * rect.size.y) / float(canvas_area)
	if area_ratio < 0.002:
		print("[DataLoader] ⚠ %s 可视面积仅 %.2f%% → 判定坏图，%s 走 fallback mesh" % [sprite_file, area_ratio * 100.0, entity_id])
		_sprite_usable_cache[sprite_file] = false
		return null
	_sprite_usable_cache[sprite_file] = true
	_sprite_rect_cache[sprite_file] = rect
	return tex

## 加载一张精灵贴图。两条路：##   1) 正常：Godot 已导入过 → ResourceLoader 直接拿 .ctex 纹理。
##   2) 兜底：AssetImporter 刚拷进 assets/sprites/ 的原始 PNG 还没有 .import 文件，
##      `ResourceLoader.exists()` 为 false，但文件真实存在 → 用 Image.load_from_file 解码。
## 没有第 2 条，"导入完立刻摆进地图"会看到 fallback 方块，必须重启 Godot 让编辑器重新扫描才生效。
func _load_sprite_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var imported: Texture2D = load(path) as Texture2D
		if imported != null:
			return imported
	if not FileAccess.file_exists(path):
		return null
	if _unimported_tex_cache.has(path):
		return _unimported_tex_cache[path]
	var abs_path: String = ProjectSettings.globalize_path(path) if path.begins_with("res://") else path
	var img: Image = Image.load_from_file(abs_path)
	if img == null or img.is_empty():
		return null
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	_unimported_tex_cache[path] = tex
	print("[DataLoader] 📥 %s 尚未被 Godot 导入 → 运行时解码（保存后重启编辑器会自动转正）" % path)
	return tex

# 各分类的「参考画布高度」（像素）：贴图按内容高度归一化到该高度，
# 使不同分辨率的贴图（如 1024 精细图 vs 早期小图）在游戏内世界尺寸保持一致。
const _SPRITE_REF_H: Dictionary = {
	"buildings": 340.0, "units": 280.0, "generals": 280.0,
	"resource_nodes": 280.0, "village": 340.0, "wild_horse": 280.0,
	"supply_cart": 280.0,
}

# 返回指定分类贴图应使用的 Sprite3D.pixel_size，保证世界尺寸一致（与贴图像素分辨率无关）。
# 例：1024px 精细图 ref_h=340 → pixel_size=0.00332，与 340px 小图(0.01) 渲染出同样大小。
func get_sprite_pixel_size(category: String, tex: Texture2D) -> float:
	var ref_h: float = _SPRITE_REF_H.get(category, 340.0)
	if tex == null:
		return 0.01
	var h: int = tex.get_height()
	if h <= 0:
		return 0.01
	return ref_h * 0.01 / float(h)

## 贴图内容在画布里的像素包围盒（alpha 非空范围）。量不到时退化为整个画布。
func get_sprite_content_rect(category: String, entity_id: String) -> Rect2i:
	var adef: Dictionary = get_asset_def(category, entity_id)
	var tex: Texture2D = get_sprite_texture(category, entity_id)
	if tex == null:
		return Rect2i(0, 0, 0, 0)
	var sprite_file: String = str(adef.get("sprite", ""))
	if _sprite_rect_cache.has(sprite_file):
		return _sprite_rect_cache[sprite_file]
	return Rect2i(0, 0, tex.get_width(), tex.get_height())

## 贴图内容底边留白占画布高度的比例（0.0 ~ 1.0）。用来诊断"这张图是不是画歪了"。
func get_sprite_bottom_pad_ratio(category: String, entity_id: String) -> float:
	var tex: Texture2D = get_sprite_texture(category, entity_id)
	if tex == null:
		return 0.0
	var h: int = tex.get_height()
	if h <= 0:
		return 0.0
	var rect: Rect2i = get_sprite_content_rect(category, entity_id)
	if rect.size.y <= 0:
		return 0.0
	return clampf(float(h - rect.end.y) / float(h), 0.0, 1.0)

## ★ 贴图内容底边贴地所需的 Sprite3D.position.y（世界单位 / 米）。
##
## 前置条件（三个必须一致，否则算出来的高度是错的）：
##   1. Sprite3D.centered = true（Godot 默认，本项目没动过）
##   2. Sprite3D.pixel_size = get_sprite_pixel_size(category, tex)
##   3. Sprite3D.scale = Vector3(s, s, s)，且 s 就是这里传进来的 sprite_scale
##
## 公式推导：
##   世界高度 world_h = 画布高 × pixel_size × scale
##   居中摆放时，画布底边在世界坐标 (position.y - world_h/2)
##   内容底边比画布底边高出 bottom_pad 像素 = bottom_pad × pixel_size × scale 米
##   要让它落在 y=0（地面）→ position.y = world_h/2 - bottom_pad × pixel_size × scale
##
## 为什么不继续用 asset_map 里手填的 offset_y：
##   70 张贴图的实测底边留白从 0%（wall_inner）到 21.3%（farm）不等，
##   而手填值是 0.5~1.5 且与实际留白毫无相关性 —— 结果就是有的建筑陷进地里、
##   有的浮在半空。现在改成"量出来后算"，任何新图（包括 Agnes 出的）只要遵循环保
##   的透明底规则，进来自动就对；offset_y 退居为「人工额外抬升几米」的微调旋钮。
func get_sprite_anchor_y(category: String, entity_id: String, sprite_scale: float) -> float:
	var adef: Dictionary = get_asset_def(category, entity_id)
	var tex: Texture2D = get_sprite_texture(category, entity_id)
	if tex == null:
		return 0.0
	var ps: float = get_sprite_pixel_size(category, tex) * maxf(sprite_scale, 0.0001)
	var h: float = float(tex.get_height())
	if h <= 0.0 or ps <= 0.0:
		return 0.0
	var rect: Rect2i = get_sprite_content_rect(category, entity_id)
	var pad_bottom: float = clampf(h - float(rect.end.y), 0.0, h)
	# offset_y 语义已改为「在地面之上的额外抬升（米）」，默认 0；留着给人手调特例。
	var nudge: float = float(adef.get("offset_y", 0.0))
	return h * ps * 0.5 - pad_bottom * ps + nudge

