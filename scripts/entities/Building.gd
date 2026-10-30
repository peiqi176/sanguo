extends StaticBody3D
class_name Building
## Building — 建筑基类
## 包含：产出、训练队列、人口提供、建造/升级、集结点

const CameraController = preload("res://scripts/core/CameraController.gd")
const SpriteProjector = preload("res://scripts/core/SpriteProjector.gd")

signal built(building)
signal destroyed(building)

# 🔥 静态缓存 —— 所有建筑共享，减少 GPU 上传
var _static_hp_bg_tex: ImageTexture = null
var _static_hp_fg_tex: ImageTexture = null
var _static_platform_mesh: BoxMesh = null
var _static_edge_mesh: BoxMesh = null
var _static_sel_ring_mesh: BoxMesh = null

@export var building_id: String = "house"
@export var faction: String = "shu"

var def: Dictionary = {}
var hp: float = 250.0
var max_hp: float = 250.0
var grid_pos: Vector2i = Vector2i.ZERO
var size: Vector2i = Vector2i(2, 2)
var is_selected: bool = false
var build_progress: float = 1.0  # 0-1, 1=完成
var base_build_time: float = 20.0  # 秒，来自 config/buildings.json
var _builders: Array = []       # 当前正在建造的农夫列表
var max_builders: int = 4       # 傲世三国式：最多 4 个共建
var training_queue: Array = []  # [{unit_id, time_left}]
var rally_point: Vector3 = Vector3.ZERO
var workers: Array = []
var workers_max: int = 0
var production_accum: float = 0.0
var garrisoned_units: Array = []  # 驻扎在建筑内的单位
var can_garrison: bool = false
var garrison_cap: int = 0
# 【🔥 v4】消耗农夫训练模式: { worker_instance_id: time_left }
var _worker_training: Dictionary = {}
var consumes_peasant: bool = false

# 防御塔/弩台攻击参数（crossbow_tower / wall_tower 等）
var attack_damage: float = 0.0
var attack_range: float = 0.0
var attack_speed: float = 1.0  # 攻击间隔秒数
var armor_pierce: float = 0.0
var _attack_timer: float = 0.0

# 组件
var _selection_ring: MeshInstance3D = null
var _hp_bar: Node = null
var _sprite: Sprite3D = null

func _ready() -> void:
	def = DataLoader.get_building_def(building_id)
	if not def.is_empty():
		_init_from_def()
	_create_selection_ring()
	_create_hp_bar()
	GameManager.register_building(self)
	# 编辑器里摆的 house 不该改写人口的全局上限
	if not GameManager.editor_mode and building_id == "house":
		GameManager.add_population_cap(faction, def.get("pop_provide", 0))
	# 🏗️ 地基/完工两阶段外观
	if build_progress >= 1.0:
		_create_full_appearance()   # 官府/牌坊等初始就建好的
		if building_id == "inn":
			refresh_inn_roster()    # 地图上已有 / 读档进来的客栈：马上挂出首月名单
	else:
		_create_foundation()        # 玩家新建：先只有地基
	built.emit(self)

# ---------- HP 条 ----------
var _hp_bar_bg: Sprite3D = null
var _hp_bar_fg: Sprite3D = null

func _ensure_static_cache() -> void:
	if _static_hp_bg_tex == null:
		var bg_img: Image = Image.create(24, 5, false, Image.FORMAT_RGBA8)
		bg_img.fill(Color(0.2, 0.05, 0.05, 0.9))
		_static_hp_bg_tex = ImageTexture.create_from_image(bg_img)
	if _static_hp_fg_tex == null:
		var fg_img: Image = Image.create(24, 5, false, Image.FORMAT_RGBA8)
		fg_img.fill(Color(0.1, 0.8, 0.2, 0.95))
		_static_hp_fg_tex = ImageTexture.create_from_image(fg_img)

func _create_hp_bar() -> void:
	_ensure_static_cache()
	_hp_bar_bg = Sprite3D.new()
	_hp_bar_bg.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hp_bar_bg.shaded = false
	_hp_bar_bg.texture = _static_hp_bg_tex
	_hp_bar_bg.scale = Vector3(0.5, 0.5, 0.5)
	_hp_bar_bg.position = Vector3(0, float(size.x) * 1.5 + 2.0, 0)
	add_child(_hp_bar_bg)
	
	_hp_bar_fg = Sprite3D.new()
	_hp_bar_fg.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hp_bar_fg.shaded = false
	_hp_bar_fg.texture = _static_hp_fg_tex
	_hp_bar_fg.scale = Vector3(0.5, 0.5, 0.5)
	_hp_bar_fg.position = Vector3(0, float(size.x) * 1.5 + 2.0, -0.05)
	add_child(_hp_bar_fg)
	_update_hp_bar()

func _update_hp_bar() -> void:
	if _hp_bar_fg == null or hp <= 0:
		return
	var ratio: float = clampf(hp / max_hp, 0.0, 1.0)
	var full_scale: float = 0.5  # 只声明一次，全函数共用
	if ratio < 0.999 and build_progress >= 1.0:
		_hp_bar_bg.visible = true
		_hp_bar_fg.visible = true
		_hp_bar_fg.scale = Vector3(full_scale * ratio, full_scale, full_scale)
		_hp_bar_fg.position.x = -full_scale * (1.0 - ratio) * 0.5
		if ratio < 0.3:
			_hp_bar_fg.modulate = Color(1.0, 0.3, 0.3)
		elif ratio < 0.6:
			_hp_bar_fg.modulate = Color(1.0, 0.8, 0.3)
		else:
			_hp_bar_fg.modulate = Color.WHITE
	elif build_progress < 1.0:
		# 建造中显示建造进度条
		_hp_bar_bg.visible = true
		_hp_bar_fg.visible = true
		var progress_ratio: float = build_progress
		_hp_bar_fg.scale = Vector3(full_scale * progress_ratio, full_scale, full_scale)
		_hp_bar_fg.position.x = -full_scale * (1.0 - progress_ratio) * 0.5
		_hp_bar_fg.modulate = Color(0.3, 0.9, 1.0)  # 蓝绿色表示建造
	else:
		_hp_bar_bg.visible = false
		_hp_bar_fg.visible = false

func _init_from_def() -> void:
	max_hp = def.get("hp", 250)
	# 🧬 防御科技：城墙/城门/官府血量（研究后新建/重建生效）
	if building_id == "government" and GameManager.has_tech_flag(faction, "government_hp_to_10000"):
		max_hp = 10000.0
	elif building_id.begins_with("wall_"):
		max_hp *= GameManager.get_tech_bonus(faction, "wall_hp")
	elif building_id.begins_with("gate_"):
		max_hp *= GameManager.get_tech_bonus(faction, "gate_hp")
	size = Vector2i(def.get("size", [2,2])[0], def.get("size", [2,2])[1])
	can_garrison = def.get("can_garrison", false)
	garrison_cap = def.get("garrison_cap", 0)
	workers_max = int(def.get("workers_max", 0))
	consumes_peasant = def.get("consumes_peasant", false)
	# 🏗️ 建造系统：从 JSON 读 build_time，官府=0 表示已建好
	base_build_time = float(def.get("build_time", 20))
	# ★ spawn_as_complete：从地图文件 / 地图编辑器载入的建筑，本来就该是完成态。
	#   不加这个标志的话，house 这种 build_time=18 的建筑会被当成"刚开工"，
	#   载入后只显示一块阵营色的地基平台、没有房屋外观 —— 实测就是这样。
	if base_build_time <= 0.0 or spawn_as_complete:
		build_progress = 1.0
		hp = max_hp
	else:
		build_progress = 0.0  # 玩家新建的：从 0 开始
		hp = 1.0              # 🏗️ 地基只有 1HP，随建造进度增长
	# 防御塔攻击参数
	attack_damage = float(def.get("attack", 0.0))
	attack_range = float(def.get("range", 0.0))
	attack_speed = float(def.get("atk_speed", 1.0))
	armor_pierce = float(def.get("armor_pierce", 0.0))

# 🏗️ 地基节点 + 建筑外观节点（分阶段创建）
var _foundation_nodes: Array = []    # [MeshInstance3D, ...] — platform + edge
var _appearance_nodes: Array = []    # [Sprite3D/MeshInstance3D, ...] — 完整建筑外观
var _glb_holder: Node3D = null       # 真 3D GLB 外观（贴片删除后的主路径）

## 由 ObjectSpawner 在 add_child 之前置 true：表示"这栋是存档里已建成的"，
## 跳过 build_time 的从 0 开始逻辑，直接给完成态外观。
var spawn_as_complete: bool = false

