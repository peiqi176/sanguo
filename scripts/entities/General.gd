extends "res://scripts/entities/Unit.gd"
class_name General
## General — 武将类（继承Unit）
## 四层技能：基础(5个全武将)/被动/主动/名将特殊主动

@export var general_id: String = "guanyu"

var general_def: Dictionary = {}

# 🎯 设计 v3 新增：武将四维属性（武力/智谋/统御/内政）
# stats / level 由基类 Unit 声明，此处直接复用（避免与父类重名）
var general_class: String = "warrior"  # 猛将/防御/进攻/谋臣/异人

# 等级 + 天赋点（1-9级，每级1天赋点共9点）；level 继承自 Unit
var xp: float = 0.0
var talent_points: int = 0

# 🩸 血量复利成长模型（Lv1 → Lv9，每级 × hp_growth_rate ≈ 1.17）
var hp_lv1_base: float = 500.0
var hp_lv9_base: float = 2000.0
var hp_growth_rate: float = 1.17

# 🎯 设计 v3 新增：通用技能系统（最多3个，每3级满级）
var equipped_skills: Array = []        # [{skill_id, level}, ...]  通用+武将技混合
var max_skills: int = 3
var max_skill_level: int = 3
var skill_cooldowns: Dictionary = {}   # skill_id -> remain_seconds
var mp: float = 80.0
var max_mp: float = 100.0
var mp_regen_timer: float = 0.0

# 🎯 设计 v3 新增：单挑系统
var solo_duel_enabled: bool = false
var is_in_solo_duel: bool = false

# 🎯 设计 v3 新增：复活倒计时
var grace_period_seconds: float = -1.0  # -1=活着，>=0=重伤倒计时

# 保留旧字段兼容
var basic_skills: Array = []
var active_skill: Dictionary = {}
var ultimate_skill: Dictionary = {}
var passive_skills: Array = []
var is_legend: bool = false
var self_speed_buffs: Array = []

func _ready() -> void:
	is_general = true
	super._ready()
	general_def = DataLoader.get_general_def(general_id)
	if not general_def.is_empty():
		_init_general()
	# 🐎 武将默认骑马（三国武将皆乘马）：无论 general_def 是否存在都尝试
	# 用 call_deferred 确保节点完全进入场景树后再 add_child 马 mesh
	call_deferred("_auto_mount_if_possible")

func _auto_mount_if_possible() -> void:
	if not is_inside_tree():
		return
	if GameManager.get_resource(faction, "horse") >= 1.0 and has_method("command_mount"):
		command_mount()

func _init_general() -> void:
	# 🎯 设计 v3：优先从新结构读取四维 stats
	var v3_def: Dictionary = general_def.get("base", {})
	if not v3_def.is_empty():
		# 新版 generals.json 结构
		stats["might"] = float(v3_def.get("might", 70.0))
		stats["intelligence"] = float(v3_def.get("intelligence", 60.0))
		stats["command"] = float(v3_def.get("command", 60.0))
		stats["politics"] = float(v3_def.get("politics", 55.0))
		general_class = general_def.get("class", general_class)
		# HP/ATK/DEF 从 general_class + might 推
		var cls_mult: Dictionary = {
			"warrior": {"hp_mult": 1.15, "atk_mult": 1.15, "def_mult": 1.0},
			"defense": {"hp_mult": 1.30, "atk_mult": 0.90, "def_mult": 1.30},
			"assault": {"hp_mult": 1.05, "atk_mult": 1.20, "def_mult": 0.90},
			"strategist": {"hp_mult": 0.85, "atk_mult": 0.75, "def_mult": 0.75},
			"trickster": {"hp_mult": 1.00, "atk_mult": 1.05, "def_mult": 0.95}
		}
		var cm: Dictionary = cls_mult.get(general_class, cls_mult["warrior"])
		# 🩸 血量改为「Lv1 基础 → Lv9 上限」的复利模型（2026-10-27 定稿）
		#   名将读 generals.json → hp_lv1 / hp_lv9；没有则按 promoted_hp 兜底
		var prom: Dictionary = DataLoader.generals.get("promoted_hp", {})
		var cls_pm: Dictionary = prom.get("class_mult", {})
		var p_m: float = float(cls_pm.get(general_class, 1.0))
		hp_lv1_base = float(general_def.get("hp_lv1", float(prom.get("lv1_base", 500.0)) * p_m))
		hp_lv9_base = float(general_def.get("hp_lv9", float(prom.get("lv9_base", 2000.0)) * p_m))
		hp_growth_rate = pow(hp_lv9_base / maxf(hp_lv1_base, 1.0), 1.0 / 8.0)
		max_hp = hp_lv1_base
		atk = 25.0 * float(cm.get("atk_mult", 1.0)) * (1.0 + (stats["might"] - 70.0) * 0.005)
		defense = 10.0 * float(cm.get("def_mult", 1.0))
		move_speed = 2.6 + (stats["might"] - 70.0) * 0.005 + (0.4 if general_class == "assault" else 0.0)
		max_mp = general_def.get("base_mp", 80) + int(stats["intelligence"] * 0.3)
		# 🧪 特殊科技：浴血奋战（武将攻击+15%，HP+15%）
		var elite_atk: float = GameManager.get_elite_tech_bonus(faction, "general_attack_mult")
		var elite_hp: float = GameManager.get_elite_tech_bonus(faction, "general_hp_mult")
		atk *= elite_atk
		max_hp *= elite_hp
	else:
		# 兼容旧版结构
		max_hp = general_def.get("hp", 350)
		atk = general_def.get("atk", 28)
		defense = general_def.get("def", 10)
		move_speed = general_def.get("speed", 3.0)
		max_mp = 100
	# ⚔ 攻击范围走 config/attack_ranges.json（by_general > by_class > default）
	range = DataLoader.get_general_attack_range(general_id, general_class)
	stats["might"] = float(general_def.get("might", 70))
	stats["intelligence"] = float(general_def.get("intelligence", 60))
	stats["command"] = float(general_def.get("command", 60))
	stats["politics"] = float(general_def.get("politics", 55))
	# 📖 将领科技：名望（全属性 +）+ 点将台（基础属性 +）
	var attr_mult: float = 1.0 + GameManager.get_tech_sum(faction, "general_base_attr") + GameManager.get_tech_sum(faction, "all_general_attr")
	if attr_mult > 1.0:
		for k in stats.keys():
			stats[k] = float(stats[k]) * attr_mult
	hp = max_hp
	mp = max_mp
	morale = general_def.get("morale", 90)
	is_legend = general_def.get("rarity", "epic") == "legend"
	passive_skills = general_def.get("passive", [])
	active_skill = general_def.get("active", {})
	ultimate_skill = general_def.get("ultimate", {})
	# 🎯 P1-23 名将自带技能进技能栏（level 1）
	var own_skills: Array = general_def.get("skills", [])
	for sid in own_skills:
		if get_skill_level(str(sid)) == 0:
			equipped_skills.append({"skill_id": str(sid), "level": 1})
	_apply_passives()
	solo_duel_enabled = GameManager.solo_duel_enabled  # 默认跟随游戏设置
	# 初始化技能CD
	for skill_id in basic_skills:
		skill_cooldowns[skill_id] = 0.0
	skill_cooldowns["active"] = 0.0
	skill_cooldowns["ultimate"] = 0.0
	# 注册到 GameManager
	if GameManager.all_generals == null:
		GameManager.all_generals = []
	GameManager.all_generals.append(self)
	print("[General] ⚔ %s Lv%d (类型:%s 武力%.0f 智%.0f 统%.0f 内%.0f)" % [
		name, level, general_class, stats["might"], stats["intelligence"], stats["command"], stats["politics"]])
	# 🐎 自动骑马已移至 _ready 的 call_deferred("_auto_mount_if_possible")，确保所有武将（含不在 generals.json 的）都能骑马

