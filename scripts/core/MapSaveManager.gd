extends Node
## MapSaveManager — 地图 + 游戏状态 存档/读档（autoload）
## 支持：F5 快速存档 / F9 快速读档 / ESC 菜单手动存档

const SAVE_DIR: String = "user://saves/"
const SLOT_COUNT: int = 5  # 5 个存档位（0=快速存档）
const QUICK_SLOT: int = 0

# ============================================================
#  📦 游戏状态存档（核心）
# ============================================================

func save_game(slot: int) -> bool:
	"""把当前整个游戏状态存到 user://saves/slot_N.json"""
	var dir := DirAccess.open("user://")
	if dir == null:
		push_error("[Save] 无法访问 user://")
		return false
	dir.make_dir_recursive(SAVE_DIR)
	
	var d: Dictionary = {}
	d["version"] = "2.0"
	d["timestamp"] = Time.get_datetime_string_from_system()
	d["slot"] = slot
	# 地图参数（读档时 Terrain.generate 精确还原）
	if Terrain.params != null:
		d["terrain"] = params_to_dict(Terrain.params)
	# 势力资源/人口/科技
	d["factions"] = {}
	for fid in GameManager.factions.keys():
		var fs = GameManager.factions[fid]
		d["factions"][fid] = _serialize_faction(fs)
	d["player_faction"] = GameManager.player_faction
	# 全局实体
	var blist: Array = []
	for b in GameManager.all_buildings:
		if is_instance_valid(b) and b.has_method("serialize"):
			blist.append(b.serialize())
	d["buildings"] = blist
	var ulist: Array = []
	for u in GameManager.all_units:
		if is_instance_valid(u) and u.has_method("serialize"):
			ulist.append(u.serialize())
	d["units"] = ulist
	# 地图生态：村庄 / 资源点 / 野马
	var vlist: Array = []
	for v in GameManager.villages:
		if is_instance_valid(v) and v.has_method("serialize"):
			vlist.append(v.serialize())
	d["villages"] = vlist
	var rlist: Array = []
	for rn in GameManager.resource_nodes:
		if is_instance_valid(rn) and rn.has_method("serialize"):
			rlist.append(rn.serialize())
	d["resource_nodes"] = rlist
	var hlist: Array = []
	for h in GameManager.wild_horses:
		if is_instance_valid(h) and h.has_method("serialize"):
			hlist.append(h.serialize())
	d["wild_horses"] = hlist
	# 特殊科技（13选3）
	d["elite_techs"] = GameManager.elite_techs.duplicate(true)
	# 政务任命：只存 general_id 字符串，读档后回填节点引用
	var offs: Dictionary = {}
	for fid2 in GameManager.appointed_officials.keys():
		var src: Dictionary = GameManager.appointed_officials[fid2]
		var dst: Dictionary = {}
		for office in src.keys():
			var gen = src[office]
			if is_instance_valid(gen):
				dst[str(office)] = str(gen.get("general_id"))
		offs[str(fid2)] = dst
	d["appointed_officials"] = offs
	# 全局状态
	d["game_speed"] = GameManager.game_speed
	d["current_season"] = GameManager.current_season
	d["season_timer"] = GameManager.season_timer
	d["selected_map_id"] = GameManager.selected_map_id
	# 战争迷雾探索进度（记忆层永久保留）
	if FogOfWar != null:
		d["fog"] = FogOfWar.export_state()
	# 🙏 寺庙祈福限时 Buff / ⏱ 开局时长 / 🏮 在野武将池 / 💀 重伤待复活武将
	d["game_elapsed"] = GameManager.game_elapsed
	d["faction_buffs"] = GameManager.faction_buffs.duplicate(true)
	d["generals_pool"] = GameManager.generals_pool.duplicate()
	var dead_list: Array = []
	for g in GameManager.dead_generals:
		if is_instance_valid(g):
			dead_list.append({
				"name": str(g.name),
				"general_id": str(g.get("general_id")),
				"level": int(g.get("level")),
				"grace": float(g.get("grace_period_seconds")),
			})
	d["dead_general_pending"] = dead_list
	
	var slot_name: String = _slot_name(slot)
	var f := FileAccess.open(SAVE_DIR + slot_name, FileAccess.WRITE)
	if f == null:
		push_error("[Save] 无法写入存档 " + slot_name)
		return false
	f.store_string(JSON.stringify(d, "", true))
	f.close()
	print("[Save] ✅ 存档成功 -> " + slot_name + " (" + str(blist.size()) + " 建筑, " + str(ulist.size()) + " 单位)")
	return true

