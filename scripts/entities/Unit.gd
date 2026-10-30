extends CharacterBody3D
class_name Unit
## Unit — 单位基类（士兵/农夫/武将）
## 包含：移动(A*寻路)、攻击(微克制+暴击)、采集、状态机、等级/老兵系统

signal died(unit)

# 基础属性
@export var unit_id: String = "sword"
@export var faction: String = "shu"
@export var is_general: bool = false

var def: Dictionary = {}
var hp: float = 100.0
var max_hp: float = 100.0
var atk: float = 10.0
var defense: float = 4.0
var atk_speed: float = 1.0
var move_speed: float = 2.6
var range: float = 0.6
var morale: float = 60.0
## 🚫 后勤兵（农夫/工兵）没有士气：不吃士气衰减，攻击也不受士气系数影响
var no_morale: bool = false
var level: int = 1
var exp: float = 0.0
var kills: int = 0
var veteran_atk_bonus: float = 0.0
var stamina: float = 100.0
# 🎯 设计 v3：士兵9级升级曲线 + 暴击（士兵无暴击率）
var max_level: int = 9
var xp_to_next: float = 100.0  # Lv1→2 需要 100
var mounted: bool = false
var mount_speed_bonus: float = 0.0  # 骑乘带来的基础速度加成（下马时归零）
var _horse_mesh: Node3D = null     # 马 mesh 引用，方便下马/阵亡时移除
var horse_tier: int = 1            # 🐎 马匹等级：1劣马 2骏马 3良马 4白马（数值见 logistics.json horse_tiers）
var _pending_mount: bool = false   # 🐎 正在前往马厩取马（到达后上马）
var _mount_stable: Node = null     # 目标马厩
var _mount_dest: Vector3 = Vector3.ZERO  # 取马集合点（马厩 rally_point 或马厩位置）
var _mount_check_timer: float = 0.0
# ⚔ 冲锋 / 架枪（动量机制，对标 AoE4）
const CHARGE_MIN_DISTANCE: float = 6.0      # 连续冲刺距离门槛（米）
const CHARGE_DAMAGE_MULT: float = 1.8       # 冲锋首击伤害倍率
const BRACE_TIME: float = 2.0               # 静止多少秒进入架枪
const BRACE_DAMAGE_REDUCTION: float = 0.5   # 架枪受冲锋伤害减免（乘算）
const BRACE_REFLECT_RATIO: float = 0.3      # 架枪反弹给冲锋者的伤害比例
const CHARGE_DECAY_SPEED: float = 4.0       # 静止时冲锋蓄势衰减速度（米/秒）
var _charge_distance: float = 0.0
var charge_ready: bool = false
var braced: bool = false
var _brace_timer: float = 0.0
var field_rations: float = 0.0     # 🍞 出征携带的包子（军粮）
var _ration_accum: float = 0.0     # 军粮消耗累加器
var out_of_food: bool = false      # 断粮状态（体力流失加速 + 攻击惩罚）

# 🔥 v4 器械操控相关
var is_siege_unit: bool = false  # 是否为器械单位（category=siege）
var required_haulers: int = 0   # 需要多少郎勇操控
var current_haulers: int = 0    # 当前已架起郎勇数
var is_operated: bool = false   # 是否已架起（可攻击）
var haulers_list: Array = []   # 郎勇操控者列表
# 🔥 v4 郎勇相关
var can_operate_siege: bool = false  # 是否为郎勇（sentinel）
## 🔥 霹雳车落点起火冷却：同台车 duration 内最多铺一处火
var _thunder_fire_cd: float = 0.0

# 状态
enum State { IDLE, MOVING, ATTACKING, GATHERING, RETURNING, BUILDING, REPAIRING, GUARDING, WORKING }
var state: int = State.IDLE
# 🔥 v4 士兵行为模式（主动进攻/防守/睡觉） + 坚守
enum BehaviorMode { ACTIVE_ATTACK, DEFENSE, SLEEP, HOLD }
var behavior_mode: int = BehaviorMode.ACTIVE_ATTACK  # 默认主动进攻
var behavior_attack_range: float = 15.0  # 主动进攻搜索范围
var hold_position: Vector3 = Vector3.ZERO  # 坚守驻点（切换到坚守时记录当前位置）
var attack_cooldown: float = 0.0
var is_selected: bool = false
var garrisoned: bool = false  # 是否已入驻建筑（入驻后冻结单位逻辑）

# 目标
var move_target: Vector3 = Vector3.ZERO
var attack_target: Node = null
var gather_target: Node = null
var repair_target: Node = null
var garrison_building: Node = null
var build_target = null     # 🏗️ 正在建造的建筑
var current_building = null  # 入岗工作/驻扎的建筑
var command_queue: Array = []  # 指令队列 (Shift+点击排队)
var path: Array = []
var path_index: int = 0

# 城墙驻防 buff（由 Wall.garrison 入驻时设置）
var wall_atk_bonus: float = 0.0   # 驻防时攻击加成
var wall_range_bonus: float = 0.0  # 驻防时射程加成

# 阵型（由 SelectionManager 设置）
var current_formation: String = ""  # "" / "square" / "circle" / "echelon"
var formation_atk_mod: float = 1.0
var formation_def_mod: float = 1.0
var formation_speed_mod: float = 1.0

# 临时增益（武将光环/buff）：带时长回收，避免永久乘算导致数值膨胀
var atk_buffs: Array = []        # 元素 {"mult": float, "remain": float}
var morale_buffs: Array = []     # 元素 {"amt": float, "remain": float}
var stamina_buffs: Array = []    # 元素 {"rate": float, "remain": float} 体力恢复/s
var _atk_buff_mult: float = 1.0  # 由 atk_buffs 每帧重算

# 🎯 P1-23 技能效果计时器（全部由技能系统写入，_tick_buffs 统一回收）
var stun_timer: float = 0.0           # 眩晕/冰冻：不能移动、不能攻击
var invuln_timer: float = 0.0         # 无敌：免疫伤害
var no_drain_timer: float = 0.0       # 养气：期间不掉体力
var speed_buffs: Array = []           # {mult, remain}
var atk_speed_buffs: Array = []       # {mult, remain}
var armor_pen_buffs: Array = []       # {add, remain}
var hp_regen_buffs: Array = []        # {rate, remain} 每秒回血
var _speed_buff_mult: float = 1.0
var _atk_speed_buff_mult: float = 1.0
var _armor_pen_buff: float = 0.0

# 组件
var _selection_ring: MeshInstance3D = null
var _hp_bar: Sprite3D = null
var _pathfinder = null
var _sprite: Sprite3D = null
var _glb_holder: Node3D = null       # 真 3D GLB 外观（贴片删除后的主路径）
var _sprite_base_pos: Vector3 = Vector3.ZERO
var _sprite_base_scale: Vector3 = Vector3.ONE
var _silhouette: Sprite3D = null   # 🫥 被建筑遮挡时叠的穿透剪影（AoE4 Obscured Unit Alpha）
var _obscured: bool = false
var _anim_time: float = 0.0

# 补给区状态（0.5s 缓存一次）
var supply_state: Dictionary = {}
var _supply_timer: float = 0.0

var _is_naval: bool = false  # 海军单位：贴水面而非地形
var capacity: int = 0        # 🚢 运兵上限（船只）
var passengers: Array = []   # 🚢 船上单位
var on_board: bool = false   # 🚢 本单位是否正待在船上（视觉隐藏，不可点选）
var _board_target: Node = null  # 正在前往登船的船

# 🪨 古碑护送目标（cargo / person 任务）
var is_escort: bool = false
var follow_unit: Node = null     # 玩家右键指定的护送部队
var escort_dest: Vector3 = Vector3.ZERO
var escort_relic: Node = null    # 所属古碑
var _escort_move_cd: float = 0.0

func _ready() -> void:
	def = DataLoader.get_unit_def(unit_id)
	if not def.is_empty():
		_init_from_def()
	_create_sprite()
	_create_selection_ring()
	_create_hp_bar()
	GameManager.register_unit(self)
	# 友军阵亡士气惩罚：半径8格内友军死亡时 -4 士气
	if not EventBus.unit_died.is_connected(_on_ally_died):
		EventBus.unit_died.connect(_on_ally_died)

func _init_from_def() -> void:
	max_hp = def.get("hp", 100)
	hp = max_hp
	atk = def.get("atk", 10)
	defense = def.get("def", 4)
	atk_speed = def.get("atk_speed", 1.0)
	move_speed = def.get("move_speed", 2.6)
	range = def.get("range", 0.6)
	capacity = int(def.get("capacity", 0))
	morale = def.get("morale", 60)
	no_morale = bool(def.get("no_morale", false))
	if no_morale:
		morale = 0.0
	# 🔥 v4 器械/郎勇标记
	var cat: String = str(def.get("category", ""))
	if cat == "siege":
		is_siege_unit = true
		required_haulers = int(def.get("requires_haulers", 2))
		# 📖 器械科技：器械耐久 +20%
		max_hp *= GameManager.get_tech_bonus(faction, "siege_hp")
		hp = max_hp
	if unit_id == "sentinel":
		can_operate_siege = true

func _create_sprite() -> void:
	# 船只单位使用3D模型
	if def.has("is_naval") and def["is_naval"]:
		_is_naval = true
		var ship_script: GDScript = load("res://scripts/world/Ship.gd") as GDScript
		var ship: Node3D = ship_script.new()
		ship.position.y = 0.0
		if unit_id == "warship":
			ship.set_ship_type(1)
		else:
			ship.set_ship_type(0)
		add_child(ship)
		_sprite = Sprite3D.new()
		_sprite.visible = false
		add_child(_sprite)
		_sprite_base_pos = Vector3.ZERO
		_sprite_base_scale = Vector3.ONE
		return
	
	var cat: String = "units"
	var eid: String = unit_id
	if is_general:
		cat = "generals"
		var gid: Variant = get("general_id")
		eid = str(gid) if gid != null and str(gid) != "" else "default"
	var adef: Dictionary = DataLoader.get_asset_def(cat, eid)
	var tex: Texture2D = DataLoader.get_sprite_texture(cat, eid)
	
	if tex:
		# 正常路径：Sprite3D + 贴图
		# ⚠ 千万不要写 `_sprite.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA`。
		#   Godot 4 里 GeometryInstance3D.transparency 是 **float 淡出值**（0=不透明，1=全透明），
		#   而 TRANSPARENCY_ALPHA 这个枚举恰好等于 1 —— 赋进去等于把精灵设成 100% 透明，
		#   于是贴图加载日志一切正常、画面上什么都没有。Sprite3D 自带 RGBA 纹理时
		#   会自动开 alpha 混合，这一行原本就不需要（是从 Godot 3 抄过来的写法）。
		_sprite = Sprite3D.new()
		_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_sprite.shaded = false
		_sprite.texture = tex
		_sprite.pixel_size = DataLoader.get_sprite_pixel_size(cat, tex)
		# V2：Sprite3D 投真阴影（Forward+ 完美支持，2D精灵在3D地形上有真影子）
		# 注意：Godot 4 里属性叫 cast_shadow（shadow_cast 是 Godot 3 的写法，会直接报错刷屏）
		_sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var s: float = float(adef.get("scale", 1.0)) if not adef.is_empty() else 1.2
		_sprite.scale = Vector3(s, s, s)
		# 贴地高度：由贴图内容的 alpha 包围盒量出来，不再读 asset_map 里手填的 offset_y。
		# 见 DataLoader.get_sprite_anchor_y 的推导 —— 手填值和真实底边留白没有相关性，
		# 是"有的兵陷进地里、有的浮空"的根因。
		_sprite.position.y = DataLoader.get_sprite_anchor_y(cat, eid, s)
		# 硬边透明（M3-4）：billboard 精灵进不透明队列，几十个单位挤在一起时
		# 不会因为透明排序抖动而互相闪烁。
		_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		_sprite_base_pos = _sprite.position
		_sprite_base_scale = _sprite.scale
		# 势力颜色染色（70%原色 + 30%势力色），保留贴图细节
		var fc: Color = GameManager.get_faction_color(faction)
		_sprite.modulate = Color(
			1.0 + (fc.r - 0.5) * 0.3,
			1.0 + (fc.g - 0.5) * 0.3,
			1.0 + (fc.b - 0.5) * 0.3,
			1.0
		)
		add_child(_sprite)
		print("[Unit] ✅ %s/%s 贴图加载成功 (faction=%s color=%s)" % [cat, eid, faction, GameManager.get_faction_color(faction)])
	else:
		# GLB 优先（2026-10-29 贴片已删）：标定表里有的实体走真 3D 模型
		var glb_holder: Node3D = EntityGLTF.spawn(cat, eid, self, Vector3.ZERO)
		if glb_holder != null:
			print("[Unit] ✅ %s/%s GLB 模型加载成功" % [cat, eid])
			_glb_holder = glb_holder
			_sprite = Sprite3D.new()
			_sprite.visible = false
			add_child(_sprite)
			_sprite_base_pos = Vector3.ZERO
			_sprite_base_scale = Vector3.ONE
		else:
			# Fallback：彩色 BoxMesh（确保永远可见！）+ 势力颜色
			print("[Unit] ⚠ %s/%s 贴图/GLB 缺失 → 用彩色 fallback mesh (faction=%s)" % [cat, eid, faction])
			var mesh_instance: MeshInstance3D = MeshInstance3D.new()
			var box: BoxMesh = BoxMesh.new()
			var size_f: float = 0.6 if not is_general else 0.9
			if unit_id == "peasant":
				size_f = 0.5
			box.size = Vector3(size_f, size_f * 1.6, size_f)
			mesh_instance.mesh = box
			var mat: StandardMaterial3D = StandardMaterial3D.new()
			mat.albedo_color = GameManager.get_faction_color(faction)  # 势力颜色！
			mat.roughness = 0.6
			mesh_instance.material_override = mat
			mesh_instance.position.y = size_f * 0.8
			add_child(mesh_instance)
			# 挂到 _sprite 变量上（下游逻辑需要引用一个 Node）
			_sprite = Sprite3D.new()
			_sprite.visible = false
			add_child(_sprite)
			_sprite_base_pos = Vector3(0, size_f * 0.8, 0)
			_sprite_base_scale = Vector3(size_f, size_f, size_f)

func _get_fallback_color() -> Color:
	"""根据 unit 类型返回 fallback 颜色"""
	if is_general:
		return Color(1.0, 0.85, 0.2)  # 金色 = 武将
	match unit_id:
		"peasant": return Color(0.75, 0.65, 0.45)  # 土黄 = 农夫
		"sword": return Color(0.85, 0.25, 0.25)   # 红 = 刀兵
		"archer": return Color(0.3, 0.55, 0.8)   # 蓝 = 弓手
		"spear": return Color(0.55, 0.35, 0.15)   # 棕 = 枪兵
		"cavalry": return Color(0.45, 0.3, 0.55)  # 紫 = 骑兵
		_: return Color(0.6, 0.6, 0.6)            # 灰 = 其他

func _create_selection_ring() -> void:
	_selection_ring = MeshInstance3D.new()
	var ring_mesh: TorusMesh = TorusMesh.new()
	ring_mesh.inner_radius = 0.4
	ring_mesh.outer_radius = 0.5
	ring_mesh.ring_segments = 32
	ring_mesh.ring_segments = 8
	_selection_ring.mesh = ring_mesh
	_selection_ring.visible = false
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color.GREEN
	mat.emission_enabled = true
	mat.emission = Color.GREEN
	_selection_ring.material_override = mat
	add_child(_selection_ring)
	_selection_ring.position.y = 0.1
	_selection_ring.rotation.x = deg_to_rad(90)

# ---------- 被建筑遮挡时的穿透剪影（AoE4 Obscured Unit Alpha）----------
## 帝国时代4 的做法：单位走到建筑后面时，建筑不透明，但会在建筑上方
## 叠一个半透明的势力色剪影，玩家始终能看到自己的兵在哪。
func set_obscured(on: bool) -> void:
	if _obscured == on:
		return
	_obscured = on
	if on:
		_ensure_silhouette()
	if _silhouette != null:
		_silhouette.visible = on