func _process(delta: float) -> void:
	super._process(delta)
	# 血量缓慢恢复（每秒0.5%上限）
	if hp < max_hp and hp > 0.0:
		hp = min(max_hp, hp + max_hp * 0.005 * delta)
	# 酒：恢复法力和士气（法力低于30%时自动饮用）
	if mp < max_mp * 0.3 and GameManager.get_resource(faction, "wine") >= 1.0:
		GameManager.add_resource(faction, "wine", -1.0)
		mp = min(max_mp, mp + 30.0)
		morale = min(100.0, morale + 10.0)
	# MP恢复（分档：野外+1/s、城池+3/s、营帐+2/s、村镇+2/s、辎重车+1.5/s）
	_tick_mp_regen(delta)
	# 技能CD
	for key in skill_cooldowns.keys():
		skill_cooldowns[key] = max(0.0, skill_cooldowns[key] - delta)
	# 自我加速 buff 时长回收
	var k: int = 0
	while k < self_speed_buffs.size():
		self_speed_buffs[k]["remain"] -= delta
		if self_speed_buffs[k]["remain"] <= 0.0:
			self_speed_buffs.remove_at(k)
		else:
			k += 1
	# V2献策系统：随机触发 + 60s冷却
	_tick_v2_counsel(delta)

# ============ 武将法力分档恢复（对标傲世三国） ============

var _mp_wine_timer: float = 0.0  # 加速档耗酒计时（每5秒）

func _tick_mp_regen(delta: float) -> void:
	"""MP恢复分档：野外+1/s、城池+3/s、营帐+2/s、村镇+2/s、辎重车+1.5/s；多源取最高档；加速档需酒"""
	var regen_rate: float = 1.0  # 默认野外
	var best_priority: int = 0    # 档位优先级：城池3 > 营帐/村镇2 > 辎重车1.5 > 野外1
	
	# 1. 城池补给区
	var gov: Node = _find_government_building(faction)
	if gov != null and is_instance_valid(gov):
		var city_radius: float = _calc_city_radius(faction)
		var dist: float = global_position.distance_to(gov.global_position)
		if dist <= city_radius + 20.0:
			regen_rate = 3.0
			best_priority = 3
	
	# 2. 营帐/村镇/辎重车（取更高档）
	if best_priority < 3:
		# 营帐（SupplyCart 扎营状态）
		for u in GameManager.all_units:
			if not is_instance_valid(u) or u == self:
				continue
			if u.has_method("is_camped") and u.faction == faction and u.is_camped():  # duck-type SupplyCart
				var d: float = global_position.distance_to(u.global_position)
				if d <= 12.0 and best_priority < 2:
					regen_rate = 2.0
					best_priority = 2
					break
				var d2: float = global_position.distance_to(u.global_position)
				if d2 <= u.aura_radius and best_priority < 1:
					regen_rate = 1.5
					best_priority = 1
					break
		
		# 村庄（10/12/14格）
		for v in GameManager.villages:
			if not is_instance_valid(v):
				continue
			if v.village_owner != faction:
				continue
			var v_radius: float = 10.0
			if v.has_method("get_level"):
				var lvl: int = v.get_level()
				if lvl == 2:
					v_radius = 12.0
				elif lvl >= 3:
					v_radius = 14.0
			var d3: float = global_position.distance_to(v.global_position)
			if d3 <= v_radius and best_priority < 2:
				regen_rate = 2.0
				best_priority = 2
				break
	
	# 加速档（>1.0/s）需要酒，每5秒每武将耗1酒
	if regen_rate > 1.0:
		_mp_wine_timer += delta
		if _mp_wine_timer >= 5.0:
			_mp_wine_timer = 0.0
			if GameManager.get_resource(faction, "wine") >= 1.0:
				GameManager.add_resource(faction, "wine", -1.0)
			else:
				# 无酒，回落到野外+1/s
				regen_rate = 1.0
	
	mp = min(max_mp, mp + regen_rate * delta)

func cast_basic_skill(skill_id: String, target_pos: Vector3 = Vector3.ZERO, target: Node = null) -> bool:
	if not basic_skills.has(skill_id):
		return false
	var skill_def: Dictionary = DataLoader.generals.get("basic_skills", {}).get(skill_id, {})
	if skill_cooldowns[skill_id] > 0:
		return false
	if mp < skill_def.get("mp_cost", 0):
		return false
	mp -= skill_def.get("mp_cost", 0)
	skill_cooldowns[skill_id] = skill_def.get("cd", 20)
	_apply_skill_effect(skill_def, target_pos, target)
	return true

func cast_active_skill(target_pos: Vector3 = Vector3.ZERO, target: Node = null) -> bool:
	if active_skill.is_empty():
		return false
	if skill_cooldowns["active"] > 0:
		return false
	if mp < active_skill.get("mp_cost", 0):
		return false
	mp -= active_skill.get("mp_cost", 0)
	skill_cooldowns["active"] = active_skill.get("cd", 20)
	_apply_skill_effect(active_skill, target_pos, target)
	return true

