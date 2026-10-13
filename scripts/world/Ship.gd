extends Node3D
## Ship - 程序化3D船只（运输船/战船）

enum ShipType { TRANSPORT, WARSHIP }

var ship_type: int = ShipType.TRANSPORT
var _hull: MeshInstance3D = null
var _deck: MeshInstance3D = null
var _mast: MeshInstance3D = null
var _sail: MeshInstance3D = null
var _oars: Array[MeshInstance3D] = []
var _flag: MeshInstance3D = null
var _anim_time: float = 0.0

func _ready() -> void:
	_build_ship()

func set_ship_type(t: int) -> void:
	ship_type = t
	for child in get_children():
		child.queue_free()
	_build_ship()

func _build_ship() -> void:
	var hull_color: Color = Color(0.45, 0.30, 0.15)
	var deck_color: Color = Color(0.60, 0.42, 0.22)
	var sail_color: Color = Color(0.90, 0.88, 0.82)
	if ship_type == ShipType.WARSHIP:
		hull_color = Color(0.30, 0.20, 0.12)
		deck_color = Color(0.50, 0.35, 0.18)
		sail_color = Color(0.85, 0.75, 0.60)

	_hull = MeshInstance3D.new()
	var hull_mesh: CylinderMesh = CylinderMesh.new()
	hull_mesh.top_radius = 0.8
	hull_mesh.bottom_radius = 1.2
	hull_mesh.height = 0.8
	hull_mesh.radial_segments = 12
	_hull.mesh = hull_mesh
	var hull_mat: StandardMaterial3D = StandardMaterial3D.new()
	hull_mat.albedo_color = hull_color
	hull_mat.roughness = 0.7
	_hull.material_override = hull_mat
	_hull.rotation.y = PI / 2.0
	_hull.scale.z = 2.5
	_hull.position.y = -0.2
	add_child(_hull)

	_deck = MeshInstance3D.new()
	var deck_mesh: CylinderMesh = CylinderMesh.new()
	deck_mesh.top_radius = 1.1
	deck_mesh.bottom_radius = 1.1
	deck_mesh.height = 0.15
	deck_mesh.radial_segments = 12
	_deck.mesh = deck_mesh
	var deck_mat: StandardMaterial3D = StandardMaterial3D.new()
	deck_mat.albedo_color = deck_color
	deck_mat.roughness = 0.8
	_deck.material_override = deck_mat
	_deck.rotation.y = PI / 2.0
	_deck.scale.z = 2.5
	_deck.position.y = 0.25
	add_child(_deck)

	_mast = MeshInstance3D.new()
	var mast_mesh: CylinderMesh = CylinderMesh.new()
	mast_mesh.top_radius = 0.08
	mast_mesh.bottom_radius = 0.1
	mast_mesh.height = 3.0
	_mast.mesh = mast_mesh
	var mast_mat: StandardMaterial3D = StandardMaterial3D.new()
	mast_mat.albedo_color = Color(0.35, 0.22, 0.10)
	mast_mat.roughness = 0.6
	_mast.material_override = mast_mat
	_mast.position.y = 1.7
	add_child(_mast)

	_sail = MeshInstance3D.new()
	var sail_mesh: PlaneMesh = PlaneMesh.new()
	sail_mesh.size = Vector2(2.0, 1.8)
	_sail.mesh = sail_mesh
	var sail_mat: StandardMaterial3D = StandardMaterial3D.new()
	sail_mat.albedo_color = sail_color
	sail_mat.roughness = 0.5
	sail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_sail.material_override = sail_mat
	_sail.position = Vector3(0, 1.7, 0)
	add_child(_sail)

	_flag = MeshInstance3D.new()
	var flag_mesh: PlaneMesh = PlaneMesh.new()
	flag_mesh.size = Vector2(0.6, 0.4)
	_flag.mesh = flag_mesh
	var flag_mat: StandardMaterial3D = StandardMaterial3D.new()
	flag_mat.albedo_color = Color(0.8, 0.15, 0.15)
	flag_mat.roughness = 0.6
	flag_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flag.material_override = flag_mat
	_flag.position = Vector3(0.35, 3.2, 0)
	add_child(_flag)

	for i in range(4):
		var oar: MeshInstance3D = MeshInstance3D.new()
		var oar_mesh: CylinderMesh = CylinderMesh.new()
		oar_mesh.top_radius = 0.04
		oar_mesh.bottom_radius = 0.05
		oar_mesh.height = 1.5
		oar.mesh = oar_mesh
		var oar_mat: StandardMaterial3D = StandardMaterial3D.new()
		oar_mat.albedo_color = Color(0.40, 0.25, 0.12)
		oar_mat.roughness = 0.7
		oar.material_override = oar_mat
		var side: int = 1 if i % 2 == 0 else -1
		var row: int = i / 2
		oar.position = Vector3(side * 1.2, 0.1, -0.6 + row * 1.2)
		oar.rotation.z = side * 0.5
		oar.rotation.y = PI / 2.0
		add_child(oar)
		_oars.append(oar)

	if ship_type == ShipType.WARSHIP:
		var tower: MeshInstance3D = MeshInstance3D.new()
		var tower_mesh: CylinderMesh = CylinderMesh.new()
		tower_mesh.top_radius = 0.5
		tower_mesh.bottom_radius = 0.6
		tower_mesh.height = 1.0
		tower.mesh = tower_mesh
		var tower_mat: StandardMaterial3D = StandardMaterial3D.new()
		tower_mat.albedo_color = Color(0.30, 0.20, 0.10)
		tower_mat.roughness = 0.8
		tower.material_override = tower_mat
		tower.position = Vector3(0, 1.0, 0)
		add_child(tower)

func _process(delta: float) -> void:
	_anim_time += delta
	var bob: float = sin(_anim_time * 1.5) * 0.05
	_hull.position.y = -0.2 + bob
	_deck.position.y = 0.25 + bob
	if _sail:
		_sail.rotation.y = sin(_anim_time * 0.8) * 0.1
	if _flag:
		_flag.rotation.y = sin(_anim_time * 3.0) * 0.3
	for i in range(_oars.size()):
		var oar: MeshInstance3D = _oars[i]
		var side: int = 1 if i % 2 == 0 else -1
		oar.rotation.z = side * (0.5 + sin(_anim_time * 4.0 + i) * 0.3)