func is_obscured() -> bool:
	return _obscured

func _ensure_silhouette() -> void:
	if _silhouette != null:
		return
	if _sprite == null or not is_instance_valid(_sprite):
		return
	if _sprite.texture == null:
		return
	_silhouette = Sprite3D.new()
	_silhouette.texture = _sprite.texture
	_silhouette.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_silhouette.shaded = false
	_silhouette.pixel_size = _sprite.pixel_size
	_silhouette.scale = _sprite.scale
	_silhouette.position = _sprite.position
	_silhouette.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	# 关键：关掉深度测试 → 剪影能"透"过建筑画出来
	_silhouette.no_depth_test = true
	_silhouette.render_priority = 10
	_silhouette.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var fc: Color = GameManager.get_faction_color(faction)
	_silhouette.modulate = Color(fc.r, fc.g, fc.b, 0.55)
	_silhouette.visible = false
	add_child(_silhouette)

# ---------- HP 条 ----------
var _hp_bar_bg: Sprite3D = null
var _hp_bar_fg: Sprite3D = null

func _create_hp_bar() -> void:
	_hp_bar_bg = Sprite3D.new()
	_hp_bar_bg.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hp_bar_bg.shaded = false
	# 生成一个 16x4 红色底条贴图
	var bg_img: Image = Image.create(16, 4, false, Image.FORMAT_RGBA8)
	bg_img.fill(Color(0.2, 0.05, 0.05, 0.9))
	_hp_bar_bg.texture = ImageTexture.create_from_image(bg_img)
	_hp_bar_bg.scale = Vector3(0.35, 0.35, 0.35)
	_hp_bar_bg.position = Vector3(0, 1.8, 0)
	add_child(_hp_bar_bg)
	
	_hp_bar_fg = Sprite3D.new()
	_hp_bar_fg.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hp_bar_fg.shaded = false
	var fg_img: Image = Image.create(16, 4, false, Image.FORMAT_RGBA8)
	fg_img.fill(Color(0.1, 0.8, 0.2, 0.95))
	_hp_bar_fg.texture = ImageTexture.create_from_image(fg_img)
	_hp_bar_fg.scale = Vector3(0.35, 0.35, 0.35)
	_hp_bar_fg.position = Vector3(0, 1.8, -0.05)
	add_child(_hp_bar_fg)
	_update_hp_bar()

func _update_hp_bar() -> void:
	if _hp_bar_fg == null or hp <= 0:
		return
	var ratio: float = clampf(hp / max_hp, 0.0, 1.0)
	if ratio < 0.999:
		_hp_bar_bg.visible = true
		_hp_bar_fg.visible = true
		# 根据比例缩放前景条（从左侧生长）
		var full_scale: float = 0.35
		_hp_bar_fg.scale = Vector3(full_scale * ratio, full_scale, full_scale)
		_hp_bar_fg.position.x = -full_scale * (1.0 - ratio) * 0.5
		# HP 低 → 变红
		if ratio < 0.3:
			_hp_bar_fg.modulate = Color(1.0, 0.3, 0.3)
		elif ratio < 0.6:
			_hp_bar_fg.modulate = Color(1.0, 0.8, 0.3)
		else:
			_hp_bar_fg.modulate = Color.WHITE
	else:
		_hp_bar_bg.visible = false
		_hp_bar_fg.visible = false

func set_selected(selected: bool) -> void:
	is_selected = selected
	if _selection_ring:
		_selection_ring.visible = selected

func set_garrisoned(g: bool) -> void:
	garrisoned = g

func get_faction() -> String:
	return faction

# ============ 🚢 水路运兵 ============

func _exit_tree() -> void:
	# 船只被清场（读档/重开/场景卸载）时先卸下乘客，避免乘客永久隐形冻结
	if _is_naval and not passengers.is_empty():
		unload_passengers()

func _board_range() -> float:
	return float(DataLoader.logistics.get("naval", {}).get("board_range", 3.0))

## 陆军右键友方船只：靠得近直接登船，否则先走过去
func command_board_ship(ship: Node) -> bool:
	if _is_naval:
		EventBus.float_text.emit("船只不能登船", global_position + Vector3(0, 3, 0), Color.GRAY)
		return false
	# 已在建筑/器械/船上的单位不能再去登船（否则建筑驻军计数会错乱）
	if garrisoned:
		EventBus.float_text.emit("该部队已在载具/建筑内", global_position + Vector3(0, 3, 0), Color.GRAY)
		return false
	if not is_instance_valid(ship) or not ship.has_method("receive_passenger"):
		return false
	if ship.get_faction() != faction:
		EventBus.float_text.emit("不能登敌方船只", global_position + Vector3(0, 3, 0), Color.GRAY)
		return false
	if ship.passengers.size() >= ship.capacity:
		EventBus.float_text.emit("船只已满", ship.global_position + Vector3(0, 3, 0), Color.GRAY)
		return false
	if global_position.distance_to(ship.global_position) <= _board_range():
		if ship.receive_passenger(self):
			return true
	_board_target = ship
	if GameManager.grid != null and GameManager.pathfinder != null:
		command_move(ship.global_position)
	else:
		move_target = ship.global_position
		state = State.MOVING
	return true

## 每帧推进登船（到达即上船）
func _tick_boarding(_delta: float) -> void:
	if _board_target == null:
		return
	if not is_instance_valid(_board_target):
		_board_target = null
		return
	if _board_target.get_faction() != faction or _board_target.passengers.size() >= _board_target.capacity:
		_board_target = null
		return
	if global_position.distance_to(_board_target.global_position) <= _board_range():
		var ship = _board_target
		_board_target = null
		ship.receive_passenger(self)

## 船接收乘客
func receive_passenger(u) -> bool:
	if not _is_naval or capacity <= 0:
		return false
	if u == null or not is_instance_valid(u):
		return false
	if passengers.size() >= capacity:
		return false
	if u.garrisoned or passengers.has(u):
		return false
	passengers.append(u)
	u.set_on_board(self)
	EventBus.float_text.emit("登船 %d/%d" % [passengers.size(), capacity], global_position + Vector3(0, 3, 0), Color.CYAN)
	return true

## 上/下船视觉与冻结
func set_on_board(ship) -> void:
	var aboard: bool = ship != null
	on_board = aboard
	garrisoned = aboard
	_board_target = null
	state = State.IDLE
	velocity = Vector3.ZERO
	if _sprite:
		_sprite.visible = not aboard
	if _hp_bar_bg:
		_hp_bar_bg.visible = not aboard
	if _hp_bar_fg:
		_hp_bar_fg.visible = not aboard
	if _selection_ring:
		_selection_ring.visible = (not aboard) and is_selected
	if _silhouette:
		_silhouette.visible = false

## 下船：由近到远找陆地落点（8 方向 × 3 圈）
func unload_passengers() -> int:
	if passengers.is_empty():
		return 0
	var radius: float = float(DataLoader.logistics.get("naval", {}).get("unload_radius", 4.0))
	var spots: Array = []
	for ring in range(1, 4):
		for i in range(8):
			var ang: float = TAU * float(i) / 8.0
			var p: Vector3 = global_position + Vector3(cos(ang), 0, sin(ang)) * (radius * float(ring) / 2.0)
			if Terrain.is_water(p.x, p.z):
				continue
			spots.append(p)
		if not spots.is_empty():
			break
	var count: int = 0
	for u in passengers:
		if not is_instance_valid(u):
			count += 1
			continue
		var land: Vector3 = global_position
		if not spots.is_empty():
			land = spots[count % spots.size()]
		else:
			land = Vector3(global_position.x + radius, 0, global_position.z + radius)
		u.set_on_board(null)
		u.global_position = Vector3(land.x, Terrain.get_height(land.x, land.z), land.z)
		if GameManager.grid != null and GameManager.pathfinder != null:
			u.command_move(land)
		else:
			u.move_target = land
			u.state = State.MOVING
		count += 1
	passengers.clear()
	return count

## 水战射箭：远程单位，或射程够的战船
func _uses_arrow_attack() -> bool:
	if is_ranged_unit():
		return true
	if _is_naval:
		var min_r: float = float(DataLoader.logistics.get("naval", {}).get("arrow_min_range", 2.0))
		return range >= min_r
	return false

# ============ 🪨 古碑护送目标 ============

## 由玩家右键护送目标触发：让目标跟随该部队
func command_escort_follow(leader) -> bool:
	if not is_escort:
		return false
	if leader == null or not is_instance_valid(leader):
		return false
	follow_unit = leader
	EventBus.float_text.emit("🛡 开始护送：%s" % def.get("name", unit_id), global_position + Vector3(0, 3, 0), Color.CYAN)
	return true

func _tick_escort(delta: float) -> void:
	if not is_escort or hp <= 0.0:
		return
	if follow_unit == null or not is_instance_valid(follow_unit):
		return
	_escort_move_cd = maxf(0.0, _escort_move_cd - delta)
	if _escort_move_cd > 0.0:
		return
	# 落后超过 4m 就重新下令追上（每 0.8s 一次，避免每帧重置寻路）
	if global_position.distance_to(follow_unit.global_position) > 4.0:
		_escort_move_cd = 0.8
		_escort_move_to(follow_unit.global_position)

func _escort_move_to(pos: Vector3) -> void:
	if GameManager.grid != null and GameManager.pathfinder != null:
		command_move(pos)
	else:
		move_target = pos
		state = State.MOVING

## 护送目标死亡：通知古碑判失败
func _notify_escort_dead() -> void:
	is_escort = false
	if escort_relic != null and is_instance_valid(escort_relic) and escort_relic.has_method("on_escort_dead"):
		escort_relic.on_escort_dead(self)

# 🔥 v4 郎勇架起器械（郎勇走到器械旁调用）
func assemble_siege_operator(siege_unit) -> bool:
	if not can_operate_siege:
		return false
	if siege_unit == null or not is_instance_valid(siege_unit):
		return false
	if not siege_unit.is_siege_unit:
		return false
	if siege_unit.faction != faction:
		return false
	if siege_unit.current_haulers >= siege_unit.required_haulers:
		return false
	if self in siege_unit.haulers_list:
		return false
	siege_unit.haulers_list.append(self)
	siege_unit.current_haulers = siege_unit.haulers_list.size()
	siege_unit.is_operated = siege_unit.current_haulers >= siege_unit.required_haulers
	garrisoned = true  # 郎勇进入器械后冻结自身逻辑
	EventBus.float_text.emit("架起! %d/%d" % [siege_unit.current_haulers, siege_unit.required_haulers], siege_unit.global_position + Vector3(0, 3, 0), Color.CYAN)
	return true

# 🔥 v4 郎勇从器械离队
func leave_siege_operator() -> void:
	for u in GameManager.all_units:
		if not is_instance_valid(u):
			continue
		if u.is_siege_unit and self in u.haulers_list:
			u.haulers_list.erase(self)
			u.current_haulers = u.haulers_list.size()
			u.is_operated = u.current_haulers >= u.required_haulers
	garrisoned = false
	EventBus.float_text.emit("离队", global_position + Vector3(0, 3, 0), Color.YELLOW)

# 🔥 v4 器械检查是否可攻击（需要郎勇架起）
func can_siege_attack() -> bool:
	if not is_siege_unit:
		return true  # 非器械始终可攻击
	return is_operated

func _process(delta: float) -> void:
	# 🗺 编辑器模式：单位只当"看得见的模型"，不寻路、不攻击、不掉体力/士气
	if GameManager.editor_mode:
		return
	# 🚢 登船途中：不冻结（garrisoned 尚未置位）
	_tick_boarding(delta)
	# 🪨 古碑护送目标：跟随指定部队
	_tick_escort(delta)
	if garrisoned:
		return
	if hp <= 0:
		return
	attack_cooldown = max(0, attack_cooldown - delta)
	_thunder_fire_cd = maxf(0.0, _thunder_fire_cd - delta)
	_tick_buffs(delta)
	# 🎯 眩晕/冰冻：锁住状态机（不移动、不攻击），只保留动画与贴地
	if stun_timer > 0.0:
		stun_timer = maxf(0.0, stun_timer - delta)
		velocity = Vector3.ZERO
		_animate_sprite(delta)
		_update_hp_bar()
		return
	_tick_pending_mount(delta)
	_tick_combat_stance(delta)
	_tick_ambush(delta)
	# 🍞 体力系统（对标傲世三国：体力决定攻击频率；馒头补体力、酒补生命）
	_tick_stamina(delta)
	
	match state:
		State.IDLE:
			_process_idle()
		State.MOVING:
			_process_moving(delta)
		State.ATTACKING:
			_process_attacking(delta)
		State.GATHERING:
			_process_gathering(delta)
		State.RETURNING:
			_process_returning(delta)
		State.REPAIRING:
			_process_repairing(delta)
		State.WORKING:
			_process_working(delta)
		State.BUILDING:
			_process_building(delta)  # 🏗️ 新增
	_animate_sprite(delta)
	_update_hp_bar()

func _physics_process(delta: float) -> void:
	# 🗺 编辑器模式：跳过移动/状态机，但**保留贴地**。
	# 单位放上去必须站在地上，而且改了地形之后也要跟着重新贴地，
	# 否则所有角色会悬在半空或陷进山里。
	if GameManager.editor_mode:
		_snap_to_ground(1.0)
		return
	# 物理步内推进移动，避免 _process（渲染帧）频率波动造成的位移抖动
	if garrisoned:
		return
	if hp <= 0:
		return
	if state == State.MOVING:
		move_and_slide()
	_snap_to_ground(delta)

## 贴地。海军单位浮在水面高度。
## 这里必须**平滑**而不是每帧硬赋值：格子中心每隔 2 米一个采样点，
## 硬赋值会让 y 一格一跳（看起来像在原地上下抽搐），平滑后是顺着坡度走。
func _snap_to_ground(delta: float) -> void:
	if _is_naval:
		global_position.y = Terrain.WATER_LEVEL
		return
	var gh: float = Terrain.get_height(global_position.x, global_position.z)
	var dy: float = gh - global_position.y
	if absf(dy) > 0.8:
		global_position.y = gh            # 差太多（传送/换地形）直接对齐
	else:
		global_position.y = lerpf(global_position.y, gh, clampf(delta * 25.0, 0.0, 1.0))

func _add_horse() -> void:
	var horse: Node3D = Node3D.new()
	var body: MeshInstance3D = MeshInstance3D.new()
	var body_mesh: CylinderMesh = CylinderMesh.new()
	body_mesh.top_radius = 0.35
	body_mesh.bottom_radius = 0.45
	body_mesh.height = 1.2
	body_mesh.radial_segments = 8
	body.mesh = body_mesh
	var body_mat: StandardMaterial3D = StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.35, 0.22, 0.12)
	body_mat.roughness = 0.6
	body.material_override = body_mat
	body.rotation.y = PI / 2.0
	body.position.y = 0.6
	horse.add_child(body)
	for i in range(4):
		var leg: MeshInstance3D = MeshInstance3D.new()
		var leg_mesh: CylinderMesh = CylinderMesh.new()
		leg_mesh.top_radius = 0.08
		leg_mesh.bottom_radius = 0.08
		leg_mesh.height = 0.7
		leg.mesh = leg_mesh
		var leg_mat: StandardMaterial3D = StandardMaterial3D.new()
		leg_mat.albedo_color = Color(0.25, 0.15, 0.08)
		leg_mat.roughness = 0.7
		leg.material_override = leg_mat
		var lx: float = 0.35 if i < 2 else -0.35
		var lz: float = 0.4 if i % 2 == 0 else -0.4
		leg.position = Vector3(lx, 0.35, lz)
		horse.add_child(leg)
	var head: MeshInstance3D = MeshInstance3D.new()
	var head_mesh: CylinderMesh = CylinderMesh.new()
	head_mesh.top_radius = 0.15
	head_mesh.bottom_radius = 0.25
	head_mesh.height = 0.5
	head_mesh.radial_segments = 6
	head.mesh = head_mesh
	var head_mat: StandardMaterial3D = StandardMaterial3D.new()
	head_mat.albedo_color = Color(0.30, 0.18, 0.10)
	head_mat.roughness = 0.6
	head.material_override = head_mat
	head.position = Vector3(0, 1.0, 0.7)
	head.rotation.x = -0.3
	horse.add_child(head)
	_horse_mesh = horse
	add_child(horse)