func cast_ultimate(target_pos: Vector3 = Vector3.ZERO, target: Node = null) -> bool:
	if ultimate_skill.is_empty():
		return false
	if skill_cooldowns["ultimate"] > 0:
		return false
	if mp < ultimate_skill.get("mp_cost", 0):
		return false
	mp -= ultimate_skill.get("mp_cost", 0)
	skill_cooldowns["ultimate"] = ultimate_skill.get("cd", 60)
	_apply_skill_effect(ultimate_skill, target_pos, target)
	return true

func _apply_skill_effect(skill: Dictionary, target_pos: Vector3, target: Node) -> void:
	var skill_type: String = skill.get("type", "")
	var visual_pos: Vector3 = target_pos if target_pos != Vector3.ZERO else global_position
	match skill_type:
		"buff_aura":
			_spawn_skill_vfx("aura_gold", global_position, skill.get("radius", 10))
			_apply_aura_buff(skill)
		"heal_single":
			if target and target.has_method("take_damage"):
				var heal: float = target.max_hp * skill.get("heal_pct", 0.2)
				target.hp = min(target.max_hp, target.hp + heal)
				_spawn_skill_vfx("heal", target.global_position, 2)
		"buff_self":
			var duration: float = skill.get("duration", 8)
			self_speed_buffs.append({"mult": 1.0 + skill.get("speed_buff", 0), "remain": duration})
			_spawn_skill_vfx("aura_gold", global_position, 3)
		"damage":
			if target:
				target.take_damage(skill.get("damage", 30), self)
				_spawn_skill_vfx("explosion", target.global_position, 2)
		"charge_damage":
			if target:
				target.take_damage(skill.get("damage", 50), self)
				_spawn_skill_vfx("explosion", target.global_position, 3)
		"fear_aura":
			_spawn_skill_vfx("explosion_red", visual_pos, skill.get("radius", 6))
			_apply_aoe_damage(skill, target_pos)
		"heal_aura":
			_spawn_skill_vfx("aura_green", global_position, skill.get("radius", 10))
			_apply_aoe_heal(skill)
		_:
			print("[General] 未实现技能类型: %s" % skill_type)
	EventBus.float_text.emit(skill.get("name", "技能"), global_position + Vector3(0, 3, 0), Color.GOLD)

# ============ 技能 VFX ============
func _spawn_skill_vfx(vfx_type: String, pos: Vector3, radius: float) -> void:
	"""生成一个短暂的技能视觉特效（0.6-1.2秒后自动销毁）"""
	var vfx_root: Node3D = Node3D.new()
	vfx_root.position = pos  # 尚未入树，global_position 会报 !is_inside_tree
	vfx_root.position.y = max(vfx_root.position.y, 0.5)  # 别埋进土里
	
	var color: Color = Color.WHITE
	var life: float = 0.8
	var mesh_size: Vector3 = Vector3(radius * 2.0, 0.1, radius * 2.0)
	var ring_size: float = radius
	
	match vfx_type:
		"aura_gold":
			color = Color(1.0, 0.85, 0.3, 0.9); life = 1.2
		"aura_green":
			color = Color(0.3, 1.0, 0.4, 0.9); life = 1.2
		"explosion":
			color = Color(1.0, 0.6, 0.2, 0.95); life = 0.7
		"explosion_red":
			color = Color(1.0, 0.25, 0.2, 0.95); life = 0.7
		"heal":
			color = Color(0.3, 1.0, 0.5, 0.9); life = 0.6
		_:
			color = Color(1.0, 1.0, 1.0, 0.9); life = 0.8
	
	# 光圈（扁平圆盘）
	var disk: MeshInstance3D = MeshInstance3D.new()
	var mesh: Mesh = CylinderMesh.new()
	(mesh as CylinderMesh).top_radius = radius
	(mesh as CylinderMesh).bottom_radius = radius
	(mesh as CylinderMesh).height = 0.15
	disk.mesh = mesh
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.5
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.alpha_scissor_threshold = 0.1
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	disk.material_override = mat
	disk.rotation.x = deg_to_rad(90)
	disk.position.y = 0.1
	vfx_root.add_child(disk)
	
	# 外圈光环（透明细线）
	var ring_mesh: TorusMesh = TorusMesh.new()
	ring_mesh.inner_radius = radius * 0.92
	ring_mesh.outer_radius = radius
	ring_mesh.ring_segments = 48
	var ring: MeshInstance3D = MeshInstance3D.new()
	ring.mesh = ring_mesh
	var ring_mat: StandardMaterial3D = StandardMaterial3D.new()
	ring_mat.albedo_color = Color(color.r, color.g, color.b, 1.0)
	ring_mat.emission_enabled = true
	ring_mat.emission = color
	ring_mat.emission_energy_multiplier = 3.0
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	ring.material_override = ring_mat
	ring.rotation.x = deg_to_rad(90)
	ring.position.y = 0.12
	vfx_root.add_child(ring)
	
	# 🏅 技能爆发粒子（CPUParticles3D 的属性直接挂在节点上，不用 ParticleProcessMaterial）
	var burst := CPUParticles3D.new()
	burst.amount = 20
	burst.lifetime = life * 0.9
	burst.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	burst.emission_sphere_radius = radius * 0.3
	burst.direction = Vector3(0, 1, 0)
	burst.spread = 85.0
	burst.gravity = Vector3(0, -1.5, 0)  # 轻微下坠
	burst.initial_velocity_min = radius * 1.2
	burst.initial_velocity_max = radius * 2.5
	burst.scale_amount_min = 0.15
	burst.scale_amount_max = 0.35
	burst.color = Color(color.r, color.g, color.b, 0.9)
	vfx_root.add_child(burst)
	
	# 注册到场景树（延迟加入，避免首帧 _ready 期间 root 正在构建子节点时报错）
	get_tree().root.add_child.call_deferred(vfx_root)
	
	# 动画：disk 放大 + fade out
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_interval(0)
	var tw2: Tween = get_tree().create_tween()
	tw2.tween_property(disk, "scale", Vector3(2.0, 2.0, 2.0), life)
	tw2.parallel().tween_property(mat, "albedo_color:a", 0.0, life)
	tw2.parallel().tween_property(mat, "emission_energy_multiplier", 0.0, life)
	var tw3: Tween = get_tree().create_tween()
	tw3.tween_property(ring, "scale", Vector3(2.5, 2.5, 2.5), life)
	tw3.parallel().tween_property(ring_mat, "albedo_color:a", 0.0, life)
	tw3.parallel().tween_property(ring_mat, "emission_energy_multiplier", 0.0, life)
	
	# 到期销毁
	get_tree().create_timer(life + 0.15).timeout.connect(func(): 
		if is_instance_valid(vfx_root): vfx_root.queue_free()
	)

