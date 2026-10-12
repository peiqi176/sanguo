extends Unit
class_name General
## General — 武将类（继承Unit）
## 四层技能：基础(5个全武将)/被动/主动/名将特殊主动

@export var general_id: String = "guanyu"

var general_def: Dictionary = {}
var mp: float = 100.0
var max_mp: float = 100.0
var basic_skills: Array = ["rally", "first_aid", "forced_march", "defensive_rally", "rallying_call"]
var active_skill: Dictionary = {}
var ultimate_skill: Dictionary = {}
var passive_skills: Array = []
var skill_cooldowns: Dictionary = {}
var is_legend: bool = false

func _ready() -> void:
	is_general = true
	super._ready()
	general_def = DataLoader.get_general_def(general_id)
	if not general_def.is_empty():
		_init_general()

func _init_general() -> void:
	max_hp = general_def.get("hp", 350)
	hp = max_hp
	atk = general_def.get("atk", 28)
	defense = general_def.get("def", 10)
	move_speed = general_def.get("speed", 3.0)
	morale = general_def.get("morale", 90)
	max_mp = 100
	mp = max_mp
	is_legend = general_def.get("rarity", "epic") == "legend"
	passive_skills = general_def.get("passive", [])
	active_skill = general_def.get("active", {})
	ultimate_skill = general_def.get("ultimate", {})
	# 初始化技能CD
	for skill_id in basic_skills:
		skill_cooldowns[skill_id] = 0.0
	skill_cooldowns["active"] = 0.0
	skill_cooldowns["ultimate"] = 0.0

func _process(delta: float) -> void:
	super._process(delta)
	# MP恢复
	mp = min(max_mp, mp + delta * 2.0)
	# 技能CD
	for key in skill_cooldowns.keys():
		skill_cooldowns[key] = max(0.0, skill_cooldowns[key] - delta)

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
	match skill_type:
		"buff_aura":
			_apply_aura_buff(skill)
		"heal_single":
			if target and target.has_method("take_damage"):
				var heal: float = target.max_hp * skill.get("heal_pct", 0.2)
				target.hp = min(target.max_hp, target.hp + heal)
		"buff_self":
			move_speed *= (1.0 + skill.get("speed_buff", 0))
		"damage":
			if target:
				target.take_damage(skill.get("damage", 30), self)
		"charge_damage":
			if target:
				target.take_damage(skill.get("damage", 50), self)
		"fear_aura":
			_apply_aoe_damage(skill, target_pos)
		"heal_aura":
			_apply_aoe_heal(skill)
		_:
			print("[General] 未实现技能类型: %s" % skill_type)
	EventBus.float_text.emit(skill.get("name", "技能"), global_position + Vector3(0, 3, 0), Color.GOLD)

func _apply_aura_buff(skill: Dictionary) -> void:
	var radius: float = skill.get("radius", 10)
	for unit in GameManager.all_units:
		if unit.get_faction() == faction and unit != self:
			if global_position.distance_to(unit.global_position) <= radius:
				unit.atk *= (1.0 + skill.get("atk_buff", 0))
				unit.morale = min(100, unit.morale + skill.get("morale_buff", 15))

func _apply_aoe_damage(skill: Dictionary, center: Vector3) -> void:
	var radius: float = skill.get("radius", 6)
	var damage: float = skill.get("damage", 30)
	for unit in GameManager.all_units:
		if unit.get_faction() != faction and is_instance_valid(unit):
			if center.distance_to(unit.global_position) <= radius:
				unit.take_damage(damage, self)
				unit.morale = max(0, unit.morale - skill.get("enemy_morale", 10))

func _apply_aoe_heal(skill: Dictionary) -> void:
	var radius: float = skill.get("radius", 10)
	var heal_pct: float = skill.get("heal_pct", 0.15)
	for unit in GameManager.all_units:
		if unit.get_faction() == faction:
			if global_position.distance_to(unit.global_position) <= radius:
				unit.hp = min(unit.max_hp, unit.hp + unit.max_hp * heal_pct)

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