func load_game(slot: int) -> bool:
	"""从 user://saves/slot_N.json 读档"""
	var slot_name: String = _slot_name(slot)
	if not FileAccess.file_exists(SAVE_DIR + slot_name):
		push_error("[Save] 存档 " + slot_name + " 不存在")
		return false
	var f := FileAccess.open(SAVE_DIR + slot_name, FileAccess.READ)
	var txt: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("[Save] 存档 JSON 解析失败")
		return false
	
	var d: Dictionary = parsed
	print("[Save] 📂 载入存档 %s (%s)" % [slot_name, str(d.get("timestamp", ""))])
	
	# 1) 先清场：删所有建筑/单位/村庄/资源点
	_clear_all_entities()
	
	# 2) 还原地图
	if d.has("terrain"):
		var MP := preload("res://scripts/core/MapParams.gd")
		var p = MP.new()
		for k in d["terrain"].keys():
			p.set(k, d["terrain"][k])
		Terrain.generate(p)
	
	# 3) 还原势力 + 资源
	var factions_d: Dictionary = d.get("factions", {})
	for fid in factions_d.keys():
		if not GameManager.factions.has(fid):
			GameManager.init_faction(fid)
		_game_manager_apply_faction(fid, factions_d[fid])
	
	# 4) 还原建筑 + 单位 + 村庄 + 资源点 + 野马
	var main_node: Node = get_tree().root.get_node("Main") if get_tree().root.has_node("Main") else get_tree().root
	var blist: Array = d.get("buildings", [])
	for bd in blist:
		_deserialize_building(bd, main_node)
	var ulist: Array = d.get("units", [])
	for ud in ulist:
		_deserialize_unit(ud, main_node)
	for vd in d.get("villages", []):
		_deserialize_village(vd, main_node)
	for rd in d.get("resource_nodes", []):
		_deserialize_resource(rd, main_node)
	for hd in d.get("wild_horses", []):
		_deserialize_horse(hd, main_node)
	
	# 5) 全局状态
	GameManager.player_faction = str(d.get("player_faction", GameManager.player_faction))
	GameManager.game_speed = float(d.get("game_speed", 1.0))
	GameManager.current_season = str(d.get("current_season", "spring"))
	GameManager.season_timer = float(d.get("season_timer", 0))
	GameManager.selected_map_id = str(d.get("selected_map_id", "jiangshan_yitong"))
	GameManager.game_over = false
	GameManager.paused = false
	# ⏱ 开局时长 / 🙏 寺庙祈福 Buff / 🏮 在野武将池
	GameManager.game_elapsed = float(d.get("game_elapsed", 0.0))
	GameManager.faction_buffs = (d.get("faction_buffs", {}) as Dictionary).duplicate(true)
	if d.has("generals_pool"):
		GameManager.generals_pool.clear()
		for gid in (d.get("generals_pool", []) as Array):
			GameManager.generals_pool.append(str(gid))
	else:
		GameManager.init_general_pool()
	# 特殊科技
	GameManager.elite_techs = (d.get("elite_techs", {}) as Dictionary).duplicate(true)
	# 6) 关系重挂（在岗/训练/驻防/政务官）
	_reattach_relations(d, main_node)
	GameManager.invalidate_tech_cache()
	
	# 6.5) 战争迷雾：读档不应把已探明的地图重新变黑
	if FogOfWar != null:
		FogOfWar.import_state(d.get("fog", {}))
	
	# 7) 重建 AIController（非玩家势力）
	if main_node.has_method("_spawn_ai"):
		main_node._spawn_ai()
	
	# 8) 触发资源栏刷新
	EventBus.resource_produced.emit(GameManager.player_faction, "gold", 0.0, null)
	print("[Save] ✅ 读档完成！%d 建筑 %d 单位 %d 村庄 %d 资源点 %d 野马" % [blist.size(), ulist.size(), (d.get("villages", []) as Array).size(), (d.get("resource_nodes", []) as Array).size(), (d.get("wild_horses", []) as Array).size()])
	return true