func _apply_aura_buff(skill: Dictionary) -> void:
	var radius: float = skill.get("radius", 10)
	var atk_mult: float = 1.0 + skill.get("atk_buff", 0)
	var morale_amt: float = skill.get("morale_buff", 0)
	var duration: float = skill.get("duration", 10)
	for unit in GameManager.all_units:
		if not is_instance_valid(unit) or unit == self:
			continue
		if unit.get_faction() == faction:
			if global_position.distance_to(unit.global_position) <= radius:
				# 带时长回收的临时增益：避免永久乘算导致攻击力指数膨胀
				if atk_mult != 1.0:
					unit.add_atk_buff(atk_mult, duration)
				if morale_amt != 0.0:
					unit.add_morale_buff(morale_amt, duration)

func _apply_aoe_damage(skill: Dictionary, center: Vector3) -> void:
	var radius: float = skill.get("radius", 6)
	var damage: float = skill.get("damage", 30)
	for unit in GameManager.all_units:
		if is_instance_valid(unit) and unit.get_faction() != faction:
			if center.distance_to(unit.global_position) <= radius:
				unit.take_damage(damage, self)
				unit.morale = max(0, unit.morale - skill.get("enemy_morale", 10))

func _apply_aoe_heal(skill: Dictionary) -> void:
	var radius: float = skill.get("radius", 10)
	var heal_pct: float = skill.get("heal_pct", 0.15)
	for unit in GameManager.all_units:
		if not is_instance_valid(unit):
			continue
		if unit.get_faction() == faction:
			if global_position.distance_to(unit.global_position) <= radius:
				unit.hp = min(unit.max_hp, unit.hp + unit.max_hp * heal_pct)

# 自我加速 buff 的临时乘算（带时长回收，覆盖父类）
func get_effective_speed() -> float:
	var mult: float = 1.0
	for b in self_speed_buffs:
		mult *= b["mult"]
	return move_speed * formation_speed_mod * mult * _speed_buff_mult

func get_passive_effects() -> Dictionary:
	# 返回带兵被动加成
	var effects: Dictionary = {}
	var pool: Dictionary = DataLoader.generals.get("passive_pool", {})
	for passive_id in passive_skills:
		if pool.has(passive_id):
			var effect: Dictionary = pool[passive_id].get("effect", {})
			for key in effect.keys():
				effects[key] = effects.get(key, 0) + effect[key]
	return effects

func _apply_passives() -> void:
	"""🎯 P1-23 把 passive_pool 的效果直接乘到自身数值上"""
	var e: Dictionary = get_passive_effects()
	if e.is_empty():
		return
	max_hp *= 1.0 + float(e.get("hp_mult", 0.0))
	atk *= 1.0 + float(e.get("atk_mult", 0.0))
	defense *= 1.0 + float(e.get("def_mult", 0.0))
	move_speed *= 1.0 + float(e.get("speed_mult", 0.0))
	atk_speed *= 1.0 + float(e.get("atk_speed_mult", 0.0))
	max_mp += float(e.get("mp_add", 0.0))
	morale = minf(100.0, morale + float(e.get("morale_add", 0.0)))
	hp = max_hp
	mp = max_mp

# ======================================================================
# 🎯 设计 v3 新增：等级 + 经验 + 天赋点系统
# ======================================================================

func add_xp(amount: float) -> void:
	xp += amount
	var curve_cfg: Dictionary = DataLoader.generals.get("level_curve", {})
	var curve: Array = curve_cfg.get("xp_per_level", [])
	var max_lv: int = int(curve_cfg.get("max_level", 9))
	var gain: Dictionary = curve_cfg.get("per_level_gain", {})
	var gr: Dictionary = curve_cfg.get("per_level_growth", {})
	while level < max_lv and level < curve.size() and xp >= curve[level]:
		xp -= curve[level]
		level += 1
		talent_points += 1
		# 📖 每级四维成长（读 config/generals.json → level_curve.per_level_gain）
		stats["might"] += float(gain.get("might", 2.0))
		stats["intelligence"] += float(gain.get("intelligence", 1.5))
		stats["command"] += float(gain.get("command", 1.5))
		stats["politics"] += float(gain.get("politics", 1.0))
		# 📖 每级数值成长（读 per_level_growth）：HP 复利 ×1.17（Lv1 500+ → Lv9 2000+），MP 线性 + 攻/防/攻速乘算
		var prev_max: float = max_hp
		max_hp = hp_lv1_base * pow(hp_growth_rate, float(level - 1))
		if max_hp <= prev_max:
			max_hp = prev_max * float(gr.get("hp_growth_rate", 1.17))
		if hp_growth_rate <= 1.0 and gr.has("max_hp"):
			max_hp = prev_max + float(gr.get("max_hp", 20.0))
		max_mp += float(gr.get("max_mp", 8.0))
		atk *= float(gr.get("atk_mult", 1.04))
		defense *= float(gr.get("def_mult", 1.04))
		atk_speed *= float(gr.get("atk_speed_mult", 1.02))
		hp = minf(max_hp, hp + max_hp * float(gr.get("hp_recover_pct", 0.30)))
		stamina = 100.0
		morale = 100.0
		print("[General] %s 升级到 Lv%d！天赋点+1（共%d） HP上限 %.0f→%.0f  MP+%d" % [
			name, level, talent_points, prev_max, max_hp, int(gr.get("max_mp", 8))])
		EventBus.float_text.emit("⬆ Lv%d!" % level, global_position + Vector3(0, 3, 0), Color.YELLOW)
		if level >= max_lv:
			print("[General] 🎉 %s 达到满级%d级！体力自动恢复（傲世特色）" % [name, max_lv])

