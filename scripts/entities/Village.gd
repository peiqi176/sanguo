extends StaticBody3D
class_name Village
## Village — 中立村庄，可占领后提供税收/粮草/人口加成
## 单位靠近村庄一定时间后占领，被敌方夺取则易主
## P3：等级/人口/繁荣度/民心/税收/任命系统

const SpriteProjector = preload("res://scripts/core/SpriteProjector.gd")

@export var village_id: String = "village_0"
var village_owner: String = ""
var occupy_progress: float = 0.0
var occupier: String = ""
var income_tick: float = 0.0
var village_name: String = "村庄"
var tax_gold: float = 0.5
var tax_food: float = 0.3
var pop_bonus: int = 5
var _flag: MeshInstance3D = null
# 🏘️ 对标傲世三国：村庄有血量，可被武力攻打；打空即易主
var max_hp: float = 1500.0
var hp: float = 1500.0

# ============ P3：村庄等级/人口/繁荣度/民心 ============
var level: int = 1  # 1=村庄, 2=村镇, 3=城镇
var prosperity: float = 100.0  # 繁荣度：100→2级300→3级（多因素计算）
var popular_support: float = 50.0  # 民心：0-100
# 🔥 v4 人口大改：村庄初始1000，城池初始3000，无上限
var population: int = 1000  # 当前人口（村庄初始1000）
var is_city: bool = false  # true=城池（初始3000，是村庄3倍以上）
var peasant_count: int = 0  # 当前民夫数
var max_peasants: int = 10  # 民夫上限：10/20/30
var appointed_civil: Node = null  # 任命文臣
var appointed_military: Node = null  # 任命武将
var _pop_timer: float = 0.0  # 人口增长计时
var _prosperity_timer: float = 0.0  # 繁荣度增长计时
var _month_timer: float = 0.0  # 🔥 v4 月度结算计时器（税收按月结算）
# 🔥 v4 税收相关（V2改：税率滑块0-100%，月度税收=人口×税率%）
var tax_rate_percent: float = 15.0  # V2：税率百分比（滑块0-100），默认15%
var tax_pop_penalty: bool = false  # V2：税率>40% 开始人口惩罚
# 🔥 v4 村镇 AI 策略
enum TownStrategy { DEFEND, ATTACK, PREPARE, PATROL }
var town_strategy: int = TownStrategy.DEFEND  # 默认防守
var _ai_timer: float = 0.0  # AI 决策计时
var garrison_soldiers: Array = []  # 村庄驻军（自动生成/消亡）

func get_faction() -> String:
	return village_owner

func _capture_conf() -> Dictionary:
	return DataLoader.combat.get("capture", {})

func get_hp_lock() -> float:
	return max_hp * float(_capture_conf().get("lock_ratio", 0.10))

func is_hp_locked() -> bool:
	return hp <= get_hp_lock() + 0.5

func take_damage(dmg: float, attacker: Node = null) -> void:
	# 🏛 血量锁 10%：锁血后不可攻击（2026-10-28 定稿），改由单位进入范围占领
	if is_hp_locked():
		return
	hp -= dmg
	var lock_line: float = get_hp_lock()
	if hp < lock_line:
		hp = lock_line
		EventBus.float_text.emit("🔒 村镇残破，需进入占领", global_position + Vector3(0, 3, 0), Color(0.9, 0.75, 0.2))
		return
	_damaged_recently = true
	_damage_idle_timer = 0.0

## 占领后缓慢回血（1%/s），只在易主后生效；被攻击时暂停
var _captured: bool = false
var _damaged_recently: bool = false
var _damage_idle_timer: float = 0.0

func _tick_capture_regen(delta: float) -> void:
	if not _captured or hp >= max_hp:
		return
	_damage_idle_timer += delta
	if _damage_idle_timer < 3.0:
		return
	hp = minf(max_hp, hp + max_hp * float(_capture_conf().get("regen_per_sec", 0.01)) * delta)

func _ready() -> void:
	GameManager.villages.append(self)
	_update_level_stats()
	_create_visual()