func _create_foundation() -> void:
	"""🏗️ 只建地基：platform + edge（玩家新建时先有这个）"""
	var fc: Color = GameManager.get_faction_color(faction)
	var sw: float = float(size.x) * 2.0 + 0.3
	var sd: float = float(size.y) * 2.0 + 0.3
	
	# 3D底座平台
	var platform: MeshInstance3D = MeshInstance3D.new()
	var plat_mesh: BoxMesh = BoxMesh.new()
	# 向地下延伸 1.7m：3×3 的建筑占地 6m，缓坡上两端高差就能到 1m，
	# 0.3m 的薄台基盖不住 → 建筑一半悬在坡外（实拍见过）。
	# 做厚之后它变成一截"埋进地里的石台"，坡地也能坐实。
	plat_mesh.size = Vector3(sw, 2.0, sd)
	platform.mesh = plat_mesh
	var plat_mat: StandardMaterial3D = StandardMaterial3D.new()
	plat_mat.albedo_color = Color(fc.r * 0.6, fc.g * 0.6, fc.b * 0.55)
	plat_mat.roughness = 0.9
	platform.material_override = plat_mat
	platform.position.y = 0.30 - 1.0
	add_child(platform)
	_foundation_nodes.append(platform)
	
	# 台阶边缘
	var edge: MeshInstance3D = MeshInstance3D.new()
	var edge_mesh: BoxMesh = BoxMesh.new()
	edge_mesh.size = Vector3(sw + 0.15, 0.1, sd + 0.15)
	edge.mesh = edge_mesh
	var edge_mat: StandardMaterial3D = StandardMaterial3D.new()
	edge_mat.albedo_color = Color(fc.r * 0.35, fc.g * 0.35, fc.b * 0.3)
	edge_mat.roughness = 0.95
	edge.material_override = edge_mat
	edge.position.y = 0.06
	add_child(edge)
	_foundation_nodes.append(edge)

func _create_full_appearance() -> void:
	"""🏗️ 建完整建筑外观（sprite 或 fallback 阶梯）"""
	var fc: Color = GameManager.get_faction_color(faction)
	var adef: Dictionary = DataLoader.get_asset_def("buildings", building_id)
	var tex: Texture2D = DataLoader.get_sprite_texture("buildings", building_id)
	
	if tex:
		# ⚠ 这里原来有一行 `_sprite.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA`，已删。
		#   Godot 4 的 GeometryInstance3D.transparency 是 float 淡出值，TRANSPARENCY_ALPHA == 1
		#   正好等于"100% 透明"，等于让整栋建筑隐身。详见 Unit.gd 里同一处的长注释。
		_sprite = Sprite3D.new()
		_sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		# ★ 纸片必须「垂直于相机视线」，不是「竖直朝前」。
		#
		# 素材是等距俯视图：俯角约 30°，能同时看到屋顶、两个侧面，底部还画了一块
		# 水平的台基地面。如果把这块纸竖直立起来、再让 45° 俯角的透视相机去斜看它：
		#   ① 图里那块「水平」台基被竖起来 → 屏幕上变成一块斜插进地里的板（实拍见图）；
		#   ② 整个平面被透视压缩 cos45°≈0.707 → 屋顶变矮、屋身发胖、整体往后倒。
		# 正确做法：让纸面绕自身 X 轴后倒 (90° - 相机俯角)，使法线正好指向相机。
		# 这样图 1:1 还原，而图里画的等距地面与真实水平地形是同一套投影（都是 45° 俯视），
		# 台基会自动和地面贴合 —— 这就是傲世三国那一代 2.5D 的标准渲染方式。
		# （公式与推导已收编到 SpriteProjector，资源点/村庄共用同一份实现。）
		_sprite.shaded = false
		_sprite.texture = tex
		_sprite.pixel_size = DataLoader.get_sprite_pixel_size("buildings", tex)
		var s: float = float(adef.get("scale", 1.5)) if not adef.is_empty() else 1.5
		_sprite.scale = Vector3(s, s, s)
		# 屋基贴地：由贴图内容的 alpha 包围盒量出「中心 → 内容底边」的距离 hb，
		# 再按倾斜后的旋转矩阵把这条底边推回原点（否则倾斜会让建筑整体往前飘）。
		var hb: float = DataLoader.get_sprite_anchor_y("buildings", building_id, s)
		SpriteProjector.align(_sprite, hb)
		# 硬边透明（M3-4）：建筑是固定朝向的 quad，和单位/树木互相穿插时靠 discard 排序。
		_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		_sprite.modulate = Color(
			1.0 + (fc.r - 0.5) * 0.3,
			1.0 + (fc.g - 0.5) * 0.3,
			1.0 + (fc.b - 0.5) * 0.3,
			1.0
		)
		add_child(_sprite)
		_appearance_nodes.append(_sprite)
		print("[Building] ✅ %s 贴图加载成功 (faction=%s)" % [building_id, faction])
	else:
		# GLB 优先（2026-10-29 贴片已删）：标定表里有的建筑走真 3D 模型
		var glb_holder: Node3D = EntityGLTF.spawn("buildings", building_id, self, Vector3.ZERO)
		if glb_holder != null:
			print("[Building] ✅ %s GLB 模型加载成功 (faction=%s)" % [building_id, faction])
			_glb_holder = glb_holder
			_appearance_nodes.append(glb_holder)   # 建造完成判断依赖此表非空
			if _sprite == null:
				_sprite = Sprite3D.new()
				_sprite.visible = false
				add_child(_sprite)
		else:
			# Fallback：多层阶梯 BoxMesh
			print("[Building] ⚠ %s 贴图/GLB 缺失 → 用阶梯 fallback mesh (faction=%s)" % [building_id, faction])
			var fb_sw: float = float(size.x) * 1.8
			var fb_sz: float = float(size.y) * 1.8
			var layers: int = 3
			var base_height: float = 1.2
			var layer_h: float = base_height / float(layers)
			var lx: float = fb_sw
			var lz: float = fb_sz
			for li in range(layers):
				var mesh_instance: MeshInstance3D = MeshInstance3D.new()
				var box: BoxMesh = BoxMesh.new()
				box.size = Vector3(lx, layer_h, lz)
				mesh_instance.mesh = box
				var mat: StandardMaterial3D = StandardMaterial3D.new()
				var darkness: float = 1.0 - float(li) * 0.18
				mat.albedo_color = Color(fc.r * darkness, fc.g * darkness, fc.b * darkness)
				mat.roughness = 0.7
				mesh_instance.material_override = mat
				mesh_instance.position.y = float(li) * layer_h + layer_h * 0.5 + 0.15
				add_child(mesh_instance)
				_appearance_nodes.append(mesh_instance)
				lx *= 0.72
				lz *= 0.72
			# 顶部装饰
			var bdef: Dictionary = DataLoader.get_building_def(building_id)
			var cat: String = bdef.get("category", "civilian")
			if cat == "governance" or cat == "tech" or cat == "military":
				var roof: MeshInstance3D = MeshInstance3D.new()
				var cone: CylinderMesh = CylinderMesh.new()
				cone.top_radius = 0.0
				cone.bottom_radius = min(fb_sw, fb_sz) * 0.25
				cone.height = 0.8
				roof.mesh = cone
				var rmat: StandardMaterial3D = StandardMaterial3D.new()
				rmat.albedo_color = Color(fc.r * 0.5, fc.g * 0.5, fc.b * 0.45)
				roof.material_override = rmat
				roof.position.y = base_height + 0.15 + 0.4
				add_child(roof)
				_appearance_nodes.append(roof)
			if _sprite == null:
				_sprite = Sprite3D.new()
				_sprite.visible = false
				add_child(_sprite)

func _on_build_complete() -> void:
	"""🏗️ 建造完成：补全建筑外观 + hp 拉满"""
	if _appearance_nodes.is_empty():
		_create_full_appearance()
	hp = max_hp
	# 🏮 客栈完工即开业，挂出首月名单（月份计时从开业算起）
	if building_id == "inn":
		refresh_inn_roster()
	print("[Building] 🏗️ %s 建造完成！" % building_id)

func _get_building_color() -> Color:
	var bdef: Dictionary = DataLoader.get_building_def(building_id)
	var cat: String = bdef.get("category", "civilian")
	match cat:
		"economy": return Color(0.7, 0.55, 0.25)   # 橙黄 = 经济
		"military": return Color(0.55, 0.25, 0.25)  # 暗红 = 军事
		"tech": return Color(0.3, 0.45, 0.7)        # 蓝 = 科技
		"governance": return Color(0.65, 0.48, 0.25) # 金棕 = 治理
		_: return Color(0.42, 0.36, 0.28)            # 土褐 = 普通

func _create_selection_ring() -> void:
	_selection_ring = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(float(size.x) * 2.0 + 0.4, 0.1, float(size.y) * 2.0 + 0.4)
	_selection_ring.mesh = box
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color.GREEN
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.8, 0.2)
	_selection_ring.material_override = mat
	_selection_ring.visible = false
	add_child(_selection_ring)
	_selection_ring.position.y = -0.45

func set_selected(selected: bool) -> void:
	is_selected = selected
	if _selection_ring:
		_selection_ring.visible = selected

func get_faction() -> String:
	return faction

# ==================== 🔥 v4 市场贸易（数据驱动） ====================
## 价格来自 buildings.json → market.trade：
##   卖出价 = base_value × sell_ratio(0.8) × (1 + 势力加成)
##   买入价 = base_value × buy_ratio(1.25) × (1 − 势力加成/2)
## 吴（东吴通商）卖出 +25%；通商官每级再加成。
func _get_trade_conf() -> Dictionary:
	return def.get("trade", {})

