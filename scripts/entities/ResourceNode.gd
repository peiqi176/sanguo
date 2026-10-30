extends StaticBody3D
class_name ResourceNode
## ResourceNode — 资源点（森林=木、铁矿=石、农田=粮）
## 农夫右键采集，可枯竭后自行再生（树木再生）
## 矿洞（is_mine=true）：无限耐久、有归属权、近水楼台先得月

const SpriteProjector = preload("res://scripts/core/SpriteProjector.gd")

@export var resource_type: String = "wood"  # wood/stone/food
@export var amount: float = 1000.0
@export var max_amount: float = 1000.0
@export var gather_rate: float = 5.0  # 每秒采集量

# 🔥 v4 树木再生
var is_regrowing: bool = false  # 是否已耗尽进入再生
var regrow_timer: float = 0.0
var regrow_rate: float = 2.0  # 每秒恢复量（amount/s）
var regrow_full_time: float = 500.0  # 从 0 恢复到 max 大约 500 秒（8.3 分钟）

# 🔥 v4 矿洞（无限耐久 + 归属权）
var is_mine: bool = false  # 是否为矿洞（无限 stone）
var mine_owner: String = ""  # 矿洞归属势力（先到先得）
var mine_cap: int = 8  # 矿洞最大同时挖的农夫数
var mine_workers: Array = []  # 当前挖矿农夫列表

var _selection_ring: MeshInstance3D = null
var _respawn_grid_pos: Vector2i = Vector2i(-1, -1)  # 🔥 记住生成位置，方便砍伐后树木原地重生
var _regen_mesh: MeshInstance3D = null  # 🔥 再生时显示为树桩/低模型

func _ready() -> void:
	GameManager.resource_nodes.append(self)
	max_amount = amount
	_create_visual()

# 🔥 v4 带网格坐标初始化（Main.gd 生成时调用）
func init_with_grid_pos(grid_pos: Vector2i) -> void:
	_respawn_grid_pos = grid_pos

func _create_visual() -> void:
	var sprite: Sprite3D = Sprite3D.new()
	sprite.shaded = false
	var adef: Dictionary = DataLoader.get_asset_def("resource_nodes", resource_type)
	if not adef.is_empty():
		var tex: Texture2D = DataLoader.get_sprite_texture("resource_nodes", resource_type)
		if tex:
			sprite.texture = tex
		sprite.pixel_size = DataLoader.get_sprite_pixel_size("resource_nodes", tex)
		var s: float = float(adef.get("scale", 1.5))
		sprite.scale = Vector3(s, s, s)
		# 立绘是等距俯视图（能同时看到原木垛的正面截面与顶面）。
		# ⚠️ 曾经用 BILLBOARD_ENABLED 全向广告牌 → 图里的"地面"被竖直立起，
		#    从 45° 俯角的相机看就是一块悬在半空的斜板（2026-10-24 实拍确认）。
		#    必须与建筑同一套投影：纸面垂直于相机视线 + 底边按旋转矩阵推回地面。
		sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		var hb: float = DataLoader.get_sprite_anchor_y("resource_nodes", resource_type, s)
		SpriteProjector.align(sprite, hb)
	add_child(sprite)

# 🔥 v4 _process：树木再生
func _process(delta: float) -> void:
	if not is_regrowing:
		return
	# 矿洞不再生（无限耐久）
	if is_mine:
		return
	regrow_timer += delta
	# 🙏 寺庙祈福：树木生长 +50%（资源点是中立的，按玩家势力结算）
	var grow_mult: float = 1.0
	if resource_type == "wood":
		grow_mult += GameManager.get_buff_value(GameManager.player_faction, "tree_growth")
	# 缓慢恢复 amount
	amount = min(max_amount, amount + regrow_rate * delta * grow_mult)
	# 恢复满了 → 退出再生
	if amount >= max_amount:
		is_regrowing = false
		regrow_timer = 0.0
		# 🔥 恢复视觉：重新挂树/恢复原 mesh（简化：把 scale 恢复）
		scale = Vector3.ONE * scale.x  # 恢复原大小
		# 再生特效
		EventBus.float_text.emit("🌱 资源已再生", global_position + Vector3(0, 2, 0), Color.GREEN)

