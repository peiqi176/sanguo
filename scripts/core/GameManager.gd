extends Node
## GameManager — 全局游戏状态单例
## 管理：资源/人口/官府等级/科技/民心/外交/胜负
## 所有系统通过此单例查询和修改游戏状态


# 资源类型
enum ResourceType { FOOD, WOOD, STONE, GOLD }

# 游戏配置
const TICK_INTERVAL: float = 1.0  # 经济tick间隔（秒）

# ========== 势力颜色系统 ==========
# 9 种可选颜色（MainMenu 选择）
const FACTION_COLORS: Dictionary = {
	"red":    Color(0.85, 0.20, 0.20),   # 红（默认）
	"blue":   Color(0.25, 0.45, 0.85),   # 蓝
	"yellow": Color(0.92, 0.78, 0.25),   # 黄
	"purple": Color(0.60, 0.30, 0.75),   # 紫
	"orange": Color(0.95, 0.55, 0.25),   # 橙
	"green":  Color(0.35, 0.75, 0.35),   # 绿
	"cyan":   Color(0.30, 0.75, 0.80),   # 青
	"brown":  Color(0.60, 0.40, 0.25),   # 褐
	"black":  Color(0.22, 0.22, 0.22),   # 黑
}

# 每个势力当前颜色（faction_id -> Color）
var faction_colors: Dictionary = {}

# 🔥 资源变化合并广播：本帧内哪个势力的资源动过（帧末统一发一次 resources_changed）
var _res_dirty: Dictionary = {}

func set_faction_color(fid: String, color_name: String) -> void:
	"""给某个势力设置颜色（通过颜色名）"""
	if FACTION_COLORS.has(color_name):
		faction_colors[fid] = FACTION_COLORS[color_name]
	else:
		# 直接传 Color 对象
		faction_colors[fid] = color_name  # 容错

func get_faction_color(fid: String) -> Color:
	"""获取势力颜色，没设置则 fallback 到 FACTION_INFO 默认色"""
	if faction_colors.has(fid):
		return faction_colors[fid]
	# 默认色（魏红/蜀绿/吴蓝）
	match fid:
		"wei": return FACTION_COLORS["red"]
		"shu": return FACTION_COLORS["green"]
		"wu": return FACTION_COLORS["blue"]
		_: return FACTION_COLORS["red"]

# 势力数据
var factions: Dictionary = {}  # faction_id -> FactionState
var player_faction: String = "shu"

# 全局实体引用
var all_units: Array = []
var all_buildings: Array = []
var resource_nodes: Array = []
var villages: Array = []
var wild_horses: Array = []
var relics: Array = []

# 游戏状态
var game_speed: float = 1.0
var paused: bool = false
var game_over: bool = false
var current_season: String = "spring"
var season_timer: float = 0.0

## 🗺 编辑器模式（地图工坊用）
##
## 编辑器里摆的是**真实**的 Building.tscn / Unit.tscn（不是占位盒），
## 这样才能做到"放下去就看到最终贴图"。但真实实体一进场景树就会自己跑起来：
##   建筑会涨建造进度、造资源、训练队列；单位会寻路、攻击、掉血。
## 放 20 个建筑，游戏就自己开了一局。
##
## 所以这个开关必须做到两件事：
##   ① 实体 _process / _physics_process 首行直接 return（单位保留贴地）
##   ② register_building / register_unit 不登记（否则全局列表里全是编辑器对象，
##      切场景进游戏时全是已释放节点的悬空引用）
var editor_mode: bool = false

# ⚙️ 开局自定义设置（MainMenu 传入，apply_settings() 读取）
var game_settings_override: Dictionary = {}

# 🎯 设计 v3 运行时变量（AI操作速度/政务/特殊科技/暴击）
var ai_reaction_delay: float = 2.0  # 简单3s/普通2s/困难1s/最高0.5s
var ai_starting_resources_mult: float = 1.0
var ai_starting_peasants: int = 2
var fog_of_war_enabled: bool = true
var disasters_enabled: bool = true
var buddha_head_enabled: bool = false
var quick_game_mode: bool = false
var selected_map_id: String = "jiangshan_yitong"
var solo_duel_enabled: bool = false
var initial_generals_count: int = 1
var initial_resources_mult: float = 1.0
var victory_condition: String = "eliminate_all"
var initial_cities: int = 1
var initial_peasants: int = 5       # 玩家和 AI 默认农夫都是 5
var initial_soldiers: Dictionary = {"sword":2, "spear":2, "archer":2, "civil":1}
var initial_civils: int = 1         # 默认 1 个文臣

# 🗺 地图来源/尺寸（主菜单写入，Main._ready 读取）
# map_mode: preset(预设) / random(随机) / seed(指定种子) / saved(读档) / live(地图编辑器直出)
var map_mode: String = "preset"
var map_seed: int = 0
var map_saved_name: String = ""
var map_size_key: String = "large"   # small(60) / medium(72) / large(84)

# 🛡️ 政务任命系统（5岗）
# faction_id -> { "政务", "科技", "祭祀", "治安", "通商"  }
var appointed_officials: Dictionary = {}

# 🧪 特殊科技系统（13选3，解锁：官府2级+翰林院2级）
# faction_id -> Set{ "tech_id1", "tech_id2", "tech_id3" }
var elite_techs: Dictionary = {}
var elite_tech_unlocked: bool = false

# 💥 暴击公式（武将专用，士兵无暴击）
func calc_crit_chance(might: float) -> float:
	"""暴击率 = 武力×0.15%，封顶15%"""
	return min(might * 0.0015, 0.15)

func calc_crit_damage(base_mult: float, might: float, has_qinglong: bool = false, qinglong_level: int = 0) -> float:
	"""暴击伤害 = 默认125% + 青龙偃月加成"""
	var crit_dmg: float = 1.25
	if has_qinglong:
		var bonuses := [0.0, 0.20, 0.30, 0.40]
		crit_dmg += bonuses[clampi(qinglong_level, 0, 3)]
	return base_mult * crit_dmg

# 📊 特殊科技加成计算（叠加所有已选科技）
func get_elite_tech_bonus(faction_id: String, effect_key: String) -> float:
	var tech_set: Dictionary = elite_techs.get(faction_id, {})
	var all_elite: Dictionary = DataLoader.tech_elite.get("categories", {})
	var total: float = 1.0
	for cat in all_elite.keys():
		for t in all_elite[cat].get("techs", []):
			if t.get("id", "") in tech_set:
				var eff: Dictionary = t.get("effect", {})
				if eff.has(effect_key):
					total *= float(eff[effect_key])
	return total