func get_trade_unit_price(resource: String, is_buy: bool) -> float:
	var tr: Dictionary = _get_trade_conf()
	var base: float = float((tr.get("base_value", {}) as Dictionary).get(resource, 1.0))
	var bonus: float = float((tr.get("faction_bonus", {}) as Dictionary).get(faction, 0.0))
	bonus += GameManager.get_official_bonus(faction, "通商")
	if is_buy:
		return base * float(tr.get("buy_ratio", 1.25)) * (1.0 - bonus * 0.5)
	return base * float(tr.get("sell_ratio", 0.8)) * (1.0 + bonus)

func market_sell(resource: String, amount: float) -> float:
	"""卖资源→金，返回实际获得金"""
	if building_id != "market" or amount <= 0.0:
		return 0.0
	if GameManager.get_resource(faction, resource) < amount:
		EventBus.float_text.emit("资源不足", global_position + Vector3(0, 3, 0), Color.RED)
		return 0.0
	var gold_out: float = amount * get_trade_unit_price(resource, false)
	GameManager.add_resource(faction, resource, -amount)
	GameManager.add_resource(faction, "gold", gold_out)
	EventBus.float_text.emit("💰 卖 %.1f %s → %.1f 金" % [amount, resource, gold_out], global_position + Vector3(0, 3, 0), Color.YELLOW)
	return gold_out

func market_buy(resource: String, amount: float) -> float:
	"""金→买资源，返回实际花费金"""
	if building_id != "market" or amount <= 0.0:
		return 0.0
	var gold_cost: float = amount * get_trade_unit_price(resource, true)
	if GameManager.get_resource(faction, "gold") < gold_cost:
		EventBus.float_text.emit("金不足（需 %.1f）" % gold_cost, global_position + Vector3(0, 3, 0), Color.RED)
		return 0.0
	GameManager.add_resource(faction, "gold", -gold_cost)
	GameManager.add_resource(faction, resource, amount)
	EventBus.float_text.emit("💰 花 %.1f 金 → %.1f %s" % [gold_cost, amount, resource], global_position + Vector3(0, 3, 0), Color.YELLOW)
	return gold_cost

# ==================== 🔥 v4 寺庙祭祀（数据驱动） ====================
var _temple_last_sacrifice: float = -999.0
var _sacrifice_cooldown: float = 90.0

func _get_service_conf(key: String) -> Dictionary:
	return (def.get("services", {}) as Dictionary).get(key, {})

func get_sacrifice_cooldown_left() -> float:
	return maxf(0.0, _sacrifice_cooldown - (Time.get_ticks_msec() / 1000.0 - _temple_last_sacrifice))

## 祭祀祈福：100 金 + 30 酒 → 120 秒内 灾害-60% / 树木生长+50% / 农业+20% / 采集+20%，全军士气+15
func temple_sacrifice() -> bool:
	if building_id != "temple":
		return false
	var conf: Dictionary = _get_service_conf("sacrifice")
	var cost: Dictionary = conf.get("cost", {"gold": 100, "wine": 30})
	if get_sacrifice_cooldown_left() > 0.0:
		EventBus.float_text.emit("祭祀冷却中 %.0fs" % get_sacrifice_cooldown_left(), global_position + Vector3(0, 3, 0), Color.RED)
		return false
	if not GameManager.can_afford(faction, cost):
		EventBus.float_text.emit("金/酒不足（需 %s）" % str(cost), global_position + Vector3(0, 3, 0), Color.RED)
		return false
	GameManager.spend_resources(faction, cost)
	_temple_last_sacrifice = Time.get_ticks_msec() / 1000.0
	_sacrifice_cooldown = float(conf.get("cooldown", 90.0))
	var dur: float = float(conf.get("duration", 120.0))
	GameManager.add_faction_buff(faction, "disaster_reduction", float(conf.get("disaster_reduction", 0.6)), dur)
	GameManager.add_faction_buff(faction, "tree_growth", float(conf.get("tree_growth", 0.5)), dur)
	GameManager.add_faction_buff(faction, "farm_output", float(conf.get("farm_output", 0.2)), dur)
	GameManager.add_faction_buff(faction, "gather_speed", float(conf.get("gather_speed", 0.2)), dur)
	var morale_gain: float = float(conf.get("army_morale", 15.0))
	for u in GameManager.all_units:
		if is_instance_valid(u) and u.get_faction() == faction:
			u.morale = minf(100.0, u.morale + morale_gain)
	GameManager.add_faction_buff(faction, "morale_aura", morale_gain, float(conf.get("morale_duration", 60.0)))
	EventBus.float_text.emit("🙏 祭祀完成！灾害↓60% 农业/采集↑ 全军士气+%.0f" % morale_gain, global_position + Vector3(0, 3, 0), Color.GREEN)
	return true

## 寺庙复活：救人（重伤倒计时中的武将），基础 300 金 + 50 酒 + 每级 60 金
func temple_revive_general() -> Node:
	if building_id != "temple":
		return null
	var conf: Dictionary = _get_service_conf("revive")
	var target = null
	for g in GameManager.dead_generals:
		if not is_instance_valid(g):
			continue
		if float(g.get("grace_period_seconds")) >= 0.0:
			target = g
			break
	if target == null:
		EventBus.float_text.emit("没有待复活的武将（超时已成在野，去客栈招募）", global_position + Vector3(0, 3, 0), Color.ORANGE)
		return null
	var lv: int = int(target.level)
	var base: Dictionary = conf.get("cost", {"gold": 300, "wine": 50})
	var cost: Dictionary = base.duplicate()
	cost["gold"] = float(cost.get("gold", 300)) + float(conf.get("cost_per_level", 60)) * float(maxi(0, lv - 1))
	if not GameManager.can_afford(faction, cost):
		EventBus.float_text.emit("复活资源不足（需 %s）" % str(cost), global_position + Vector3(0, 3, 0), Color.RED)
		return null
	GameManager.spend_resources(faction, cost)
	GameManager.dead_generals.erase(target)
	target.call("_respawn_at_temple")
	EventBus.float_text.emit("🛕 %s 在寺庙复活（Lv%d）" % [str(target.name), lv], global_position + Vector3(0, 3, 0), Color.GREEN)
	return target

# ==================== 🔥 v4 点将台随机招武将 ====================
var _general_pool: Array = [
	"赵云", "关羽", "张飞", "黄忠", "马超", "魏延", "姜维", "张苞",
	"夏侯惇", "夏侯渊", "张辽", "徐晃", "许褚", "典韦", "张郃", "于禁",
	"周瑜", "甘宁", "太史慈", "黄盖", "吕蒙", "陆逊", "鲁肃", "程普",
	"吕布", "华雄", "颜良", "文丑", "公孙瓒", "张绣", "韩遂", "马腾"
]
var _general_first_names: Dictionary = {
	"shu": ["赵", "关", "张", "黄", "马", "魏", "姜", "廖", "王", "陈"],
	"wei": ["夏", "张", "徐", "许", "典", "曹", "李", "郭", "程", "邓"],
	"wu": ["周", "甘", "太", "黄", "吕", "陆", "鲁", "程", "凌", "徐"],
	"neutral": ["吕", "华", "颜", "文", "公", "张", "韩", "马", "袁", "刘"]
}
var _general_last_names: Dictionary = {
	"shu": ["云", "羽", "飞", "忠", "超", "延", "维", "化", "平", "到"],
	"wei": ["惇", "渊", "辽", "晃", "褚", "韦", "仁", "休", "昱", "艾"],
	"wu": ["瑜", "宁", "慈", "盖", "蒙", "逊", "肃", "普", "统", "盛"],
	"neutral": ["布", "雄", "良", "丑", "瓒", "绣", "遂", "腾", "绍", "表"]
}
func random_general_name() -> String:
	var first: String = _general_first_names.get(faction, _general_first_names["neutral"]).pick_random()
	var last: String = _general_last_names.get(faction, _general_last_names["neutral"]).pick_random()
	return first + last

func recruit_general_from_recruit(cost_gold: float = 300.0) :
	"""🔥 v4 点将台/招募台随机生成新武将（立绘+名字匹配）"""
	if GameManager.get_resource(faction, "gold") < cost_gold:
		EventBus.float_text.emit("金不足（需 %.0f）" % cost_gold, global_position + Vector3(0, 3, 0), Color.RED)
		return null
	GameManager.add_resource(faction, "gold", -cost_gold)
	# 随机名字 + 随机立绘/类型
	var gname: String = random_general_name()
	var gclass: String = ["warrior", "defense", "assault", "strategist", "trickster"].pick_random()
	var scene: PackedScene = load("res://scenes/Unit.tscn")
	if scene == null:
		return null
	var g = scene.instantiate()
	g.unit_id = "sword"  # base
	g.faction = faction
	g.is_general = true
	g.general_id = gname
	g.name = "General_" + gname
	g.general_class = gclass
	get_tree().root.add_child(g)
	g.global_position = global_position + Vector3(randf_range(-3, 3), 1.5, randf_range(-3, 3))
	var g2 = g  # General（弱类型）
	if g2 != null:
		gname = gname  # 名字已设
		EventBus.float_text.emit("🎯 招来武将: %s (%s)" % [gname, gclass], g.global_position + Vector3(0, 4, 0), Color.GOLD)
	return g  # General（弱类型）