# 🐎 骑乘：消耗势力 1 匹马，获得速度 + 马 mesh + 骑兵科技加成
# 上马必须由玩家点击触发；若不在马厩附近，自动走到最近马厩的集合点取马，到达后上马
func command_mount() -> bool:
	if mounted or _pending_mount:
		return false
	# 天生骑兵/器械/船只不参与骑乘（已自带或不适配）
	var cat: String = str(def.get("category", ""))
	if cat == "cavalry" or cat == "siege" or cat == "naval":
		return false
	if GameManager.get_resource(faction, "horse") < 1:
		EventBus.float_text.emit("马匹不足", global_position + Vector3(0, 2, 0), Color.RED)
		return false
	# 🏇 就近取马：找最近的本方已建成马厩，集合点 = 马厩 rally_point（未设则马厩本体）
	var stable: Node = _find_nearest_stable()
	if stable == null:
		# 无马厩：直接从储备上马（野马捕获入池 / 武将自带坐骑的兜底）
		_do_mount()
		return true
	var gather_pos: Vector3 = stable.rally_point if stable.rally_point != Vector3.ZERO else stable.global_position
	if global_position.distance_to(gather_pos) <= 8.0:
		_do_mount()
		return true
	# 距离远：自动前往取马，到达后上马
	_mount_stable = stable
	_mount_dest = gather_pos
	command_move(gather_pos)
	_pending_mount = true
	EventBus.float_text.emit("🐎 前往马厩取马", global_position + Vector3(0, 2, 0), Color(0.5, 0.8, 1.0))
	return true

## 执行上马（不论优劣，骑上就是占用 1 匹可用马匹）
func _do_mount() -> void:
	# 🐎 马匹等级途径：马厩按官府等级提供 tier1~4，等级只影响速度加成，不改变耗马数
	if is_instance_valid(_mount_stable) and _mount_stable.has_method("get_horse_tier_available"):
		horse_tier = int(_mount_stable.get_horse_tier_available())
	if GameManager.get_resource(faction, "horse") < 1.0:
		_cancel_pending_mount("可用马匹不足（骑乘需 1 匹）")
		return
	# 骑上即从"可用马匹"中占用 1 匹，下马时归还
	GameManager.add_resource(faction, "horse", -1.0)
	mounted = true
	_pending_mount = false
	_mount_stable = null
	mount_speed_bonus = get_horse_tier_speed_bonus()
	if _horse_mesh == null or not is_instance_valid(_horse_mesh):
		_add_horse()
	EventBus.float_text.emit("🐎 上马（%s +%.1f）" % [get_horse_tier_name(), mount_speed_bonus], global_position + Vector3(0, 2, 0), Color(0.5, 0.8, 1.0))

## 最近的本方已建成马厩
func _find_nearest_stable() -> Node:
	var best: Node = null
	var best_d: float = 99999999.0
	for b in GameManager.all_buildings:
		if not is_instance_valid(b) or b.faction != faction:
			continue
		if b.building_id != "stable" or b.build_progress < 1.0:
			continue
		var d: float = global_position.distance_squared_to(b.global_position)
		if d < best_d:
			best_d = d
			best = b
	return best

## 取消取马（新指令覆盖 / 马厩被拆 / 马被用完）
func _cancel_pending_mount(reason: String = "") -> void:
	if not _pending_mount:
		return
	_pending_mount = false
	_mount_stable = null
	if reason != "":
		EventBus.float_text.emit(reason, global_position + Vector3(0, 2, 0), Color.RED)

## 取马途中校验（0.5s 一次）
func _tick_pending_mount(delta: float) -> void:
	if not _pending_mount:
		return
	_mount_check_timer -= delta
	if _mount_check_timer > 0.0:
		return
	_mount_check_timer = 0.5
	if not is_instance_valid(_mount_stable):
		_cancel_pending_mount("马厩已毁，取马取消")
		return
	if GameManager.get_resource(faction, "horse") < 1:
		_cancel_pending_mount("马匹被用完，取马取消")
		return

## 马匹等级 → 骑乘速度加成
## 🐎 马匹四档（数据来源 config/logistics.json → horse_tiers）
## 1 劣马 +2.0 / 2 骏马 +2.5 / 3 良马 +3.0 / 4 白马 +3.5
func get_horse_tier_def() -> Dictionary:
	var tiers: Dictionary = DataLoader.logistics.get("horse_tiers", {})
	return tiers.get(str(horse_tier), {})

func get_horse_tier_speed_bonus() -> float:
	return float(get_horse_tier_def().get("speed_bonus", 2.0))

func get_horse_tier_name() -> String:
	return str(get_horse_tier_def().get("name", "劣马"))

# 🐎 下马：归还 1 匹马，移除马 mesh
func command_dismount() -> void:
	if not mounted:
		return
	var cat: String = str(def.get("category", ""))
	if cat == "cavalry":
		return
	mounted = false
	mount_speed_bonus = 0.0
	if _horse_mesh != null and is_instance_valid(_horse_mesh):
		_horse_mesh.queue_free()
		_horse_mesh = null
	# 归还 1 匹到"可用马匹"（与上马占用 1 匹配平，杜绝刷马）
	GameManager.add_resource(faction, "horse", 1.0)
	EventBus.float_text.emit("🐎 下马（归还 1 匹）", global_position + Vector3(0, 2, 0), Color.CYAN)

## 读档后按 mounted 标志重建马 mesh 与速度加成（mesh 不进存档）
func refresh_mount_visual() -> void:
	if mounted:
		mount_speed_bonus = get_horse_tier_speed_bonus()
		if _horse_mesh == null or not is_instance_valid(_horse_mesh):
			_add_horse()
	else:
		mount_speed_bonus = 0.0
		if _horse_mesh != null and is_instance_valid(_horse_mesh):
			_horse_mesh.queue_free()
			_horse_mesh = null

func _animate_sprite(delta: float) -> void:
	if _sprite == null or not is_instance_valid(_sprite):
		return
	_anim_time += delta
	var t: float = _anim_time
	match state:
		State.IDLE:
			var breath: float = sin(t * 2.0) * 0.03
			_sprite.position = _sprite_base_pos + Vector3(0, breath, 0)
			_sprite.scale = _sprite_base_scale
			_sprite.rotation.z = 0.0
		State.MOVING:
			var walk: float = abs(sin(t * 8.0)) * 0.12
			_sprite.position = _sprite_base_pos + Vector3(0, walk, 0)
			_sprite.scale = _sprite_base_scale * Vector3(1.0, 1.0 - walk * 0.3, 1.0)
			_sprite.rotation.z = sin(t * 8.0) * 0.05
		State.ATTACKING:
			var atk: float = sin(t * atk_speed * 6.0)
			_sprite.position = _sprite_base_pos + Vector3(0, abs(atk) * 0.05, atk * 0.15)
			_sprite.scale = _sprite_base_scale * Vector3(1.0 + atk * 0.05, 1.0, 1.0)
			_sprite.rotation.z = atk * 0.1
		State.GATHERING:
			var rtype: String = "wood"
			if gather_target and gather_target.has("resource_type"):
				rtype = gather_target.get("resource_type")
			if rtype == "wood":
				var chop: float = sin(t * 6.0)
				_sprite.position = _sprite_base_pos + Vector3(chop * 0.1, abs(chop) * 0.04, 0)
				_sprite.rotation.z = chop * 0.25
			elif rtype == "iron":
				var mine: float = sin(t * 8.0)
				_sprite.position = _sprite_base_pos + Vector3(0, abs(mine) * 0.06, mine * 0.1)
				_sprite.rotation.z = mine * 0.15
			else:
				var forage: float = abs(sin(t * 3.0))
				_sprite.position = _sprite_base_pos + Vector3(0, -forage * 0.15, 0)
				_sprite.scale = _sprite_base_scale * Vector3(1.0, 1.0 - forage * 0.2, 1.0)
				_sprite.rotation.z = forage * 0.1
		State.RETURNING:
			var carry: float = abs(sin(t * 6.0)) * 0.08
			_sprite.position = _sprite_base_pos + Vector3(0, carry - 0.05, 0)
			_sprite.scale = _sprite_base_scale * Vector3(1.0, 0.95, 1.0)
			_sprite.rotation.z = sin(t * 6.0) * 0.03
		State.REPAIRING:
			var hammer: float = sin(t * 10.0)
			_sprite.position = _sprite_base_pos + Vector3(hammer * 0.08, abs(hammer) * 0.03, 0)
			_sprite.rotation.z = hammer * 0.2
		_:
			_sprite.position = _sprite_base_pos
			_sprite.scale = _sprite_base_scale
			_sprite.rotation.z = 0.0
	_sprite.visible = true

## 🛡 切换行为模式；坚守时记录当前驻点
func set_behavior_mode(mode: int) -> void:
	behavior_mode = mode
	attack_target = null
	if mode == BehaviorMode.HOLD:
		hold_position = global_position
	else:
		hold_position = Vector3.ZERO

func _process_idle() -> void:
	# 🪨 护送目标不索敌、不主动攻击（只跟随护送部队）
	if is_escort:
		velocity = Vector3.ZERO
		attack_target = null
		return
	# 🔥 v4 根据行为模式决定搜敌范围和策略
	if behavior_mode == BehaviorMode.SLEEP:
		# 睡觉模式：完全不搜敌，不反击（加速体力/士气恢复）
		stamina = min(100.0, stamina + 2.0 * get_process_delta_time())
		morale = min(100.0, morale + 1.0 * get_process_delta_time())
		return
	if behavior_mode == BehaviorMode.DEFENSE:
		# 防守模式：只在射程+2格内搜敌，不追击
		if attack_target == null or not is_instance_valid(attack_target):
			_find_nearest_enemy_in_range(range + 2.0)
		if attack_target:
			state = State.ATTACKING
	elif behavior_mode == BehaviorMode.HOLD:
		# 🛡 坚守：只在射程内反击，不追出驻点；被推远则回位
		if hold_position == Vector3.ZERO:
			hold_position = global_position
		if global_position.distance_to(hold_position) > range + 2.0:
			command_move(hold_position)
			return
		if attack_target == null or not is_instance_valid(attack_target):
			_find_nearest_enemy_in_range(range + 0.5)
		if attack_target:
			state = State.ATTACKING
	else:  # ACTIVE_ATTACK
		# 主动进攻模式：在 behavior_attack_range（15格）内搜敌并追击
		if attack_target == null or not is_instance_valid(attack_target):
			_find_nearest_enemy_in_range(behavior_attack_range)
		if attack_target:
			state = State.ATTACKING

func _find_nearest_enemy() -> void:
	_find_nearest_enemy_in_range(range + 3.0)

func _find_nearest_enemy_in_range(search_range: float) -> void:
	# 📖 科技：哨探（视野/搜敌范围 +）
	search_range *= GameManager.get_tech_bonus(faction, "soldier_vision")
	var nearest: Node = null
	var nearest_dist: float = search_range
	for unit in GameManager.all_units:
		# ⚠️ 必须先判有效再取阵营：训练消耗农夫会 queue_free，all_units 里可能残留已释放对象
		if is_instance_valid(unit) and unit.get_faction() != faction:
			var dist: float = global_position.distance_to(unit.global_position)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest = unit
	attack_target = nearest

func _process_moving(delta: float) -> void:
	if path.size() == 0 or path_index >= path.size():
		# 到达目的地后，触发相应动作
		velocity = Vector3.ZERO
		# 🐎 取马到达：在集合点 8 米内则上马
		if _pending_mount:
			if global_position.distance_to(_mount_dest) <= 8.0 and GameManager.get_resource(faction, "horse") >= 1:
				_do_mount()
			elif not is_instance_valid(_mount_stable):
				_cancel_pending_mount("马厩已毁，取马取消")
			elif path.is_empty():
				# 寻路失败（不可达）→ 取消，避免卡在"取马中"
				_cancel_pending_mount("无法抵达马厩，取马取消")
			state = State.IDLE
			return
		if garrison_building != null and is_instance_valid(garrison_building):
			if garrison_building.has_method('garrison'):
				garrison_building.garrison(self)
			garrison_building = null
		elif _current_work_building != null and is_instance_valid(_current_work_building):
			if _current_work_building.assign_worker(self):
				state = State.WORKING
			else:
				state = State.IDLE
			_current_work_building = null
		elif repair_target != null and is_instance_valid(repair_target):
			state = State.REPAIRING
		# 🏗️ 到达建造目标
		elif build_target != null and is_instance_valid(build_target):
			if build_target.build_progress >= 1.0:
				build_target = null
				state = State.IDLE
			else:
				if build_target.register_builder(self):
					state = State.BUILDING
				else:
					# 岗位满了，等一会儿再试
					pass
		elif attack_target != null and is_instance_valid(attack_target):
			# 追击/进攻：到达后回到攻击状态，修复“追丢目标/走到敌方基地发呆”
			state = State.ATTACKING
		else:
			state = State.IDLE
		return
	var target_grid: Vector2i = path[path_index]
	var target_pos: Vector3 = GameManager.grid.grid_to_world(target_grid)
	target_pos.y = global_position.y
	var direction: Vector3 = (target_pos - global_position)
	direction.y = 0
	var dist: float = direction.length()
	if dist < 0.3:
		velocity = Vector3.ZERO
		path_index += 1
		return
	var move_dir: Vector3 = direction.normalized()
	velocity = move_dir * get_effective_speed()
	# ⚔ 冲锋蓄势：骑兵连续冲刺累计距离，达到门槛后首击带冲锋加成
	add_charge_distance(velocity.length() * delta)
	# 🎯 移动时单位转身朝向（傲世三国风格：单位面朝行进方向）
	rotation.y = atan2(move_dir.x, move_dir.z)

func _process_attacking(delta: float) -> void:
	# 🔥 v4 器械架起检查：没架起=不能攻击=回到IDLE
	if is_siege_unit and not is_operated:
		state = State.IDLE
		return
	if not is_instance_valid(attack_target):
		attack_target = null
		state = State.IDLE
		return
	var target_pos: Vector3 = attack_target.global_position
	# 🏛 目标已易主为我方（占领完成）：立刻停手
	if attack_target.has_method("get_faction") and attack_target.get_faction() == faction:
		attack_target = null
		state = State.IDLE
		return
	var dist: float = global_position.distance_to(target_pos)
	# 🏛 目标已锁血（官府/村镇打到 10%）：停止攻击，改为进入范围驻留占领
	if _is_capture_target_locked():
		_process_capture_hold(delta)
		return
	# 建筑目标用更大的接战距离：只需贴近建筑即可攻击
	# （Pathfinder 会自动把终点换到建筑旁的可通行格，不会卡在占用格上）
	var reach: float = get_effective_range() + wall_range_bonus
	if attack_target and "size" in attack_target:  # duck-type Building
		var bsize: Vector2i = attack_target.size
		reach += float(max(bsize.x, bsize.y)) * GameManager.grid.cell_size * 0.5 + GameManager.grid.cell_size
	if dist > reach:
		# 🛡 坚守：目标离开射程就放弃，绝不追出去
		if behavior_mode == BehaviorMode.HOLD:
			attack_target = null
			state = State.IDLE
			return
		# 靠近目标（无导航网格的编辑器/探针环境直接放弃，避免空引用刷屏）
		if GameManager.grid == null or GameManager.pathfinder == null:
			return
		var target_grid: Vector2i = GameManager.grid.world_to_grid(target_pos)
		path = GameManager.pathfinder.find_path(GameManager.grid.world_to_grid(global_position), target_grid)
		path_index = 0
		state = State.MOVING
		return
	if attack_cooldown <= 0:
		_perform_attack()
		# 攻速加算公式: final_speed = atk_speed × (1 + tech_bonus - stamina_penalty)
		var stam_penalty: float = stamina_to_speed_penalty(stamina)
		var tech_bonus: float = GameManager.get_elite_tech_bonus(faction, "unit_attack_speed_mult")
		# 📖 基础/特殊科技：攻速加成（诸葛连弩等）
		tech_bonus += GameManager.get_tech_sum(faction, "all_soldier_atk_speed")
		if unit_id == "zhuge_nu":
			tech_bonus += GameManager.get_tech_sum(faction, "zhuge_nu_atk_speed")
		var final_speed: float = atk_speed * (1.0 + tech_bonus - stam_penalty) * _atk_speed_buff_mult
		final_speed = max(final_speed, 0.1)  # 最低攻速 0.1 防止除零
		attack_cooldown = 1.0 / final_speed