func gather(unit, delta: float) -> void:
	# 🔥 v4 矿洞特殊处理：无限耐久 + 归属权 + 拥挤限制
	if is_mine:
		_gather_mine(unit, delta)
		return
	# 🔥 v4 再生中不可采集
	if is_regrowing:
		return
	if amount <= 0:
		_exhausted()
		return
	var mult: float = 1.0
	# 采集业+祭祀采集加成（木/石）；精耕细作只作用于农田建筑，不作用于野外资源点
	if resource_type == "wood" or resource_type == "iron":
		mult *= GameManager.get_elite_tech_bonus(unit.faction, "gather_mult")
		mult *= (1.0 + GameManager.get_gather_official_bonus(unit.faction))
		mult *= GameManager.get_tech_bonus(unit.faction, "gather_speed")
	# 🙏 寺庙祈福：全资源采集 +20%（限时）
	mult *= (1.0 + GameManager.get_buff_value(unit.faction, "gather_speed"))
	var gathered: float = min(gather_rate * delta * mult, amount)
	amount -= gathered
	# 农夫背包机制简化：累加到单位
	if not unit.has_meta("carrying"):
		unit.set_meta("carrying", { "type": resource_type, "amount": 0.0 })
	var carrying: Dictionary = unit.get_meta("carrying")
	carrying["amount"] += gathered
	# 满载则返回掉落点（携带量：基础 20 / 科技 40 / 骑马 200）
	if carrying["amount"] >= unit.get_carry_capacity():
		unit.state = 4
	# 🔥 v4 amount 快耗尽 → 进入再生（不删除！）
	if amount <= 0:
		_exhausted()

# 🔥 v4 矿洞采集
func _gather_mine(unit, delta: float) -> void:
	# 归属权：第一个来挖的势力拥有（先到先得，中立可共享）
	if mine_owner == "":
		mine_owner = unit.faction
	elif mine_owner != unit.faction and mine_owner != "":
		# 非归属势力也能挖，但效率 -50%
		pass
	# 拥挤限制：最多 mine_cap 个农夫
	if mine_workers.size() >= mine_cap:
		return  # 已满
	if unit not in mine_workers:
		mine_workers.append(unit)
	# 无限耐久：不消耗 amount
	var gathered: float = gather_rate * delta
	# 非归属势力效率减半
	if mine_owner != unit.faction:
		gathered *= 0.5
	# 农夫背包
	if not unit.has_meta("carrying"):
		unit.set_meta("carrying", { "type": "iron", "amount": 0.0 })
	var carrying: Dictionary = unit.get_meta("carrying")
	carrying["amount"] += gathered
	if carrying["amount"] >= unit.get_carry_capacity():
		unit.state = 4

# 🔥 v4 移除矿工（农夫离开时调用）
func remove_mine_worker(unit) -> void:
	if unit in mine_workers:
		mine_workers.erase(unit)

func _exhausted() -> void:
	# 🔥 v4 树木再生：不删除节点！进入 regrowing 状态
	if is_mine:
		return  # 矿洞不会耗尽
	is_regrowing = true
	regrow_timer = 0.0
	amount = 0.0
	# 视觉：把资源点缩小/变灰（树桩效果）
	scale = scale * 0.2
	# 保留在 resource_nodes 里（不 erase），等再生满后自动恢复
	# 🔥 但不能让农夫再主动采集（检查 is_regrowing 即可）

# 💾 存档 / 读档
func serialize() -> Dictionary:
	return {
		"type": "resource_node",
		"resource_type": resource_type,
		"amount": amount,
		"max_amount": max_amount,
		"is_regrowing": is_regrowing,
		"regrow_timer": regrow_timer,
		"is_mine": is_mine,
		"mine_owner": mine_owner,
		"mine_cap": mine_cap,
		"grid": {"x": _respawn_grid_pos.x, "y": _respawn_grid_pos.y},
	}

func apply_state(d: Dictionary) -> void:
	resource_type = str(d.get("resource_type", resource_type))
	amount = float(d.get("amount", amount))
	# _ready 会把 max_amount 重置为 amount，这里必须用存档值覆盖
	max_amount = float(d.get("max_amount", amount))
	is_regrowing = bool(d.get("is_regrowing", false))
	regrow_timer = float(d.get("regrow_timer", 0.0))
	is_mine = bool(d.get("is_mine", false))
	mine_owner = str(d.get("mine_owner", ""))
	mine_cap = int(d.get("mine_cap", mine_cap))
	var g = d.get("grid", null)
	if typeof(g) == TYPE_DICTIONARY:
		_respawn_grid_pos = Vector2i(int(g.get("x", -1)), int(g.get("y", -1)))