func get_production() -> Dictionary:
	if build_progress < 1.0:
		return {}
	var produces: Dictionary = def.get("produces", {})
	var result: Dictionary = {}
	for res in produces.keys():
		result[res] = float(produces[res]) * _get_output_mult(res)
	return result

func _get_output_mult(res: String) -> float:
	"""产出倍率：基础科技 + 特殊科技 + 政务税收"""
	var mult: float = 1.0
	# 📖 基础科技（民生分支）
	if building_id == "farm":
		mult *= GameManager.get_tech_bonus(faction, "farm_output")
	if building_id == "fishery":
		mult *= GameManager.get_tech_bonus(faction, "fishery_output")
	if building_id == "workshop":
		mult *= GameManager.get_tech_bonus(faction, "gold_output")  # 作坊效率
	match res:
		"food":
			mult *= GameManager.get_elite_tech_bonus(faction, "farm_output_mult")
			mult *= (1.0 + GameManager.get_buff_value(faction, "farm_output"))  # 寺庙祈福：农业增产
		"wood", "iron":
			mult *= GameManager.get_elite_tech_bonus(faction, "gather_mult")
			mult *= (1.0 + GameManager.get_gather_official_bonus(faction))
		"gold":
			mult *= GameManager.get_elite_tech_bonus(faction, "craft_mult")
			mult *= (1.0 + GameManager.get_tax_bonus(faction))
		"wine":
			mult *= GameManager.get_elite_tech_bonus(faction, "wine_mult")
		"bun", "mantou":
			mult *= GameManager.get_elite_tech_bonus(faction, "bun_mult")
	return mult

func train_unit(unit_id: String) -> bool:
	var unit_def: Dictionary = DataLoader.get_unit_def(unit_id)
	if unit_def.is_empty():
		if unit_id == "supply_cart":
			unit_def = DataLoader.logistics.get("supply_cart", {})
			unit_def["pop_cost"] = 0
			unit_def["train_time"] = unit_def.get("build_time", 25)
		else:
			return false
	var cost: Dictionary = unit_def.get("cost", {})
	# 🏛 官府等级门槛：T2/T3/T4 兵种必须官府到位（units.json 用 government_req，tech.json 用 gov_req）
	var need_gov: int = int(unit_def.get("gov_req", unit_def.get("government_req", 1)))
	if GameManager.get_government_level(faction) < need_gov:
		EventBus.float_text.emit("需要官府 %d 级（当前 %d）" % [need_gov, GameManager.get_government_level(faction)], global_position + Vector3(0, 3, 0), Color.RED)
		return false
	# 📖 兵种科技门槛（如弩手需要 elite_unlock）
	var req_tech: String = str(unit_def.get("requires_tech", ""))
	if req_tech != "" and not GameManager.is_tech_researched(faction, req_tech):
		EventBus.float_text.emit("需要科技: %s" % req_tech, global_position + Vector3(0, 3, 0), Color.RED)
		return false
	# 📖 器械/船只科技解锁：配置为 unlock_<unit_id> 布尔效果（如云梯/冲车/投石车/战船）
	var cat: String = str(unit_def.get("category", ""))
	if (cat == "siege" or cat == "naval") and req_tech == "":
		if not GameManager.has_tech_flag(faction, "unlock_" + unit_id):
			EventBus.float_text.emit("尚未研究该器械/舰船科技", global_position + Vector3(0, 3, 0), Color.RED)
			return false
	if not GameManager.can_afford(faction, cost):
		EventBus.float_text.emit("资源不足", global_position + Vector3(0, 3, 0), Color.RED)
		return false
	if not GameManager.can_train(faction, unit_def.get("pop_cost", 1)):
		EventBus.float_text.emit("人口不足", global_position + Vector3(0, 3, 0), Color.RED)
		return false
	GameManager.spend_resources(faction, cost)
	training_queue.append({ "unit_id": unit_id, "time_left": unit_def.get("train_time", 20) })
	return true

func set_rally_point(pos: Vector3) -> void:
	rally_point = pos
	EventBus.rally_point_set.emit(self, pos)

# 🎖️ 点将台：Lv5+ 士兵自主晋升为武将
func promote_soldier_to_general(unit) -> bool:
	if building_id != "mustering_hall":
		return false
	if build_progress < 1.0:
		EventBus.float_text.emit("点将台尚未建成", global_position + Vector3(0, 3, 0), Color.RED)
		return false
	if not is_instance_valid(unit):
		return false
	if not unit.has_method("can_promote_to_general") or not unit.can_promote_to_general():
		EventBus.float_text.emit("仅 Lv5+ 士兵可晋升", global_position + Vector3(0, 3, 0), Color.RED)
		return false
	var rng: float = float(def.get("promote_range", 25))
	if global_position.distance_to(unit.global_position) > rng:
		EventBus.float_text.emit("需在点将台 %.0f 米内晋升" % rng, global_position + Vector3(0, 3, 0), Color.RED)
		return false
	var cost: Dictionary = def.get("promote_cost", {})
	if not cost.is_empty():
		if not GameManager.can_afford(faction, cost):
			EventBus.float_text.emit("晋升资源不足", global_position + Vector3(0, 3, 0), Color.RED)
			return false
		GameManager.spend_resources(faction, cost)
	var gen = unit.promote_to_general()
	return gen != null

# 🎖️ 训练营进阶：刀→刀斧手 / 枪→金枪兵 / 弓→弩手
# 直接替换单位并保留等级/经验/体力/士气，人口占用不变
func promote_unit(unit, to_id: String) -> bool:
	if building_id != "training_camp":
		return false
	if build_progress < 1.0:
		EventBus.float_text.emit("训练营尚未建成", global_position + Vector3(0, 3, 0), Color.RED)
		return false
	if not is_instance_valid(unit):
		return false
	var pmap: Dictionary = def.get("promotion_map", {})
	if str(pmap.get(unit.unit_id, "")) != to_id:
		return false
	var to_def: Dictionary = DataLoader.get_unit_def(to_id)
	if to_def.is_empty():
		return false
	var req_tech: String = str(to_def.get("requires_tech", ""))
	if req_tech != "" and not GameManager.is_tech_researched(faction, req_tech):
		EventBus.float_text.emit("需要科技: %s" % req_tech, global_position + Vector3(0, 3, 0), Color.RED)
		return false
	var cost: Dictionary = to_def.get("cost", {})
	if not GameManager.can_afford(faction, cost):
		EventBus.float_text.emit("资源不足", global_position + Vector3(0, 3, 0), Color.RED)
		return false
	GameManager.spend_resources(faction, cost)
	# 生成进阶单位
	var unit_scene: PackedScene = load("res://scenes/Unit.tscn")
	if unit_scene == null:
		return false
	var new_unit = unit_scene.instantiate()
	new_unit.unit_id = to_id
	new_unit.faction = faction
	get_tree().root.add_child(new_unit)
	new_unit.global_position = unit.global_position
	# 继承等级与经验（按等级曲线补足总经验，成长会重新结算）
	var base_level: int = int(unit.level)
	var total_xp: float = float(unit.exp)
	for lv in range(1, base_level):
		total_xp += float(unit._get_unit_xp_to_next(lv))
	if total_xp > 0.0:
		new_unit.add_exp(total_xp)
	# 🎖️ 进阶保留原等级（不同兵种经验曲线不同，add_exp 可能算出别的等级，强制对齐）
	new_unit.level = base_level
	new_unit.exp = float(unit.exp)
	# ⚔ 保留杀敌成长：击杀数、永久攻击加成、每 5 杀的生命上限加成
	var kept_kills: int = int(unit.kills)
	new_unit.kills = kept_kills
	new_unit.veteran_atk_bonus = float(unit.veteran_atk_bonus)
	if kept_kills >= 5:
		new_unit.max_hp += float(int(kept_kills / 5) * 20)
	# 🍞 保留出征军粮与马匹状态
	new_unit.field_rations = float(unit.field_rations)
	new_unit.horse_tier = int(unit.horse_tier)
	if unit.mounted and new_unit.has_method("command_mount"):
		new_unit.mounted = true
		new_unit.mount_speed_bonus = new_unit.get_horse_tier_speed_bonus()
		new_unit._add_horse()
	new_unit.hp = new_unit.max_hp * clampf(float(unit.hp) / maxf(float(unit.max_hp), 1.0), 0.0, 1.0)
	new_unit.stamina = float(unit.stamina)
	new_unit.morale = float(unit.morale)
	var from_name: String = str(DataLoader.get_unit_def(unit.unit_id).get("name", unit.unit_id))
	EventBus.float_text.emit("🎖️ %s → %s" % [from_name, str(to_def.get("name", to_id))], global_position + Vector3(0, 3, 0), Color.GOLD)
	unit.queue_free()
	return true