# 🏛 锁血目标判定：官府（Building.is_hp_locked）与村镇（Village.is_hp_locked）
func _is_capture_target_locked() -> bool:
	if attack_target == null or not is_instance_valid(attack_target):
		return false
	if attack_target.has_method("is_hp_locked"):
		return attack_target.is_hp_locked()
	return false

# 🏛 锁血后停止攻击，走进占领半径内驻留（推进占领条由目标自身完成）
func _process_capture_hold(delta: float) -> void:
	var conf: Dictionary = DataLoader.combat.get("capture", {})
	var is_village: bool = ("population" in attack_target)
	var entry: float = float(conf.get("village_entry_radius", 3.5) if is_village else conf.get("government_entry_radius", 6.0))
	var desired: float = maxf(entry * 0.7, 1.5)
	var dist: float = global_position.distance_to(attack_target.global_position)
	if dist > desired:
		if GameManager.grid == null or GameManager.pathfinder == null:
			velocity = Vector3.ZERO
			return
		var tgrid: Vector2i = GameManager.grid.world_to_grid(attack_target.global_position)
		path = GameManager.pathfinder.find_path(GameManager.grid.world_to_grid(global_position), tgrid)
		path_index = 0
		state = State.MOVING
		return
	velocity = Vector3.ZERO
	_animate_sprite(delta)
	_update_hp_bar()

func _perform_attack() -> void:
	var damage: float = 0.0
	# 对 Unit 造成伤害
	var target_unit = attack_target as Unit
	if target_unit != null:
		# 🏹 远程单位（含白马义从骑射、射程够的战船）：走箭矢弹道，飞行到位、命中才结算
		if _uses_arrow_attack() and global_position.distance_to(target_unit.global_position) > 1.5:
			_fire_arrow(target_unit)
			return
		# ⚔ 冲锋首击：骑兵蓄势达标后打出一次 ×1.8 伤害，打完清零（远程不享受冲锋）
		var is_charge: bool = charge_ready and is_cavalry_unit() and not is_ranged_unit()
		damage = _compute_damage(target_unit)
		if is_charge:
			damage *= CHARGE_DAMAGE_MULT
		target_unit.take_damage(damage, self, is_charge)
		# 🔥 霹雳车砸中：落点起火 5s 持续伤害
		_spawn_thunder_fire(target_unit.global_position)
		if is_charge:
			charge_ready = false
			_charge_distance = 0.0
			EventBus.float_text.emit("🐎 冲锋!", global_position + Vector3(0, 3, 0), Color(1.0, 0.6, 0.2))
		# 攻击轨迹闪光（瞬时）
		_show_attack_flash(target_unit.global_position)
		# 🧛 武将吸血（特殊科技嗜血如命）
		if is_general and has_method("get_lifesteal_ratio"):
			var ls: float = call("get_lifesteal_ratio")
			if ls > 0.0:
				hp = min(max_hp, hp + damage * ls)
		return
	# 对 Building 造成伤害
	var target_building = attack_target if (attack_target and "size" in attack_target) else null  # duck-type Building
	if target_building != null:
		# 阵型攻击加成（formation_atk_mod）乘到基础攻击上，墙防 buff 单独乘避免重复
		var base: float = atk * formation_atk_mod
		damage = base * 0.5  # 对建筑伤害减半
		# 攻城器械加成（ram/trebuchet/bed_bow 等）
		var cat: String = def.get("category", "")
		if cat == "siege":
			var siege_mult: float = float(def.get("siege_damage", 1.0))
			damage = base * siege_mult  # 攻城器械不减半！用 siege_damage 直接乘
		# 墙防 buff（驻防城墙时额外 20% 攻击）
		damage *= (1.0 + wall_atk_bonus)
		target_building.take_damage(damage, self)
		_spawn_thunder_fire(target_building.global_position)
		_show_attack_flash(target_building.global_position)
		return
	# 🏘️ 对村庄造成伤害（打空即武力夺取）
	var target_village = attack_target if (attack_target and "population" in attack_target) else null  # duck-type Village
	if target_village != null:
		damage = atk * formation_atk_mod * 0.5
		target_village.take_damage(damage, self)
		_spawn_thunder_fire(target_village.global_position)
		_show_attack_flash(target_village.global_position)
		return

func _show_attack_flash(target_pos: Vector3) -> void:
	"""攻击轨迹闪光（100ms 短寿命 Sprite3D）"""
	var flash: Sprite3D = Sprite3D.new()
	var tex: Texture2D = ImageTexture.create_from_image(Image.create(8, 8, false, Image.FORMAT_RGBA8))
	flash.texture = tex
	flash.modulate = Color(1.0, 0.9, 0.5, 0.6)
	flash.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	flash.scale = Vector3(0.5, 0.5, 0.5)
	add_child(flash)
	flash.global_position = (global_position + target_pos) / 2.0 + Vector3(0, 1.2, 0)
	get_tree().create_timer(0.1).timeout.connect(func(): if is_instance_valid(flash): flash.queue_free())

## 🔥 霹雳车砸中区域起火 5 秒（config/combat.json → fire_zone.thunder_car）
func _spawn_thunder_fire(pos: Vector3) -> void:
	if unit_id != "thunder_car" or _thunder_fire_cd > 0.0:
		return
	var conf: Dictionary = DataLoader.combat.get("fire_zone", {}).get("thunder_car", {})
	if conf.is_empty():
		return
	var fire = load("res://scripts/entities/BurningGround.gd").new()
	get_parent().add_child(fire)
	fire.configure(pos, faction, self, conf)
	_thunder_fire_cd = float(conf.get("cooldown", float(conf.get("duration", 5.0))))

## 🎲 伤害浮动区间（对标傲世三国：攻击是一个范围）
## 数值来自 units.json 的 dmg_roll_min / dmg_roll_max（默认 0.80~1.20）
## 士气越高，结算越贴近区间上限：士气 0 纯随机，士气 100 偏移一半
func get_damage_roll() -> float:
	var lo: float = float(def.get("dmg_roll_min", 0.80))
	var hi: float = float(def.get("dmg_roll_max", 1.20))
	var m: float = clampf(_morale_with_buffs() / 100.0, 0.0, 1.0)
	var t: float = clampf(randf() * 0.6 + m * 0.4, 0.0, 1.0)
	return lerpf(lo, hi, t)

## ⚔ 士气 → 攻击系数（分段）：0 → ×0.85，50 → ×1.0，100 → ×1.30
## 低于 50 惩罚更陡（崩溃感），高于 50 奖励更缓（稳定收益）
func morale_attack_coef() -> float:
	if no_morale:
		return 1.0
	var m: float = clampf(_morale_with_buffs(), 0.0, 100.0)
	if m <= 50.0:
		return lerpf(0.85, 1.00, m / 50.0)
	return lerpf(1.00, 1.30, (m - 50.0) / 50.0)

# ==================== 🏹 弓兵弹道与命中（P1-18） ====================

func _archery_conf() -> Dictionary:
	return DataLoader.combat.get("archery", {})

func _projectile_conf() -> Dictionary:
	return DataLoader.combat.get("projectile", {})

## 远程判定：category=ranged，或标记了 mounted_archer（白马义从骑射）
func is_ranged_unit() -> bool:
	return str(def.get("category", "")) == "ranged" or bool(def.get("mounted_archer", false))

## 🎯 命中率：基础 accuracy × 骑乘惩罚(×0.55) + 弓术科技（白马义从有独立上限）
func get_ranged_accuracy() -> float:
	var ac: Dictionary = _archery_conf()
	var acc: float = float(def.get("accuracy", ac.get("base_accuracy", 0.90)))
	if mounted and not bool(def.get("ignore_mounted_penalty", false)):
		acc *= float(ac.get("mounted_accuracy_mult", 0.55))
	var per: float = float(ac.get("accuracy_tech_per_level", 0.04))
	var bonus: float = GameManager.get_tech_sum(faction, "archer_accuracy") * per
	var cap: float = float(ac.get("accuracy_tech_cap", 0.20))
	if unit_id == "baima_yicong":
		bonus += GameManager.get_tech_sum(faction, "baima_accuracy") * per
		cap = float(ac.get("baima_tech_cap", 0.10))
	acc += minf(bonus, cap)
	return clampf(acc, 0.05, 0.99)

## 可否"靠马速躲箭"：必须正在跑动，且有效移速超过配置阈值
func _target_can_evade(tgt) -> bool:
	if not tgt.has_method("get_effective_speed"):
		return false
	if not ("velocity" in tgt):
		return false
	var v: Vector3 = tgt.velocity
	if v.length() < 2.0:
		return false
	return tgt.get_effective_speed() > float(_archery_conf().get("evade_base_threshold", 5.0))

## 🏹 发射箭矢：先判定命中，未命中就飞向偏移落点（纯视觉射空）
func _fire_arrow(tgt) -> void:
	var pc: Dictionary = _projectile_conf()
	var land: Vector3 = tgt.global_position
	var dmg: float = _compute_damage(tgt)
	var will_hit: bool = randf() <= get_ranged_accuracy()
	if will_hit and _target_can_evade(tgt):
		var over: float = tgt.get_effective_speed() - float(_archery_conf().get("evade_base_threshold", 5.0))
		var evade: float = minf(float(_archery_conf().get("evade_max", 0.45)), over * float(_archery_conf().get("evade_per_speed", 0.12)))
		if randf() < evade:
			will_hit = false
	if not will_hit:
		var ang: float = randf() * TAU
		var spread: float = randf_range(float(pc.get("miss_spread_min", 1.6)), float(pc.get("miss_spread_max", 3.2)))
		land += Vector3(cos(ang), 0.0, sin(ang)) * spread
		dmg = 0.0
		EventBus.float_text.emit("🏹 射空", land + Vector3(0, 2.0, 0), Color(0.75, 0.75, 0.75))
	var arrow = load("res://scripts/entities/Arrow.gd").new()
	get_parent().add_child(arrow)
	arrow.configure(
		global_position + Vector3(0, 1.2, 0),
		land + Vector3(0, 1.0, 0),
		float(pc.get("arrow_speed", 30.0)),
		float(pc.get("arc_height", 1.6)),
		dmg, self, tgt,
		float(pc.get("hit_radius", 1.3))
	)

func _compute_damage(target) -> float:
	# 阵型攻击加成 + 墙防 buff 通过 get_effective_atk() 生效；veteran_atk_bonus 为额外平加
	# 🎲 2026-10-27 对标定稿：攻击取【浮动区间】，士气越高结算越贴近区间上限
	var base_atk: float = (get_effective_atk() + veteran_atk_bonus) * morale_attack_coef() * get_damage_roll()
	# 【🔥 v4 新公式】减算: 伤害 = (攻 × 克制) - (防 × (1 - 穿甲))
	# ===== 克制系数 =====
	var counter_coef: float = 1.0
	if def.has("counters"):
		if target.unit_id in def["counters"]:
			counter_coef = 1.0 + float(def.get("counter_bonus", 0.35))
	# ===== 穿甲系数（基础 + 技能穿甲，上限 100%）=====
	var armor_pen: float = minf(1.0, float(def.get("armor_pierce", 0.0)) + _armor_pen_buff)
	# ===== 士气改为影响【攻击】，不再影响防御（2026-10-27 对标定稿）=====
	# 士气 0 → 攻 ×0.85，50 → ×1.0，100 → ×1.30；防御不受士气影响
	var eff_def: float = target.get_effective_defense()
	# ===== 先算基础伤害 =====
	var pre_damage: float = base_atk * counter_coef
	var normal_dmg: float = max(1.0, pre_damage - eff_def * (1.0 - armor_pen))
	# ===== 暴击 =====
	var crit_chance: float = get_crit_chance()
	if randf() < crit_chance:
		var crit_mult: float = GameManager.calc_crit_damage(1.0, float(stats.get("might", 70.0)), has_qinglongyanyue(), get_qinglong_level())
		# 暴击公式：(攻 × 克制 × 暴击伤害) - (防 × (1 - 穿甲))
		var crit_dmg_val: float = max(1.0, base_atk * counter_coef * crit_mult - eff_def * (1.0 - armor_pen))
		EventBus.float_text.emit("💥 暴击! %.0f" % crit_dmg_val, global_position + Vector3(0, 3, 0), Color.ORANGE)
		return crit_dmg_val
	# 建筑/村庄攻击用旧逻辑（在 _perform_attack 单独处理）
	return normal_dmg

func take_damage(amount: float, attacker: Node = null, is_charge: bool = false) -> void:
	# 🛡 无敌（长坂坡/空城计）：免疫一切伤害
	if invuln_timer > 0.0:
		EventBus.float_text.emit("🛡 无敌", global_position + Vector3(0, 3, 0), Color(0.6, 0.85, 1.0))
		return
	# ⛏ 架枪：减免冲锋伤害，并把一部分反弹给冲锋者
	if is_charge and braced:
		var orig: float = amount
		amount *= BRACE_DAMAGE_REDUCTION
		EventBus.float_text.emit("⛏ 挡下冲锋", global_position + Vector3(0, 3, 0), Color(0.6, 0.9, 1.0))
		if attacker != null and is_instance_valid(attacker) and attacker.has_method("take_damage"):
			attacker.take_damage(orig * BRACE_REFLECT_RATIO, self)
	hp -= amount
	_record_xp_contributor(attacker, amount)
	EventBus.float_text.emit(str(int(amount)), global_position + Vector3(0, 2.5, 0), Color.WHITE)
	# 受击闪烁
	_flash_red()
	if hp <= 0:
		_die(attacker)

var _flashing: bool = false

# ==================== 🎖 经验分配（P1-21） ====================
## 伤害贡献者：instance_id -> {"node": Node, "dmg": float, "t": float}
var _xp_contributors: Dictionary = {}

func _record_xp_contributor(attacker, dmg: float) -> void:
	if attacker == null or not is_instance_valid(attacker):
		return
	if not attacker.has_method("get_faction") or attacker.get_faction() == faction:
		return
	if dmg <= 0.0:
		return
	var id: int = attacker.get_instance_id()
	var now: float = Time.get_ticks_msec() / 1000.0
	if _xp_contributors.has(id):
		_xp_contributors[id]["dmg"] = float(_xp_contributors[id]["dmg"]) + dmg
		_xp_contributors[id]["t"] = now
	else:
		_xp_contributors[id] = {"node": attacker, "dmg": dmg, "t": now}

func _xp_participants(window: float) -> Array:
	var now: float = Time.get_ticks_msec() / 1000.0
	var out: Array = []
	for id in _xp_contributors.keys():
		var rec: Dictionary = _xp_contributors[id]
		if not is_instance_valid(rec.get("node", null)):
			continue
		if now - float(rec.get("t", 0.0)) > window:
			continue
		out.append(rec["node"])
	return out

