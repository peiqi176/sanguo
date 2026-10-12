extends CharacterBody3D
class_name WildHorse
## WildHorse — 野马，可被捕获后供部队骑乘
## 单位靠近并持续接触一段时间后捕获
## 捕获后给该势力增加马匹储备，可训练骑兵

@export var horse_id: String = "horse_0"
@export var horse_type: String = "white"  # white/red/chitu/dilu
var captured: bool = false
var capture_progress: float = 0.0
var capturer_faction: String = ""
var wander_timer: float = 0.0
var wander_dir: Vector3 = Vector3.ZERO

# 马匹属性
var horse_name: String = "白马"
var speed_bonus: float = 0.0
var atk_bonus: float = 0.0
var rarity: String = "common"  # common/rare/legendary

var _selection_ring: MeshInstance3D = null

func _ready() -> void:
	GameManager.wild_horses.append(self)
	_init_stats()
	_create_visual()

func _init_stats() -> void:
	match horse_type:
		"white":
			horse_name = "白马"
			speed_bonus = 0.5
			rarity = "common"
		"red":
			horse_name = "红马"
			speed_bonus = 0.5
			atk_bonus = 1.0
			rarity = "common"
		"chitu":
			horse_name = "赤兔"
			speed_bonus = 1.2
			atk_bonus = 3.0
			rarity = "legendary"
		"dilu":
			horse_name = "的卢"
			speed_bonus = 1.0
			rarity = "rare"

func _create_visual() -> void:
	var sprite: Sprite3D = Sprite3D.new()
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.shaded = false
	sprite.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var adef: Dictionary = DataLoader.get_asset_def("wild_horse", horse_type)
	if not adef.is_empty():
		var tex: Texture2D = DataLoader.get_sprite_texture("wild_horse", horse_type)
		if tex:
			sprite.texture = tex
		var s: float = float(adef.get("scale", 1.3))
		sprite.scale = Vector3(s, s, s)
		sprite.position.y = float(adef.get("offset_y", 0.7))
	add_child(sprite)

func _process(delta: float) -> void:
	if GameManager.paused or GameManager.game_over or captured:
		return
	_check_capturers(delta)
	_wander(delta)

func _wander(delta: float) -> void:
	wander_timer -= delta
	if wander_timer <= 0:
		wander_timer = randf_range(2.0, 5.0)
		var ang: float = randf() * TAU
		wander_dir = Vector3(cos(ang), 0, sin(ang))
	velocity = wander_dir * 1.5
	move_and_slide()

func _check_capturers(delta: float) -> void:
	var near_units: Array = []
	for u in GameManager.all_units:
		if is_instance_valid(u) and u.has_method("get_faction"):
			if global_position.distance_to(u.global_position) < 2.5:
				near_units.append(u)
	if near_units.is_empty():
		if capture_progress > 0:
			capture_progress = max(0.0, capture_progress - 10.0 * delta)
		capturer_faction = ""
		return
	var faction_counts: Dictionary = {}
	for u in near_units:
		var f: String = u.get_faction()
		faction_counts[f] = faction_counts.get(f, 0) + 1
	if faction_counts.size() == 1:
		var f: String = near_units[0].get_faction()
		capturer_faction = f
		capture_progress = min(100.0, capture_progress + 20.0 * delta)
		if capture_progress >= 100.0:
			_capture(f, near_units)
	else:
		capturer_faction = ""

func _capture(faction_id: String, capturers: Array) -> void:
	captured = true
	EventBus.float_text.emit("捕获 %s!" % horse_name, global_position + Vector3(0, 2, 0), Color(0.5, 0.8, 1.0))
	# 给捕获单位所在势力增加马匹储备
	if not "horses" in GameManager.factions[faction_id]:
		GameManager.factions[faction_id].horses = 0
	GameManager.factions[faction_id].horses += 1
	# 名马额外加成
	if rarity == "legendary":
		GameManager.factions[faction_id].morale = min(100.0, GameManager.factions[faction_id].morale + 10.0)
	# 给附近最近的单位上骑马效果
	var nearest: Node = null
	var min_dist: float = 999.0
	for u in capturers:
		var d: float = global_position.distance_to(u.global_position)
		if d < min_dist:
			min_dist = d
			nearest = u
	if nearest and not nearest.mounted:
		nearest.mounted = true
		nearest.move_speed += speed_bonus
		nearest.atk += atk_bonus
		EventBus.float_text.emit("%s 骑乘 %s!" % [nearest.unit_id, horse_name], nearest.global_position + Vector3(0, 2, 0), Color(0.5, 0.8, 1.0))
	GameManager.wild_horses.erase(self)
	queue_free()