func list_saves() -> Array[Dictionary]:
	"""列出所有存档的元信息 [{slot, timestamp, player, buildings, units, size}]"""
	var out: Array = []
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var n := dir.get_next()
	while n != "":
		if n.begins_with("slot_"):
			var f := FileAccess.open(SAVE_DIR + n, FileAccess.READ)
			if f:
				var txt: String = f.get_as_text()
				f.close()
				var parsed: Variant = JSON.parse_string(txt)
				if typeof(parsed) == TYPE_DICTIONARY:
					var d: Dictionary = parsed
					out.append({
						"file": n,
						"slot": int(d.get("slot", -1)),
						"timestamp": str(d.get("timestamp", "")),
						"player": str(d.get("player_faction", "")),
						"buildings": int(d.get("buildings", []).size()),
						"units": int(d.get("units", []).size()),
					})
		n = dir.get_next()
	dir.list_dir_end()
	out.sort_custom(func(a, b2): return int(a["slot"]) < int(b2["slot"]))
	return out

func delete_save(slot: int) -> bool:
	var slot_name: String = _slot_name(slot)
	if FileAccess.file_exists(SAVE_DIR + slot_name):
		DirAccess.open(SAVE_DIR).remove(slot_name)
		return true
	return false

# ============================================================
#  序列化辅助
# ============================================================

func _serialize_faction(fs) -> Dictionary:
	var d: Dictionary = {}
	d["resources"] = fs.resources.duplicate()
	d["population_used"] = fs.population_used
	d["population_cap"] = fs.population_cap
	d["government_level"] = fs.government_level
	d["morale"] = fs.morale
	d["tax_rate"] = fs.tax_rate
	d["tax_rate_value"] = fs.tax_rate_value
	d["researched_techs"] = fs.researched_techs.duplicate()
	d["researching"] = fs.researching.duplicate()
	d["trust"] = fs.trust.duplicate()
	d["tax_pop_penalty"] = fs.tax_pop_penalty
	d["tech_completion"] = fs.tech_completion
	d["defeated"] = fs.defeated
	return d

func _game_manager_apply_faction(fid: String, d: Dictionary) -> void:
	if not GameManager.factions.has(fid):
		return
	var fs = GameManager.factions[fid]
	for k in d.keys():
		if k == "resources":
			fs.resources = d[k].duplicate()
		else:
			fs.set(k, d[k])
	# 读档后科技可能与本局缓存不一致，强制重算科技加成
	GameManager.invalidate_tech_cache()

func _deserialize_building(d: Dictionary, parent: Node) -> Node:
	var scene: PackedScene = load("res://scenes/Building.tscn")
	if scene == null:
		return null
	var b = scene.instantiate()
	b.building_id = str(d.get("building_id", "house"))
	b.faction = str(d.get("faction", "shu"))
	var gp: Dictionary = d.get("grid_pos", {"x": 0, "y": 0})
	b.grid_pos = Vector2i(int(gp.get("x", 0)), int(gp.get("y", 0)))
	var progress: float = float(d.get("build_progress", 1.0))
	# 完成态外观必须在 add_child 之前决定（_ready 里就建好模型了）
	b.spawn_as_complete = progress >= 1.0
	# 占格：城墙/城门 = 2（可破屏障），普通建筑 = 1
	var grid = GameManager.grid
	var bdef: Dictionary = DataLoader.get_building_def(b.building_id)
	var size: Vector2i = Vector2i(2, 2)
	var s = bdef.get("size", [2, 2])
	if typeof(s) == TYPE_ARRAY and (s as Array).size() >= 2:
		size = Vector2i(int(s[0]), int(s[1]))
	var occ_val: int = 2 if (b.building_id.begins_with("wall_") or b.building_id == "gate") else 1
	if grid != null:
		grid.set_occupied(b.grid_pos, size, occ_val)
	if parent == null:
		return b
	parent.add_child(b)
	if grid != null:
		b.global_position = grid.grid_to_world(b.grid_pos)
	else:
		b.global_position = Vector3(float(b.grid_pos.x) * 2.0, 0.0, float(b.grid_pos.y) * 2.0)
	if GameManager.pathfinder != null:
		GameManager.pathfinder.clear_cache()
	# _ready 已跑完 _init_from_def()，此处用存档值覆盖
	b.max_hp = float(d.get("max_hp", b.max_hp))
	b.hp = float(d.get("hp", b.max_hp))
	b.build_progress = progress
	b.training_queue.clear()
	for item in d.get("training_queue", []):
		var uid: String = str(item.get("unit_id", ""))
		if uid == "":
			continue
		b.training_queue.append({"unit_id": uid, "time_left": float(item.get("time_left", 0.0))})
	var rp = d.get("rally", null)
	if typeof(rp) == TYPE_DICTIONARY:
		b.rally_point = Vector3(float(rp.get("x", 0)), float(rp.get("y", 0)), float(rp.get("z", 0)))
	return b

