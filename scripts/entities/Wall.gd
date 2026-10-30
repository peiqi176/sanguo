extends Building
class_name Wall

# Wall — 城墙（继承 Building）
# 特点：
#  1. 网格占用值 = 2（阻挡但可破坏，GridManager 已定义）
#  2. 倒塌时有破碎粒子动画
#  3. 驻防单位自动获得 +30% 射程 / +20% 攻击 buff（筑墙优势）
#  4. wall_inner 是系统内城墙，不可被玩家建造/拆除

const WALL_OCCUPIED_VALUE: int = 2

func _ready() -> void:
	super._ready()
	# 覆盖父类的占用值（Building 默认用 1，城墙用 2）
	GameManager.grid.clear_occupied(grid_pos, size)
	GameManager.grid.set_occupied(grid_pos, size, WALL_OCCUPIED_VALUE)
	print("[Wall] %s 城墙就绪, HP=%d, 占用值=2" % [building_id, hp])

# ============ 驻防 buff ============
# 驻防单位（通过 Building.garrison 入驻城墙）自动获得筑墙优势：
# 攻击 +siege_defense_bonus（默认 25%），射程 +bonus*1.5（默认 37.5%）
# 直接覆盖 Building 的入驻/撤离入口，确保 buff 真正生效。

func garrison(unit) -> bool:
	var ok: bool = super.garrison(unit)
	if ok and unit.has_method("set_wall_bonus"):
		unit.set_wall_bonus(true, float(def.get("siege_defense_bonus", 0.25)))
	return ok

func unload_unit(unit) -> void:
	if unit.has_method("set_wall_bonus"):
		unit.set_wall_bonus(false, 0.0)
	super.unload_unit(unit)

# ============ 被攻城器械攻击时的额外处理 ============
func take_damage(amount: float, attacker: Node = null) -> void:
	# 木栅（wall_wood）对火攻和冲车更脆弱
	if building_id == "wall_wood" and attacker != null:
		var attacker_id: String = ""
		if attacker.has_method("get_unit_id"):
			attacker_id = attacker.get_unit_id()
		if attacker_id == "ram" or attacker_id == "trebuchet":
			amount *= 1.5  # 冲车/投石对木栅额外 50% 伤害
	super.take_damage(amount, attacker)

# ============ 倒塌 ============
func _destroyed() -> void:
	_spawn_collapse_particles()
	super._destroyed()

func _spawn_collapse_particles() -> void:
	"""倒塌破碎粒子效果"""
	var ps: CPUParticles3D = CPUParticles3D.new()
	ps.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	ps.emission_box_extents = Vector3(float(size.x) * 2.0, 1.0, float(size.y) * 2.0)
	ps.amount = 60
	ps.lifetime = 1.2
	ps.preprocess = 0.5
	
	# 根据城墙类型选颜色
	var color: Color = Color(0.45, 0.38, 0.3)  # 默认夯土色
	match building_id:
		"wall_wood": color = Color(0.5, 0.38, 0.22)
		"wall_rammed": color = Color(0.45, 0.38, 0.3)
		"wall_stone": color = Color(0.55, 0.55, 0.52)
		"wall_inner": color = Color(0.5, 0.42, 0.32)
	
	ps.color = color
	ps.gravity = Vector3(0, -9.8, 0)
	ps.direction = Vector3(-1, 1, -1).normalized()
	ps.spread = 45.0
	ps.initial_velocity_min = 1.5
	ps.initial_velocity_max = 4.0
	ps.scale_min = 0.1
	ps.scale_max = 0.4
	
	ps.global_position = global_position
	ps.position.y = 0.3
	get_tree().root.add_child(ps)
	# 0.5 秒后停止发射，1.8 秒后销毁
	get_tree().create_timer(0.5).timeout.connect(func(): ps.emitting = false)
	get_tree().create_timer(2.0).timeout.connect(func(): 
		if is_instance_valid(ps): ps.queue_free()
	)
