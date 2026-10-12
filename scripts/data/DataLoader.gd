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

var level_curve: Dictionary = {}
var veteran_bonus: Dictionary = {}

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
	if units.has("level_curve"):
		level_curve = units["level_curve"]
	if units.has("veteran_bonus"):
		veteran_bonus = units["veteran_bonus"]
	print("[DataLoader] 全部配置加载完成")

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

func get_unit_def(unit_id: String) -> Dictionary:
	if units.has("units") and units["units"].has(unit_id):
		return units["units"][unit_id]
	return {}

func get_building_def(building_id: String) -> Dictionary:
	if buildings.has("buildings") and buildings["buildings"].has(building_id):
		return buildings["buildings"][building_id]
	return {}

func get_general_def(general_id: String) -> Dictionary:
	if generals.has("generals") and generals["generals"].has(general_id):
		return generals["generals"][general_id]
	return {}

func get_faction_def(faction_id: String) -> Dictionary:
	if factions.has("factions") and factions["factions"].has(faction_id):
		return factions["factions"][faction_id]
	return {}

func get_asset_def(category: String, entity_id: String) -> Dictionary:
	if asset_map.has(category):
		var cat: Dictionary = asset_map[category]
		if cat.has(entity_id):
			return cat[entity_id]
		if cat.has("default"):
			return cat["default"]
	return {}

func get_sprite_texture(category: String, entity_id: String) -> Texture2D:
	var adef: Dictionary = get_asset_def(category, entity_id)
	if adef.is_empty():
		return null
	var sprite_file: String = adef.get("sprite", "")
	if sprite_file == "":
		return null
	var tex_path: String = "res://assets/sprites/" + sprite_file
	if not ResourceLoader.exists(tex_path):
		return null
	return load(tex_path) as Texture2D