func _deserialize_unit(d: Dictionary, parent: Node) -> Node:
	if str(d.get("type", "unit")) == "supply_cart":
		return _deserialize_cart(d, parent)
	var scene: PackedScene = load("res://scenes/Unit.tscn")
	if scene == null:
		return null
	var u = scene.instantiate()
	var is_gen: bool = bool(d.get("is_general", false))
	if is_gen:
		var gen_script: GDScript = load("res://scripts/entities/General.gd")
		if gen_script:
			u.set_script(gen_script)
		u.general_id = str(d.get("general_id", "liubei"))
		u.unit_id = str(d.get("unit_id", "general_" + str(d.get("general_id", "liubei"))))
	else:
		u.unit_id = str(d.get("unit_id", "peasant"))
	u.faction = str(d.get("faction", "shu"))
	u.is_general = is_gen
	u.behavior_mode = int(d.get("behavior_mode", 0))
	u.state = int(d.get("state", 0))
	if parent == null:
		return u
	parent.add_child(u)
	var p: Dictionary = d.get("pos", {"x": 0, "y": 1, "z": 0})
	u.global_position = Vector3(float(p.get("x", 0)), float(p.get("y", 1)), float(p.get("z", 0)))
	# 💾 统一走 Unit.apply_save_data —— 过去这里和 Unit.deserialize 各写一套，
	# 新增字段只在一处补、另一处就漏（军粮/断粮/马匹/驻守/伏兵曾经全丢）
	u.apply_save_data(d)
	if is_gen:
		_restore_general(u, d)
	return u

func _restore_general(u: Node, d: Dictionary) -> void:
	if u.get("xp") != null:
		u.xp = float(d.get("xp", 0.0))
	if u.get("mp") != null:
		u.mp = float(d.get("mp", u.mp))
	if u.get("talent_points") != null:
		u.talent_points = int(d.get("talent_points", 0))
	if u.get("equipped_skills") != null:
		u.equipped_skills = (d.get("equipped_skills", []) as Array).duplicate(true)
	if u.get("skill_cooldowns") != null:
		var cd: Dictionary = {}
		var saved_cd: Dictionary = d.get("skill_cooldowns", {})
		for k in saved_cd.keys():
			cd[str(k)] = float(saved_cd[k])
		u.skill_cooldowns = cd
	if u.get("stats") != null:
		var st: Dictionary = u.stats
		var saved_st: Dictionary = d.get("stats", {})
		for k in saved_st.keys():
			st[k] = float(saved_st[k])
		u.stats = st

func _deserialize_cart(d: Dictionary, parent: Node) -> Node:
	var scene: PackedScene = load("res://scenes/SupplyCart.tscn")
	if scene == null:
		return null
	var c = scene.instantiate()
	if parent == null:
		return c
	parent.add_child(c)
	c.apply_state(d)
	var p: Dictionary = d.get("pos", {})
	c.global_position = Vector3(float(p.get("x", 0)), float(p.get("y", 0)), float(p.get("z", 0)))
	return c

func _deserialize_village(d: Dictionary, parent: Node) -> Node:
	var scene: PackedScene = load("res://scenes/Village.tscn")
	if scene == null:
		return null
	var v = scene.instantiate()
	v.village_id = str(d.get("village_id", ""))
	if parent == null:
		return v
	parent.add_child(v)
	var p: Dictionary = d.get("pos", {})
	v.global_position = Vector3(float(p.get("x", 0)), float(p.get("y", 0)), float(p.get("z", 0)))
	v.apply_state(d)
	return v