func _award_death_xp(killer) -> void:
	"""🎖 死亡经验：击杀士兵 20（击杀者 20 / 参与者平分 20 池，每人 ≤10）；
			  击杀武将 50（击杀者 50 / 参与者平分 50 池，每人 ≤10）。见 config/combat.json → experience"""
	var cfg_all: Dictionary = DataLoader.combat.get("experience", {})
	var key: String = "kill_general" if is_general else "kill_soldier"
	# 🛠 敌方器械（云梯/冲车/投石车/床弩/霹雳车）单独结算：共享 30 池，单人 ≤10
	if str(def.get("category", "")) == "siege":
		key = "destroy_siege"
	var cfg: Dictionary = cfg_all.get(key, {})
	if cfg.is_empty():
		return
	var window: float = float(cfg_all.get("contributor_window", 30.0))
	var participants: Array = _xp_participants(window)
	var valid_killer: bool = killer != null and is_instance_valid(killer) and killer.has_method("get_faction")
	if valid_killer and key != "destroy_siege":
		var killer_amt: float = float(cfg.get("killer", 0.0))
		GameManager.grant_xp_to(killer, killer_amt)
	var others: Array = []
	var seen: Dictionary = {}
	for p in participants:
		if not is_instance_valid(p):
			continue
		# 只结算击杀者同势力（含击杀者本人势力）
		if valid_killer and p.get_faction() != killer.get_faction():
			continue
		var pid: int = p.get_instance_id()
		if seen.has(pid):
			continue
		seen[pid] = true
		others.append(p)
	# 🛠 器械：不做"补刀者额外奖励"，所有人都只平分 30 池（单人 ≤10）
	if key != "destroy_siege":
		# 普通击杀：击杀者已单拿固定值，从共享池里剔除，避免双份
		if valid_killer and seen.has(killer.get_instance_id()):
			others.erase(killer)
	GameManager.grant_shared_xp(others, float(cfg.get("share_pool", 0.0)), float(cfg.get("per_recipient_max", 10.0)))


func _flash_red() -> void:
	if _sprite == null or not is_instance_valid(_sprite):
		return
	_sprite.modulate = Color.RED
	if _flashing:
		return
	_flashing = true
	get_tree().create_timer(0.12).timeout.connect(_end_flash)

func _end_flash() -> void:
	_flashing = false
	if _sprite and is_instance_valid(_sprite):
		var fc: Color = GameManager.get_faction_color(faction)
		_sprite.modulate = Color(
			1.0 + (fc.r - 0.5) * 0.3,
			1.0 + (fc.g - 0.5) * 0.3,
			1.0 + (fc.b - 0.5) * 0.3,
			1.0
		)

func _die(killer: Node = null) -> void:
	hp = 0
	# 🪨 护送目标阵亡 → 古碑任务失败
	if is_escort:
		_notify_escort_dead()
	# 🚢 沉船不连坐：先把船上部队卸到陆地
	if _is_naval and not passengers.is_empty():
		unload_passengers()
	# 💥 死亡碎片粒子（傲世三国风格）
	_spawn_death_particles()
	_award_death_xp(killer)
	if killer and killer.has_method("on_kill"):
		killer.on_kill(self)
	# 民夫被杀：通知附近村庄（民心-10 繁荣-20）
	if unit_id == "peasant":
		_notify_village_peasant_died()
	# 🐎 骑乘单位阵亡：归还 1 匹马（天生骑兵不还）
	if mounted and str(def.get("category", "")) != "cavalry":
		GameManager.add_resource(faction, "horse", 1.0)
	GameManager.unregister_unit(self)
	EventBus.unit_died.emit(self)
	died.emit(self)
	queue_free()

func _notify_village_peasant_died() -> void:
	"""民夫死亡时通知归属村庄"""
	for v in GameManager.villages:
		if not is_instance_valid(v):
			continue
		if v.village_owner != faction:
			continue
		# 民夫在村庄范围内工作，死亡影响该村庄
		var v_radius: float = 10.0
		if v.level == 2:
			v_radius = 12.0
		elif v.level >= 3:
			v_radius = 14.0
		if global_position.distance_to(v.global_position) <= v_radius:
			v.on_peasant_died()
			break

func _spawn_death_particles() -> void:
	"""生成死亡碎片：小石块 + 势力色碎布向外飞溅"""
	var ps := CPUParticles3D.new()
	ps.amount = 14
	ps.lifetime = 0.7
	# 让碎片有实体碰撞视觉：用小方块 mesh
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.1, 0.1, 0.1)
	ps.mesh = mesh
	ps.global_position = global_position + Vector3(0, 1.0, 0)
	# 把粒子挂到世界根节点，这样 unit queue_free 后粒子还能继续
	get_tree().root.add_child(ps)
	# 0.7 秒后自动清理
	get_tree().create_timer(0.8).timeout.connect(func(): if is_instance_valid(ps): ps.queue_free())

func on_kill(victim) -> void:
	kills += 1
	# ⚔ 杀敌成长：每杀 +0.5 攻击（无上限）；每累计 5 杀 → 生命上限 +20
	var per_kill: float = DataLoader.veteran_bonus.get("atk_per_kill", 0.5)
	veteran_atk_bonus += per_kill
	if kills % 5 == 0:
		max_hp += 20.0
		hp = min(max_hp, hp + 20.0)
		EventBus.float_text.emit("⚔ 杀敌 %d：生命上限 +20" % kills, global_position + Vector3(0, 2.5, 0), Color(1.0, 0.85, 0.3))
	# 🎯 击杀经验已统一由死者侧 _award_death_xp() 结算（2026-10-27），此处不再重复发放
	# 🎖 击杀士气 +3，附近友军 +1（数值见 combat.json → morale）
	var mc: Dictionary = _morale_conf()
	morale = min(100.0, morale + float(mc.get("kill_bonus", 3.0)))
	_give_allies_morale(float(mc.get("kill_ally_bonus", 1.0)), float(mc.get("kill_ally_radius", 10.0)))

# ==================== 指令 ====================

func command_move(target: Vector3, queue: bool = false) -> void:
	_cancel_pending_mount()
	if queue:
		command_queue.append({"type": "move", "pos": target})
		return
	command_queue.clear()
	_on_stop_gathering()  # 🔥 v4 切指令时清理矿洞状态
	move_target = target
	# 🛡 坚守单位被玩家手动移动时，驻点跟着走（否则会自己跑回原位）
	if behavior_mode == BehaviorMode.HOLD:
		hold_position = target
	attack_target = null
	var start_grid: Vector2i = GameManager.grid.world_to_grid(global_position)
	var end_grid: Vector2i = GameManager.grid.world_to_grid(target)
	path = GameManager.pathfinder.find_path(start_grid, end_grid)
	path_index = 0
	state = State.MOVING

func command_attack(target: Node, queue: bool = false) -> void:
	if not is_instance_valid(target):
		return
	if queue:
		command_queue.append({"type": "attack", "target": target})
		return
	command_queue.clear()
	_cancel_pending_mount()
	attack_target = target
	state = State.ATTACKING

func command_gather(node: Node, queue: bool = false) -> void:
	if unit_id != "peasant":
		return
	if queue:
		command_queue.append({"type": "gather", "target": node})
		return
	command_queue.clear()
	_cancel_pending_mount()
	gather_target = node
	state = State.GATHERING

func _process_gathering(delta: float) -> void:
	if not is_instance_valid(gather_target):
		_on_stop_gathering()
		state = State.IDLE
		return
	var dist: float = global_position.distance_to(gather_target.global_position)
	if dist > 1.5:
		command_move(gather_target.global_position)
		return
	# 采集逻辑由农夫子类实现
	if unit_id == "peasant" and gather_target.has_method("gather"):
		gather_target.gather(self, delta)

# 🔥 v4 清理矿洞/资源点状态
func _on_stop_gathering() -> void:
	if gather_target != null and is_instance_valid(gather_target):
		if gather_target.has_method("remove_mine_worker"):
			gather_target.remove_mine_worker(self)
	gather_target = null

# 🧺 按资源类型返回合法掉落点建筑（顺序 = 优先级）
func _get_dropoff_ids(res_type: String) -> Array:
	match res_type:
		"wood":
			return ["lumber_camp", "warehouse", "paifang", "government", "tent"]
		"iron":
			return ["mining_camp", "warehouse", "paifang", "government", "tent"]
		"food", "meat", "fish", "bun", "mantou":
			return ["farm", "government", "paifang", "warehouse", "tent"]
		_:
			return ["warehouse", "paifang", "government", "farm", "tent"]

func _process_returning(delta: float) -> void:
	# 🧺 按携带的资源类型选择合法掉落点（伐木场/矿场/农场/仓库/牌楼/营帐）
	var res_type: String = "food"
	if has_meta("carrying"):
		res_type = str(get_meta("carrying").get("type", "food"))
	var drop_ids: Array = _get_dropoff_ids(res_type)
	var drop_off: Node = null
	var nearest_dist: float = 999999.0
	for b in GameManager.all_buildings:
		if not is_instance_valid(b) or b.get_faction() != faction:
			continue
		if not (b.building_id in drop_ids):
			continue
		var d: float = global_position.distance_to(b.global_position)
		if d < nearest_dist:
			nearest_dist = d
			drop_off = b
	if drop_off == null:
		state = State.IDLE
		return
	if nearest_dist > 2.0:
		command_move(drop_off.global_position)
		return
	# 存放资源
	if has_meta("carrying"):
		var carrying: Dictionary = get_meta("carrying")
		var amount: float = carrying.get("amount", 0.0)
		GameManager.add_resource(faction, res_type, amount)
		remove_meta("carrying")
		EventBus.float_text.emit("+%d %s" % [int(amount), res_type], global_position + Vector3(0, 2, 0), Color.GREEN)
	# 返回采集点继续采集
	if is_instance_valid(gather_target):
		state = State.GATHERING
	else:
		state = State.IDLE

func command_build(building) -> void:
	"""🏗️ 派农夫/工兵去建造指定建筑"""
	if unit_id != "peasant" and unit_id != "engineer":
		return
	if not is_instance_valid(building):
		return
	# 🏰 城防类（城墙/城门/箭塔）只能由工兵建造
	var bcat: String = str(building.def.get("category", ""))
	if bcat == "defense" and unit_id != "engineer":
		EventBus.float_text.emit("城防建筑需工兵建造", building.global_position + Vector3(0, 2, 0), Color.RED)
		return
	if building.build_progress >= 1.0:
		return
	if building.get_builder_slots_available() <= 0:
		return
	build_target = building
	velocity = Vector3.ZERO
	move_target = building.global_position
	path.clear()
	path_index = 0
	# 寻路到建筑附近（避开建筑本体）
	var gr = GameManager.grid
	if gr:
		var gpos: Vector2i = gr.world_to_grid(building.global_position)
		# 找建筑周围 1 格空地
		var found_pos: Vector3 = building.global_position + Vector3(2, 0, 2)
		var found: bool = false
		for dx in range(-2, 3):
			if found:
				break
			for dz in range(-2, 3):
				var try_g: Vector2i = Vector2i(gpos.x + dx, gpos.y + dz)
				# ⚠ 这里原来写的是 gr.is_passable()，而 GridManager 里根本没有这个方法
				# （只有 is_walkable）。运行时报 "Nonexistent function"，
				# 函数直接中断在 state = State.MOVING 之前 —— 于是农夫永远不会去建造，
				# 建筑永远停在 0% 进度，看起来就是"建不了房子"。
				if gr.is_walkable(try_g):
					found_pos = gr.grid_to_world(try_g)
					found = true
					break
		move_target = found_pos
		if GameManager.pathfinder:
			path = GameManager.pathfinder.find_path(gr.world_to_grid(global_position), gr.world_to_grid(found_pos))
			if path.is_empty():
				move_target = found_pos
	state = State.MOVING

func command_repair(target: Node) -> void:
	"""农夫/工兵修理受损建筑"""
	if unit_id != "peasant" and unit_id != "engineer":
		return
	if not is_instance_valid(target) or not target.has_method("is_damaged"):
		return
	if not target.is_damaged():
		EventBus.float_text.emit("无需修理", target.global_position + Vector3(0, 3, 0), Color.GRAY)
		return
	repair_target = target
	state = State.REPAIRING

func command_work(building) -> void:
	"""农夫入岗工作（经济建筑）"""
	if unit_id != "peasant":
		EventBus.float_text.emit("只有农夫能入岗", global_position + Vector3(0, 3, 0), Color.GRAY)
		return
	if not is_instance_valid(building):
		return
	if not building.can_accept_workers():
		EventBus.float_text.emit("此建筑不接受工人", building.global_position + Vector3(0, 3, 0), Color.GRAY)
		return
	if building.get_worker_slots_available() <= 0:
		EventBus.float_text.emit("岗位已满", building.global_position + Vector3(0, 3, 0), Color.GRAY)
		return
	# 先走到建筑旁的工作区域
	var work_pos: Vector3 = building.global_position + Vector3(float(building.size.x) + 0.5, 0, 0)
	var dist: float = global_position.distance_to(work_pos)
	if dist > 2.5:
		move_target = work_pos
		var start_grid: Vector2i = GameManager.grid.world_to_grid(global_position)
		var end_grid: Vector2i = GameManager.grid.world_to_grid(building.global_position)
		path = GameManager.pathfinder.find_path(start_grid, end_grid)
		path_index = 0
		# 记录目标建筑，到达后自动入岗
		_current_work_building = building
		state = State.MOVING
	else:
		building.assign_worker(self)
		state = State.WORKING

var _current_work_building = null

func _process_working(delta: float) -> void:
	"""农夫在岗工作中 —— 站立不动，Building.gd 负责每秒产出"""
	if current_building == null or not is_instance_valid(current_building):
		state = State.IDLE
		return
	if not current_building.can_accept_workers():
		# 建筑被摧毁或不再接受工人 → 离岗
		current_building.unassign_worker(self)
		current_building = null
		state = State.IDLE
		return
	# 偶尔动一动（微动画），不离开建筑工作范围
	if _sprite:
		var sway: float = sin(_anim_time * 3.0) * 0.03
		_sprite.rotation.z = sway

func _process_building(delta: float) -> void:
	"""🏗️ 正在建造中：在建筑旁待命，building._process 里的 builders 数组驱动加速"""
	if not is_instance_valid(build_target):
		state = State.IDLE
		build_target = null
		return
	if build_target.build_progress >= 1.0:
		# 建造完成：建筑会调 self.on_building_completed()，此处双保险
		build_target.unregister_builder(self)
		build_target = null
		state = State.IDLE
		EventBus.float_text.emit("建造完成！", global_position + Vector3(0, 3, 0), Color.GREEN)
		return
	# 农夫保持在建筑附近 + 轻微晃动（假装在挥锤）
	rotation.y = atan2(build_target.global_position.x - global_position.x,
					   build_target.global_position.z - global_position.z)
	if _sprite:
		var sway: float = sin(_anim_time * 6.0) * 0.06  # 快节奏的挥锤动画
		_sprite.rotation.z = sway

func on_building_completed() -> void:
	"""🏗️ 被 Building 在建造完成时回调"""
	if build_target and is_instance_valid(build_target):
		build_target.unregister_builder(self)
	build_target = null
	state = State.IDLE

func _process_repairing(delta: float) -> void:
	if not is_instance_valid(repair_target):
		state = State.IDLE
		return
	if not repair_target.has_method("is_damaged") or not repair_target.is_damaged():
		state = State.IDLE
		EventBus.float_text.emit("修理完成", repair_target.global_position + Vector3(0, 3, 0), Color.GREEN)
		return
	var dist: float = global_position.distance_to(repair_target.global_position)
	if dist > 2.0:
		command_move(repair_target.global_position)
		return
	# 修理速度：每秒恢复15点HP
	var repair_amount: float = 15.0 * delta
	if repair_target.has_method("repair"):
		repair_target.repair(repair_amount)

func command_garrison(building: Node) -> void:
	"""单位入驻建筑"""
	if not is_instance_valid(building) or not building.has_method("garrison"):
		return
	if not building.can_garrison:
		EventBus.float_text.emit("无法入驻", building.global_position + Vector3(0, 3, 0), Color.GRAY)
		return
	if building.get_garrison_count() >= building.garrison_cap:
		EventBus.float_text.emit("驻扎已满", building.global_position + Vector3(0, 3, 0), Color.GRAY)
		return
	garrison_building = building
	var dist: float = global_position.distance_to(building.global_position)
	if dist > 2.0:
		# 先走到建筑旁
		move_target = building.global_position
		var start_grid: Vector2i = GameManager.grid.world_to_grid(global_position)
		var end_grid: Vector2i = GameManager.grid.world_to_grid(building.global_position)
		path = GameManager.pathfinder.find_path(start_grid, end_grid)
		path_index = 0
		state = State.MOVING
		# 到达后自动入驻
	else:
		building.garrison(self)