func _create_visual() -> void:
	var sprite: Sprite3D = Sprite3D.new()
	sprite.shaded = false
	var adef: Dictionary = DataLoader.get_asset_def("village", "village")
	if not adef.is_empty():
		var tex: Texture2D = DataLoader.get_sprite_texture("village", "village")
		if tex:
			sprite.texture = tex
		sprite.pixel_size = DataLoader.get_sprite_pixel_size("village", tex)
		var s: float = float(adef.get("scale", 1.8))
		sprite.scale = Vector3(s, s, s)
		# 与建筑/资源点同一套投影：村庄立绘也是等距俯视图（能看到农舍正立面和屋顶），
		# 用全向 billboard 会让整个院落像一块悬空的斜板。
		sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		var hb: float = DataLoader.get_sprite_anchor_y("village", "village", s)
		SpriteProjector.align(sprite, hb)
	add_child(sprite)
	_flag = MeshInstance3D.new()
	var fbox: BoxMesh = BoxMesh.new()
	fbox.size = Vector3(0.6, 1.2, 0.1)
	_flag.mesh = fbox
	_flag.position = Vector3(1.2, 1.8, 0)
	add_child(_flag)
	_update_flag()

func _update_flag() -> void:
	if _flag == null:
		return
	var fmat: StandardMaterial3D = StandardMaterial3D.new()
	if village_owner == "":
		fmat.albedo_color = Color(0.8, 0.8, 0.8)
	else:
		fmat.albedo_color = GameManager.factions[village_owner].color
	_flag.material_override = fmat

func _process(delta: float) -> void:
	if GameManager.paused or GameManager.game_over:
		return
	_check_occupiers(delta)
	_tick_capture_regen(delta)
	if village_owner != "" and village_owner in GameManager.factions:
		# 🔥 v4 月度结算（傲世三国每月约几分钟，这里统一 30 秒 = 1 月）
		_month_timer += delta
		if _month_timer >= 30.0:
			_month_timer = 0.0
			_apply_monthly_settlement()
		# 🔥 v4 村镇 AI 策略决策（每 10 秒一次）
		_ai_timer += delta
		if _ai_timer >= 10.0:
			_ai_timer = 0.0
			_execute_town_strategy()
		# 人口增长：无上限，基础 +1/30s，受税收惩罚/富饶度加成
		_pop_timer += delta
		if _pop_timer >= 30.0:
			_pop_timer = 0.0
			_grow_population()
		# 繁荣度增长：多因素计算（树木/矿洞/和平/任命）
		_prosperity_timer += delta
		if _prosperity_timer >= 60.0:
			_prosperity_timer = 0.0
			_grow_prosperity_v4()

# 🔥 v4 月度结算（V2改：税收=人口×税率%，滑块0-100）
func _apply_monthly_settlement() -> void:
	if village_owner not in GameManager.factions:
		return
	var state = GameManager.factions[village_owner]
	# 1) V2月度税收 = 人口 × (税率/100) × 民心% × 政务加成
	var tax_mult_official: float = 1.0 + GameManager.get_tax_bonus(village_owner)
	var tax_mult_popularity: float = popular_support / 100.0
	var monthly_tax: float = float(population) * (tax_rate_percent / 100.0) * tax_mult_popularity * tax_mult_official
	state.resources["gold"] += monthly_tax
	# 2) V2：税率>40% 人口惩罚
	tax_pop_penalty = tax_rate_percent > 40.0
	# 3) 文臣民心加成：+0.5/分 → 月度累计 +15/月
	if appointed_civil != null and is_instance_valid(appointed_civil):
		popular_support = min(100.0, popular_support + 15.0)
	# 4) 武将驻军士气加成（战斗时生效，月度保持）
	print("[Village] %s 月度结算: 人口=%d 税率=%.0f%% 税收=%.1f金 民心=%.0f 繁荣=%.0f" % [village_id, population, tax_rate_percent, monthly_tax, popular_support, prosperity])

func _check_occupiers(delta: float) -> void:
	var radius: float = float(_capture_conf().get("village_entry_radius", 3.5))
	var near_units: Array = []
	for u in GameManager.all_units:
		if is_instance_valid(u) and u.has_method("get_faction"):
			if global_position.distance_to(u.global_position) < radius:
				near_units.append(u)
	if near_units.is_empty():
		if occupy_progress > 0 and occupier != village_owner:
			occupy_progress = max(0.0, occupy_progress - 5.0 * delta)
		occupier = ""
		return
	var faction_counts: Dictionary = {}
	for u in near_units:
		var f: String = u.get_faction()
		faction_counts[f] = faction_counts.get(f, 0) + 1
	var best_faction: String = ""
	var best_count: int = 0
	for f in faction_counts.keys():
		if faction_counts[f] > best_count:
			best_count = faction_counts[f]
			best_faction = f
	if faction_counts.size() == 1:
		occupier = best_faction
		if occupier == village_owner:
			occupy_progress = 100.0
		elif village_owner == "" or is_hp_locked():
			# 🏛 中立空村可直接进驻；已归属敌方的村镇必须先打到 10% 锁血线
			var prev: float = occupy_progress
			occupy_progress = min(100.0, occupy_progress + 15.0 * delta)
			if int(prev / 25.0) < int(occupy_progress / 25.0):
				EventBus.float_text.emit("🏘 占领 %d%%" % int(occupy_progress), global_position + Vector3(0, 4.0, 0), Color(0.95, 0.85, 0.3))
			if occupy_progress >= 100.0:
				_capture(occupier)
		else:
			# 未打残（>10%）不能直接占领
			occupy_progress = max(0.0, occupy_progress - 5.0 * delta)
	else:
		occupier = ""