func _deserialize_resource(d: Dictionary, parent: Node) -> Node:
	var scene: PackedScene = load("res://scenes/ResourceNode.tscn")
	if scene == null:
		return null
	var n = scene.instantiate()
	n.resource_type = str(d.get("resource_type", "wood"))
	if parent == null:
		n.apply_state(d)
		return n
	parent.add_child(n)
	n.apply_state(d)
	var g = d.get("grid", null)
	if typeof(g) == TYPE_DICTIONARY and GameManager.grid != null:
		n.global_position = GameManager.grid.grid_to_world(Vector2i(int(g.get("x", 0)), int(g.get("y", 0))))
	return n

func _deserialize_horse(d: Dictionary, parent: Node) -> Node:
	var scene: PackedScene = load("res://scenes/WildHorse.tscn")
	if scene == null:
		return null
	var h = scene.instantiate()
	h.horse_id = str(d.get("horse_id", ""))
	h.horse_type = str(d.get("horse_type", "white"))
	if parent == null:
		return h
	parent.add_child(h)
	h.apply_state(d)
	var p: Dictionary = d.get("pos", {})
	h.global_position = Vector3(float(p.get("x", 0)), float(p.get("y", 0)), float(p.get("z", 0)))
	return h

func _reattach_relations(d: Dictionary, _parent: Node) -> void:
	# 建筑索引：grid_pos -> building
	var bmap: Dictionary = {}
	for b in GameManager.all_buildings:
		if is_instance_valid(b):
			bmap[b.grid_pos] = b
	# 在岗农夫 / 驻防单位
	for u in GameManager.all_units:
		if not is_instance_valid(u):
			continue
		if u.has_meta("restore_work_grid"):
			var gp: Vector2i = u.get_meta("restore_work_grid")
			if bmap.has(gp) and bmap[gp].has_method("restore_worker"):
				bmap[gp].restore_worker(u, float(u.get_meta("restore_work_train", -1.0)))
			u.remove_meta("restore_work_grid")
			u.remove_meta("restore_work_train")
		if u.has_meta("restore_garrison_grid"):
			var gpg: Vector2i = u.get_meta("restore_garrison_grid")
			if bmap.has(gpg) and bmap[gpg].has_method("garrison"):
				bmap[gpg].garrison(u)
			u.remove_meta("restore_garrison_grid")
	# 政务任命：general_id -> 已恢复的武将节点
	GameManager.appointed_officials.clear()
	var offs: Dictionary = d.get("appointed_officials", {})
	for fid in offs.keys():
		var src: Dictionary = offs[fid]
		var dst: Dictionary = {}
		for office in src.keys():
			var gid: String = str(src[office])
			for g in GameManager.all_units:
				if not is_instance_valid(g):
					continue
				if g.get("general_id") == null:
					continue
				if str(g.get("general_id")) == gid:
					dst[str(office)] = g
					break
		if not dst.is_empty():
			GameManager.appointed_officials[str(fid)] = dst

func _clear_all_entities() -> void:
	"""清空当前场景所有可存档实体，准备读档重建"""
	# 先从 GameManager 清理引用
	for b in GameManager.all_buildings.duplicate():
		if is_instance_valid(b):
			GameManager.unregister_building(b)
			b.queue_free()
	for u in GameManager.all_units.duplicate():
		if is_instance_valid(u):
			GameManager.unregister_unit(u)
			u.queue_free()
	for v in GameManager.villages.duplicate():
		if is_instance_valid(v):
			v.queue_free()
	for rn in GameManager.resource_nodes.duplicate():
		if is_instance_valid(rn):
			rn.queue_free()
	for h in GameManager.wild_horses.duplicate():
		if is_instance_valid(h):
			h.queue_free()
	# 古碑不入存档：读档时一并清掉（避免旧进度悬留在新地图上）
	for rl in GameManager.relics.duplicate():
		if is_instance_valid(rl):
			rl.queue_free()
	GameManager.relics.clear()
	# 全局数组同步清空（必须同步：否则会在下一帧把刚读入的新实体抹掉）
	GameManager.all_buildings.clear()
	GameManager.all_units.clear()
	GameManager.villages.clear()
	GameManager.resource_nodes.clear()
	GameManager.wild_horses.clear()
	GameManager.all_generals.clear()
	GameManager.dead_generals.clear()
	GameManager.faction_buffs.clear()
	# 清 AI
	for child in get_tree().root.get_children():
		if child.name.begins_with("AI_") and child is Node:
			child.queue_free()

