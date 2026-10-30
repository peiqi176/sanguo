extends Node3D
## 🔥 燃烧地面（P1-22 霹雳车落点起火）
##
## 由 Unit._spawn_thunder_fire() 创建：霹雳车砸中目标后，在落点铺一块火区，
## 持续 duration 秒，每 tick_interval 秒对半径内【非本方】单位造成 dps×interval 点灼烧。
## 数值全部来自 config/combat.json → fire_zone.thunder_car

var duration: float = 5.0
var radius: float = 3.0
var tick_interval: float = 0.5
var dps: float = 8.0
var source_faction: String = ""
var attacker: Node = null

var _elapsed: float = 0.0
var _tick_accum: float = 0.0
var _disc: MeshInstance3D = null

func configure(pos: Vector3, faction: String, src: Node, conf: Dictionary) -> void:
	global_position = pos
	source_faction = faction
	attacker = src
	duration = float(conf.get("duration", 5.0))
	radius = float(conf.get("radius", 3.0))
	tick_interval = float(conf.get("tick_interval", 0.5))
	dps = float(conf.get("dps", 8.0))
	_build_visual()

func _build_visual() -> void:
	_disc = MeshInstance3D.new()
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 0.08
	cyl.radial_segments = 20
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.35, 0.05, 0.45)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cyl.material = mat
	_disc.mesh = cyl
	_disc.position = Vector3(0, 0.06, 0)
	add_child(_disc)

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= duration:
		queue_free()
		return
	# 火苗闪动 + 末段淡出
	if _disc != null:
		var k: float = clampf(_elapsed / duration, 0.0, 1.0)
		var mat: StandardMaterial3D = (_disc.mesh as CylinderMesh).material
		if mat != null:
			mat.albedo_color = Color(1.0, 0.35 + 0.25 * randf(), 0.05, 0.45 * (1.0 - k * 0.6))
		_disc.scale = Vector3.ONE * (1.0 + 0.04 * sin(_elapsed * 12.0))
	_tick_accum += delta
	if _tick_accum < tick_interval:
		return
	var chunk: float = dps * _tick_accum
	_tick_accum = 0.0
	for u in GameManager.all_units:
		if not is_instance_valid(u):
			continue
		if not u.has_method("take_damage") or not u.has_method("get_faction"):
			continue
		if u.get_faction() == source_faction:
			continue
		if u.global_position.distance_to(global_position) > radius:
			continue
		u.take_damage(chunk, attacker, false)