# 📖 基础科技（39 项）效果查询 —— 这些 effect 字段由此处统一消费
# 缓存：faction -> { "count": 已研究数量, "effects": {effect_key: 累加值} }
var _tech_effect_cache: Dictionary = {}

func invalidate_tech_cache() -> void:
	_tech_effect_cache.clear()

func _get_tech_effects(faction_id: String) -> Dictionary:
	var state = factions.get(faction_id)
	if state == null:
		return {}
	var count_now: int = state.researched_techs.size()
	var cached: Dictionary = _tech_effect_cache.get(faction_id, {})
	if int(cached.get("count", -1)) == count_now:
		return cached.get("effects", {})
	var effects: Dictionary = {}
	var branches: Dictionary = DataLoader.tech.get("branches", {})
	for tech_id in state.researched_techs:
		for branch in branches.values():
			var techs: Dictionary = branch.get("techs", {})
			if not techs.has(tech_id):
				continue
			for key in techs[tech_id].get("effect", {}).keys():
				var v = techs[tech_id]["effect"][key]
				if typeof(v) == TYPE_BOOL:
					effects[key] = bool(effects.get(key, false)) or bool(v)
				elif typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
					effects[key] = float(effects.get(key, 0.0)) + float(v)
			break
	_tech_effect_cache[faction_id] = { "count": count_now, "effects": effects }
	return effects

func get_tech_sum(faction_id: String, effect_key: String) -> float:
	return float(_get_tech_effects(faction_id).get(effect_key, 0.0))

func get_tech_bonus(faction_id: String, effect_key: String) -> float:
	"""百分比加成：1.0 + 已研究科技该字段之和"""
	return 1.0 + get_tech_sum(faction_id, effect_key)

func get_tech_reduction(faction_id: String, effect_key: String) -> float:
	"""减益类（如体力消耗 -15%）：返回剩余比例，最低 0"""
	return maxf(0.0, 1.0 - get_tech_sum(faction_id, effect_key))

func has_tech_flag(faction_id: String, effect_key: String) -> bool:
	"""布尔型科技效果（如城墙升到 10000 HP）"""
	return bool(_get_tech_effects(faction_id).get(effect_key, false))

func is_tech_researched(faction_id: String, tech_id: String) -> bool:
	var state = factions.get(faction_id)
	if state == null:
		return false
	return state.researched_techs.has(tech_id)

# 🧪 特殊科技（13选3）——解锁判定：官府≥2级 且 已建翰林院
func is_elite_unlocked(faction_id: String) -> bool:
	if get_government_level(faction_id) < 2:
		return false
	if not factions.has(faction_id):
		return false
	for b in factions[faction_id].buildings:
		if is_instance_valid(b) and b.building_id == "hanlinyuan":
			return true
	return false

func get_selected_elite_count(faction_id: String) -> int:
	return (elite_techs.get(faction_id, {}) as Dictionary).size()

# 返回 tech_id 所属分类 key（找不到返回 ""）
func _find_elite_category(tech_id: String) -> String:
	var cats: Dictionary = DataLoader.tech_elite.get("categories", {})
	for ck in cats.keys():
		for t in cats[ck].get("techs", []):
			if t.get("id", "") == tech_id:
				return ck
	return ""

func select_elite_tech(faction_id: String, tech_id: String) -> bool:
	"""选择一个特殊科技（受总上限3 + 分类上限约束，需解锁+资源足够）"""
	if not is_elite_unlocked(faction_id):
		return false
	var sel: Dictionary = elite_techs.get(faction_id, {})
	if sel.has(tech_id):
		return false
	var rules: Dictionary = DataLoader.tech_elite.get("research_rules", {})
	if sel.size() >= int(rules.get("max_selected", 3)):
		return false
	var cat_key: String = _find_elite_category(tech_id)
	if cat_key == "":
		return false
	var cats: Dictionary = DataLoader.tech_elite.get("categories", {})
	# 分类内已选数量
	var cat_count: int = 0
	for tid in sel.keys():
		for t in cats[cat_key].get("techs", []):
			if t.get("id", "") == tid:
				cat_count += 1
	if cat_count >= int(cats[cat_key].get("max", 99)):
		return false
	# 扣费
	var cost: Dictionary = rules.get("cost", {})
	if not spend_resources(faction_id, cost):
		return false
	sel[tech_id] = true
	elite_techs[faction_id] = sel
	if faction_id == player_faction:
		elite_tech_unlocked = true
	print("[特殊科技] ✅ %s 选择 %s（%d/%d）" % [faction_id, tech_id, sel.size(), int(rules.get("max_selected", 3))])
	EventBus.float_text.emit("🧪 特殊科技已激活", Vector3.ZERO, Color.GOLD)
	return true

# 🏛️ 政务任命效果
func get_official_bonus(faction_id: String, office_type: String) -> float:
	var appts: Dictionary = appointed_officials.get(faction_id, {})
	var gen = appts.get(office_type, null)
	if gen == null or not is_instance_valid(gen):
		return 0.0
	# 属性不匹配（内政<60）效果减半
	var match_bonus: float = 1.0
	var poli: float = float(gen.stats.get("politics", 50.0))
	if poli < 60:
		match_bonus = 0.5
	var bonuses: Dictionary = {
		"政务": 0.20,      # 税收+20%
		"科技": 0.25,      # 研究速度+25%
		"祭祀": 0.15,      # 灾祸-60% + 采集+15%
		"治安": 0.20,      # 守军防御+20%
		"通商": 0.25       # 贸易价+25%
	}
	return bonuses.get(office_type, 0.0) * match_bonus

# 政务官匹配系数：任命且存活=1.0（内政<60为0.5），未任命=0.0
func get_official_match_mult(faction_id: String, office_type: String) -> float:
	var appts: Dictionary = appointed_officials.get(faction_id, {})
	var gen = appts.get(office_type, null)
	if gen == null or not is_instance_valid(gen):
		return 0.0
	var poli: float = float(gen.stats.get("politics", 50.0))
	return 1.0 if poli >= 60 else 0.5

func get_tax_bonus(faction_id: String) -> float:
	return 0.20 * get_official_match_mult(faction_id, "政务")