func _capture(new_owner: String) -> void:
	var old: String = village_owner
	village_owner = new_owner
	occupy_progress = 100.0
	# 🏛 易主瞬间恢复到 50% 血，之后 1%/s 缓慢回满（2026-10-28 定稿）
	_captured = true
	_damage_idle_timer = 0.0
	hp = max_hp * float(_capture_conf().get("restore_ratio", 0.50))
	_update_flag()
	if old != "" and old in GameManager.factions:
		GameManager.factions[old].population_cap -= pop_bonus
	if new_owner in GameManager.factions:
		GameManager.factions[new_owner].population_cap += pop_bonus
	EventBus.float_text.emit("%s 占领村庄!" % new_owner.to_upper(), global_position + Vector3(0, 4, 0), Color.YELLOW)
	print("[Village] %s 占领村庄 %s (原属 %s)" % [new_owner, village_id, old])
	# 🎖 占领村镇经验：参与单位平分 200 池，单人 ≤50（config/combat.json → capture_settlement）
	var cap: Dictionary = DataLoader.combat.get("experience", {}).get("capture_settlement", {})
	var participants: Array = GameManager.get_units_near(global_position, 15.0, new_owner)
	GameManager.grant_shared_xp(participants, float(cap.get("share_pool", 200.0)), float(cap.get("per_recipient_max", 50.0)))

# ============ P3：等级/人口/繁荣度/民心系统 ============

func _update_level_stats() -> void:
	"""🔥 v4 更新等级属性：无人口上限！只有民夫/驻军相关"""
	match level:
		1:
			village_name = "村庄"
			max_peasants = 10
		2:
			village_name = "村镇"
			max_peasants = 20
		3:
			village_name = "城镇"
			max_peasants = 30

func get_level() -> int:
	return level

# 💾 存档 / 读档
func serialize() -> Dictionary:
	return {
		"type": "village",
		"village_id": village_id,
		"pos": {"x": global_position.x, "y": global_position.y, "z": global_position.z},
		"owner": village_owner,
		"hp": hp,
		"max_hp": max_hp,
		"level": level,
		"prosperity": prosperity,
		"popular_support": popular_support,
		"population": population,
		"is_city": is_city,
		"peasant_count": peasant_count,
		"tax_rate_percent": tax_rate_percent,
		"tax_pop_penalty": tax_pop_penalty,
		"town_strategy": town_strategy,
	}

func apply_state(d: Dictionary) -> void:
	# 归属直接赋值（不再走 _capture，避免人口上限重复累加；人口上限已由势力存档恢复）
	village_owner = str(d.get("owner", ""))
	hp = float(d.get("hp", hp))
	max_hp = float(d.get("max_hp", max_hp))
	level = int(d.get("level", 1))
	_update_level_stats()
	prosperity = float(d.get("prosperity", prosperity))
	popular_support = float(d.get("popular_support", popular_support))
	population = int(d.get("population", population))
	is_city = bool(d.get("is_city", false))
	peasant_count = int(d.get("peasant_count", 0))
	tax_rate_percent = float(d.get("tax_rate_percent", tax_rate_percent))
	tax_pop_penalty = bool(d.get("tax_pop_penalty", false))
	town_strategy = int(d.get("town_strategy", town_strategy))
	_update_flag()

# 🔥 v4 重写：无上限人口增长，基础+1/30s，受税收惩罚/民心加成
func _grow_population() -> void:
	if village_owner == "":
		return
	if GameManager.get_resource(village_owner, "food") <= 0:
		return
	var growth: float = 1.0  # 基础 +1
	# 📖 科技：村庄人口增长 +50%
	growth *= GameManager.get_tech_bonus(village_owner, "village_pop_growth")
	# 税收惩罚：>40% 时减少 50%
	if tax_pop_penalty:
		growth *= 0.5
	# 民心加成：民心80+ 额外+50%
	if popular_support >= 80.0:
		growth *= 1.5
	# 武将任命加成 +20%
	if appointed_military != null and is_instance_valid(appointed_military):
		growth *= 1.2
	# 🔥 v4 无上限增长
	population += max(1, int(growth))