# ============ 城墙驻防 buff ============
func set_wall_bonus(on_wall: bool, bonus: float) -> void:
	if on_wall:
		wall_atk_bonus = bonus
		wall_range_bonus = bonus * 1.5  # 射程加成更多
	else:
		wall_atk_bonus = 0.0
		wall_range_bonus = 0.0

# ============ 阵型 ============
func set_formation(fid: String) -> void:
	current_formation = fid
	match fid:
		"square":
			formation_atk_mod = 1.05; formation_def_mod = 1.2; formation_speed_mod = 0.85
		"circle":
			formation_atk_mod = 1.1; formation_def_mod = 0.95; formation_speed_mod = 1.0
		"echelon":
			formation_atk_mod = 1.25; formation_def_mod = 0.8; formation_speed_mod = 0.95
		"wedge":
			# 锋矢：骑兵突击阵，重骑兵/武将顶在最前，攻击强、防御低
			formation_atk_mod = 1.15; formation_def_mod = 0.9; formation_speed_mod = 1.05
		"line":
			# 横阵：正面展开，防骑兵绕后
			formation_atk_mod = 1.0; formation_def_mod = 1.1; formation_speed_mod = 1.0
		_:
			formation_atk_mod = 1.0; formation_def_mod = 1.0; formation_speed_mod = 1.0

# 🧺 单次携带量：基础 20，科技 40，骑马农夫最高 200
func get_carry_capacity() -> float:
	if mounted:
		return 200.0
	if GameManager.has_tech_flag(faction, "carry_40") or GameManager.get_tech_sum(faction, "carry_capacity") >= 40.0:
		return 40.0
	return 20.0

# 🍞 军粮：出征前从库存包子中领取（按人数 × 秒数用量）
func load_field_rations(seconds_per_person: float = 60.0) -> float:
	if is_general or unit_id == "peasant" or unit_id == "engineer" or unit_id == "scout":
		return 0.0
	if str(def.get("category", "")) == "civilian":
		return 0.0
	var want: float = seconds_per_person / RATION_SECONDS_PER_UNIT
	var avail: float = GameManager.get_resource(faction, "bun")
	var take: float = min(want, avail)
	if take <= 0.0:
		EventBus.float_text.emit("包子不足，无法出征", global_position + Vector3(0, 2, 0), Color.RED)
		return 0.0
	GameManager.add_resource(faction, "bun", -take)
	field_rations += take
	EventBus.float_text.emit("🍞 携带军粮 %.0f" % field_rations, global_position + Vector3(0, 2, 0), Color(1.0, 0.9, 0.4))
	return take

# 🍞 出补给圈时消耗军粮；断粮则标记 out_of_food
const RATION_SECONDS_PER_UNIT: float = 10.0
func _tick_rations(delta: float, in_zone: bool) -> void:
	if is_general or unit_id == "peasant" or unit_id == "engineer" or unit_id == "scout":
		out_of_food = false
		return
	if str(def.get("category", "")) == "civilian":
		out_of_food = false
		return
	if in_zone:
		# 回营自动补粮：从库存包子补满 60 秒用量
		out_of_food = false
		if field_rations <= 0.0:
			var need: float = 60.0 / RATION_SECONDS_PER_UNIT
			var have: float = GameManager.get_resource(faction, "bun")
			var take: float = min(need, have)
			if take > 0.0:
				GameManager.add_resource(faction, "bun", -take)
				field_rations += take
		return
	# 圈外：每 10 秒消耗 1 包子
	if field_rations > 0.0:
		_ration_accum += delta
		while _ration_accum >= RATION_SECONDS_PER_UNIT and field_rations > 0.0:
			_ration_accum -= RATION_SECONDS_PER_UNIT
			field_rations -= 1.0
		out_of_food = false
	else:
		_ration_accum = 0.0
		out_of_food = true

# 工具方法：获取阵型调整后的 move_speed（含特殊科技疾行如风、骑兵科技）
func get_effective_speed() -> float:
	var speed_mult: float = formation_speed_mod * GameManager.get_elite_tech_bonus(faction, "unit_speed_mult")
	if mounted:
		speed_mult *= GameManager.get_tech_bonus(faction, "cavalry_speed")
	return (move_speed + mount_speed_bonus) * speed_mult * _speed_buff_mult

# 工具方法：获取阵型调整后的攻击距离（含弓弩/器械射程科技）
func get_effective_range() -> float:
	var r: float = range
	# ⚔ 武将：骑马长兵再加 +0.2（读数见 config/attack_ranges.json）
	if is_general and mounted:
		r += DataLoader.get_general_mounted_range_bonus()
		r = minf(r, DataLoader.get_general_range_cap())
	var cat: String = str(def.get("category", ""))
	if cat == "ranged" or cat == "siege":
		r *= GameManager.get_tech_bonus(faction, "ranged_range")
	return r

# 工具方法：获取阵型调整后的 attack（含墙防 buff、临时增益、基础/特殊科技）
func get_effective_atk() -> float:
	var tech_mult: float = GameManager.get_tech_bonus(faction, "all_soldier_atk")
	var cat: String = str(def.get("category", ""))
	if cat == "ranged":
		tech_mult *= GameManager.get_tech_bonus(faction, "ranged_atk")
	if mounted or cat == "cavalry":
		tech_mult *= GameManager.get_tech_bonus(faction, "cavalry_atk")
	if is_siege_unit:
		tech_mult *= GameManager.get_tech_bonus(faction, "siege_atk")
	if int(def.get("tier", 1)) >= 3:
		tech_mult *= GameManager.get_tech_bonus(faction, "tier3_atk")
	# 📖 特殊科技（蜀·诸葛连弩 / 魏·虎豹骑 / 吴·水战）
	if unit_id == "trebuchet":
		tech_mult *= GameManager.get_tech_bonus(faction, "trebuchet_atk")
	if unit_id == "tiger_leopard":
		tech_mult *= GameManager.get_tech_bonus(faction, "tiger_leopard_atk")
	if unit_id == "warship":
		tech_mult *= GameManager.get_tech_bonus(faction, "warship_atk")
	if unit_id == "jinfan_jun" or _is_naval:
		tech_mult *= GameManager.get_tech_bonus(faction, "jinfan_jun_water_bonus")
	var atk_mult: float = 0.7 if out_of_food else 1.0  # 🍞 断粮攻击 −30%
	return atk * formation_atk_mod * (1.0 + wall_atk_bonus) * _atk_buff_mult * GameManager.get_elite_tech_bonus(faction, "unit_attack_mult") * tech_mult * atk_mult

# 工具方法：获取实际防御（含基础/特殊科技、治安守军、村庄任命）
func get_effective_defense() -> float:
	var def_mult: float = GameManager.get_elite_tech_bonus(faction, "unit_defense_mult")
	def_mult *= GameManager.get_tech_bonus(faction, "all_soldier_def")
	if int(def.get("tier", 1)) >= 3:
		def_mult *= GameManager.get_tech_bonus(faction, "tier3_def")
	var garrison_mult: float = 1.0
	if garrisoned:
		garrison_mult = 1.0 + GameManager.get_garrison_defense_bonus(faction)
	# 村庄武将任命防御加成
	var village_def_bonus: float = _get_village_defense_bonus()
	return defense * def_mult * garrison_mult * (1.0 + village_def_bonus)

# ===== 临时增益（带时长回收） =====
func add_atk_buff(mult: float, duration: float) -> void:
	if mult != 1.0 and duration > 0.0:
		atk_buffs.append({"mult": mult, "remain": duration})

func add_morale_buff(amt: float, duration: float) -> void:
	if amt != 0.0 and duration > 0.0:
		morale_buffs.append({"amt": amt, "remain": duration})

# ⚔ 冲锋 / 架枪状态推进
func _tick_combat_stance(delta: float) -> void:
	var moving: bool = velocity.length() > 0.05
	# ===== 架枪：枪兵静止蓄势 2 秒进入架枪 =====
	if can_brace() and not moving and state != State.ATTACKING:
		_brace_timer += delta
		if _brace_timer >= BRACE_TIME and not braced:
			braced = true
			EventBus.float_text.emit("⛏ 架枪", global_position + Vector3(0, 2, 0), Color(0.6, 0.9, 1.0))
	else:
		braced = false
		_brace_timer = 0.0
	# ===== 冲锋：静止无指令时蓄势衰减 =====
	if state == State.IDLE:
		_charge_distance = max(0.0, _charge_distance - CHARGE_DECAY_SPEED * delta)
		if _charge_distance < CHARGE_MIN_DISTANCE:
			charge_ready = false

# ===== 🌲 树林伏兵（P1-11）=====
const AMBUSH_BUFF_TIME: float = 3.0      # 出林后攻击加成持续（秒）
const AMBUSH_ATK_MULT: float = 1.2        # 出林首击 +20% 攻击
const AMBUSH_COOLDOWN: float = 10.0       # 加成冷却（秒）
const AMBUSH_REVEAL_RANGE: float = 4.0    # 林内被贴脸到该距离会被发现

var in_forest: bool = false
var _ambush_cd: float = 0.0
var _terrain_check_timer: float = 0.0

## 敌方视角：林内且没人贴脸 → 视为隐形（FogOfWar 每帧读取）
func is_hidden_in_forest() -> bool:
	if not in_forest:
		return false
	return not _enemy_within(AMBUSH_REVEAL_RANGE)

func _enemy_within(r: float) -> bool:
	for u in GameManager.all_units:
		if not is_instance_valid(u):
			continue
		if u.get_faction() == faction:
			continue
		if "hp" in u and float(u.hp) <= 0.0:
			continue
		if u.global_position.distance_to(global_position) <= r:
			return true
	return false

func _tick_ambush(delta: float) -> void:
	if _ambush_cd > 0.0:
		_ambush_cd = max(0.0, _ambush_cd - delta)
	_terrain_check_timer -= delta
	if _terrain_check_timer > 0.0:
		return
	_terrain_check_timer = 0.3
	var now_forest: bool = false
	if Terrain != null and Terrain.has_method("is_forest"):
		now_forest = Terrain.is_forest(global_position.x, global_position.z)
	var was_forest: bool = in_forest
	in_forest = now_forest
	# 出林瞬间：3 秒 +20% 攻击（10 秒冷却）
	# 敌人在原地就有视野（贴脸）则伏兵失败，不给加成
	if was_forest and not now_forest and _ambush_cd <= 0.0:
		_on_leave_forest()

## 离开树林的瞬间结算伏兵（探针直接调用）
func _on_leave_forest() -> bool:
	if _ambush_cd > 0.0:
		return false
	if _enemy_within(AMBUSH_REVEAL_RANGE + 4.0):
		return false
	_ambush_cd = AMBUSH_COOLDOWN
	add_atk_buff(AMBUSH_ATK_MULT, AMBUSH_BUFF_TIME)
	EventBus.float_text.emit("🌲 伏兵突击 +20%!", global_position + Vector3(0, 3, 0), Color(0.5, 1.0, 0.5))
	return true

## 视野半径（斥候 18 格，普通 10 格；骑乘 +2）
func get_vision_range() -> float:
	var v: float = float(def.get("vision_range", 10.0))
	if mounted:
		v += 2.0
	v *= GameManager.get_tech_bonus(faction, "soldier_vision")
	return v

## 是否重骑兵/重甲（阵型前排用）
func is_heavy_unit() -> bool:
	return bool(def.get("heavy", false))

## 阵型编排优先级：越小越靠前（重骑兵与武将在最前）
func get_formation_rank() -> int:
	if is_general:
		return 0
	var cat: String = str(def.get("category", ""))
	if cat == "cavalry":
		return 1 if is_heavy_unit() else 2
	match cat:
		"infantry":
			return 3
		"ranged":
			return 4
		"siege":
			return 5
		_:
			return 6

## 累积冲锋蓄势距离（仅骑兵生效）
func add_charge_distance(dist: float) -> void:
	if not is_cavalry_unit():
		return
	_charge_distance += dist
	if _charge_distance >= CHARGE_MIN_DISTANCE and not charge_ready:
		charge_ready = true

## 是否骑兵（天生骑兵或骑乘单位）
func is_cavalry_unit() -> bool:
	return str(def.get("category", "")) == "cavalry" or mounted

## 是否可架枪（只有枪兵类长枪步兵，且未骑马）
func can_brace() -> bool:
	if mounted or str(def.get("category", "")) != "infantry":
		return false
	# 显式配置优先：units.json 里 brace=true 的才是枪兵（枪兵/金枪兵/御林枪…）
	if def.has("brace"):
		return bool(def.get("brace", false))
	return "cavalry" in def.get("counters", [])

func _tick_buffs(delta: float) -> void:
	if atk_buffs.is_empty():
		_atk_buff_mult = 1.0
	else:
		_atk_buff_mult = 1.0
		var i: int = 0
		while i < atk_buffs.size():
			atk_buffs[i]["remain"] -= delta
			if atk_buffs[i]["remain"] <= 0.0:
				atk_buffs.remove_at(i)
			else:
				_atk_buff_mult *= atk_buffs[i]["mult"]
				i += 1
	# 士气增益：仅移除过期项（实时求和，无需缓存）
	if not morale_buffs.is_empty():
		var j: int = 0
		while j < morale_buffs.size():
			morale_buffs[j]["remain"] -= delta
			if morale_buffs[j]["remain"] <= 0.0:
				morale_buffs.remove_at(j)
	# 体力恢复增益（村庄购买等）
	if not stamina_buffs.is_empty():
		var k: int = 0
		while k < stamina_buffs.size():
			stamina_buffs[k]["remain"] -= delta
			if stamina_buffs[k]["remain"] <= 0.0:
				stamina_buffs.remove_at(k)
			else:
				stamina = min(100.0, stamina + stamina_buffs[k]["rate"] * delta)
				k += 1
	# 🎯 技能增益：移速 / 攻速 / 穿甲 / 持续回血 / 无敌与养气计时
	_speed_buff_mult = _tick_mult_buffs(speed_buffs, delta)
	_atk_speed_buff_mult = _tick_mult_buffs(atk_speed_buffs, delta)
	_armor_pen_buff = _tick_add_buffs(armor_pen_buffs, delta)
	if not hp_regen_buffs.is_empty():
		var h: int = 0
		while h < hp_regen_buffs.size():
			hp_regen_buffs[h]["remain"] -= delta
			if hp_regen_buffs[h]["remain"] <= 0.0:
				hp_regen_buffs.remove_at(h)
			else:
				if hp > 0.0:
					hp = min(max_hp, hp + float(hp_regen_buffs[h]["rate"]) * delta)
				h += 1
	invuln_timer = maxf(0.0, invuln_timer - delta)
	no_drain_timer = maxf(0.0, no_drain_timer - delta)

func _tick_mult_buffs(arr: Array, delta: float) -> float:
	var mult: float = 1.0
	var i: int = 0
	while i < arr.size():
		arr[i]["remain"] -= delta
		if arr[i]["remain"] <= 0.0:
			arr.remove_at(i)
		else:
			mult *= float(arr[i]["mult"])
			i += 1
	return mult

func _tick_add_buffs(arr: Array, delta: float) -> float:
	var total: float = 0.0
	var i: int = 0
	while i < arr.size():
		arr[i]["remain"] -= delta
		if arr[i]["remain"] <= 0.0:
			arr.remove_at(i)
		else:
			total += float(arr[i]["add"])
			i += 1
	return total

# ===== 🎯 P1-23 技能系统对外接口（General 调用） =====
func apply_stun(seconds: float) -> void:
	if seconds > 0.0:
		stun_timer = maxf(stun_timer, seconds)

func apply_invuln(seconds: float) -> void:
	if seconds > 0.0:
		invuln_timer = maxf(invuln_timer, seconds)

func apply_no_drain(seconds: float) -> void:
	if seconds > 0.0:
		no_drain_timer = maxf(no_drain_timer, seconds)

func add_speed_buff(mult: float, duration: float) -> void:
	if mult != 1.0 and duration > 0.0:
		speed_buffs.append({"mult": mult, "remain": duration})

func add_atk_speed_buff(mult: float, duration: float) -> void:
	if mult != 1.0 and duration > 0.0:
		atk_speed_buffs.append({"mult": mult, "remain": duration})