func get_research_speed_mult(faction_id: String) -> float:
	var off_mult: float = get_official_match_mult(faction_id, "科技")
	var base: float = 1.0 + 0.25 * off_mult
	var elite: float = get_elite_tech_bonus(faction_id, "research_speed_mult")
	# 🏛 翰林院：每座 +25% 研究速度，最多计 2 座（+50%）
	return base * elite * get_hanlin_speed_mult(faction_id)

func get_hanlin_speed_mult(faction_id: String) -> float:
	var n: int = 0
	for b in all_buildings:
		if is_instance_valid(b) and b.get("building_id") == "hanlinyuan" and b.get("faction") == faction_id:
			if float(b.get("build_progress")) >= 1.0:
				n += 1
	return 1.0 + 0.25 * float(mini(n, 2))

## 某势力是否拥有指定建筑（已建成）
func has_building_of(faction_id: String, bid: String) -> bool:
	for b in all_buildings:
		if not is_instance_valid(b):
			continue
		if b.get("building_id") == bid and b.get("faction") == faction_id:
			if float(b.get("build_progress")) >= 1.0:
				return true
	return false

func get_gather_official_bonus(faction_id: String) -> float:
	return 0.15 * get_official_match_mult(faction_id, "祭祀")

func get_disaster_reduction(faction_id: String) -> float:
	# 政务祭祀官基础减免 + 寺庙祈福限时减免（上限 90%）
	var base: float = 0.60 * get_official_match_mult(faction_id, "祭祀")
	return minf(0.90, base + get_buff_value(faction_id, "disaster_reduction"))

func get_garrison_defense_bonus(faction_id: String) -> float:
	return 0.20 * get_official_match_mult(faction_id, "治安")

# 特殊科技原始数值累加（用于吸血等非乘算效果）
func get_elite_tech_value(faction_id: String, effect_key: String) -> float:
	var tech_set: Dictionary = elite_techs.get(faction_id, {})
	var all_elite: Dictionary = DataLoader.tech_elite.get("categories", {})
	var total: float = 0.0
	for cat in all_elite.keys():
		for t in all_elite[cat].get("techs", []):
			if t.get("id", "") in tech_set:
				var eff: Dictionary = t.get("effect", {})
				if eff.has(effect_key):
					total += float(eff[effect_key])
	return total

func has_general_immunity(faction_id: String, effect_type: String) -> bool:
	var tech_set: Dictionary = elite_techs.get(faction_id, {})
	var all_elite: Dictionary = DataLoader.tech_elite.get("categories", {})
	for cat in all_elite.keys():
		for t in all_elite[cat].get("techs", []):
			if t.get("id", "") in tech_set:
				var eff: Dictionary = t.get("effect", {})
				if eff.has("general_immunity"):
					var val = eff["general_immunity"]
					if val is Array and effect_type in val:
						return true
	return false

# 📖 献策系统
func try_give_advice(faction_id: String) -> void:
	"""智谋≥50的武将，30s内最多触发1次献策"""
	var generals: Array = get_all_generals_for_faction(faction_id)
	if generals.is_empty():
		return
	for g in generals:
		if g.stats.get("intelligence", 0) < 50:
			continue
		var chance: float = min(g.stats.get("intelligence", 0) * 0.0015, 0.15)
		if randf() < chance:
			print("[献策] %s（智%.0f）给 %s 献策！" % [g.general_def.get("name", g.name), g.stats.get("intelligence", 0), faction_id])
			EventBus.float_text.emit("💡 献计！", g.global_position + Vector3(0, 3, 0), Color.YELLOW)
			# 简单效果: 标记敌方位置 5s
			if g.has_method("mark_enemies"):
				g.mark_enemies(5)
			return

func get_all_generals_for_faction(faction_id: String) -> Array:
	var result: Array = []
	for g in all_generals:
		if is_instance_valid(g) and g.get_faction() == faction_id:
			result.append(g)
	return result

# ==================== 🙏 寺庙祈福限时 Buff ====================

func add_faction_buff(fid: String, key: String, value: float, duration: float) -> void:
	if not factions.has(fid):
		return
	if not faction_buffs.has(fid):
		faction_buffs[fid] = {}
	var b: Dictionary = faction_buffs[fid]
	if b.has(key):
		# 同类祈福不叠加：数值取最高、时长取最长
		var old: Dictionary = b[key]
		b[key] = {
			"value": maxf(float(old.get("value", 0.0)), value),
			"remain": maxf(float(old.get("remain", 0.0)), duration),
		}
	else:
		b[key] = {"value": value, "remain": duration}

func get_buff_value(fid: String, key: String) -> float:
	var b: Dictionary = faction_buffs.get(fid, {})
	if not b.has(key):
		return 0.0
	return float(b[key].get("value", 0.0))

# ==================== 🎖 经验经济（2026-10-27 定稿） ====================
## 单个单位加经验：武将走 add_xp，士兵走 add_exp
func grant_xp_to(unit, amt: float) -> void:
	if unit == null or not is_instance_valid(unit) or amt <= 0.0:
		return
	if unit.has_method("add_xp"):
		unit.add_xp(amt)
	elif unit.has_method("add_exp"):
		unit.add_exp(amt)

## 参与者平分一个经验池，每人封顶 per_max（人数 > 池/上限 时每人只拿上限，剩余不发给谁）
func grant_shared_xp(units: Array, pool: float, per_max: float) -> void:
	var valid: Array = []
	for u in units:
		if is_instance_valid(u) and (u.has_method("add_exp") or u.has_method("add_xp")):
			valid.append(u)
	if valid.is_empty() or pool <= 0.0:
		return
	var share: float = minf(per_max, pool / float(valid.size()))
	for u in valid:
		grant_xp_to(u, share)

## 🪨 古碑任务奖励：给该势力全部武将发放训练经验（前期练将）
func grant_officer_xp(fid: String, amount: float) -> int:
	if amount <= 0.0:
		return 0
	var count: int = 0
	for g in all_generals:
		if not is_instance_valid(g):
			continue
		if not g.has_method("get_faction") or g.get_faction() != fid:
			continue
		grant_xp_to(g, amount)
		count += 1
	return count

## 取某个坐标附近某势力的单位（占领结算用）
func get_units_near(pos: Vector3, radius: float, fid: String) -> Array:
	var out: Array = []
	for u in all_units:
		if not is_instance_valid(u):
			continue
		if not u.has_method("get_faction") or u.get_faction() != fid:
			continue
		if u.global_position.distance_to(pos) <= radius:
			out.append(u)
	return out

