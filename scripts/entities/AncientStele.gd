extends Node3D
class_name AncientStele
## AncientStele — 古碑任务系统（P1-28）
##
## 阶段：BROKEN(待修复) → REPAIRING(修复中) → QUEST(任务中) → DONE / FAILED
## repair.mode == "gather" 时需先拾集残片才能付材料修复。
## 修复完成后从 quest_pool 随机派发任务：cargo(护送辎重到村) / person(护送名士到指定地点) / raid(清剿山贼)。
## 护送与清剿途中按波次刷山贼；任务达成给资源 + 武将训练经验 + 限时增益。数值见 config/relics.json。

const STAGE_BROKEN := "BROKEN"
const STAGE_REPAIRING := "REPAIRING"
const STAGE_QUEST := "QUEST"
const STAGE_DONE := "DONE"
const STAGE_FAILED := "FAILED"

var relic_id: String = "xuanyuan_bei"
var faction: String = ""
var hp: float = 0.0
var max_hp: float = 600.0
var repair_radius: float = 4.0

var stage: String = STAGE_BROKEN
var fragments_needed: int = 0
var fragments_found: int = 0
var quest_type: String = ""
var quest_desc: String = ""
var quest_dest: Vector3 = Vector3.ZERO
var quest_dest_name: String = ""

var _def: Dictionary = {}
var _cost_paid: bool = false
var _no_afford_cd: float = 0.0
var _repairers: Dictionary = {}   # instance_id -> Unit
var _visual: MeshInstance3D = null
var _label: Label3D = null
var _escort: Node = null
var _marker: Node3D = null
var _bandits: Array = []
var _raid_total: int = 0
var _wave_timer: float = 0.0
var _waves_spawned: int = 0
var _max_waves: int = 0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	_def = DataLoader.get_relic_def(relic_id)
	if _def.is_empty():
		_def = {"name": relic_id, "repair_hp": 600.0}
	max_hp = float(_def.get("repair_hp", 600.0))
	hp = 0.0
	var rep: Dictionary = _def.get("repair", {})
	if str(rep.get("mode", "direct")) == "gather":
		fragments_needed = int(rep.get("fragments", 2))
	_create_visual()
	_update_label()
	GameManager.relics.append(self)

func _exit_tree() -> void:
	GameManager.relics.erase(self)

func _process(delta: float) -> void:
	_no_afford_cd = maxf(0.0, _no_afford_cd - delta)
	if stage == STAGE_QUEST:
		_tick_quest(delta)

# ==================== 查询接口 ====================

func get_faction() -> String:
	return faction

func get_relic_name() -> String:
	return str(_def.get("name", relic_id))

func get_tier() -> String:
	return str(_def.get("tier", "near"))

func get_progress() -> float:
	return clampf(hp / max_hp, 0.0, 1.0) if max_hp > 0.0 else 1.0

func is_completed() -> bool:
	return stage == STAGE_DONE

func is_damaged() -> bool:
	return stage == STAGE_BROKEN or stage == STAGE_REPAIRING

func get_stage() -> String:
	return stage

func get_quest_type() -> String:
	return quest_type

## HUD 单行文案（GameUI 每 1s 调一次）
func get_hud_line() -> String:
	match stage:
		STAGE_BROKEN:
			if fragments_needed > 0 and fragments_found < fragments_needed:
				return "🪨 %s  残片 %d/%d" % [get_relic_name(), fragments_found, fragments_needed]
			return "🪨 %s  待修复" % get_relic_name()
		STAGE_REPAIRING:
			return "🪨 %s  修复 %d%%" % [get_relic_name(), int(round(get_progress() * 100.0))]
		STAGE_QUEST:
			return "%s  %s" % [_quest_icon(), quest_desc]
		STAGE_DONE:
			return "✅ %s" % get_relic_name()
		STAGE_FAILED:
			return "❌ %s（任务失败）" % get_relic_name()
	return get_relic_name()

func get_hud_color() -> Color:
	match stage:
		STAGE_DONE: return Color(0.55, 0.95, 0.55)
		STAGE_FAILED: return Color(0.95, 0.45, 0.40)
		STAGE_QUEST: return Color(0.85, 0.85, 1.0)
		_: return Color(0.95, 0.90, 0.75)

func _quest_icon() -> String:
	match quest_type:
		"cargo", "person": return "📦"
		"raid": return "⚔"
	return "📜"

# ==================== 修复阶段 ====================

func can_repair_now() -> bool:
	return fragments_needed <= 0 or fragments_found >= fragments_needed