func _slot_name(slot: int) -> String:
	if slot == QUICK_SLOT:
		return "quick_save.json"
	return "slot_%d.json" % slot

# ============================================================
#  旧版地图存档保留（兼容）
# ============================================================

const SAVE_DIR_LEGACY: String = "user://maps/"
const FIELDS: Array[String] = [
	"seed", "world_size", "heightmap_size", "biome_size", "max_height", "water_level",
	"noise_frequency", "noise_octaves", "moisture_frequency", "rock_frequency",
	"base_height", "height_scale", "island_radius", "island_center_factor",
	"island_falloff_inner", "island_falloff_outer", "ocean_depth",
	"river_count", "river_width", "river_depth", "river_wind", "river_wind2",
	"lake_count", "lake_radius", "lake_depth",
	"forest_density", "dirt_density", "stone_density",
]

func save_current_map(name: String) -> bool:
	if Terrain.params == null:
		push_error("[MapSave] 没有可保存的地图")
		return false
	var base: String = SAVE_DIR_LEGACY + name + "/"
	var dir := DirAccess.open("user://")
	if dir == null:
		return false
	dir.make_dir_recursive(base)
	var d := params_to_dict(Terrain.params)
	var f := FileAccess.open(base + "params.json", FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(d, "", true))
	f.close()
	if Terrain.biome_img != null:
		Terrain.biome_img.save_png(base + "biome.png")
	print("[MapSave] 地图已保存 -> " + base)
	return true

func load_map(name: String):
	var p = get_map_params(name)
	if p == null:
		return null
	Terrain.generate(p)
	return p

func get_map_params(name: String):
	var base: String = SAVE_DIR_LEGACY + name + "/"
	if not FileAccess.file_exists(base + "params.json"):
		return null
	var f := FileAccess.open(base + "params.json", FileAccess.READ)
	var txt := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return null
	var MP := preload("res://scripts/core/MapParams.gd")
	var p := MP.new()
	for k in FIELDS:
		if parsed.has(k):
			p.set(k, parsed[k])
	return p

## 列出**本类自己格式**的地图（只含 params.json 的老参数图）。
##
## ⚠️ user://maps/ 是共享目录：地图工坊（MapIO）的地图也住在这里，
##    但它写的是 map.json + height.raw，格式完全不同。
##    不加这个过滤，两边会互相把对方的目录当成自己的图读，
##    结果是列表里出现"点进去打不开"的幽灵条目。
func list_maps() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(SAVE_DIR_LEGACY)
	if dir == null:
		return out
	dir.list_dir_begin()
	var n := dir.get_next()
	while n != "":
		if n != "." and n != ".." and dir.current_is_dir():
			if FileAccess.file_exists(SAVE_DIR_LEGACY + n + "/params.json"):
				out.append(n)
		n = dir.get_next()
	dir.list_dir_end()
	return out

## 只删**本类自己格式**的地图。地图工坊的地图（有 map.json）一律拒绝，
## 避免用户在"参数图列表"里误删掉辛苦画的工坊地图。
## 工坊地图请用 MapIO.delete_map()。
func delete_map(name: String) -> bool:
	var base: String = SAVE_DIR_LEGACY + name + "/"
	var dir := DirAccess.open(SAVE_DIR_LEGACY)
	if dir == null or not dir.dir_exists(name):
		return false
	if not FileAccess.file_exists(base + "params.json"):
		push_warning("[MapSave] 拒绝删除非参数图目录（可能是地图工坊的地图）：" + base)
		return false
	_remove_dir_recursive(base)
	return true

func _remove_dir_recursive(dir_path: String) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		if n != "." and n != "..":
			var full: String = dir_path + "/" + n
			if d.current_is_dir():
				_remove_dir_recursive(full)
			else:
				d.remove(full)
		n = d.get_next()
	d.list_dir_end()
	d.remove(dir_path)

func params_to_dict(p) -> Dictionary:
	var d: Dictionary = {}
	for k in FIELDS:
		d[k] = p.get(k)
	return d