var _built_checked: bool = false
# ⚡ 错峰：每个建筑的产出计时器初始相位随机，避免几十栋建筑挤在同一帧结算。
var _production_timer: float = randf()

func _process(delta: float) -> void:
	# 🗺 编辑器模式：建筑只当"看得见的模型"，不涨建造进度、不产资源、不训兵。
	# 不做这个门，编辑器里放 20 个建筑，游戏就自己开了一局。
	if GameManager.editor_mode:
		return
	_update_hp_bar()
	# 🏛 官府锁血后的进入占领 + 易主后缓慢回血（2026-10-28 定稿）
	_tick_capture(delta)
	_tick_capture_regen(delta)
	if build_progress < 1.0:
		# 🏗️ 没人建造就停着（地基摆在那，没工人不涨进度）
		if _builders.is_empty():
			return
		# 🏗️ 建造进度：base_build_time 来自 JSON + 多农民加速
		var time_per_unit: float = max(1.0, base_build_time)
		# 加速公式：1 个农民 = 1x，2 个 = 1.4x，3 个 = 1.8x，4 个 = 2.2x
		var n: int = clampi(_builders.size(), 1, max_builders)
		var speed_mult: float = 1.0 + 0.4 * float(n - 1)
		build_progress = min(1.0, build_progress + (delta * speed_mult) / time_per_unit)
		# 🏗️ hp 随建造进度从 1 增长到 max_hp
		hp = lerp(1.0, max_hp, build_progress)
		# 建造完成时补全外观 + emit 信号一次
		if build_progress >= 1.0 and not _built_checked:
			_built_checked = true
			_on_build_complete()
			built.emit(self)
			# 💬 通知所有建造工人：完工了，撤！
			for b in _builders.duplicate():
				if b and is_instance_valid(b) and b.has_method("on_building_completed"):
					b.on_building_completed()
			_builders.clear()
		return
	
	# 训练队列（保留给器械房/造船厂等多兵种，兵营/郎勇营用消耗农夫模式）
	if not consumes_peasant and training_queue.size() > 0:
		var item: Dictionary = training_queue[0]
		var uid: String = str(item.get("unit_id", ""))
		var train_mult: float = GameManager.get_elite_tech_bonus(faction, "train_speed_mult")
		if building_id == "siege_workshop":
			train_mult *= GameManager.get_elite_tech_bonus(faction, "siege_manufacture_mult")
		item["time_left"] = float(item["time_left"]) - delta * train_mult
		if item["time_left"] <= 0:
			_spawn_unit(uid)
			training_queue.pop_front()
	
	# 【🔥 v4 消耗农夫训练模式】—— 兵营/郎勇营（单一兵种）
	if consumes_peasant and not _worker_training.is_empty():
		var train_mult: float = GameManager.get_elite_tech_bonus(faction, "train_speed_mult")
		var finished: Array = []
		for wid in _worker_training.keys():
			_worker_training[wid] -= delta * train_mult
			if _worker_training[wid] <= 0.0:
				finished.append(wid)
		for fid in finished:
			var worker_unit = null
			for w in workers:
				if is_instance_valid(w) and w.get_instance_id() == fid:
					worker_unit = w
					break
			if worker_unit:
				var trains: Array = def.get("trains", [])
				if not trains.is_empty():
					var spawn_pos: Vector3 = rally_point if rally_point != Vector3.ZERO else global_position + Vector3(0, 1, 0)
					_spawn_specific_unit(str(trains[0]), spawn_pos)
				workers.erase(worker_unit)
				worker_unit.current_building = null
				worker_unit.queue_free()
			_worker_training.erase(fid)
	
	# Worker 经济产出
	_production_timer += delta
	if _production_timer >= 1.0:
		_production_timer = 0.0
		var prod: Dictionary = get_production_per_second()
		# 🏭 原料消耗（对标傲世作坊：粟米→馒头/酒，原料不足则按比例减产）
		var consumes_map: Dictionary = def.get("consumes", {})
		if not consumes_map.is_empty() and not prod.is_empty():
			var wrk_ratio: float = float(workers.size()) / float(workers_max)
			var afford_ratio: float = 1.0
			for cres in consumes_map.keys():
				var need_per_sec: float = float(consumes_map[cres]) * wrk_ratio
				var have_amt: float = GameManager.get_resource(faction, cres)
				if need_per_sec > 0.0 and have_amt < need_per_sec:
					afford_ratio = min(afford_ratio, have_amt / need_per_sec)
			if afford_ratio <= 0.0:
				prod = {}
			else:
				for cres in consumes_map.keys():
					GameManager.add_resource(faction, cres, -float(consumes_map[cres]) * wrk_ratio * afford_ratio)
				if afford_ratio < 1.0:
					for res in prod.keys():
						prod[res] = float(prod[res]) * afford_ratio
		for res in prod.keys():
			var amt: float = float(prod[res])
			if amt > 0.0:
				GameManager.add_resource(faction, res, amt)
				EventBus.resource_produced.emit(faction, res, amt, self)
	
	# 防御塔自动攻击（crossbow_tower 等有 attack/range 的建筑）
	if attack_damage > 0.0 and attack_range > 0.0:
		_attack_timer -= delta
		if _attack_timer <= 0.0:
			_attack_timer = attack_speed
			var target = _find_nearest_enemy()
			if target:
				_fire_at(target)
	# 🏹 驻军射箭：官府/民居等无攻击建筑，驻军人数决定射击伤害（防骚扰）
	if attack_damage <= 0.0 and can_garrison and not garrisoned_units.is_empty():
		_garrison_fire_timer -= delta
		if _garrison_fire_timer <= 0.0:
			_garrison_fire_timer = 1.2
			var gt = _find_nearest_enemy_in_range(GARRISON_FIRE_RANGE)
			if gt:
				_fire_garrison_at(gt, GARRISON_FIRE_DAMAGE * float(garrisoned_units.size()))

const GARRISON_FIRE_RANGE: float = 9.0
const GARRISON_FIRE_DAMAGE: float = 6.0
var _garrison_fire_timer: float = 0.0

func _find_nearest_enemy_in_range(rng: float):
	var nearest = null
	var best: float = rng * rng
	for u in GameManager.all_units:
		if not is_instance_valid(u):
			continue
		if u.get_faction() == faction:
			continue
		var d: float = global_position.distance_squared_to(u.global_position)
		if d <= best:
			best = d
			nearest = u
	return nearest

func _fire_garrison_at(target, damage: float) -> void:
	if not is_instance_valid(target):
		return
	target.take_damage(damage, self)

func _find_nearest_enemy() :
	"""找范围内最近的敌方单位"""
	var nearest = null
	var nearest_dist: float = attack_range * attack_range
	for u in GameManager.all_units:
		if not is_instance_valid(u):
			continue
		if u.get_faction() == faction:
			continue
		var d: float = global_position.distance_squared_to(u.global_position)
		if d <= nearest_dist:
			nearest_dist = d
			nearest = u
	return nearest

func _fire_at(target) -> void:
	"""对目标发射箭矢 + 伤害"""
	var damage: float = attack_damage
	if armor_pierce > 0.0:
		damage *= (1.0 + armor_pierce)
	target.take_damage(damage, self)
	# 箭矢轨迹 VFX
	var arrow: Sprite3D = Sprite3D.new()
	arrow.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	arrow.shaded = false
	var img: Image = Image.create(8, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.6, 0.4, 0.2, 1.0))
	arrow.texture = ImageTexture.create_from_image(img)
	arrow.scale = Vector3(0.5, 0.5, 0.5)
	arrow.global_position = global_position + Vector3(0, 1.0, 0)
	arrow.look_at(target.global_position + Vector3(0, 1, 0), Vector3.UP)
	get_tree().root.add_child(arrow)
	var tween: Tween = get_tree().create_tween()
	tween.tween_property(arrow, "global_position", target.global_position + Vector3(0, 1, 0), 0.15).set_trans(Tween.TRANS_LINEAR)
	tween.tween_callback(func():
		if is_instance_valid(arrow): arrow.queue_free()
	)
	EventBus.float_text.emit(str(int(damage)), target.global_position + Vector3(0, 2.5, 0), Color.YELLOW)