## 供 Unit._process_repairing 调用（沿用建筑修理接口）
func repair(amount: float) -> void:
	if not is_damaged():
		return
	if not can_repair_now():
		if _no_afford_cd <= 0.0:
			_no_afford_cd = 2.0
			EventBus.float_text.emit("还需 %d 枚残片" % (fragments_needed - fragments_found), global_position + Vector3(0, 3, 0), Color.RED)
		return
	if not _cost_paid:
		var payer = _find_repairer()
		if payer == null:
			return
		if not _try_pay_cost(payer.faction):
			return
	if stage == STAGE_BROKEN:
		stage = STAGE_REPAIRING
		_update_label()
	# 记录半径内全部参修者（多个农夫同修时经验不漏发）
	for u in GameManager.all_units:
		if not is_instance_valid(u) or not ("unit_id" in u):
			continue
		var uid: String = str(u.unit_id)
		if uid != "peasant" and uid != "engineer":
			continue
		if _horiz_dist(global_position, u.global_position) <= repair_radius:
			_repairers[u.get_instance_id()] = u
	hp = minf(max_hp, hp + amount)
	if hp >= max_hp:
		_finish_repair()

func on_fragment_collected(_frag) -> void:
	if stage != STAGE_BROKEN and stage != STAGE_REPAIRING:
		return
	fragments_found = mini(fragments_needed, fragments_found + 1)
	_update_label()
	if fragments_found >= fragments_needed:
		EventBus.float_text.emit("🧩 %s 残片集齐，可开始修复" % get_relic_name(), global_position + Vector3(0, 3.5, 0), Color.GOLD)

func _try_pay_cost(repair_faction: String) -> bool:
	if _cost_paid:
		return true
	if repair_faction == "":
		return false
	faction = repair_faction
	var cost: Dictionary = _def.get("repair", {}).get("cost", {})
	if not cost.is_empty() and not GameManager.can_afford(faction, cost):
		if _no_afford_cd <= 0.0:
			_no_afford_cd = 2.0
			EventBus.float_text.emit("修复材料不足", global_position + Vector3(0, 3, 0), Color.RED)
		return false
	if not cost.is_empty():
		GameManager.spend_resources(faction, cost)
	_cost_paid = true
	EventBus.float_text.emit("🪨 开始修复：%s" % get_relic_name(), global_position + Vector3(0, 3, 0), Color.CYAN)
	return true

func _find_repairer():
	for u in GameManager.all_units:
		if not is_instance_valid(u):
			continue
		if not ("unit_id" in u):
			continue
		var uid: String = str(u.unit_id)
		if uid != "peasant" and uid != "engineer":
			continue
		if _horiz_dist(global_position, u.global_position) <= repair_radius:
			return u
	return null

## 修复半径只按水平距离算：地形起伏时 y 差会把贴脸的农夫判成"太远"
func _horiz_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

# ==================== 任务阶段 ====================

func _finish_repair() -> void:
	hp = max_hp
	stage = STAGE_QUEST
	# 参修单位经验（修复功劳，任务奖励在任务达成时另发）
	var units: Array = []
	for iid in _repairers.keys():
		var u = _repairers[iid]
		if is_instance_valid(u):
			units.append(u)
	if not units.is_empty():
		GameManager.grant_shared_xp(units, float(_def.get("xp", 0.0)), float(_def.get("xp", 0.0)))
	_repairers.clear()
	_start_quest()
	_update_label()

func _start_quest() -> void:
	var pool: Array = _def.get("quest_pool", ["raid"])
	quest_type = str(pool[_rng.randi_range(0, pool.size() - 1)]) if not pool.is_empty() else "raid"
	var qdef: Dictionary = DataLoader.relics.get("quest", {}).get(quest_type, {})
	match quest_type:
		"cargo", "person":
			_start_escort(quest_type, qdef)
		_:
			quest_type = "raid"
			_start_raid(qdef)

func _start_raid(qdef: Dictionary) -> void:
	var bandit_conf: Dictionary = DataLoader.relics.get("bandit", {})
	var tier: String = get_tier()
	var sizes: Dictionary = bandit_conf.get("raid_size", {})
	_raid_total = int(sizes.get(tier, 4))
	for i in range(_raid_total):
		var pos: Vector3 = _find_land_near(global_position, float(qdef.get("spawn_radius", 12.0)))
		_spawn_bandit(pos)
	quest_desc = "清剿山贼 0/%d" % _raid_total
	EventBus.float_text.emit("⚔ 「%s」周边山贼来袭！" % get_relic_name(), global_position + Vector3(0, 4, 0), Color.RED)