func upgrade_skill(skill_id: String) -> bool:
	"""消耗1天赋点给技能升1级（最多3级）"""
	if talent_points <= 0:
		return false
	for sk in equipped_skills:
		if sk.get("skill_id", "") == skill_id:
			if int(sk.get("level", 1)) >= max_skill_level:
				return false
			sk["level"] = int(sk.get("level", 1)) + 1
			talent_points -= 1
			return true
	if equipped_skills.size() >= max_skills:
		return false
	equipped_skills.append({"skill_id": skill_id, "level": 1})
	talent_points -= 1
	return true

func get_skill_level(skill_id: String) -> int:
	for sk in equipped_skills:
		if sk.get("skill_id", "") == skill_id:
			return int(sk.get("level", 1))
	return 0

# ======================================================================
# 🎯 设计 v3 新增：MP 恢复 + CD 处理
# ======================================================================

func _process_v3_skill_system(delta: float) -> void:
	# 脱离战斗时 MP 恢复
	if is_in_combat():
		mp_regen_timer = 0.0
	else:
		mp_regen_timer += delta
		if mp_regen_timer >= 1.0:
			mp = min(max_mp, mp + 5.0)
			mp_regen_timer = 0.0
	# CD 倒计时
	for sid in skill_cooldowns.keys():
		skill_cooldowns[sid] = max(0.0, skill_cooldowns[sid] - delta)

func cast_common_skill(skill_id: String, level: int, target: Node = null) -> bool:
	"""基础技能（无CD，耗MP）。效果读 config/generals.json → common_skills"""
	var pool: Array = DataLoader.generals.get("common_skills", {}).get("skills", [])
	var skill: Dictionary = {}
	for s in pool:
		if s.get("id", "") == skill_id:
			skill = s
			break
	if skill.is_empty():
		return false
	var lv: int = clampi(level, 1, max_skill_level)
	var lv_cfg: Dictionary = _skill_level_cfg(skill, lv)
	var mp_cost: float = float(skill.get("mp_cost", 0)) * lv
	if skill.has("mp_cost_per_sec"):
		mp_cost = float(skill.get("mp_cost_per_sec", 25)) * float(lv_cfg.get("duration", 4))
	if mp < mp_cost:
		return false
	mp -= mp_cost
	_apply_common_skill(skill, lv, lv_cfg, target)
	return true

func cast_unique_skill(skill_id: String, level: int, target: Node = null) -> bool:
	"""武将技（有CD，不耗MP）。效果读 config/generals.json → unique_skills"""
	if skill_cooldowns.get(skill_id, 0.0) > 0.0:
		return false
	var pool: Array = DataLoader.generals.get("unique_skills", {}).get("skills", [])
	var skill: Dictionary = {}
	for s in pool:
		if s.get("id", "") == skill_id:
			skill = s
			break
	if skill.is_empty():
		return false
	var lv: int = clampi(level, 1, max_skill_level)
	var lv_cfg: Dictionary = _skill_level_cfg(skill, lv)
	var cd: float = float(skill.get("cooldown", 120))
	if cd > 0:
		skill_cooldowns[skill_id] = cd
	_apply_unique_skill(skill, lv_cfg, target)
	print("[General] ⚡ %s 释放武将技 %s Lv%d (CD %.0fs)" % [name, skill.get("name", ""), lv, cd])
	return true

func _skill_level_cfg(skill: Dictionary, lv: int) -> Dictionary:
	var arr: Array = skill.get("levels", [])
	if arr.is_empty():
		return {}
	return arr[clampi(lv - 1, 0, arr.size() - 1)]

# ===== 技能目标查询 =====
func _allies_near(radius: float, limit: int = 0) -> Array:
	var out: Array = []
	for u in GameManager.all_units:
		if not is_instance_valid(u) or u == self or not u.has_method("get_faction"):
			continue
		if u.get_faction() != faction or u.hp <= 0.0:
			continue
		if global_position.distance_to(u.global_position) <= radius:
			out.append(u)
	out.sort_custom(func(a, b): return global_position.distance_to(a.global_position) < global_position.distance_to(b.global_position))
	if limit > 0 and out.size() > limit:
		out = out.slice(0, limit)
	return out

func _enemies_near(radius: float) -> Array:
	var out: Array = []
	for u in GameManager.all_units:
		if not is_instance_valid(u) or not u.has_method("get_faction"):
			continue
		if u.get_faction() == faction or u.hp <= 0.0:
			continue
		if global_position.distance_to(u.global_position) <= radius:
			out.append(u)
	return out