func get_buff_remain(fid: String, key: String) -> float:
	var b: Dictionary = faction_buffs.get(fid, {})
	if not b.has(key):
		return 0.0
	return float(b[key].get("remain", 0.0))

func _tick_buffs(d: float) -> void:
	for fid in faction_buffs.keys():
		var b: Dictionary = faction_buffs[fid]
		var expired: Array = []
		for k in b.keys():
			b[k]["remain"] = float(b[k]["remain"]) - d
			if float(b[k]["remain"]) <= 0.0:
				expired.append(k)
		for k in expired:
			b.erase(k)

# ==================== 🏮 在野武将池 / 客栈招募 ====================

func init_general_pool() -> void:
	generals_pool.clear()
	dead_generals.clear()
	for g in DataLoader.generals.get("general_pool", []):
		var gid: String = str(g.get("id", ""))
		if gid != "" and not is_general_taken(gid):
			generals_pool.append(gid)

func is_general_taken(gid: String) -> bool:
	for u in all_units:
		if is_instance_valid(u) and bool(u.get("is_general")) and str(u.get("general_id")) == gid:
			return true
	for g in dead_generals:
		if is_instance_valid(g) and str(g.get("general_id")) == gid:
			return true
	return false

func get_general_def_by_id(gid: String) -> Dictionary:
	for g in DataLoader.generals.get("general_pool", []):
		if str(g.get("id", "")) == gid:
			return g
	return {}

## 客栈可给的等级区间：<10 分钟 Lv1；10-20 分钟 Lv1-5；20 分钟后 Lv1-7
func get_recruit_level_range(bdef: Dictionary) -> Vector2i:
	for w in (bdef.get("recruit", {}) as Dictionary).get("level_windows", []):
		var until: float = float(w.get("until", -1))
		if until < 0.0 or game_elapsed < until:
			return Vector2i(int(w.get("min", 1)), int(w.get("max", 1)))
	return Vector2i(1, 1)

## 🏮 客栈声望：每占 1 座村庄 -2%，封顶 -10%
func get_recruit_renown_discount(rc: Dictionary, fid: String) -> float:
	var rn: Dictionary = rc.get("renown", {})
	var n: int = 0
	for v in villages:
		if is_instance_valid(v) and str(v.get("village_owner")) == fid:
			n += 1
	return minf(float(rn.get("max", 0.10)), float(rn.get("per_village", 0.02)) * float(n))

## 🏮 招募价拆解（唯一定价入口，UI/扣费共用）
## 价格 = base × 等级曲线 × 属性溢价（夹 400~2000）
##        × (1 − 同势力折扣 − 声望折扣 + 敌对在野溢价)
func get_recruit_price_breakdown(bdef: Dictionary, lv: int, gid: String, fid: String) -> Dictionary:
	var rc: Dictionary = bdef.get("recruit", {})
	var base: float = float(rc.get("base_cost", 500))
	var curve: Dictionary = rc.get("level_curve", {})
	var lv_mult: float = float(curve.get(str(clampi(lv, 1, 7)), 1.0))
	var level_price: float = base * lv_mult

	var gdef: Dictionary = get_general_def_by_id(gid)
	var bs: Dictionary = gdef.get("base", {})
	var stat_sum: float = float(bs.get("might", 70)) + float(bs.get("intelligence", 70)) + float(bs.get("command", 70))
	var ref: float = float(rc.get("stat_reference", 210))
	var div: float = maxf(1.0, float(rc.get("stat_divisor", 500)))
	var stat_mult: float = clampf(1.0 + (stat_sum - ref) / div,
		float(rc.get("stat_mult_min", 0.85)), float(rc.get("stat_mult_max", 1.15)))

	var lo: float = float(rc.get("min_cost", 400))
	var hi: float = float(rc.get("max_cost", 2000))
	var pre: float = clampf(level_price * stat_mult, lo, hi)

	# 🎖 势力加成：同势力 -20%；敌对势力在野名将 +10%（招降更难）；群雄不加价
	var gf: String = str(gdef.get("faction", ""))
	var same_disc: float = float((rc.get("faction_discount", {}) as Dictionary).get(fid, 0.0)) if gf == fid else 0.0
	var enemy_prem: float = float(rc.get("enemy_premium", 0.0)) if (gf != "" and gf != fid and gf != "qunxiong") else 0.0
	var renown: float = get_recruit_renown_discount(rc, fid)
	var total_mult: float = maxf(0.3, 1.0 - same_disc - renown + enemy_prem)
	var final_price: float = clampf(pre * total_mult, lo, hi)

	return {
		"base": base,
		"level_mult": lv_mult,
		"level_price": level_price,
		"stat_sum": stat_sum,
		"stat_mult": stat_mult,
		"pre": pre,
		"same_faction_discount": same_disc,
		"renown_discount": renown,
		"enemy_premium": enemy_prem,
		"total_mult": total_mult,
		"final": roundf(final_price)
	}

func get_recruit_cost(bdef: Dictionary, lv: int, gid: String, fid: String) -> float:
	return float(get_recruit_price_breakdown(bdef, lv, gid, fid).get("final", 500))

## 🏮 客栈换批周期：游戏内 1 个月 = 60s（配置在 buildings.json → inn.recruit.refresh_seconds）
func get_inn_refresh_seconds(bdef: Dictionary) -> float:
	return maxf(1.0, float((bdef.get("recruit", {}) as Dictionary).get("refresh_seconds", 60.0)))

## 该在野武将是否已经被别的客栈挂在本月名单里（避免多客栈重复展示同一人）
func is_general_claimed_elsewhere(gid: String, except_inn: Node) -> bool:
	for b in all_buildings:
		if not is_instance_valid(b) or b == except_inn:
			continue
		if str(b.get("building_id")) != "inn":
			continue
		var roster = b.get("inn_roster")
		if roster == null:
			continue
		for e in roster:
			if str((e as Dictionary).get("id", "")) == gid:
				return true
	return false

## 客栈按月自动换批（由 _process 统一推进，玩家无法手动刷新）
func tick_inn_rosters(d: float) -> void:
	for b in all_buildings:
		if is_instance_valid(b) and str(b.get("building_id")) == "inn" and b.has_method("inn_tick"):
			b.inn_tick(d)