func _spawn_unit(unit_id: String, at_pos: Vector3 = Vector3.ZERO) -> void:
	var spawn_pos: Vector3 = at_pos
	if spawn_pos == Vector3.ZERO:
		spawn_pos = global_position if is_inside_tree() else Vector3.ZERO
	var sx: float = float(size.x) if size.x > 0 else 2.0
	
	if unit_id == "supply_cart":
		var cart_scene: PackedScene = load("res://scenes/SupplyCart.tscn")
		if cart_scene:
			var cart = cart_scene.instantiate()
			cart.cart_id = "cart_" + str(randi())
			cart.faction = faction
			cart.global_position = spawn_pos + Vector3(sx, 0, 0)
			get_tree().root.add_child(cart)
			GameManager.factions[faction].units.append(cart)
		return
	var unit_scene: PackedScene = load("res://scenes/Unit.tscn")
	if not unit_scene:
		print("[Building] ❌ Unit.tscn load 失败")
		return
	var unit = unit_scene.instantiate()
	unit.unit_id = unit_id
	unit.faction = faction
	get_tree().root.add_child(unit)
	unit.global_position = spawn_pos + Vector3(sx, 0, 0)
	print("[Building] ✅ 训练出 %s at %s" % [unit_id, unit.global_position])
	GameManager.change_population(faction, DataLoader.get_unit_def(unit_id).get("pop_cost", 1))
	EventBus.unit_trained.emit(faction, unit_id)
	if rally_point != Vector3.ZERO:
		unit.command_move(rally_point)

func _spawn_specific_unit(unit_id: String, pos: Vector3) -> void:
	_spawn_unit(unit_id, pos)

func repair(amount: float) -> void:
	"""修理建筑，恢复HP，消耗木材和石料"""
	if hp >= max_hp:
		return
	# 修理消耗：每点HP消耗0.5木材+0.3镔铁
	var wood_cost: float = amount * 0.5
	var iron_cost: float = amount * 0.3
	if not GameManager.can_afford(faction, {"wood": wood_cost, "iron": iron_cost}):
		return
	GameManager.spend_resources(faction, {"wood": wood_cost, "iron": iron_cost})
	hp = min(max_hp, hp + amount)

func is_damaged() -> bool:
	return hp < max_hp

func garrison(unit) -> bool:
	"""单位入驻建筑"""
	if not can_garrison:
		return false
	if garrisoned_units.size() >= garrison_cap:
		return false
	if unit in garrisoned_units:
		return false
	garrisoned_units.append(unit)
	unit.visible = false
	unit.garrisoned = true
	if unit.has_method("set_physics_process"):
		unit.set_physics_process(false)
	if unit.has_method("set_process"):
		unit.set_process(false)
	EventBus.float_text.emit("入驻", global_position + Vector3(0, 3, 0), Color.CYAN)
	return true

func unload_unit(unit) -> void:
	"""让一个单位离开建筑"""
	if unit in garrisoned_units:
		garrisoned_units.erase(unit)
		unit.visible = true
		unit.garrisoned = false
		unit.attack_target = null
		if unit.has_method("set_physics_process"):
			unit.set_physics_process(true)
		if unit.has_method("set_process"):
			unit.set_process(true)
		unit.global_position = global_position + Vector3(size.x, 0, 0)
		unit.state = 0

func unload_all() -> void:
	"""所有驻扎单位离开"""
	for u in garrisoned_units.duplicate():
		unload_unit(u)

func get_garrison_count() -> int:
	return garrisoned_units.size()

# ============ 建造工人（农夫建造系统） ============

func get_builder_slots_available() -> int:
	"""还有多少建造岗位空着"""
	if build_progress >= 1.0:
		return 0
	return max(0, max_builders - _builders.size())

func register_builder(unit) -> bool:
	"""农夫报到开始建造"""
	if build_progress >= 1.0:
		return false
	if _builders.size() >= max_builders:
		return false
	if unit in _builders:
		return false
	_builders.append(unit)
	return true

func unregister_builder(unit) -> void:
	"""农夫离开建造岗位"""
	_builders.erase(unit)

# ============ 农夫入岗（经济建筑专属） ============

func can_accept_workers() -> bool:
	"""是否可以接受农夫入岗工作"""
	if build_progress < 1.0:
		return false
	if workers_max <= 0:
		return false
	return true

func get_worker_slots_available() -> int:
	"""还有多少岗位空着"""
	return max(0, workers_max - workers.size())

func assign_worker(unit) -> bool:
	"""把一个农夫分配到本建筑工作"""
	if not can_accept_workers():
		return false
	if get_worker_slots_available() <= 0:
		return false
	if unit in workers:
		return false
	workers.append(unit)
	unit.current_building = self
	# 【🔥 v4】消耗农夫训练模式：初始化训练计时器
	if consumes_peasant:
		# 🔥 v4 征兵需谷物（每训练1单位耗 15 food）
		var food_cost: float = 15.0
		if GameManager.get_resource(faction, "food") < food_cost:
			workers.erase(unit)
			unit.current_building = null
			EventBus.float_text.emit("征兵需 %.0f 谷!" % food_cost, global_position + Vector3(0, 3, 0), Color.RED)
			return false
		GameManager.add_resource(faction, "food", -food_cost)
		var trains: Array = def.get("trains", [])
		var train_time: float = 25.0
		if not trains.is_empty():
			var tdef: Dictionary = DataLoader.get_unit_def(str(trains[0]))
			train_time = float(tdef.get("train_time", 25.0))
		_worker_training[unit.get_instance_id()] = train_time
		EventBus.float_text.emit("入岗(耗%.0f谷)" % food_cost, global_position + Vector3(0, 3, 0), Color.CYAN)
	EventBus.float_text.emit("入岗", global_position + Vector3(0, 3, 0), Color.CYAN)
	return true

func unassign_worker(unit) -> void:
	"""让一个农夫离岗"""
	if unit in workers:
		workers.erase(unit)
		if unit.current_building == self:
			unit.current_building = null
		# 清除训练计时器
		_worker_training.erase(unit.get_instance_id())

func unassign_all_workers() -> void:
	for w in workers.duplicate():
		unassign_worker(w)
	_worker_training.clear()

# 💾 读档专用：恢复在岗农夫，不再扣谷物、不再重新计时
func restore_worker(unit, train_left: float = -1.0) -> void:
	if unit == null or unit in workers:
		return
	workers.append(unit)
	unit.current_building = self
	if consumes_peasant and train_left > 0.0:
		_worker_training[unit.get_instance_id()] = train_left

func get_production_per_second() -> Dictionary:
	"""根据当前在岗工人数，计算每秒实际产出"""
	if build_progress < 1.0 or workers_max <= 0 or workers.is_empty():
		return {}
	var produces: Dictionary = def.get("produces", {})
	var ratio: float = float(workers.size()) / float(workers_max)
	var season_mod: float = _get_season_modifier()
	var result: Dictionary = {}
	for res in produces.keys():
		var base: float = float(produces[res])
		result[res] = base * ratio * season_mod * _get_output_mult(res)
	return result

func _get_season_modifier() -> float:
	var sm: Dictionary = def.get("season_modifier", {})
	if sm.is_empty():
		return 1.0
	var season: String = GameManager.current_season
	return float(sm.get(season, 1.0))

# ==================== 🏭 作坊配方 / 🐎 马厩等级 / 📦 营帐打包 ====================

## 作坊配方文本（UI 展示用）：2谷+1肉→1包子
func get_recipe_text() -> String:
	var recipe: Dictionary = def.get("recipe", {})
	if recipe.is_empty():
		return ""
	var parts: Array = []
	for out_res in recipe.keys():
		var ins: Dictionary = recipe[out_res]
		var seg: Array = []
		for r in ins.keys():
			seg.append("%s×%.1f" % [_res_cn(r), float(ins[r])])
		parts.append("%s→%s" % ["+".join(seg), _res_cn(out_res)])
	# 单农夫每分钟产量
	var per: String = ""
	if workers_max > 0:
		var bun_ps: float = float(def.get("produces", {}).get("bun", 0.0)) / float(workers_max)
		per = "　单农夫 %.1f 包/分" % (bun_ps * 60.0)
	return "配方 " + "，".join(parts) + per

func _res_cn(res: String) -> String:
	match res:
		"food": return "谷"
		"wood": return "木"
		"iron": return "铁"
		"gold": return "金"
		"bun": return "包子"
		"wine": return "酒"
		"fish": return "鱼"
		"meat": return "肉"
		"horse": return "马"
	return res

## 马厩提供的马匹等级：官府 1→tier1，2→tier2，3→tier3，3级+战马品种→tier4
func get_horse_tier_available() -> int:
	if building_id != "stable":
		return 1
	var lv: int = GameManager.get_government_level(faction)
	var tier: int = 1
	if lv >= 2:
		tier = 2
	if lv >= 3:
		tier = 3
	if lv >= 3 and GameManager.is_tech_researched(faction, "horse_types"):
		tier = 4
	return tier

## 营帐打包搬迁：返还建造费，拆除自身，玩家在原处重建（Main.start_build_mode）
func pack_up() -> bool:
	if building_id != "tent":
		EventBus.float_text.emit("只有营帐可以打包搬迁", global_position + Vector3(0, 3, 0), Color.ORANGE)
		return false
	# 在岗/驻军先放出来，避免读档式悬空引用
	unassign_all_workers()
	unload_all()
	var cost: Dictionary = def.get("cost", {})
	for res in cost.keys():
		GameManager.add_resource(faction, str(res), float(cost[res]))
	EventBus.float_text.emit("📦 营帐已打包，返还建造资源", global_position + Vector3(0, 3, 0), Color.CYAN)
	GameManager.unregister_building(self)
	queue_free()
	return true