func _start_escort(kind: String, qdef: Dictionary) -> void:
	var unit_id: String = str(qdef.get("unit_id", "escort_cargo"))
	var scene: PackedScene = load("res://scenes/Unit.tscn")
	if scene == null:
		return
	_escort = scene.instantiate()
	_escort.unit_id = unit_id
	_escort.faction = faction
	add_child(_escort)
	_escort.global_position = _find_land_near(global_position, 3.5)
	_escort.is_escort = true
	_escort.escort_relic = self
	var dest: Dictionary = _pick_dest(kind)
	quest_dest = dest["pos"]
	quest_dest_name = str(dest["name"])
	_escort.escort_dest = quest_dest
	quest_desc = str(qdef.get("desc", "护送目标到 %s")) % quest_dest_name
	_create_marker()
	var bandit_conf: Dictionary = DataLoader.relics.get("bandit", {})
	_max_waves = int(bandit_conf.get("waves", {}).get(get_tier(), 1))
	_waves_spawned = 0
	_wave_timer = float(bandit_conf.get("wave_interval", 22.0))
	EventBus.float_text.emit("📜 新任务：%s" % quest_desc, global_position + Vector3(0, 4, 0), Color.CYAN)

func _pick_dest(kind: String) -> Dictionary:
	if kind == "cargo":
		var best: Node = null
		var best_d: float = INF
		for v in GameManager.villages:
			if not is_instance_valid(v):
				continue
			var d: float = global_position.distance_to(v.global_position)
			if d < 20.0:
				continue
			if d < best_d:
				best_d = d
				best = v
		if best != null:
			var vname: String = str(best.village_id)
			return {"pos": best.global_position, "name": "%s村" % vname}
	# person：指定地点（距碑 60~90m 的陆地）
	var pos: Vector3 = _find_land_near(global_position, 90.0, 60.0)
	return {"pos": pos, "name": "指定地点"}

func _tick_quest(delta: float) -> void:
	if quest_type == "raid":
		quest_desc = "清剿山贼 %d/%d" % [_raid_total - _count_alive_bandits(), _raid_total]
		if _count_alive_bandits() <= 0:
			_finish_quest(true)
		return
	# 护送
	if _escort == null or not is_instance_valid(_escort) or float(_escort.hp) <= 0.0:
		_finish_quest(false)
		return
	var arrive: float = float(DataLoader.relics.get("quest", {}).get(quest_type, {}).get("arrive_radius", 6.0))
	if quest_dest != Vector3.ZERO and _escort.global_position.distance_to(quest_dest) <= arrive:
		_finish_quest(true)
		return
	# 波次刷贼
	if _waves_spawned < _max_waves:
		_wave_timer -= delta
		if _wave_timer <= 0.0:
			_wave_timer = float(DataLoader.relics.get("bandit", {}).get("wave_interval", 22.0))
			_waves_spawned += 1
			_spawn_bandit_wave()

func _count_alive_bandits() -> int:
	var n: int = 0
	for b in _bandits:
		if is_instance_valid(b) and float(b.hp) > 0.0:
			n += 1
	return n

## 在护送目标前方（朝目标方向）刷一波山贼
func _spawn_bandit_wave() -> void:
	var bandit_conf: Dictionary = DataLoader.relics.get("bandit", {})
	var tiers: Dictionary = bandit_conf.get("wave_size", {})
	var rng_size: Array = tiers.get(get_tier(), [2, 3])
	var n: int = _rng.randi_range(int(rng_size[0]), int(rng_size[1]))
	var base: Vector3 = global_position
	var aim: Vector3 = quest_dest
	if _escort != null and is_instance_valid(_escort):
		base = _escort.global_position
		var dir: Vector3 = (aim - base)
		dir.y = 0
		if dir.length() > 1.0:
			base += dir.normalized() * float(bandit_conf.get("spawn_ahead", 8.0))
	for i in range(n):
		_spawn_bandit(_find_land_near(base, 4.0))
	EventBus.float_text.emit("⚔ 山贼拦截！", base + Vector3(0, 3, 0), Color.RED)

func _spawn_bandit(pos: Vector3) -> void:
	var bandit_conf: Dictionary = DataLoader.relics.get("bandit", {})
	var ids: Array = bandit_conf.get("unit_ids", ["bandit_footman"])
	var scene: PackedScene = load("res://scenes/Unit.tscn")
	if scene == null or ids.is_empty():
		return
	var b = scene.instantiate()
	b.unit_id = str(ids[_rng.randi_range(0, ids.size() - 1)])
	b.faction = str(bandit_conf.get("faction", "bandit"))
	add_child(b)
	b.global_position = pos
	_bandits.append(b)

## 护送目标阵亡（Unit._die 回调）
func on_escort_dead(_u) -> void:
	if stage != STAGE_QUEST:
		return
	_finish_quest(false)