## 武将三维总和（UI 展示 / 排序用）
func get_general_stat_sum(gid: String) -> int:
	var bs: Dictionary = get_general_def_by_id(gid).get("base", {})
	return int(bs.get("might", 70)) + int(bs.get("intelligence", 70)) + int(bs.get("command", 70))

# ==================== 🏛 通用查询（General.gd 依赖，此前缺失） ====================

func get_government(fid: String) -> Node:
	for b in all_buildings:
		if is_instance_valid(b) and b.get("building_id") == "government" and b.get("faction") == fid:
			return b
	return null

func has_temple_nearby(fid: String, pos: Vector3, rng: float = 10.0) -> bool:
	for b in all_buildings:
		if not is_instance_valid(b):
			continue
		if b.get("building_id") != "temple" or b.get("faction") != fid:
			continue
		if pos.distance_to(b.global_position) <= rng:
			return true
	return false

func get_all_nearby_enemies(pos: Vector3, rng: float, fid: String = "") -> Array:
	var out: Array = []
	for u in all_units:
		if not is_instance_valid(u):
			continue
		if fid != "" and u.get_faction() == fid:
			continue
		if pos.distance_to(u.global_position) <= rng:
			out.append(u)
	return out

# 应用设置到运行时变量（在 Main._ready 最早调用）
func apply_settings() -> void:
	# 以 JSON default_settings 为基底，再用 override / 磁盘存档逐键覆盖
	# —— 避免旧存档缺键时静默回退到硬编码错值（如颜色变红）
	var cfg: Dictionary = (DataLoader.game_settings.get("default_settings", {}) as Dictionary).duplicate()
	if not game_settings_override.is_empty():
		for k in game_settings_override.keys():
			cfg[k] = game_settings_override[k]
	else:
		# 兜底：直接跑 Main 场景（没经过主菜单）时，从 user:// 存档恢复
		var disk: Dictionary = _load_settings_from_disk()
		for k in disk.keys():
			cfg[k] = disk[k]
	player_faction = cfg.get("player_faction", "shu")
	selected_map_id = cfg.get("map_id", "jiangshan_yitong")
	# 🗺 地图来源/尺寸
	map_mode = cfg.get("map_mode", "preset")
	map_seed = int(cfg.get("map_seed", 0))
	map_saved_name = str(cfg.get("map_saved_name", ""))
	map_size_key = str(cfg.get("map_size_key", "large"))
	fog_of_war_enabled = cfg.get("fog_of_war", true)
	disasters_enabled = cfg.get("disasters", true)
	buddha_head_enabled = cfg.get("buddha_head", false)
	quick_game_mode = cfg.get("quick_game", false)
	solo_duel_enabled = cfg.get("solo_duel_enabled", false)
	initial_generals_count = int(cfg.get("initial_generals_count", 1))
	initial_cities = int(cfg.get("initial_cities", 1))
	victory_condition = cfg.get("victory_condition", "eliminate_all")
	# 从难度预设读取反应延迟/初始资源倍率/初始农夫
	var dpresets: Dictionary = DataLoader.game_settings.get("difficulty_presets", {})
	var dp: Dictionary = dpresets.get(cfg.get("difficulty", "normal"), dpresets.get("normal", {}))
	ai_reaction_delay = float(dp.get("reaction_delay", 2.0))
	ai_starting_resources_mult = float(dp.get("starting_resources_mult", 1.0))
	ai_starting_peasants = int(dp.get("starting_peasants", 5))
	# 初始资源阶层
	var reslvl: Dictionary = DataLoader.game_settings.get("initial_resources_level", {})
	initial_resources_mult = float(reslvl.get(cfg.get("initial_resources", "normal"), {}).get("mult", 1.0))
	# � v4 新字段：农夫/士兵/文臣
	if cfg.has("initial_peasants"): initial_peasants = int(cfg["initial_peasants"])
	if cfg.has("initial_soldiers"):
		var sd: Variant = cfg["initial_soldiers"]
		if sd is Dictionary and not sd.is_empty(): initial_soldiers = sd
	if cfg.has("initial_civils"): initial_civils = int(cfg["initial_civils"])
	# �� 势力颜色（主菜单存的是颜色名 key，不是 HTML 串）
	var color_key: String = str(cfg.get("faction_color_key", "green"))
	if not FACTION_COLORS.has(color_key):
		color_key = "green"
	set_faction_color(player_faction, color_key)
	# 特殊科技已解锁（官府2+翰林院2级后设 true）
	elite_tech_unlocked = false
	print("[GameManager] ⚙ apply_settings OK:")
	print("  faction=%s color=%s map=%s ai_delay=%.1fs ai_res=%.1fx ai_peasants=%d fog=%s disaster=%s solo=%s" % [
		player_faction, color_key, selected_map_id, ai_reaction_delay, ai_starting_resources_mult,
		ai_starting_peasants, fog_of_war_enabled, disasters_enabled, solo_duel_enabled])

# 从 user://game_settings.cfg 读取主菜单上次保存的设置
func _load_settings_from_disk() -> Dictionary:
	var path: String = "user://game_settings.cfg"
	if not FileAccess.file_exists(path):
		return {}
	var c := ConfigFile.new()
	if c.load(path) != OK:
		return {}
	var out: Dictionary = {}
	if c.has_section("game"):
		for k in c.get_section_keys("game"):
			out[k] = c.get_value("game", k)
	return out

# all_generals 引用（General 注册到此数组）
var all_generals: Array = []
var generals_pool: Array = []     # 🏮 在野武将池（客栈可招募的 general_id）
var dead_generals: Array = []     # 💀 重伤中的武将节点（寺庙 5 分钟内可救）
# 🙏 寺庙祈福限时 Buff：faction_id -> { key: {"value": float, "remain": float} }
var faction_buffs: Dictionary = {}
# ⏱ 本局已进行时长（秒），用于客栈按时间段给武将等级
var game_elapsed: float = 0.0

# 网格
var grid: Node = null
var pathfinder: Node = null
var map_size: Vector2i = Vector2i(84, 84)
var cell_size: float = 1.0

# tick计时
var _tick_timer: float = 0.0
var _advice_timer: float = 0.0  # 📖 献策轮询（每30s）
var _month_timer: float = 0.0   # 🏛 政务每月经验（每30s=1月）