## 通用技能效果（11 个基础技全覆盖）；lv_idx = 1/2/3，同时决定受益人数（含自身）
func _apply_common_skill(skill: Dictionary, lv_idx: int, lv: Dictionary, target: Node) -> void:
	var stype: String = str(skill.get("type", ""))
	var sname: String = str(skill.get("name", ""))
	var allies: Array = _allies_near(8.0, lv_idx)
	match stype:
		"buff":  # 养气：不掉体力
			var secs: float = float(lv.get("no_drain_seconds", 15.0))
			apply_no_drain(secs)
			for u in allies:
				if u.has_method("apply_no_drain"):
					u.apply_no_drain(secs)
			_spawn_skill_vfx("aura_gold", global_position, 3)
		"heal_stamina":
			var amt: float = float(lv.get("stamina_restore", 40.0))
			stamina = minf(100.0, stamina + amt)
			for u in allies:
				u.stamina = minf(100.0, u.stamina + amt)
			_spawn_skill_vfx("aura_green", global_position, 3)
		"heal_hp":
			var rate: float = float(lv.get("hp_per_sec", 30.0))
			var dur: float = float(lv.get("duration", 4.0))
			var tgt = target if (target != null and is_instance_valid(target)) else self
			if tgt.has_method("add_hp_regen"):
				tgt.add_hp_regen(rate, dur)
				_spawn_skill_vfx("heal", tgt.global_position, 2)
		"knockup":  # 开天：周围敌人击退+眩晕
			var stun: float = float(lv.get("stun_seconds", 1.5))
			var back: float = float(lv.get("knockup_grids", 1.0)) * GameManager.grid.cell_size
			for e in _enemies_near(2.5):
				if e.has_method("apply_stun"):
					e.apply_stun(stun)
					var dir: Vector3 = (e.global_position - global_position)
					dir.y = 0.0
					if dir.length() < 0.01:
						dir = Vector3(0, 0, 1)
					e.global_position += dir.normalized() * back
			_spawn_skill_vfx("explosion", global_position, 2.5)
		"buff_speed":
			var m: float = float(lv.get("speed_mult", 1.3))
			var d: float = float(lv.get("duration", 6.0))
			add_speed_buff(m, d)
			for u in allies:
				if u.has_method("add_speed_buff"):
					u.add_speed_buff(m, d)
			_spawn_skill_vfx("aura_gold", global_position, 3)
		"buff_attack":
			var am: float = float(lv.get("attack_mult", 1.15))
			var ad: float = float(lv.get("duration", 8.0))
			add_atk_buff(am, ad)
			for u in allies:
				if u.has_method("add_atk_buff"):
					u.add_atk_buff(am, ad)
			_spawn_skill_vfx("aura_gold", global_position, 3)
		"armor_pierce":
			add_armor_pen_buff(float(lv.get("pierce_percent", 0.2)), float(lv.get("duration", 8.0)))
			_spawn_skill_vfx("explosion", global_position, 2)
		"freeze":
			var fe: Array = _enemies_near(4.0)
			if not fe.is_empty() and fe[0].has_method("apply_stun"):
				fe[0].apply_stun(float(lv.get("freeze_seconds", 1.5)))
				_spawn_skill_vfx("heal", fe[0].global_position, 2)
		"slow":
			var se: Array = _enemies_near(4.0)
			if not se.is_empty() and se[0].has_method("add_speed_buff"):
				se[0].add_speed_buff(float(lv.get("speed_mult", 0.6)), float(lv.get("duration", 4.0)))
				_spawn_skill_vfx("aura_green", se[0].global_position, 2)
		"buff_attack_speed":
			var asm: float = float(lv.get("atkspeed_mult", 1.25))
			var asd: float = float(lv.get("duration", 6.0))
			add_atk_speed_buff(asm, asd)
			for u in allies:
				if u.has_method("add_atk_speed_buff"):
					u.add_atk_speed_buff(asm, asd)
			_spawn_skill_vfx("aura_gold", global_position, 3)
		"morale":
			var ma: float = float(lv.get("morale_restore", 8.0))
			morale = minf(100.0, morale + ma)
			for u in allies:
				u.morale = minf(100.0, u.morale + ma)
			_spawn_skill_vfx("aura_gold", global_position, 3)
		_:
			print("[General] 未实现基础技能类型: %s" % stype)
	EventBus.float_text.emit(sname, global_position + Vector3(0, 3, 0), Color.GOLD)

## 名将技效果（10 个武将技全覆盖）
func _apply_unique_skill(skill: Dictionary, lv: Dictionary, target: Node) -> void:
	var stype: String = str(skill.get("type", ""))
	var sname: String = str(skill.get("name", ""))
	match stype:
		"passive_crit_bonus":
			pass  # 青龙偃月：被动，读取见 calc_crit_damage
		"aoe_damage_debuff":  # 水淹七军
			var dmg: float = float(lv.get("damage", 60.0))
			var slow: float = float(lv.get("slow_seconds", 3.0))
			for e in _enemies_near(5.0):
				e.take_damage(dmg, self)
				if e.has_method("add_speed_buff"):
					e.add_speed_buff(0.5, slow)
			_spawn_skill_vfx("aura_green", global_position, 5)
		"invuln":  # 长坂坡
			apply_invuln(float(lv.get("invuln_seconds", 3.0)))
			_spawn_skill_vfx("aura_gold", global_position, 3)
		"aura_buff":  # 八阵图
			var a: float = float(lv.get("ally_atk_add", 0.1))
			_atk_aura_buff(a, 20.0)
			_spawn_skill_vfx("aura_gold", global_position, 6)
		"mass_invuln":  # 空城计
			var secs: float = float(lv.get("invuln_seconds", 4.0))
			for u in _allies_near(10.0):
				if u.has_method("apply_invuln"):
					u.apply_invuln(secs)
			_spawn_skill_vfx("aura_gold", global_position, 8)
		"fog_pierce":  # 鹰视狼顾
			mark_enemies(float(lv.get("reveal_seconds", 6.0)))
		"mass_buff_fear":  # 号令天威
			_atk_aura_buff(float(lv.get("ally_atk_add", 0.15)), 15.0)
			var fear: float = float(lv.get("fear_seconds", 1.0))
			for e in _enemies_near(8.0):
				if e.has_method("apply_stun"):
					e.apply_stun(fear)
			_spawn_skill_vfx("explosion_red", global_position, 6)
		"aoe_dot":  # 赤壁：落点起火（复用 BurningGround）
			var dmg: float = float(lv.get("damage", 50.0))
			var pos: Vector3 = target.global_position if (target != null and is_instance_valid(target)) else global_position
			for e in _enemies_near(6.0):
				e.take_damage(dmg, self)
			var fire = load("res://scripts/entities/BurningGround.gd").new()
			get_parent().add_child(fire)
			fire.configure(pos, faction, self, {
				"duration": float(lv.get("duration", 3.0)),
				"radius": 4.0,
				"tick_interval": 0.5,
				"dps": float(lv.get("burn_per_sec", 15.0)),
			})
		"multi_hit":  # 方天画戟
			var tgt = target if (target != null and is_instance_valid(target) and target.has_method("take_damage")) else null
			if tgt == null:
				var es: Array = _enemies_near(2.5)
				tgt = es[0] if not es.is_empty() else null
			if tgt != null:
				var hits: int = int(lv.get("hits", 3))
				var mul: float = float(lv.get("multiplier_per_hit", 1.1))
				for i in range(hits):
					tgt.take_damage(get_effective_atk() * mul, self)
				_spawn_skill_vfx("explosion", tgt.global_position, 2)
		"mass_charge_stun":  # 威震逍遥津
			var spd: float = float(lv.get("ally_speed_add", 0.3))
			var stun_s: float = float(lv.get("stun_seconds", 2.0))
			for u in _allies_near(10.0):
				if u.has_method("add_speed_buff"):
					u.add_speed_buff(1.0 + spd, 10.0)
			for e in _enemies_near(8.0):
				if e.has_method("apply_stun"):
					e.apply_stun(stun_s)
			_spawn_skill_vfx("explosion_red", global_position, 6)
		_:
			print("[General] 未实现武将技类型: %s" % stype)
	EventBus.float_text.emit("⚡" + sname, global_position + Vector3(0, 3, 0), Color.GOLD)