# 🔥 v4 多因素繁荣度计算
# 5-10 分钟升2级（300繁荣），10-20分钟升3级（600繁荣）
# 每分钟基础 +1，额外加成因素：
#   - 任命文臣：+1/分
#   - 附近有矿洞：每个 +0.5/分（最多+2）
#   - 附近有树林：每片 +0.3/分（最多+1.5）
#   - 附近有河流：+0.5/分
#   - 长期和平（最近3分钟无战争）：+1/分
func _grow_prosperity_v4() -> void:
	var growth: float = 1.0  # 基础
	if appointed_civil != null and is_instance_valid(appointed_civil):
		growth += 1.0
	# 附近资源（简化：检查 GameManager.villages 数量或直接硬编码）
	# 🔧 占位：后续加资源检测
	var mine_bonus: float = 0.0  # 附近矿洞
	var tree_bonus: float = 0.0  # 附近树林
	var river_bonus: float = 0.0  # 附近河流
	growth += mine_bonus + tree_bonus + river_bonus
	# 和平加成（简化：无战事则+1）
	var peace_bonus: float = 1.0  # 🔧 后续接 AI 战事统计
	growth += peace_bonus
	prosperity += growth
	# 升级判定
	if prosperity >= 300 and level == 1:
		level = 2
		_update_level_stats()
		EventBus.float_text.emit("🏘️ 升级为村镇！", global_position + Vector3(0, 4, 0), Color.GOLD)
	elif prosperity >= 600 and level == 2:
		level = 3
		_update_level_stats()
		EventBus.float_text.emit("🏘️ 升级为城镇！", global_position + Vector3(0, 4, 0), Color.GOLD)

func appoint_civil(general: Node) -> bool:
	"""任命文臣：民心+0.5/分、产出+10%×内政/100"""
	if appointed_civil != null:
		return false
	appointed_civil = general
	return true

func appoint_military(general: Node) -> bool:
	"""任命武将：驻军士气不掉、防御+15%×武力/100"""
	if appointed_military != null:
		return false
	appointed_military = general
	return true

# 🔥 v4 村镇 AI 策略执行
func _execute_town_strategy() -> void:
	# 只有 level 2+ 才有自动驻军
	# V2：自动驻军数量（无硬上限，按等级动态）
	var target_count: int = 0
	match level:
		1: target_count = 0  # 1级村庄无自动驻军（可手动驻扎）
		2: target_count = 10  # 2级村镇 10 基础兵
		3: target_count = 20  # 3级城镇 20 高级兵
	# 清理死亡驻军
	var alive: Array = []
	for s in garrison_soldiers:
		if is_instance_valid(s) and s.hp > 0:
			alive.append(s)
	garrison_soldiers = alive
	# 自动补充驻军（简化：每 10s 检查）
	if garrison_soldiers.size() < target_count and level >= 2:
		var unit_id: String = "sword" if level < 3 else "heavy_sword"
		var udef: Dictionary = DataLoader.get_unit_def(unit_id)
		if not udef.is_empty():
			var unit_scene: PackedScene = load("res://scenes/Unit.tscn")
			if unit_scene:
				var unit = unit_scene.instantiate()
				unit.unit_id = unit_id
				unit.faction = village_owner
				get_tree().root.add_child(unit)
				unit.global_position = global_position + Vector3(randf_range(-3, 3), 1, randf_range(-3, 3))
				unit.behavior_mode = 1
				garrison_soldiers.append(unit)
				GameManager.factions[village_owner].units.append(unit)
				print("[Village] %s 自动驻军 +1 (共%d/%d)" % [village_id, garrison_soldiers.size(), target_count])
	# 根据策略行为
	match town_strategy:
		TownStrategy.DEFEND:
			# 所有驻军守在村庄附近
			for s in garrison_soldiers:
				if s.is_instance_valid(s):
					s.behavior_mode = 1
		TownStrategy.ATTACK:
			# 搜附近15格内敌军并主动进攻
			for s in garrison_soldiers:
				if s.is_instance_valid(s):
					s.behavior_mode = 0
					s.behavior_attack_range = 15.0
		TownStrategy.PREPARE:
			# 备战：不进攻但保持警戒，+经验/训练（简化：给驻军加 exp）
			for s in garrison_soldiers:
				if s.is_instance_valid(s):
					s.behavior_mode = 1
					if s.has_method("add_exp"):
						s.add_exp(5.0)  # 每10秒+5经验
		TownStrategy.PATROL:
			# 巡逻：在村庄周围5格内移动
			for s in garrison_soldiers:
				if s.is_instance_valid(s):
					s.behavior_mode = 0
					s.behavior_attack_range = 8.0
					if s.state == 0 and randf() < 0.3:
						var patrol_pos: Vector3 = global_position + Vector3(randf_range(-5, 5), 0, randf_range(-5, 5))
						s.command_move(patrol_pos)