class FactionState:
	var faction_id: String
	var resources: Dictionary = { "food": 200, "wood": 200, "iron": 100, "gold": 150, "bun": 0, "wine": 0 }
	var population_used: int = 0
	var population_cap: int = 20
	var government_level: int = 1
	var morale: float = 70.0
	var tax_rate: String = "medium"
	var tax_rate_value: float = 0.15  # 🔥 v4 滑条税收值（金/人/月，0.1-0.5）
	var tax_pop_penalty: bool = false  # 🔥 v4 税收>0.40时设为true，影响人口增长
	var tech_completion: float = 0.0
	var researched_techs: Array = []
	var researching: Dictionary = {}  # tech_id -> { "branch": String, "remaining": float, "total": float }
	var units: Array = []
	var buildings: Array = []
	var color: Color = Color.WHITE
	var trust: Dictionary = {}  # other_faction -> trust value
	var resource_rates: Dictionary = {}  # res -> per-second rate
	var defeated: bool = false
	
	func _init(id: String):
		faction_id = id


func _ready() -> void:
	_init_factions()
	init_general_pool()
	print("[GameManager] 初始化完成")

func _init_factions() -> void:
	_tech_effect_cache.clear()
	for faction_id in DataLoader.factions["factions"].keys():
		var def := DataLoader.get_faction_def(faction_id)
		var state := FactionState.new(faction_id)
		if def.has("starting_resources"):
			state.resources = def["starting_resources"].duplicate()
		if def.has("color"):
			state.color = Color.from_string(def["color"], Color.WHITE)
		# 初始化信任度
		for other in DataLoader.factions["factions"].keys():
			if other != faction_id:
				state.trust[other] = 50
		factions[faction_id] = state

func _process(delta: float) -> void:
	if paused or game_over:
		return
	# 🔥 资源信号帧末合并广播：一帧内 N 次 add/spend 只发 1 次 resources_changed，
	# 资源栏 UI 每帧最多刷新一次（此前每栋建筑每秒结算都全量重建 UI，造成 1s 周期卡顿尖峰）。
	if not _res_dirty.is_empty():
		for fid in _res_dirty.keys():
			EventBus.resources_changed.emit(fid)
		_res_dirty.clear()
	var d := delta * game_speed
	game_elapsed += d
	tick_inn_rosters(d)
	_tick_buffs(d)
	_tick_timer += d
	if _tick_timer >= TICK_INTERVAL:
		_tick_timer = 0.0
		_economic_tick()
		check_victory()  # ⚔️ 胜负判定轮询：官府被毁/单位全灭/只剩一势力
	# 季节推进
	season_timer += d
	var season_duration: float = 120.0
	if DataLoader.seasons.has("duration_per_season"):
		season_duration = DataLoader.seasons["duration_per_season"]
	if season_timer >= season_duration:
		season_timer = 0.0
		_advance_season()
	# 📖 献策轮询：每 30s 让各势力智谋≥50 的武将按几率献策
	_advice_timer += d
	if _advice_timer >= 30.0:
		_advice_timer = 0.0
		for fid in factions.keys():
			try_give_advice(fid)
	# 📜 研究进度推进（按科技所需时间 / 研究速度）
	for fid2 in factions.keys():
		var state2: FactionState = factions[fid2]
		var completed: Array = []
		for tech_id in state2.researching.keys():
			var rinfo: Dictionary = state2.researching[tech_id]
			rinfo["remaining"] = float(rinfo["remaining"]) - d
			if float(rinfo["remaining"]) <= 0.0:
				completed.append(tech_id)
		for tech_id in completed:
			state2.researching.erase(tech_id)
			state2.researched_techs.append(tech_id)
			var total_techs: int = 0
			var branches2: Dictionary = DataLoader.tech.get("branches", {})
			for b in branches2.values():
				total_techs += b.get("techs", {}).size()
			state2.tech_completion = float(state2.researched_techs.size()) / float(total_techs)
			EventBus.tech_researched.emit(fid2, tech_id)
			print("[研究] ✅ %s 完成 %s" % [fid2, tech_id])
			if fid2 == player_faction:
				EventBus.float_text.emit("研究完成: %s" % tech_id, Vector3.ZERO, Color.GREEN)
	# 🏛 政务每月经验结算（30s=1月，每岗+50）
	_month_timer += d
	if _month_timer >= 30.0:
		_month_timer = 0.0
		for fid3 in factions.keys():
			var appts: Dictionary = appointed_officials.get(fid3, {})
			for office_type in appts.keys():
				var gen = appts[office_type]
				if gen != null and is_instance_valid(gen) and gen.has_method("add_xp"):
					gen.add_xp(50.0)

func _economic_tick() -> void:
	for faction_id in factions.keys():
		var state: FactionState = factions[faction_id]
		# 🏭 建筑产出统一由 Building._process 结算（包含农夫在岗比例、原料消耗、季节倍率）
		# 这里不再重复加资源，否则会出现"不派农夫也满产 + 资源双份"
		# 民心随税率变化
		var tax_rates: Dictionary = DataLoader.factions.get("tax_rates", {})
		if tax_rates.has(state.tax_rate):
			var morale_delta: float = tax_rates[state.tax_rate].get("morale_delta", 0.0)
			state.morale = clampf(state.morale + morale_delta, 0, 100)
		# 饥荒检测
		if state.resources.get("food", 0) < 0:
			state.morale = clampf(state.morale - 2.0, 0, 100)
			state.resources["food"] = 0
		# 补给区通用消耗：区内每单位(士兵+武将)1包子+1酒/分钟（无拥挤惩罚）
		var units_in_zone: int = 0
		for u in state.units:
			if is_instance_valid(u) and u.has_method("get_supply_in_zone") and u.get_supply_in_zone():
				units_in_zone += 1
		var bun_cost: float = float(units_in_zone) / 60.0
		var wine_cost: float = float(units_in_zone) / 60.0
		# 优先消耗包子（体力更关键），酒不够按剩余量扣
		var actual_bun_consume: float = min(bun_cost, state.resources.get("bun", 0))
		state.resources["bun"] = state.resources.get("bun", 0) - actual_bun_consume
		var actual_wine_consume: float = min(wine_cost, state.resources.get("wine", 0))
		state.resources["wine"] = state.resources.get("wine", 0) - actual_wine_consume
		EventBus.morale_changed.emit(faction_id, state.morale)
		_update_resource_rates(faction_id)
		_res_dirty[faction_id] = true  # 🔥 合并广播（见 _process 注释）

