## DisasterSystem — 灾祸系统（设计v3）
## 5 种灾害：旱灾/涝灾/瘟疫/地震/蝗灾，由 GameManager.disasters_enabled 开关控制
## Main._ready 里挂载：var ds := Node.new(); ds.set_script(load(...)); add_child(ds)

extends Node

var _disaster_timer: float = 90.0   # 开局 90s 后开始
var _interval: float = 120.0        # 之后每 120s roll 一次

const DISASTERS := [
	{"id": "drought", "name": "旱灾", "desc": "赤地千里，粮食歉收", "color": Color(0.9, 0.6, 0.2)},
	{"id": "flood",   "name": "涝灾", "desc": "洪水泛滥，木料漂散", "color": Color(0.3, 0.5, 0.9)},
	{"id": "plague",  "name": "瘟疫", "desc": "疫病流行，士卒病倒", "color": Color(0.6, 0.8, 0.3)},
	{"id": "quake",   "name": "地震", "desc": "地动山摇，建筑受损", "color": Color(0.7, 0.5, 0.4)},
	{"id": "locust",  "name": "蝗灾", "desc": "蝗虫蔽日，金库耗损", "color": Color(0.8, 0.7, 0.2)},
]

func _process(delta: float) -> void:
	if GameManager.game_over or GameManager.paused:
		return
	if not GameManager.disasters_enabled:
		return
	_disaster_timer -= delta
	if _disaster_timer <= 0:
		_disaster_timer = _interval
		_trigger_random_disaster()

func _trigger_random_disaster() -> void:
	var fids: Array = GameManager.factions.keys()
	if fids.is_empty():
		return
	var d: Dictionary = DISASTERS[randi() % DISASTERS.size()]
	# 影响 1~2 个随机势力（35% 概率波及第二家）
	var victims: Array = [fids[randi() % fids.size()]]
	if randf() < 0.35 and fids.size() > 1:
		var extra: String = fids[randi() % fids.size()]
		if not victims.has(extra):
			victims.append(extra)
	for fid in victims:
		_apply_disaster(d, fid)
	print("[灾祸] ☄️ %s：%s（波及 %s）" % [d["name"], d["desc"], ", ".join(PackedStringArray(victims))])
	EventBus.disaster_occurred.emit(d["id"], d["name"], victims)

func _apply_disaster(d: Dictionary, fid: String) -> void:
	var state = GameManager.factions.get(fid)
	if state == null:
		return
	# 🏛 祭祀官减免：灾祸损失 ×(1 - 减免率)，减免率=60%×内政匹配系数
	var reduction: float = GameManager.get_disaster_reduction(fid)
	# 保留比例换算：原保留 keep → 新保留 = 1 - (1-keep)*(1-reduction)
	var k07: float = 1.0 - 0.3 * (1.0 - reduction)   # 原保留 70%
	var k075: float = 1.0 - 0.25 * (1.0 - reduction)  # 原保留 75%
	var k08: float = 1.0 - 0.2 * (1.0 - reduction)   # 原保留 80%
	match d["id"]:
		"drought":  # 旱灾：粮食 -30%
			state.resources["food"] = maxi(0, int(state.resources.get("food", 0) * k07))
		"flood":    # 涝灾：木材 -25%
			state.resources["wood"] = maxi(0, int(state.resources.get("wood", 0) * k075))
		"plague":   # 瘟疫：所有单位 HP -20%（不致死）
			for u in state.units:
				if is_instance_valid(u) and u.hp > 0:
					u.hp = maxf(1.0, u.hp * k08)
		"quake":    # 地震：随机一座建筑 HP -30%
			if not state.buildings.is_empty():
				var b = state.buildings[randi() % state.buildings.size()]
				if is_instance_valid(b):
					b.hp = maxf(1.0, b.hp * k07)
		"locust":   # 蝗灾：金 -20%
			state.resources["gold"] = maxi(0, int(state.resources.get("gold", 0) * k08))
	# 在受影响势力官府上方飘字提示
	for b in state.buildings:
		if is_instance_valid(b) and b.building_id == "government":
			EventBus.float_text.emit("☄️ %s！" % d["name"], b.global_position + Vector3(0, 5, 0), d["color"])
			break