# ==================== 🏮 客栈：招募在野武将 ====================
## 每个客栈最多挂 candidates(3) 名在野武将，每"月"(recruit.refresh_seconds=60s)自动换一批；
## 期间名单固定（不能靠反复开关窗口手动刷新），被招走的武将立刻消失且不再回池。
var inn_roster: Array = []      # [{id, level}] 本客栈本月的在野名单
var _inn_t: float = 0.0         # 距下次换批的计时
var _inn_ready: bool = false    # 是否已生成过名单（避免空名单被反复惰性重抽）
var _inn_missed: bool = false   # 本月换批运气失败（无人应募），UI 用于提示

func inn_get_candidates() -> Array:
	if building_id != "inn":
		return []
	if not _inn_ready:
		refresh_inn_roster()
	return _inn_candidate_payload()

func inn_roster_missed() -> bool:
	return _inn_missed

## 换一批：先掷"是否有人来"的概率，再抽 1~candidates 名；首月保底有人，避免客栈刚建好却是空的
func refresh_inn_roster() -> void:
	if building_id != "inn":
		return
	var first: bool = not _inn_ready
	inn_roster.clear()
	_inn_ready = true
	_inn_t = 0.0
	_inn_missed = false
	var rc: Dictionary = def.get("recruit", {})
	var want: int = int(rc.get("candidates", 3))
	var chance: float = float(rc.get("spawn_chance", 0.6))
	if not first and randf() > chance:
		_inn_missed = true
		return
	var lv_r: Vector2i = GameManager.get_recruit_level_range(def)
	var avail: Array = []
	for gid in GameManager.generals_pool:
		var s: String = str(gid)
		if GameManager.is_general_taken(s):
			continue
		if GameManager.is_general_claimed_elsewhere(s, self):
			continue
		avail.append(s)
	if avail.is_empty():
		_inn_missed = true
		return
	avail.shuffle()
	# 首月挂满 3 名；之后每月 1~3 名随机，运气好才满员
	var n: int = want if first else randi_range(1, want)
	for i in range(mini(n, avail.size())):
		inn_roster.append({"id": str(avail[i]), "level": randi_range(lv_r.x, lv_r.y)})

## 距下次自动换批剩余秒数（UI 倒计时）
func inn_refresh_left() -> float:
	return maxf(0.0, GameManager.get_inn_refresh_seconds(def) - _inn_t)

## 按月节拍推进（由 GameManager 统一调用）
func inn_tick(delta: float) -> bool:
	if building_id != "inn":
		return false
	_inn_t += delta
	if _inn_t >= GameManager.get_inn_refresh_seconds(def):
		refresh_inn_roster()
		return true
	return false

## 名单 -> UI 数据（等级在换批时已定死，价格实时算）
func _inn_candidate_payload() -> Array:
	var out: Array = []
	for e in inn_roster:
		var gid: String = str(e.get("id", ""))
		if gid == "" or GameManager.is_general_taken(gid):
			continue
		if not GameManager.generals_pool.has(gid):
			continue
		var gdef: Dictionary = GameManager.get_general_def_by_id(gid)
		var lv: int = int(e.get("level", 1))
		var bst: Dictionary = gdef.get("base", {})
		var skill_names: Array = []
		for sid in gdef.get("skills", []):
			skill_names.append(DataLoader.get_skill_name(str(sid)))
		var passive_names: Array = []
		for pid in gdef.get("passive", []):
			passive_names.append(DataLoader.get_skill_name(str(pid)))
		out.append({
			"id": gid,
			"name": str(gdef.get("name", gid)),
			"class": str(gdef.get("class", "warrior")),
			"class_name": DataLoader.get_class_name(str(gdef.get("class", "warrior"))),
			"faction": str(gdef.get("faction", "qunxiong")),
			"level": lv,
			"might": int(bst.get("might", 70)),
			"intelligence": int(bst.get("intelligence", 70)),
			"command": int(bst.get("command", 70)),
			"politics": int(bst.get("politics", 55)),
			"skills": skill_names,
			"passives": passive_names,
			"cost": GameManager.get_recruit_cost(def, lv, gid, faction),
			"price": GameManager.get_recruit_price_breakdown(def, lv, gid, faction),
		})
	return out

func inn_recruit(gid: String, lv: int) -> Node:
	if building_id != "inn":
		return null
	if not GameManager.generals_pool.has(gid):
		EventBus.float_text.emit("该武将已不在野", global_position + Vector3(0, 3, 0), Color.RED)
		return null
	var cost: float = GameManager.get_recruit_cost(def, lv, gid, faction)
	if GameManager.get_resource(faction, "gold") < cost:
		EventBus.float_text.emit("金不足（需 %.0f）" % cost, global_position + Vector3(0, 3, 0), Color.RED)
		return null
	GameManager.add_resource(faction, "gold", -cost)
	GameManager.generals_pool.erase(gid)
	# 招走的人立刻从本客栈名单消失（本月内不会补位，等下个月换批）
	for i in range(inn_roster.size() - 1, -1, -1):
		if str((inn_roster[i] as Dictionary).get("id", "")) == gid:
			inn_roster.remove_at(i)
	var gen_script: GDScript = load("res://scripts/entities/General.gd")
	if gen_script == null or not gen_script.can_instantiate():
		return null
	var g: Node = gen_script.call(
		"spawn_general", faction, gid, lv, get_parent(), global_position + Vector3(0, 0.5, 3.5))
	if g != null:
		var pb: Dictionary = GameManager.get_recruit_price_breakdown(def, lv, gid, faction)
		var tag: String = ""
		if float(pb.get("same_faction_discount", 0.0)) > 0.0:
			tag += "（同势力-%.0f%%" % (float(pb.get("same_faction_discount", 0.0)) * 100.0)
		if float(pb.get("renown_discount", 0.0)) > 0.0:
			tag += "（声望-%.0f%%" % (float(pb.get("renown_discount", 0.0)) * 100.0)
		if float(pb.get("enemy_premium", 0.0)) > 0.0:
			tag += "（敌将+%.0f%%" % (float(pb.get("enemy_premium", 0.0)) * 100.0)
		if tag != "":
			tag += "）"
		EventBus.float_text.emit("🏮 招募 %s（Lv%d）花费 %.0f 金%s" % [str(g.name), lv, cost, tag],
			global_position + Vector3(0, 3, 0), Color.GREEN)
	return g

func get_capture_conf() -> Dictionary:
	return DataLoader.combat.get("capture", {})

func get_hp_lock() -> float:
	return max_hp * float(get_capture_conf().get("lock_ratio", 0.10))

func is_capturable() -> bool:
	return building_id == "government"

func is_hp_locked() -> bool:
	return is_capturable() and hp <= get_hp_lock() + 0.5

func take_damage(amount: float, attacker: Node = null) -> void:
	# 【🔥 v4】wall_inner 不可破坏
	if def.get("is_indestructible", false):
		return
	# 🏛 官府血量锁 10%：锁血后不可攻击（2026-10-28 定稿），改由单位进入范围占领
	if is_capturable() and hp <= get_hp_lock() + 0.5:
		return
	hp -= amount
	_record_building_contributor(attacker, amount)
	if is_capturable():
		var lock_line: float = get_hp_lock()
		if hp < lock_line:
			hp = lock_line
			damaged_recently = true
			capture_regen_timer = 0.0
			EventBus.float_text.emit("🔒 官府残破，需进入占领", global_position + Vector3(0, 3.5, 0), Color(0.9, 0.75, 0.2))
			return
	damaged_recently = true
	capture_regen_timer = 0.0
	if hp <= 0:
		# V2：官府被摧毁 → 触发城池占领（不是直接 destroy）
		if building_id == "government" and attacker != null and is_instance_valid(attacker) and attacker.has_method("get_faction"):
			var atk_faction: String = attacker.get_faction()
			if atk_faction != "" and atk_faction != faction:
				_government_capture(atk_faction)
				return
		_destroyed(attacker)

# 🏛 官府占领：锁血后单位进入范围推进占领条 → 易主 → 恢复 50% 血 → 缓慢回满
var capture_progress: float = 0.0
var capture_occupier: String = ""
var damaged_recently: bool = false
var capture_regen_timer: float = 0.0
var _capture_milestone: int = 0  # 占领条 25/50/75/100 飘字用