func _advance_season() -> void:
	var order: Array = DataLoader.seasons.get("seasons", ["spring","summer","autumn","winter"])
	var idx: int = order.find(current_season)
	idx = (idx + 1) % order.size()
	current_season = order[idx]
	EventBus.season_changed.emit(current_season)
	print("[GameManager] 季节变更: %s" % current_season)

# ==================== 资源系统 ====================

func get_resource(faction_id: String, res: String) -> float:
	if not factions.has(faction_id):
		return 0.0
	return factions[faction_id].resources.get(res, 0.0)

func add_resource(faction_id: String, res: String, amount: float) -> void:
	if not factions.has(faction_id):
		return
	factions[faction_id].resources[res] = (factions[faction_id].resources.get(res, 0.0) as float) + amount
	if factions[faction_id].resources[res] < 0:
		factions[faction_id].resources[res] = 0
	# 🔥 不再逐次广播：每栋建筑每秒产出都调这里，逐次广播会让资源栏 UI
	# 被销毁重建几十次/秒（实测造成每秒 ~100ms 卡顿尖峰）。改成帧末合并广播。
	_res_dirty[faction_id] = true

func can_afford(faction_id: String, cost: Dictionary) -> bool:
	if not factions.has(faction_id):
		return false
	var state: FactionState = factions[faction_id]
	for res in cost.keys():
		if state.resources.get(res, 0) < cost[res]:
			return false
	return true

func spend_resources(faction_id: String, cost: Dictionary) -> bool:
	if not can_afford(faction_id, cost):
		return false
	var state: FactionState = factions[faction_id]
	for res in cost.keys():
		state.resources[res] -= cost[res]
	_res_dirty[faction_id] = true  # 🔥 合并广播（见 add_resource 注释）
	return true

# ==================== 人口系统 ====================

func get_population(faction_id: String) -> Dictionary:
	if not factions.has(faction_id):
		return { "used": 0, "cap": 0 }
	var state: FactionState = factions[faction_id]
	return { "used": state.population_used, "cap": state.population_cap }

func can_train(faction_id: String, pop_cost: int) -> bool:
	if not factions.has(faction_id):
		return false
	var state: FactionState = factions[faction_id]
	return state.population_used + pop_cost <= state.population_cap

func change_population(faction_id: String, delta: int) -> void:
	if not factions.has(faction_id):
		return
	factions[faction_id].population_used = max(0, factions[faction_id].population_used + delta)
	_res_dirty[faction_id] = true  # 🔥 合并广播（见 add_resource 注释）

func add_population_cap(faction_id: String, amount: int) -> void:
	if not factions.has(faction_id):
		return
	factions[faction_id].population_cap += amount
	EventBus.resources_changed.emit(faction_id)

# ==================== 官府等级 ====================

func get_government_level(faction_id: String) -> int:
	if not factions.has(faction_id):
		return 1
	return factions[faction_id].government_level

func can_upgrade_government(faction_id: String) -> bool:
	if not factions.has(faction_id):
		return false
	var state: FactionState = factions[faction_id]
	var cur: int = state.government_level
	if cur >= 4:
		return false
	var upgrade_key: String = "%d_to_%d" % [cur, cur + 1]
	var upgrades: Dictionary = DataLoader.tech.get("government_upgrade", {})
	if not upgrades.has(upgrade_key):
		return false
	var up: Dictionary = upgrades[upgrade_key]
	# 每一级都要达到对应科技完成率（L2/L3 需 60%，L4 需 100%）——
	# 此前只校验 L1→L2，导致 L3/L4 可以跳过科技门槛直接升。
	if state.tech_completion < float(up.get("tech_completion_required", 0.0)):
		return false
	return can_afford(faction_id, up.get("cost", {}))

func upgrade_government(faction_id: String) -> bool:
	if not can_upgrade_government(faction_id):
		return false
	var state: FactionState = factions[faction_id]
	var cur: int = state.government_level
	var upgrade_key: String = "%d_to_%d" % [cur, cur + 1]
	var up: Dictionary = DataLoader.tech["government_upgrade"][upgrade_key]
	spend_resources(faction_id, up["cost"])
	state.government_level = cur + 1
	EventBus.government_upgraded.emit(faction_id, state.government_level)
	return true

# ==================== 科技系统 ====================

func research_tech(faction_id: String, branch: String, tech_id: String) -> bool:
	if not factions.has(faction_id):
		return false
	var state: FactionState = factions[faction_id]
	var branches: Dictionary = DataLoader.tech.get("branches", {})
	if not branches.has(branch) or not branches[branch].has("techs"):
		return false
	var techs: Dictionary = branches[branch]["techs"]
	if not techs.has(tech_id):
		return false
	var tech_def: Dictionary = techs[tech_id]
	if state.researched_techs.has(tech_id):
		return false
	# 检查官府等级
	if state.government_level < tech_def.get("gov_req", 1):
		return false
	# 检查前置科技
	if tech_def.has("requires"):
		for req in tech_def["requires"]:
			if not state.researched_techs.has(req):
				return false
	# 🔀 互斥研究组：同一组只能选一项（例如农政二选一、兵制二选一）
	var mutex: String = str(tech_def.get("mutex_group", ""))
	if mutex != "":
		for other_branch in branches.keys():
			for other_id in branches[other_branch].get("techs", {}).keys():
				if other_id == tech_id:
					continue
				var od: Dictionary = branches[other_branch]["techs"][other_id]
				if str(od.get("mutex_group", "")) == mutex and state.researched_techs.has(other_id):
					return false
	if state.researching.has(tech_id):
		return false
	# 🏛 建筑前置：骑兵/器械/造船科技必须有对应建筑（此前该字段配了却没校验）
	var req_b: String = str(tech_def.get("requires_building", ""))
	if req_b != "" and not has_building_of(faction_id, req_b):
		return false
	if not can_afford(faction_id, tech_def.get("cost", {})):
		return false
	spend_resources(faction_id, tech_def["cost"])
	var raw_time: float = tech_def.get("time", 30.0)
	var speed: float = get_research_speed_mult(faction_id)
	var total_time: float = max(1.0, raw_time / speed)
	state.researching[tech_id] = { "branch": branch, "remaining": total_time, "total": total_time }
	print("[研究] %s 开始研究 %s，原始%.0fs，速度%.2f，实际%.1fs" % [faction_id, tech_id, raw_time, speed, total_time])
	return true