func _atk_aura_buff(add: float, duration: float) -> void:
	add_atk_buff(1.0 + add, duration)
	for u in _allies_near(10.0):
		if u.has_method("add_atk_buff"):
			u.add_atk_buff(1.0 + add, duration)

# ======================================================================
# 🎯 设计 v3 新增：单挑系统（可开关）
# ======================================================================

func try_solo_duel_with(other) -> bool:
	"""
	V2单挑规则：
	- 伤害公式 = 和正常攻击完全一样（用 Unit.gd 伤害公式）
	- 开启单挑后，两人自动互打直到一方倒下
	- 其他人不会攻击单挑中的双方（is_in_solo_duel 标记）
	- 其他人也不会被单挑双方攻击（攻击时检查对方 is_in_solo_duel）
	"""
	if not GameManager.solo_duel_enabled:
		return false
	if not solo_duel_enabled or not other.solo_duel_enabled:
		return false
	if is_in_solo_duel or other.is_in_solo_duel:
		return false
	# 进入单挑
	is_in_solo_duel = true
	other.is_in_solo_duel = true
	print("[单挑] ⚔ %s vs %s 开始单挑！（伤害公式=正常）" % [name, other.name])
	EventBus.float_text.emit("⚔ 单挑！其他人观战", global_position + Vector3(0, 4, 0), Color.RED)
	# V2：伤害公式和正常攻击完全一样（走 Unit.gd 的 calc_damage）
	var dmg_to_other: float = GameManager.calc_damage(float(atk), atk_speed, other, false)
	var dmg_to_self: float = GameManager.calc_damage(float(other.atk), other.atk_speed, self, false)
	other.take_damage(dmg_to_other)
	take_damage(dmg_to_self)
	# 结算
	is_in_solo_duel = false
	other.is_in_solo_duel = false
	if hp <= 0.0:
		print("[单挑] 💀 %s 阵亡！" % name)
	elif other.hp <= 0.0:
		morale = min(100.0, morale + 15.0)  # 胜利 +15 士气
		print("[单挑] 🎉 %s 单挑获胜！(+15士气)" % name)
		EventBus.float_text.emit("🎉 %s 单挑胜利！+15士气" % name, global_position + Vector3(0, 4, 0), Color.YELLOW)
	return other.hp <= 0.0

# ======================================================================
# 🎯 设计 v3 新增：复活倒计时系统
# ======================================================================

func enter_grace_period() -> void:
	"""
	V2武将复活：阵亡后5分钟内可在寺庙复活，过时变在野武将
	grace_period_seconds = 300s (5分钟)
	寺庙附近(10格)调用 GameManager.has_temple_nearby(faction, pos) → 满血复活
	超时 → 从 all_generals 移除 → 加到 inn_available_generals（在野池）
	"""
	grace_period_seconds = 300.0
	set_process(true)
	# 🛕 登记到待复活列表：寺庙可用「祭祀复活」主动救人
	if not GameManager.dead_generals.has(self):
		GameManager.dead_generals.append(self)
	print("[General] 💀 %s 重伤！300s内前往寺庙可复活" % name)
	EventBus.float_text.emit("💀 %s 重伤中！(寺庙复活)" % name, global_position + Vector3(0, 4, 0), Color.RED)

func _process_grace_period(delta: float) -> void:
	if grace_period_seconds < 0.0:
		return
	grace_period_seconds -= delta
	# V2：在寺庙附近 → 满血复活
	if GameManager.has_method("has_temple_nearby") and GameManager.has_temple_nearby(faction, global_position):
		_respawn_at_temple()
		return
	if grace_period_seconds <= 0.0:
		print("[General] 💀💀 %s 重伤超时！变为在野武将" % name)
		# 从 all_generals / 待复活列表移除
		if GameManager.all_generals.has(self):
			GameManager.all_generals.erase(self)
		if GameManager.dead_generals.has(self):
			GameManager.dead_generals.erase(self)
		# 加入在野池（客栈/点将台可招募）
		if not GameManager.generals_pool.has(general_id):
			GameManager.generals_pool.append(general_id)
		queue_free()

func _respawn_at_temple() -> void:
	"""V2：寺庙复活 → 满血满状态，位置重置到城池"""
	max_hp = max_hp  # 不变
	hp = max_hp
	mp = max_mp
	morale = 100.0
	grace_period_seconds = -1.0  # 标记不再倒计时
	if GameManager.dead_generals.has(self):
		GameManager.dead_generals.erase(self)
	print("[General] 🛕 %s 在寺庙复活！满血满状态" % name)
	EventBus.float_text.emit("🛕 %s 寺庙复活！" % name, global_position + Vector3(0, 4, 0), Color.GREEN)
	# 重置到城池附近
	var gov: Node = GameManager.get_government(faction)
	if gov != null and is_instance_valid(gov):
		global_position = gov.global_position + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))
	is_in_solo_duel = false

# ======================================================================
# 🎯 设计 v3 新增：标记敌人（智谋献策用）
# ======================================================================

func mark_enemies(seconds: float) -> void:
	"""智谋献策效果：标记附近敌方位置"""
	print("[General] 🎯 %s 标记敌方位置 %.0fs" % [name, seconds])
	var nearby: Array = GameManager.get_all_nearby_enemies(global_position, 20.0) if GameManager.has_method("get_all_nearby_enemies") else []
	for e in nearby:
		if is_instance_valid(e):
			EventBus.float_text.emit("⚠ 敌方在此！", e.global_position + Vector3(0, 4, 0), Color.RED)

# ======================================================================
# 🎯 设计 v3 新增：暴击计算（武力挂钩）
# ======================================================================

func get_crit_chance() -> float:
	return GameManager.calc_crit_chance(stats.get("might", 70.0))

func has_qinglongyanyue() -> bool:
	for sk in equipped_skills:
		if sk.get("skill_id", "") == "qinglongyanyue":
			return true
	return false

func get_qinglong_level() -> int:
	return get_skill_level("qinglongyanyue")

func get_lifesteal_ratio() -> float:
	"""特殊科技嗜血如命：吸血比例"""
	return GameManager.get_elite_tech_value(faction, "general_lifesteal")

func is_control_immune(effect_type: String) -> bool:
	"""特殊科技金刚不坏：免控判定"""
	return GameManager.has_general_immunity(faction, effect_type)