func _tick_capture(delta: float) -> void:
	if not is_capturable() or not is_hp_locked():
		capture_progress = 0.0
		capture_occupier = ""
		_capture_milestone = 0
		return
	var conf: Dictionary = get_capture_conf()
	var radius: float = float(conf.get("government_entry_radius", 6.0))
	var counts: Dictionary = {}
	for u in GameManager.all_units:
		if not is_instance_valid(u) or not u.has_method("get_faction"):
			continue
		if u.global_position.distance_to(global_position) > radius:
			continue
		var f: String = u.get_faction()
		if f == faction or f == "":
			continue
		counts[f] = int(counts.get(f, 0)) + 1
	if counts.is_empty():
		capture_progress = maxf(0.0, capture_progress - 10.0 * delta)
		if capture_progress <= 0.0:
			capture_occupier = ""
		return
	if counts.size() > 1:
		capture_progress = maxf(0.0, capture_progress - 5.0 * delta)
		return
	var f2: String = str(counts.keys()[0])
	if capture_occupier != f2:
		capture_occupier = f2
		capture_progress = 0.0
	capture_progress = minf(100.0, capture_progress + 15.0 * delta)
	# 🏛 占领进度飘字（25% 一档），让玩家/AI 都能看见"进入范围"确实在生效
	var pct: int = int(capture_progress / 25.0)
	if pct > _capture_milestone:
		_capture_milestone = pct
		EventBus.float_text.emit("🏛 占领 %d%%" % mini(100, pct * 25), global_position + Vector3(0, 4.5, 0), Color(0.95, 0.85, 0.3))
	if capture_progress >= 100.0:
		_government_capture(f2)

func _tick_capture_regen(delta: float) -> void:
	if not is_capturable() or hp >= max_hp:
		return
	capture_regen_timer += delta
	if capture_regen_timer < 3.0:
		return
	hp = minf(max_hp, hp + max_hp * float(get_capture_conf().get("regen_per_sec", 0.01)) * delta)

# V2：官府占领逻辑——被攻占后城池易主
var _gov_capture_timer: float = 0.0
var _gov_capture_active: bool = false

func _government_capture(new_faction: String) -> void:
	"""V2城池占领：官府被攻破→城池自动易主+所有建筑归属变更+民心暴跌"""
	var old_faction: String = faction
	faction = new_faction
	EventBus.float_text.emit("🏛️ 官府被攻占！城池易主！", global_position + Vector3(0, 4, 0), Color.RED)
	print("[Building] 🏛️ 官府被 %s 攻占！城池归属变更：%s → %s" % [new_faction, old_faction, new_faction])
	# 遍历同一城池内的建筑，归属变更
	for b in GameManager.all_buildings:
		if not is_instance_valid(b) or b == self:
			continue
		if b.faction == old_faction:
			b.faction = new_faction
	# 民心暴跌（村庄同理，可在 Village.gd 处理）
	GameManager.add_population_cap(old_faction, -def.get("pop_provide", 0))
	GameManager.add_population_cap(new_faction, def.get("pop_provide", 0))
	# 🏛 易主瞬间恢复到 50% 血，之后 1%/s 缓慢回满（2026-10-28 定稿）
	max_hp = def.get("hp", 5000)
	hp = max_hp * float(get_capture_conf().get("restore_ratio", 0.50))
	damaged_recently = false
	capture_regen_timer = 0.0
	capture_progress = 0.0
	capture_occupier = ""
	# 🎖 占领城池经验：参与单位平分 200 池，单人 ≤50（config/combat.json → capture_settlement）
	var cap: Dictionary = DataLoader.combat.get("experience", {}).get("capture_settlement", {})
	var participants: Array = GameManager.get_units_near(global_position, 20.0, new_faction)
	GameManager.grant_shared_xp(participants, float(cap.get("share_pool", 200.0)), float(cap.get("per_recipient_max", 50.0)))
	# 胜利检查
	GameManager.check_victory()
	# 不 queue_free，城池保留

# ==================== 🎖 建筑经验（P1-21） ====================
var _xp_contributors: Dictionary = {}

func _record_building_contributor(attacker, dmg: float) -> void:
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

func _award_destroy_xp(attacker) -> void:
	"""摧毁建筑：补刀者 20；参与者平分 50 池，单人 ≤10（config/combat.json → experience.destroy_building）"""
	var cfg_all: Dictionary = DataLoader.combat.get("experience", {})
	var cfg: Dictionary = cfg_all.get("destroy_building", {})
	if cfg.is_empty():
		return
	var window: float = float(cfg_all.get("contributor_window", 30.0))
	var now: float = Time.get_ticks_msec() / 1000.0
	var valid_attacker: bool = attacker != null and is_instance_valid(attacker) and attacker.has_method("get_faction")
	if valid_attacker:
		GameManager.grant_xp_to(attacker, float(cfg.get("final_destroyer", 20.0)))
	var others: Array = []
	for id in _xp_contributors.keys():
		var rec: Dictionary = _xp_contributors[id]
		var n = rec.get("node", null)
		if not is_instance_valid(n):
			continue
		if now - float(rec.get("t", 0.0)) > window:
			continue
		if valid_attacker and (n == attacker or n.get_faction() != attacker.get_faction()):
			continue
		others.append(n)
	GameManager.grant_shared_xp(others, float(cfg.get("share_pool", 0.0)), float(cfg.get("per_recipient_max", 10.0)))

func _destroyed(attacker = null) -> void:
	_award_destroy_xp(attacker)
	# 🏛️ 建筑倒塌粒子（石块 + 烟尘双层）
	_spawn_collapse_particles()
	unassign_all_workers()
	unload_all()
	GameManager.unregister_building(self)
	GameManager.grid.clear_occupied(grid_pos, size)
	if building_id == "house":
		GameManager.add_population_cap(faction, -def.get("pop_provide", 0))
	EventBus.building_destroyed.emit(self)
	destroyed.emit(self)
	GameManager.check_victory()
	queue_free()

func _spawn_collapse_particles() -> void:
	"""建筑倒塌：两层粒子（大石块 + 烟尘）"""
	var root := get_tree().root
	
	# 层 1：大石块（向外飞溅 + 重力）
	var rocks := CPUParticles3D.new()
	rocks.amount = 18
	rocks.lifetime = 1.2
	var rmat := ParticleProcessMaterial.new()
	rmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	rmat.emission_sphere_radius = 1.2
	rmat.direction = Vector3(0, 1, 0)
	rmat.spread = 75.0
	rmat.gravity = Vector3(0, -9.8, 0)
	rmat.initial_velocity_min = 2.0
	rmat.initial_velocity_max = 5.5
	rmat.scale_min = 0.25
	rmat.scale_max = 0.6
	rmat.color = Color(0.5, 0.42, 0.32)
	rocks.process_material = rmat
	var rmesh := BoxMesh.new()
	rmesh.size = Vector3(0.25, 0.25, 0.25)
	rocks.mesh = rmesh
	rocks.global_position = global_position + Vector3(0, 2.5, 0)
	root.add_child(rocks)
	
	# 层 2：烟尘（向上飘 + 渐变消散）
	var smoke := CPUParticles3D.new()
	smoke.amount = 24
	smoke.lifetime = 1.8
	var smat := ParticleProcessMaterial.new()
	smat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	smat.emission_box_extents = Vector3(4, 2, 4)
	smat.direction = Vector3(0, 1, 0)
	smat.spread = 15.0
	smat.gravity = Vector3(0, -0.8, 0)
	smat.initial_velocity_min = 1.5
	smat.initial_velocity_max = 3.0
	smat.scale_min = 0.8
	smat.scale_max = 2.2
	smat.color = Color(0.55, 0.55, 0.55, 0.6)
	smoke.process_material = smat
	smoke.global_position = global_position + Vector3(0, 3, 0)
	root.add_child(smoke)
	
	get_tree().create_timer(2.0).timeout.connect(func():
		if is_instance_valid(rocks): rocks.queue_free()
		if is_instance_valid(smoke): smoke.queue_free()
	)

# ==================== 📦 存档序列化 ====================

func serialize() -> Dictionary:
	var d: Dictionary = {}
	d["type"] = "building"
	d["building_id"] = building_id
	d["faction"] = faction
	d["grid_pos"] = {"x": grid_pos.x, "y": grid_pos.y}
	d["hp"] = hp
	d["max_hp"] = max_hp
	d["build_progress"] = build_progress
	d["base_build_time"] = base_build_time
	d["government_level"] = GameManager.factions.get(faction, null).government_level if GameManager.factions.has(faction) else 1
	d["morale"] = GameManager.factions.get(faction, null).morale if GameManager.factions.has(faction) else 70.0
	# workers / garrisoned / training_queue 只存 ID 引用（读档时重建）
	d["workers_count"] = workers.size()
	d["garrison_count"] = garrisoned_units.size()
	var tq: Array = []
	for item in training_queue:
		tq.append({"unit_id": str(item.get("unit_id", "")), "time_left": float(item.get("time_left", 0))})
	d["training_queue"] = tq
	d["rally"] = {"x": rally_point.x, "y": rally_point.y, "z": rally_point.z}
	return d

static func deserialize(d: Dictionary) -> Node:
	var scene: PackedScene = load("res://scenes/Building.tscn")
	if scene == null:
		return null
	var b = scene.instantiate()
	b.building_id = str(d.get("building_id", "house"))
	b.faction = str(d.get("faction", "shu"))
	var gp: Dictionary = d.get("grid_pos", {"x": 0, "y": 0})
	b.grid_pos = Vector2i(int(gp.get("x", 0)), int(gp.get("y", 0)))
	# _init_from_def() 需要先 def 才有 hp/max_hp/build_time 的正确默认值
	return b