func get_tech_completion(faction_id: String) -> float:
	if not factions.has(faction_id):
		return 0.0
	return factions[faction_id].tech_completion

# ==================== 民心/税率 ====================

func get_morale(faction_id: String) -> float:
	if not factions.has(faction_id):
		return 50.0
	return factions[faction_id].morale

func set_tax_rate(faction_id: String, rate: String) -> void:
	if not factions.has(faction_id):
		return
	if rate in ["low", "medium", "high"]:
		factions[faction_id].tax_rate = rate

# 🔥 v4 滑条税收接口
func get_tax_rate(faction_id: String) -> float:
	if not factions.has(faction_id):
		return 0.15
	return factions[faction_id].tax_rate_value

func set_tax_rate_value(faction_id: String, value: float) -> void:
	if not factions.has(faction_id):
		return
	value = clamp(value, 0.1, 0.5)
	factions[faction_id].tax_rate_value = value
	factions[faction_id].tax_pop_penalty = value > 0.40

# ==================== 注册实体 ====================

func register_unit(unit) -> void:
	if editor_mode:
		return
	if not all_units.has(unit):
		all_units.append(unit)
	if unit.get_faction() in factions:
		factions[unit.get_faction()].units.append(unit)

func unregister_unit(unit) -> void:
	all_units.erase(unit)
	if unit.get_faction() in factions:
		factions[unit.get_faction()].units.erase(unit)

func register_building(building) -> void:
	if editor_mode:
		return
	if not all_buildings.has(building):
		all_buildings.append(building)
	if building.get_faction() in factions:
		factions[building.get_faction()].buildings.append(building)

func unregister_building(building) -> void:
	all_buildings.erase(building)
	if building.get_faction() in factions:
		factions[building.get_faction()].buildings.erase(building)

# ==================== 胜负判定 ====================

func check_victory() -> void:
	if game_over:
		return
	for faction_id in factions.keys():
		var state: FactionState = factions[faction_id]
		# 检查是否有官府存在
		var has_government: bool = false
		for b in state.buildings:
			if b.building_id == "government":
				has_government = true
				break
		if not has_government and not state.defeated:
			state.defeated = true
			EventBus.defeat.emit(faction_id)
			print("[GameManager] %s 被击败" % faction_id)
	# 检查是否只剩一个势力
	var alive: Array = []
	for fid in factions.keys():
		if not factions[fid].defeated:
			alive.append(fid)
	if alive.size() == 1:
		game_over = true
		EventBus.victory.emit(alive[0])
		print("[GameManager] 游戏结束，%s 胜利" % alive[0])

func set_paused(p: bool) -> void:
	paused = p

func set_game_speed(s: float) -> void:
	game_speed = s









# ==================== 外交系统 ====================

func get_trust(from_faction: String, to_faction: String) -> int:
	if not factions.has(from_faction):
		return 50
	return int(factions[from_faction].trust.get(to_faction, 50))

func get_relation(from_faction: String, to_faction: String) -> String:
	var trust_val: int = get_trust(from_faction, to_faction)
	if trust_val >= 80:
		return "alliance"
	elif trust_val <= 20:
		return "war"
	else:
		return "neutral"

func diplomatic_action(from_faction: String, to_faction: String, action_id: String) -> bool:
	if not factions.has(from_faction) or not factions.has(to_faction):
		return false
	var actions: Dictionary = DataLoader.diplomacy.get("actions", {})
	if not actions.has(action_id):
		return false
	var adef: Dictionary = actions[action_id]
	var from_state: FactionState = factions[from_faction]
	var to_state: FactionState = factions[to_faction]
	var cost: Dictionary = adef.get("cost", {})
	if not cost.is_empty() and not can_afford(from_faction, cost):
		return false
	if adef.has("trust_required") and from_state.trust.get(to_faction, 50) < adef["trust_required"]:
		return false
	if not cost.is_empty():
		spend_resources(from_faction, cost)
	match adef.get("effect", ""):
		"hostile":
			from_state.trust[to_faction] = clampi(from_state.trust.get(to_faction, 50) + adef.get("trust_delta", 0), 0, 100)
			to_state.trust[from_faction] = clampi(to_state.trust.get(from_faction, 50) + adef.get("trust_delta", 0), 0, 100)
		"alliance":
			from_state.trust[to_faction] = 100
			to_state.trust[from_faction] = 100
		"trade", "tribute", "marriage":
			from_state.trust[to_faction] = clampi(from_state.trust.get(to_faction, 50) + adef.get("trust_delta", 0), 0, 100)
			to_state.trust[from_faction] = clampi(to_state.trust.get(from_faction, 50) + int(adef.get("trust_delta", 0) * 0.5), 0, 100)
		"sabotage":
			var success: bool = randf() < adef.get("success_rate", 0.5)
			if success:
				to_state.trust[from_faction] = clampi(to_state.trust.get(from_faction, 50) + adef.get("trust_delta_target", 0), 0, 100)
			return success
	EventBus.diplomatic_action.emit(action_id, from_faction, to_faction)
	return true

# ==================== 资源速率 ====================

func is_faction_starving(faction_id: String) -> bool:
	if not factions.has(faction_id):
		return false
	return factions[faction_id].resources.get("food", 0) <= 0.0

func get_resource_rate(faction_id: String, res: String) -> float:
	if not factions.has(faction_id):
		return 0.0
	return factions[faction_id].resource_rates.get(res, 0.0)

func _update_resource_rates(faction_id: String) -> void:
	if not factions.has(faction_id):
		return
	var state: FactionState = factions[faction_id]
	var rates: Dictionary = {}
	for b in state.buildings:
		if b.has_method("get_production_per_second"):
			var prod: Dictionary = b.get_production_per_second()
			for res in prod.keys():
				rates[res] = rates.get(res, 0.0) + prod[res]
			# 原料消耗按在岗比例计入速率，UI 与实际结算一致
			var cmap: Dictionary = b.def.get("consumes", {})
			if not cmap.is_empty() and b.workers_max > 0:
				var wr: float = float(b.workers.size()) / float(b.workers_max)
				for cres in cmap.keys():
					rates[cres] = rates.get(cres, 0.0) - float(cmap[cres]) * wr
	state.resource_rates = rates

