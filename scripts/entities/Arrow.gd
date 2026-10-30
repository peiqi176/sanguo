extends Node3D
## 🏹 箭矢（P1-18 弓兵弹道）
##
## 由 Unit._fire_arrow() 创建：
##   · 按抛物线飞向【落点】（不是追着人飞）——所以目标跑动会自然躲开
##   · 到达落点后用 hit_radius 判定是否真的打中（落空 = 纯视觉，不结算伤害）
##   · 自带生命周期，攻击者/目标中途死亡也不会报错

var start_pos: Vector3 = Vector3.ZERO
var land_pos: Vector3 = Vector3.ZERO
var arc_height: float = 1.6
var travel_time: float = 0.2
var hit_radius: float = 1.3
var damage: float = 0.0
var attacker: Node = null
var target: Node = null

var _t: float = 0.0
var _mesh: MeshInstance3D = null
var _resolved: bool = false

func configure(from: Vector3, to: Vector3, speed: float, arc_h: float, dmg: float,
		src: Node, tgt: Node, radius: float) -> void:
	start_pos = from
	land_pos = to
	arc_height = arc_h
	damage = dmg
	attacker = src
	target = tgt
	hit_radius = radius
	var dist: float = from.distance_to(to)
	travel_time = maxf(0.05, dist / maxf(speed, 1.0))
	global_position = from
	_build_mesh(from, to)

func _build_mesh(from: Vector3, to: Vector3) -> void:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(0.05, 0.05, 0.7)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.30, 0.16)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	box.material = mat
	mi.mesh = box
	var dir: Vector3 = to - from
	dir.y = 0.0
	if dir.length() > 0.01:
		mi.rotation.y = atan2(dir.x, dir.z)
	add_child(mi)
	_mesh = mi

func _process(delta: float) -> void:
	if _resolved:
		return
	_t += delta
	var k: float = clampf(_t / travel_time, 0.0, 1.0)
	var p: Vector3 = start_pos.lerp(land_pos, k)
	p.y += sin(k * PI) * arc_height
	global_position = p
	if _mesh != null:
		# 后半段箭头下压，视觉上像"落下来"
		_mesh.rotation.x = lerpf(0.25, -0.6, k)
	if k >= 1.0:
		_resolve()
		queue_free()

func _resolve() -> void:
	_resolved = true
	if not is_instance_valid(target):
		return
	if not target.has_method("take_damage"):
		return
	var gap: float = target.global_position.distance_to(land_pos)
	if gap > hit_radius:
		return
	if damage > 0.0:
		target.take_damage(damage, attacker, false)