func add_armor_pen_buff(add: float, duration: float) -> void:
	if add > 0.0 and duration > 0.0:
		armor_pen_buffs.append({"add": add, "remain": duration})

func add_hp_regen(rate: float, duration: float) -> void:
	if rate > 0.0 and duration > 0.0:
		hp_regen_buffs.append({"rate": rate, "remain": duration})

func is_stunned() -> bool:
	return stun_timer > 0.0

func _morale_with_buffs() -> float:
	var m: float = morale
	for b in morale_buffs:
		m += b["amt"]
	return clamp(m, 0.0, 100.0)

func get_unit_id() -> String:
	return unit_id

func get_supply_in_zone() -> bool:
	"""是否在补给区内（供 GameManager 通用消耗统计）"""
	return supply_state.get("in_zone", false)

# ============ 补给区两级模型（对标傲世三国） ============

func _on_ally_died(victim) -> void:
	"""🏷 附近友军阵亡 → 士气惩罚（config/combat.json → morale.friendly_death_penalty）
	旧版另有 0.5s 扫描（_has_friendly_death_nearby），与信号重复计数，已删除。"""
	if victim == null or not is_instance_valid(victim):
		return
	if victim.get_faction() != faction:
		return
	if no_morale:
		return
	var mc: Dictionary = _morale_conf()
	if global_position.distance_to(victim.global_position) <= float(mc.get("friendly_death_radius", 8.0)):
		morale = max(0.0, morale - float(mc.get("friendly_death_penalty", 4.0)))

func _count_nearby_friends(radius: float) -> int:
	var count: int = 0
	for u in GameManager.all_units:
		if not is_instance_valid(u) or u == self:
			continue
		if not u.has_method("get_faction") or u.get_faction() != faction:
			continue
		if global_position.distance_to(u.global_position) <= radius:
			count += 1
	return count

func _update_supply_state() -> void:
	"""0.5秒缓存一次补给区状态

	V3 补给圈四档（2026-10-26 用户定稿）：
	  · 城池（官府 + 城墙内圈）→ 恢复 +2/s
	  · 村庄                    → 恢复 +2/s
	  · 营帐/据点               → 恢复 +4/s（加速）
	  · 辎重车旁                → 只"保持不降"，不回体力
	"""
	_supply_timer = 0.5
	var st: Dictionary = _stamina_conf()
	var best_rate: float = 0.0
	var zone_type: String = ""
	var zone_source: Node = null
	var cart_near: Node = null

	# 1. 城池补给区（官府为中心，半径=city_radius+20外延）
	var gov: Node = _find_government_building(faction)
	if gov != null and is_instance_valid(gov):
		var city_radius: float = _calc_city_radius(faction)
		var dist: float = global_position.distance_to(gov.global_position)
		if dist <= city_radius + 20.0:
			best_rate = maxf(best_rate, float(st.get("recover_city", 2.0)))
			zone_type = "city"
			zone_source = gov

	# 2. 村庄（1/2/3级半径10/12/14）
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
		# 📖 科技：村庄补给范围 +2 格
		v_radius += GameManager.get_tech_sum(faction, "village_supply_range")
		if global_position.distance_to(v.global_position) <= v_radius:
			var vr: float = float(st.get("recover_village", 2.0))
			if vr > best_rate:
				best_rate = vr
				zone_type = "village"
				zone_source = v
			break

	# 3. 野外补给建筑（营帐 +4/s，仓库等 +2/s），取更高的一档
	for b in GameManager.all_buildings:
		if not is_instance_valid(b) or b.faction != faction:
			continue
		var sr: float = float(b.def.get("supply_radius", 0.0))
		if sr <= 0.0:
			continue
		if global_position.distance_to(b.global_position) > sr:
			continue
		var br: float = float(b.def.get("stamina_recover", st.get("recover_building", 2.0)))
		if br > best_rate:
			best_rate = br
			zone_type = b.building_id
			zone_source = b

	# 4. 辎重车（移动补给点）：身边体力不降，但也回不了多少
	if cart_near == null:
		for u in GameManager.all_units:
			if not is_instance_valid(u) or u == self:
				continue
			if not u.has_method("is_camped"):
				continue
			# SupplyCart 的库存字段是 bun / wine（旧代码误写成 u.food，会直接报错）
			if u.faction != faction or float(u.bun) <= 0.0:
				continue
			if global_position.distance_to(u.global_position) <= u.aura_radius:
				cart_near = u
				break

	var mode: String = "none"
	if best_rate > 0.0:
		mode = "recover"
	elif cart_near != null:
		mode = "hold"
	var in_zone: bool = mode != "none"

	supply_state = {
		"in_zone": in_zone,
		"mode": mode,
		"recover_rate": best_rate,
		"zone_type": zone_type,
		"zone_source": zone_source,
		"cart": cart_near,
		"has_wine": in_zone,
		"has_bun": in_zone
	}

func _find_government_building(fid: String) -> Node:
	for b in GameManager.all_buildings:
		if is_instance_valid(b) and b.faction == fid and b.building_id == "government":
			return b
	return null

func _calc_city_radius(fid: String) -> float:
	var gov: Node = _find_government_building(fid)
	if gov == null:
		return 15.0
	var max_dist: float = 15.0
	for b in GameManager.all_buildings:
		if is_instance_valid(b) and b.faction == fid and b.building_id.begins_with("wall_"):
			var d: float = gov.global_position.distance_to(b.global_position)
			if d > max_dist:
				max_dist = d
	return max_dist

func _has_village_military_commander() -> bool:
	"""检查是否在拥有武将任命的村庄范围内"""
	for v in GameManager.villages:
		if not is_instance_valid(v):
			continue
		if v.village_owner != faction:
			continue
		if v.appointed_military == null or not is_instance_valid(v.appointed_military):
			continue
		var v_radius: float = 10.0
		if v.level == 2:
			v_radius = 12.0
		elif v.level >= 3:
			v_radius = 14.0
		if global_position.distance_to(v.global_position) <= v_radius:
			return true
	return false

# ============ 体力→攻速惩罚曲线（V2：体力0攻速减半CD×2.0） ============

func stamina_to_speed_penalty(stam: float) -> float:
	"""
	V2规则：体力0时攻速减半（攻击延迟×2.0）
	80-100: 无惩罚 (倍率1.0)
	50-80: 0→0.15 插值 (0.85→1.0倍率)
	30-50: 0.15→0.30 插值 (0.70→0.85倍率)
	0-30: 0.30→0.50 插值 (0.50→0.70倍率)
	公式: final_atk_speed = base_atk_speed * (1 - stamina_penalty)
	体力0时 penalty=0.50 → 攻速×0.5 → CD×2.0
	"""
	if stam >= 80.0:
		return 0.0
	elif stam >= 50.0:
		return lerp(0.0, 0.15, (80.0 - stam) / 30.0)
	elif stam >= 30.0:
		return lerp(0.15, 0.30, (50.0 - stam) / 20.0)
	else:
		return lerp(0.30, 0.50, (30.0 - stam) / 30.0)

func _get_village_defense_bonus() -> float:
	"""获取村庄武将任命的防御加成：+15%×武力/100"""
	for v in GameManager.villages:
		if not is_instance_valid(v):
			continue
		if v.village_owner != faction:
			continue
		if v.appointed_military == null or not is_instance_valid(v.appointed_military):
			continue
		var v_radius: float = 10.0
		if v.level == 2:
			v_radius = 12.0
		elif v.level >= 3:
			v_radius = 14.0
		if global_position.distance_to(v.global_position) <= v_radius:
			var might: float = float(v.appointed_military.stats.get("might", 50.0))
			return 0.15 * might / 100.0
	return 0.0

# ============ 体力/士气模型（补给圈四档 · V3） ============

func _stamina_conf() -> Dictionary:
	return DataLoader.logistics.get("stamina", {})

func _tick_stamina(delta: float) -> void:
	"""
	V3 体力模型（2026-10-26 用户定稿）：体力**只随时间变化**，攻击/移动/建造都不额外扣。

	补给圈内（体力只升不降）：
	  · 城池内城 / 村庄      → +2.0 /s
	  · 营帐（据点）         → +4.0 /s（加速恢复）
	辎重车旁：mode = hold → 体力**保持不动**（不降也不回）

	圈外（纯时间衰减，数值见 config/logistics.json → stamina）：
	  · 基础 0.06/s（100→0 约 28 分钟），低于 50 时 0.09/s
	  · 小队(≤4)×0.7、大队(>15)×1.25、拥挤(>20)×1.25
	  · 断粮只额外 +0.10/s（旧版 -3/s 太快，已废弃）
	"""
	if is_general:
		# 🎖 满级武将（Lv9）体力自动回满（傲世三国九级特色，config/generals.json → level_curve.nine_bonus）
		if level >= 9 and stamina < 100.0:
			stamina = minf(100.0, stamina + 2.0 * delta)
		return
	if unit_id == "peasant":
		return
	# 🎯 养气：期间体力不掉
	if no_drain_timer > 0.0:
		return

	_supply_timer -= delta
	if _supply_timer <= 0.0:
		_update_supply_state()

	var st: Dictionary = _stamina_conf()
	var in_zone: bool = supply_state.get("in_zone", false)
	var mode: String = str(supply_state.get("mode", "none"))
	var nearby: int = _count_nearby_friends(6.0)
	var starving: bool = GameManager.is_faction_starving(faction)
	var crowded: bool = nearby > 20
	# 🍞 军粮：圈外消耗出征携带的包子，断粮则标记 out_of_food
	_tick_rations(delta, in_zone)

	# ===== 体力 =====
	if mode == "recover":
		var rate: float = float(supply_state.get("recover_rate", st.get("recover_building", 2.0)))
		stamina = min(100.0, stamina + rate * GameManager.get_tech_bonus(faction, "stamina_recover") * delta)
	elif mode == "hold":
		pass  # 🚚 辎重车旁：体力冻结，不降不回
	else:
		var low_line: float = float(st.get("drain_low_threshold", 50.0))
		var drain: float = float(st.get("drain_outside", 0.06)) if stamina > low_line \
			else float(st.get("drain_outside_low", 0.09))
		# 小部队骚扰体力掉得慢，大部队开拔掉得快
		if nearby <= 4:
			drain *= float(st.get("small_party_mult", 0.7))
		elif nearby > 15:
			drain *= float(st.get("large_party_mult", 1.25))
		if crowded:
			drain *= float(st.get("crowd_mult", 1.25))
		# 🍞 断粮：轻微加速流失（不再是 -3/s）
		if out_of_food:
			drain += float(st.get("starving_extra_drain", 0.10))
		# 📖 科技：体力消耗降低
		drain *= GameManager.get_tech_reduction(faction, "stamina_drain_reduction")
		stamina = max(0.0, stamina - drain * delta)
	
	# ===== 🍶 酒=回血（与士气无关）=====
	_tick_wine_heal(delta, str(supply_state.get("mode", "none")))
	# ===== 士气（独立条，不消耗酒）=====
	_tick_morale(delta, in_zone, nearby, starving)

func _morale_conf() -> Dictionary:
	return DataLoader.combat.get("morale", {})

func _wine_conf() -> Dictionary:
	return DataLoader.combat.get("wine_heal", {})

func _tick_morale(delta: float, in_zone: bool, nearby: int, starving: bool) -> void:
	"""
	🎖 士气模型（2026-10-27 对标定稿）：士气与酒完全无关——酒只回血、包子只回体力。

	增加：补给圈内 +2/s（免费）｜击杀 +3（附近友军 +1）｜寺庙祭祀 +15（60s）｜驻村庄武将不掉
	降低：圈外 -0.05/s ｜交战中再 -0.15/s ｜断粮再 -0.2/s ｜友军阵亡 -4 ｜被伏击 -10
	"""
	var mc: Dictionary = _morale_conf()
	var max_m: float = float(mc.get("max", 100.0))
	if no_morale:
		return
	if in_zone:
		if morale < max_m:
			var regen: float = float(mc.get("zone_recover_per_sec", 2.0))
			regen *= GameManager.get_tech_bonus(faction, "morale_recover")
			morale = minf(max_m, morale + regen * delta)
	else:
		var mdrain: float = float(mc.get("decay_outside_per_sec", 0.05))
		if state == State.ATTACKING:
			mdrain += float(mc.get("combat_extra_decay_per_sec", 0.15))
		if starving:
			mdrain += float(mc.get("famine_decay_per_sec", 0.2))
		# 人越多越互相支撑（消耗分摊）
		if nearby > 0:
			mdrain /= (1.0 + float(mc.get("crowd_support_divisor", 0.08)) * float(nearby))
		# 村庄驻军（武将任命）士气不掉
		if bool(mc.get("village_commander_no_decay", true)) and _has_village_military_commander():
			mdrain = 0.0
		morale = max(0.0, morale - mdrain * delta)

func _tick_wine_heal(delta: float, mode: String) -> void:
	"""🍶 酒=回血：1 酒 ≈ 25 HP；补给圈内（含辎重车旁）自动饮酒，圈外默认不回血"""
	if hp <= 0.0 or hp >= max_hp:
		return
	var wc: Dictionary = _wine_conf()
	var rate: float = 0.0
	if mode == "recover":
		rate = float(wc.get("zone_rate", 2.0))
	elif mode == "hold":
		rate = float(wc.get("cart_rate", 2.0))
	else:
		rate = float(wc.get("field_rate", 0.0))
	if rate <= 0.0:
		return
	var heal: float = minf(max_hp - hp, rate * delta)
	var per_wine: float = maxf(1.0, float(wc.get("hp_per_wine", 25.0)))
	var cost: float = heal / per_wine
	if GameManager.get_resource(faction, "wine") < cost:
		return
	GameManager.add_resource(faction, "wine", -cost)
	hp = minf(max_hp, hp + heal)

func _give_allies_morale(amt: float, radius: float) -> void:
	if amt <= 0.0:
		return
	for u in GameManager.all_units:
		if not is_instance_valid(u) or u == self:
			continue
		if not u.has_method("get_faction") or u.get_faction() != faction:
			continue
		if global_position.distance_to(u.global_position) <= radius:
			u.morale = minf(100.0, float(u.morale) + amt)

# ======================================================================
# V2：士兵升级系统（9级，经验从 units.json 读，删除硬编码表）
# ======================================================================

func _get_unit_xp_to_next(lvl: int) -> float:
	"""从 units.json level_curve 读取升级经验，兼容旧硬编码表作为 fallback"""
	var lc: Dictionary = DataLoader.level_curve
	if not lc.is_empty():
		var key: String = "%d_to_%d" % [lvl, lvl + 1]
		if lc.has(key):
			var v = lc[key]
			if typeof(v) == TYPE_DICTIONARY:
				return float(v.get("exp", 100))
			return float(v)
	# Fallback：旧硬编码表（已废弃，仅用于 JSON 加载失败时）
	var fallback: Array = [120, 140, 160, 180, 200, 230, 260, 300]
	var idx: int = clampi(lvl - 1, 0, fallback.size() - 1)
	return float(fallback[idx])