# 🔥 v4 设定村镇策略（UI 调用）
func set_strategy(strategy: int) -> void:
	if strategy >= TownStrategy.DEFEND and strategy <= TownStrategy.PATROL:
		town_strategy = strategy
		var names: Dictionary = {
			TownStrategy.DEFEND: "🛡 防守",
			TownStrategy.ATTACK: "⚔ 攻击",
			TownStrategy.PREPARE: "📜 备战",
			TownStrategy.PATROL: "🏃 巡逻"
		}
		EventBus.float_text.emit("村镇策略: %s" % names[strategy], global_position + Vector3(0, 4, 0), Color.GOLD)

func on_peasant_died() -> void:
	"""民夫被杀：死1民心-10繁荣-20"""
	peasant_count = max(0, peasant_count - 1)
	popular_support = max(0.0, popular_support - 10.0)
	prosperity = max(0.0, prosperity - 20.0)

# ============ 运输队系统 ============

func send_transport(target_pos: Vector3, resources: Dictionary, peasants: int = 1) -> Node:
	"""发送运输队到城池/营帐/其他村"""
	if village_owner == "":
		return null
	var tconf: Dictionary = DataLoader.logistics.get("transport", {})
	var max_peas: int = int(tconf.get("max_peasants", 5))
	var cap_per: float = float(tconf.get("capacity_per_peasant", 50.0))
	peasants = clampi(peasants, 1, max_peas)
	if peasant_count < peasants:
		EventBus.float_text.emit("民夫不足（需 %d）" % peasants, global_position + Vector3(0, 3, 0), Color.RED)
		return null
	# 载重校验：超载直接拒绝，不扣资源/民夫
	var total: float = 0.0
	for k in resources.keys():
		total += float(resources[k])
	if total > float(peasants) * cap_per:
		EventBus.float_text.emit("超载：%d 民夫最多运 %d" % [peasants, int(float(peasants) * cap_per)], global_position + Vector3(0, 3, 0), Color.RED)
		return null
	# 检查资源是否足够
	for k in resources.keys():
		if GameManager.get_resource(village_owner, k) < float(resources[k]):
			EventBus.float_text.emit("资源不足", global_position + Vector3(0, 3, 0), Color.RED)
			return null
	# 扣除资源
	for k in resources.keys():
		GameManager.add_resource(village_owner, k, -float(resources[k]))
	# 扣除民夫
	peasant_count -= peasants
	# 创建运输队
	var team_script: GDScript = load("res://scripts/entities/TransportTeam.gd") as GDScript
	var team: Node = team_script.new()
	team.team_id = "%s_transport_%d" % [village_id, randi()]
	team.faction = village_owner
	team.global_position = global_position + Vector3(0, 0, 2.0)
	if not team.setup_transport(self, target_pos, resources, peasants, village_owner):
		# 超载兜底：退回资源与民夫
		for k in resources.keys():
			GameManager.add_resource(village_owner, k, float(resources[k]))
		peasant_count += peasants
		team.free()
		return null
	GameManager.add_child(team)
	EventBus.float_text.emit("📦 运输队出发", global_position + Vector3(0, 3, 0), Color.YELLOW)
	print("[Village] %s 派出运输队，押运: %s，民夫: %d" % [village_id, str(resources), peasants])
	return team

# ============ 中立/盟友村庄买体力 ============

func can_buy_stamina(unit) -> bool:
	"""中立或盟友村庄可向单位出售体力"""
	if unit == null or not is_instance_valid(unit):
		return false
	# 中立村庄（无归属）或盟友村庄（归属该势力）
	if village_owner == "" or village_owner == unit.faction:
		return true
	return false

func buy_stamina(unit) -> bool:
	"""0.5金/兵，+5/s 体力恢复，不补士气"""
	if not can_buy_stamina(unit):
		return false
	if GameManager.get_resource(unit.faction, "gold") < 0.5:
		return false
	GameManager.add_resource(unit.faction, "gold", -0.5)
	# 给单位一个临时体力恢复 buff（+5/s，持续10秒）
	if "stamina_buffs" in unit:
		unit.stamina_buffs.append({"rate": 5.0, "remain": 10.0})
	return true