# ======================================================================
# V2：献策系统（随机触发 + 60s 冷却 + 新效果池）
# 智谋越高，献策越频繁；名将（rarity=legend）献策强度更高
# ======================================================================

var _counsel_cooldown: float = 30.0  # 初始30s后开始第一次献策判定

# V2效果池（智谋 + 名将等级决定触发概率和强度）
var COUNSEL_POOL: Array = [
	# {id, name, desc, chance, effect_type, duration}
	{"id": "rare_mount", "name": "发现稀有马匹", "desc": "在附近标记稀有马", "chance": 0.15, "type": "marker", "target": "rare_mount", "radius": 30.0},
	{"id": "treasure", "name": "发现宝物", "desc": "标记附近宝物点", "chance": 0.12, "type": "marker", "target": "treasure", "radius": 40.0},
	{"id": "strategic_point", "name": "战略要地", "desc": "标记战略点（可建造防御）", "chance": 0.10, "type": "marker", "target": "strategic_point", "radius": 35.0},
	{"id": "fog_village", "name": "探明黑雾村庄", "desc": "揭开附近黑雾村庄", "chance": 0.18, "type": "reveal", "radius": 25.0},
	{"id": "enemy_morale_drain", "name": "散布谣言", "desc": "敌军士气-10（10秒）", "chance": 0.15, "type": "debuff", "target": "enemy_morale", "value": -10.0, "duration": 10.0, "radius": 20.0},
	{"id": "own_morale_boost", "name": "激励士气", "desc": "友军士气+5", "chance": 0.20, "type": "buff", "target": "own_morale", "value": 5.0, "radius": 20.0},
	{"id": "supply_raid", "name": "粮道截获", "desc": "盗取敌军补给（+10金+3酒）", "chance": 0.10, "type": "resource", "gold": 10, "wine": 3},
]

func _tick_v2_counsel(delta: float) -> void:
	"""V2献策：60s冷却，智谋越高触发概率越大，名将效果翻倍"""
	_counsel_cooldown -= delta
	if _counsel_cooldown > 0.0:
		return
	# 重置冷却（基础60s，名将-20%，智谋>80额外-10%）
	var cd: float = 60.0
	if is_legend:
		cd *= 0.8
	if stats.get("intelligence", 60.0) > 80.0:
		cd *= 0.9
	_counsel_cooldown = cd
	# 触发概率：基础30% + 智谋/200（智100→30+50=80%）
	var trigger_prob: float = 0.30 + stats.get("intelligence", 60.0) / 200.0
	if randf() > trigger_prob:
		return
	# 从效果池随机选一个
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	var roll: float = rng.randf()
	var cumu: float = 0.0
	var chosen: Dictionary = {}
	for c in COUNSEL_POOL:
		cumu += c.chance
		if roll <= cumu:
			chosen = c
			break
	if chosen.is_empty():
		chosen = COUNSEL_POOL[0]
	_execute_counsel(chosen)

func _execute_counsel(counsel: Dictionary) -> void:
	"""执行献策效果，名将时数值×1.5"""
	var mult: float = 1.5 if is_legend else 1.0
	print("[献策] 💡 %s 献策：%s（名将×%.1f）" % [name, counsel.get("name", ""), mult])
	EventBus.float_text.emit("💡 %s：%s" % [name, counsel.get("name", "")], global_position + Vector3(0, 4, 0), Color.CYAN)
	
	var ctype: String = counsel.get("type", "")
	match ctype:
		"marker":
			var target: String = counsel.get("target", "")
			var radius: float = counsel.get("radius", 30.0)
			if GameManager.has_method("mark_special_resource"):
				GameManager.mark_special_resource(faction, target, global_position, radius)
		"reveal":
			var rr: float = counsel.get("radius", 25.0)
			if GameManager.has_method("reveal_fog_village"):
				GameManager.reveal_fog_village(faction, global_position, rr)
		"debuff":
			var val: float = counsel.get("value", -10.0) * mult
			var r2: float = counsel.get("radius", 20.0)
			var dur: float = counsel.get("duration", 10.0)
			if GameManager.has_method("apply_enemy_morale_debuff"):
				GameManager.apply_enemy_morale_debuff(faction, global_position, r2, val, dur)
		"buff":
			var val2: float = counsel.get("value", 5.0) * mult
			var r3: float = counsel.get("radius", 20.0)
			if GameManager.has_method("apply_own_morale_buff"):
				GameManager.apply_own_morale_buff(faction, global_position, r3, val2)
		"resource":
			var g: int = int(counsel.get("gold", 10) * mult)
			var w: int = int(counsel.get("wine", 3) * mult)
			GameManager.add_resource(faction, "gold", float(g))
			GameManager.add_resource(faction, "wine", float(w))
			print("[献策] 💡 %s 粮道截获！+%d金 +%d酒" % [name, g, w])

# ======================================================================
# V2：名将/普通将领战斗成长区分
# 名将（rarity=legend）：HP+20/攻+3/防+2
# 普通（rarity<legend）：HP+15/攻+2/防+1
# ======================================================================

func v2_get_growth_per_level() -> Dictionary:
	"""返回每级成长数值（名将vs普通）"""
	if is_legend:
		return {"hp": 20.0, "atk": 3.0, "def": 2.0, "mp": 5.0}
	else:
		return {"hp": 15.0, "atk": 2.0, "def": 1.0, "mp": 3.0}

# ======================================================================
# 🏮 招募 / 复活工厂
# 客栈招募、寺庙复活统一走这里，避免"两处各写一套初始化"
# ======================================================================
static func spawn_general(fid: String, gid: String, lv: int, parent: Node, pos: Vector3) -> Node:
	var g: Node = load("res://scripts/entities/General.gd").new()
	g.general_id = gid
	g.faction = fid
	g.name = "General_" + gid
	parent.add_child(g)
	# 等级成长与 Unit.add_exp 的每级 +5%HP / +3%攻 / +2%防 / +5%攻速保持一致
	if lv > 1:
		var steps: int = lv - 1
		g.level = lv
		g.max_hp *= pow(1.05, float(steps))
		g.atk *= pow(1.03, float(steps))
		g.defense *= pow(1.02, float(steps))
		g.atk_speed *= pow(1.05, float(steps))
		g.hp = g.max_hp
	g.global_position = pos
	return g