func _finish_quest(ok: bool) -> void:
	if stage != STAGE_QUEST:
		return
	_clear_bandits()
	_clear_marker()
	if _escort != null and is_instance_valid(_escort):
		_escort.queue_free()
	_escort = null
	if not ok:
		stage = STAGE_FAILED
		_update_label()
		EventBus.relic_completed.emit(faction, relic_id, "%s（失败）" % get_relic_name())
		EventBus.float_text.emit("❌ 古碑任务失败：%s" % get_relic_name(), global_position + Vector3(0, 4, 0), Color.RED)
		return
	stage = STAGE_DONE
	# 资源奖励
	var reward: Dictionary = _def.get("reward", {})
	for res in reward.keys():
		GameManager.add_resource(faction, str(res), float(reward[res]))
	# 武将训练经验（前期练将）
	var officer_xp: float = float(_def.get("officer_xp", 0.0))
	if officer_xp > 0.0:
		var n: int = GameManager.grant_officer_xp(faction, officer_xp)
		if n > 0:
			EventBus.float_text.emit("🎖 全军武将 +%.0f 训练经验" % officer_xp, global_position + Vector3(0, 5, 0), Color.YELLOW)
	# 限时势力增益
	var buff: Dictionary = _def.get("buff", {})
	if not buff.is_empty():
		GameManager.add_faction_buff(faction, str(buff.get("key", "")), float(buff.get("value", 0.0)), float(buff.get("duration", 600.0)))
	_update_label()
	EventBus.relic_completed.emit(faction, relic_id, get_relic_name())
	EventBus.float_text.emit("🏆 古碑任务达成：%s" % get_relic_name(), global_position + Vector3(0, 4, 0), Color.GOLD)

func _clear_bandits() -> void:
	for b in _bandits:
		if is_instance_valid(b):
			b.queue_free()
	_bandits.clear()

## 任务目的地光柱（护送任务期间显示，避免玩家不知道往哪走）
func _create_marker() -> void:
	_clear_marker()
	if quest_dest == Vector3.ZERO:
		return
	_marker = Node3D.new()
	add_child(_marker)
	_marker.global_position = quest_dest
	var pole: MeshInstance3D = MeshInstance3D.new()
	var cm: CylinderMesh = CylinderMesh.new()
	cm.top_radius = 0.18
	cm.bottom_radius = 0.18
	cm.height = 6.0
	pole.mesh = cm
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.80, 0.30)
	mat.emission_enabled = true
	mat.emission = Color(0.55, 0.40, 0.10)
	pole.material_override = mat
	pole.position.y = 3.0
	_marker.add_child(pole)
	var lb: Label3D = Label3D.new()
	lb.text = "📍 %s" % quest_dest_name
	lb.font_size = 40
	lb.pixel_size = 0.007
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.modulate = Color(1.0, 0.92, 0.55)
	lb.position.y = 7.0
	_marker.add_child(lb)

func _clear_marker() -> void:
	if _marker != null and is_instance_valid(_marker):
		_marker.queue_free()
	_marker = null

# ==================== 通用 ====================

## 在 center 附近找陆地坐标（min_d 起，最多 radius）
func _find_land_near(center: Vector3, radius: float, min_d: float = 0.0) -> Vector3:
	for i in range(30):
		var ang: float = _rng.randf_range(0.0, TAU)
		var dist: float = _rng.randf_range(min_d, radius) if radius > min_d else _rng.randf_range(0.0, radius)
		var p: Vector3 = center + Vector3(cos(ang), 0.0, sin(ang)) * dist
		if not Terrain.is_water(p.x, p.z):
			return Vector3(p.x, Terrain.get_height(p.x, p.z), p.z)
	return center

func _update_label() -> void:
	if _label == null:
		return
	_label.text = get_hud_line()

func _create_visual() -> void:
	_visual = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(1.0, 2.4, 0.5)
	_visual.mesh = box
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.44, 0.40)
	mat.roughness = 0.9
	_visual.material_override = mat
	_visual.position.y = 1.2
	add_child(_visual)
	# 底座
	var base: MeshInstance3D = MeshInstance3D.new()
	var bm: BoxMesh = BoxMesh.new()
	bm.size = Vector3(1.6, 0.3, 1.0)
	base.mesh = bm
	var bmat: StandardMaterial3D = StandardMaterial3D.new()
	bmat.albedo_color = Color(0.30, 0.30, 0.28)
	base.material_override = bmat
	base.position.y = 0.15
	add_child(base)
	_label = Label3D.new()
	_label.font_size = 40
	_label.pixel_size = 0.006
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position.y = 3.2
	_label.modulate = Color(0.95, 0.92, 0.80)
	add_child(_label)