func add_exp(amount: float) -> void:
	# 📖 科技：练兵有方 +25% 经验
	var xp_amount: float = amount * GameManager.get_tech_bonus(faction, "exp_gain")
	exp += xp_amount * GameManager.get_elite_tech_bonus(faction, "unit_xp_mult")
	# 🔥 v4 农夫等级：1-5 级，每级 +5 HP + 采集效率+10%
	if unit_id == "peasant":
		# 农夫独立等级（用一个 meta 存，不占用士兵 level）
		var p_level: int = get_meta("peasant_level", 1)
		var p_exp: float = get_meta("peasant_exp", 0.0)
		p_exp += xp_amount
		var p_need: float = 50.0 * float(p_level)  # Lv1→2 需50, Lv2→3 需100 ...
		while p_exp >= p_need and p_level < 5:
			p_exp -= p_need
			p_level += 1
			max_hp += 5.0  # +5 HP
			hp = max_hp
			EventBus.float_text.emit("🪓 农夫升 Lv%d! +5HP +采效率" % p_level, global_position + Vector3(0, 4, 0), Color.CYAN)
			p_need = 50.0 * float(p_level)
		set_meta("peasant_level", p_level)
		set_meta("peasant_exp", p_exp)
		return  # 农夫不走士兵升级链
	while level < max_level:
		var need: float = _get_unit_xp_to_next(level)
		if exp < need:
			break
		exp -= need
		level += 1
		# V2成长：HP+5%/攻+3%/防+2%/攻速+5%（移速不变）
		var hp_growth: float = 0.05
		var atk_growth: float = 0.03
		var def_growth: float = 0.02
		var spd_growth: float = 0.05
		max_hp *= (1.0 + hp_growth)
		atk *= (1.0 + atk_growth)
		defense *= (1.0 + def_growth)
		atk_speed *= (1.0 + spd_growth)
		# 升级恢复全部体力/士气，血量恢复30%
		hp = min(max_hp, hp + max_hp * 0.3)
		stamina = 100.0
		morale = 100.0
		print("[Unit] %s(%s) 升级到 Lv%d！HP×%.0f%% 攻×%.0f%% 防×%.0f%% 攻速×%.0f%%，体力/士气全满" % [
			unit_id, name, level,
			(1+hp_growth)*100, (1+atk_growth)*100, (1+def_growth)*100, (1+spd_growth)*100])
		if level == 5 and not is_general:
			EventBus.float_text.emit("🎖️ Lv5!", global_position + Vector3(0, 3, 0), Color.YELLOW)
		# 🎖️ 5 级 30% / 6 级 60% / 7 级 100% 自动晋升武将（晋升后本体会被释放，必须立即返回）
		if not is_general and level >= 5 and level <= 7:
			if _try_auto_promote():
				return

## 达到晋升等级时按概率自动晋升；返回是否晋升成功
func _try_auto_promote() -> bool:
	var chance: float = 0.0
	match level:
		5: chance = 0.30
		6: chance = 0.60
		7: chance = 1.0
		_:
			return false
	if randf() > chance:
		print("[晋升] %s Lv%d 晋升判定失败（概率 %.0f%%），可去点将台手动晋升" % [unit_id, level, chance * 100.0])
		return false
	return promote_to_general() != null

func can_promote_to_general() -> bool:
	"""Lv5+ 的士兵可晋升为武将"""
	return level >= 5 and not is_general

func promote_to_general() -> Node:
	"""晋升武将：随机类型，等级降 2（最低 1），保留杀敌成长，赠 1 通用武将技"""
	if not can_promote_to_general():
		return null
	# 随机武将类型
	var classes: Array = ["warrior", "defense", "assault", "strategist", "trickster"]
	var cls: String = classes[randi() % classes.size()]
	var scene: PackedScene = load("res://scenes/General.tscn")
	if scene == null:
		return null
	var gen = scene.instantiate()
	gen.general_class = cls
	gen.solo_duel_enabled = false  # 默认关
	gen.talent_points = 1  # 晋升奖励 1 天赋点
	gen.faction = faction
	# 🎖️ 晋升后等级 -2（最低 1）
	var new_level: int = max(1, level - 2)
	gen.unit_id = "general_promoted_%s" % cls
	# 先入树，再设属性（避免 _ready 默认值覆盖）
	GameManager.add_child(gen)
	gen.global_position = global_position
	gen.level = new_level
	# 基础属性：从士兵继承 + 类型偏向
	gen.stats["might"] = clamp(float(atk) * 3.0 + randf_range(0, 10), 50.0, 85.0)
	gen.stats["intelligence"] = randf_range(40.0, 70.0)
	gen.stats["command"] = clamp(float(defense) * 5.0 + randf_range(0, 8), 45.0, 80.0)
	gen.stats["politics"] = randf_range(30.0, 60.0)
	# 类型系数（与 General._init_general 保持一致的量纲）
	var cls_mult: Dictionary = {
		"warrior": {"hp_mult": 1.15, "atk_mult": 1.15, "def_mult": 1.0},
		"defense": {"hp_mult": 1.30, "atk_mult": 0.90, "def_mult": 1.30},
		"assault": {"hp_mult": 1.05, "atk_mult": 1.20, "def_mult": 0.90},
		"strategist": {"hp_mult": 0.85, "atk_mult": 0.75, "def_mult": 0.75},
		"trickster": {"hp_mult": 1.00, "atk_mult": 1.05, "def_mult": 0.95}
	}
	var cm: Dictionary = cls_mult.get(cls, cls_mult["warrior"])
	var might: float = float(gen.stats["might"])
	# 🩸 晋升武将血量：Lv1 500+ → Lv9 2000（config/generals.json → promoted_hp）
	var prom: Dictionary = DataLoader.generals.get("promoted_hp", {})
	var pm: float = float(prom.get("class_mult", {}).get(cls, 1.0))
	gen.hp_lv1_base = float(prom.get("lv1_base", 500.0)) * pm
	gen.hp_lv9_base = float(prom.get("lv9_base", 2000.0)) * pm
	gen.hp_growth_rate = pow(gen.hp_lv9_base / maxf(gen.hp_lv1_base, 1.0), 1.0 / 8.0)
	gen.max_hp = gen.hp_lv1_base * pow(gen.hp_growth_rate, float(new_level - 1))
	gen.atk = (25.0 + new_level * 2.0) * float(cm.get("atk_mult", 1.0)) * (1.0 + (might - 70.0) * 0.005)
	gen.defense = (10.0 + new_level * 1.5) * float(cm.get("def_mult", 1.0))
	gen.move_speed = 2.6 + (might - 70.0) * 0.005 + (0.4 if cls == "assault" else 0.0)
	gen.max_mp = 80 + int(float(gen.stats["intelligence"]) * 0.3)
	gen.hp = gen.max_hp
	gen.stamina = 100.0
	gen.morale = 100.0
	# ⚔ 保留杀敌成长
	gen.kills = kills
	gen.veteran_atk_bonus = veteran_atk_bonus
	# 🎖️ 授予 3 个基础技（本类型池优先，不足从通用池补）+ 1 个带兵被动（config/generals.json → promote）
	var pc: Dictionary = DataLoader.generals.get("promote", {})
	var want: int = int(pc.get("skill_count", 3))
	var class_pool: Array = pc.get("class_skill_pool", {}).get(cls, [])
	var fill_pool: Array = pc.get("common_fill", [])
	var picked: Array = []
	for sid in class_pool:
		if picked.size() >= want:
			break
		if not picked.has(sid):
			picked.append(sid)
	var fi: int = 0
	while picked.size() < want and fi < fill_pool.size():
		var sid2: String = str(fill_pool[(randi() + fi) % fill_pool.size()])
		if not picked.has(sid2):
			picked.append(sid2)
		fi += 1
	gen.equipped_skills = []
	for sid3 in picked:
		gen.equipped_skills.append({"skill_id": sid3, "level": 1})
	var passive_pool: Dictionary = DataLoader.generals.get("passive_pool", {})
	var pkeys: Array = []
	for pk in passive_pool.keys():
		if not str(pk).begins_with("_"):
			pkeys.append(pk)
	if not pkeys.is_empty():
		gen.passive_skills = [str(pkeys[randi() % pkeys.size()])]
	# 被动在晋升后才写入，需手动补乘一次（_ready 时还读的是默认名将配置）
	var pe: Dictionary = gen.get_passive_effects()
	if not pe.is_empty():
		gen.max_hp *= 1.0 + float(pe.get("hp_mult", 0.0))
		gen.atk *= 1.0 + float(pe.get("atk_mult", 0.0))
		gen.defense *= 1.0 + float(pe.get("def_mult", 0.0))
		gen.move_speed *= 1.0 + float(pe.get("speed_mult", 0.0))
		gen.atk_speed *= 1.0 + float(pe.get("atk_speed_mult", 0.0))
		gen.max_mp += float(pe.get("mp_add", 0.0))
		gen.hp = gen.max_hp
	print("[晋升] 🎖️ %s Lv%d → 武将(%s) Lv%d，武力%.0f" % [unit_id, level, cls, new_level, gen.stats.get("might", 50.0)])
	EventBus.float_text.emit("🎖️ 晋升武将！Lv%d" % new_level, global_position + Vector3(0, 4, 0), Color.YELLOW)
	queue_free()
	return gen

# ======================================================================
# 🎯 设计 v3：士兵无暴击（武将有暴击，靠武力挂钩）
# ======================================================================

# ======================================================================
# 🎯 设计 v3：基类四维/暴击/战斗状态（供 General 覆盖）
# 士兵无暴击（get_crit_chance 恒为 0），无青龙偃月
# ======================================================================
var stats: Dictionary = {"might": 60.0, "intelligence": 40.0, "command": 50.0, "politics": 40.0}

func get_crit_chance() -> float:
	return 0.0

func has_qinglongyanyue() -> bool:
	return false

func get_qinglong_level() -> int:
	return 0

func is_in_combat() -> bool:
	return is_instance_valid(attack_target)

# 士兵攻击伤害计算
func calc_soldier_attack_damage() -> float:
	var base: float = get_effective_atk() * (1.0 + veteran_atk_bonus)
	# 士兵永远不暴击，正常伤害
	return base

# 武将攻击伤害计算（有暴击）
func calc_general_attack_damage() -> float:
	if not is_general:
		return calc_soldier_attack_damage()
	var base: float = get_effective_atk() * (1.0 + veteran_atk_bonus)
	var crit_rate: float = get_crit_chance() if has_method("get_crit_chance") else 0.0
	if randf() < crit_rate:
		var crit_mult: float = GameManager.calc_crit_damage(1.0, stats.get("might", 70.0), has_qinglongyanyue() if has_method("has_qinglongyanyue") else false, get_qinglong_level() if has_method("get_qinglong_level") else 0)
		print("[暴击] 💥 %s 暴击！%.0fx 伤害" % [name, crit_mult])
		EventBus.float_text.emit("💥 暴击！", global_position + Vector3(0, 3, 0), Color.ORANGE)
		return base * crit_mult
	return base

# 简化版：get_effective_damage
func get_effective_damage() -> float:
	return calc_general_attack_damage()

# ==================== 📦 存档序列化 ====================

## 统一的读档入口：MapSaveManager 只负责"建节点 + 挂 parent + 摆位置"，
## 所有字段恢复都在这里做，避免过去"Unit.deserialize 一套、MapSaveManager 又一套"的双写。
func apply_save_data(d: Dictionary) -> void:
	behavior_mode = int(d.get("behavior_mode", behavior_mode))
	state = int(d.get("state", state))
	level = int(d.get("level", 1))
	exp = float(d.get("exp", 0.0))
	kills = int(d.get("kills", 0))
	veteran_atk_bonus = float(d.get("veteran_atk_bonus", 0.0))
	stamina = float(d.get("stamina", 100.0))
	morale = float(d.get("morale", 60.0))
	max_hp = float(d.get("max_hp", max_hp))
	hp = float(d.get("hp", max_hp))
	mounted = bool(d.get("mounted", false))
	var formation: String = str(d.get("formation", ""))
	if formation != "" and has_method("set_formation"):
		set_formation(formation)
	# 🍞 军粮 / 断粮 / 马匹 / 坚守 / 伏兵
	field_rations = float(d.get("field_rations", 0.0))
	_ration_accum = float(d.get("ration_accum", 0.0))
	out_of_food = bool(d.get("out_of_food", false))
	horse_tier = int(d.get("horse_tier", 1))
	in_forest = bool(d.get("in_forest", false))
	_ambush_cd = float(d.get("ambush_cd", 0.0))
	var hp_pos: Dictionary = d.get("hold_position", {})
	hold_position = Vector3(
		float(hp_pos.get("x", 0.0)), float(hp_pos.get("y", 0.0)), float(hp_pos.get("z", 0.0)))
	if unit_id == "peasant":
		set_meta("peasant_level", int(d.get("peasant_level", 1)))
		set_meta("peasant_exp", float(d.get("peasant_exp", 0.0)))
	# 关系重挂信息（等所有实体恢复后由 MapSaveManager._reattach_relations 统一挂接）
	var wg = d.get("work_grid", null)
	if typeof(wg) == TYPE_DICTIONARY:
		set_meta("restore_work_grid", Vector2i(int(wg.get("x", -1)), int(wg.get("y", -1))))
		set_meta("restore_work_train", float(d.get("work_train_left", -1.0)))
	var gg = d.get("garrison_grid", null)
	if typeof(gg) == TYPE_DICTIONARY:
		set_meta("restore_garrison_grid", Vector2i(int(gg.get("x", -1)), int(gg.get("y", -1))))
	if is_general and has_method("apply_general_data"):
		call("apply_general_data", d)
	# 🐎 骑乘单位需要重建马 mesh（mesh 不进存档）
	if mounted and has_method("refresh_mount_visual"):
		refresh_mount_visual()

func serialize() -> Dictionary:
	var d: Dictionary = {}
	d["type"] = "unit"
	d["unit_id"] = unit_id
	d["faction"] = faction
	d["pos"] = {"x": global_position.x, "y": global_position.y, "z": global_position.z}
	d["hp"] = hp
	d["max_hp"] = max_hp
	d["state"] = state
	d["behavior_mode"] = behavior_mode
	d["is_general"] = is_general
	# 💾 战斗/成长状态（读档后经验体力士气不丢）
	d["level"] = level
	d["exp"] = exp
	d["kills"] = kills
	d["veteran_atk_bonus"] = veteran_atk_bonus
	d["stamina"] = stamina
	d["morale"] = morale
	d["mounted"] = mounted
	d["formation"] = current_formation
	# 🍞 军粮 / 断粮 / 马匹等级 / 坚守驻点 / 伏兵状态（此前漏存，读档会丢）
	d["field_rations"] = field_rations
	d["ration_accum"] = _ration_accum
	d["out_of_food"] = out_of_food
	d["horse_tier"] = horse_tier
	d["hold_position"] = {"x": hold_position.x, "y": hold_position.y, "z": hold_position.z}
	d["in_forest"] = in_forest
	d["ambush_cd"] = _ambush_cd
	if unit_id == "peasant":
		d["peasant_level"] = int(get_meta("peasant_level", 1))
		d["peasant_exp"] = float(get_meta("peasant_exp", 0.0))
	# 💾 在岗/驻防关系（读档时由 MapSaveManager 重新挂接）
	if is_instance_valid(current_building) and current_building is Node:
		d["work_grid"] = {"x": current_building.grid_pos.x, "y": current_building.grid_pos.y}
		if current_building.get("_worker_training") != null:
			d["work_train_left"] = float(current_building._worker_training.get(get_instance_id(), -1.0))
	if is_instance_valid(garrison_building) and garrison_building is Node:
		d["garrison_grid"] = {"x": garrison_building.grid_pos.x, "y": garrison_building.grid_pos.y}
	if is_general:
		# 🔥 用 duck-type get() 读 General.gd 属性（Unit.gd extends CharacterBody3D 没有这些字段）
		d["general_id"] = get("general_id") if get("general_id") != null else ""
		d["general_class"] = get("general_class") if get("general_class") != null else "warrior"
		d["level"] = int(get("level")) if get("level") != null else 1
		d["xp"] = float(get("xp")) if get("xp") != null else 0.0
		d["mp"] = float(get("mp")) if get("mp") != null else 0.0
		d["talent_points"] = int(get("talent_points")) if get("talent_points") != null else 0
		d["equipped_skills"] = get("equipped_skills").duplicate(true) if get("equipped_skills") != null else []
		d["skill_cooldowns"] = get("skill_cooldowns").duplicate(true) if get("skill_cooldowns") != null else {}
		d["stats"] = get("stats").duplicate(true) if get("stats") != null else {}
	return d

static func deserialize(d: Dictionary) -> Node:
	var scene: PackedScene = load("res://scenes/Unit.tscn")
	if scene == null:
		return null
	var u = scene.instantiate()
	u.unit_id = str(d.get("unit_id", "peasant"))
	u.faction = str(d.get("faction", "shu"))
	var p: Dictionary = d.get("pos", {"x": 0, "y": 0, "z": 0})
	u.global_position = Vector3(float(p.get("x", 0)), float(p.get("y", 1)), float(p.get("z", 0)))
	return u
