extends Node
## 森林地面 + 随机感验证：编辑器刷一片林地地被，近/远两张截图。

const SplatBrush = preload("res://scripts/mapeditor/SplatBrush.gd")
const TerrainBrush = preload("res://scripts/mapeditor/TerrainBrush.gd")

var _ed = null

func _ready() -> void:
	_ed = load("res://scenes/MapEditor.tscn").instantiate()
	add_child(_ed)
	await get_tree().create_timer(3.0).timeout
	var ws: float = Terrain.params.world_size
	var ssz: int = Terrain.SPLAT_SIZE
	# 刷一片不规则林地（多圆叠加）
	var centers := [Vector2(85, 70), Vector2(100, 78), Vector2(112, 66), Vector2(93, 88), Vector2(115, 85)]
	for cc in centers:
		var c: Vector2 = TerrainBrush.world_to_pixel(Vector3(cc.x, 0, cc.y), ws, ssz)
		var r: float = TerrainBrush.world_radius_to_pixel(14.0, ws, ssz)
		SplatBrush.apply(Terrain.splat_img, c, r, SplatBrush.Layer.FOREST, 1.0)
	Terrain.refresh_splat_texture()
	var cam: Node3D = _ed.get_node_or_null("CameraController")
	if cam != null:
		if cam.has_method("focus_on"):
			cam.focus_on(Vector3(100, 0, 76))
		if "_distance" in cam:
			cam.set("_distance", 18.0)
		await get_tree().create_timer(2.2).timeout
		get_viewport().get_texture().get_image().save_png("C:/Users/shy/桌面/Godot/_shot_forest.png")
		# 远景看整体随机感
		if cam.has_method("focus_on"):
			cam.focus_on(Vector3(ws * 0.45, 0, ws * 0.45))
		cam.set("_distance", 120.0)
		await get_tree().create_timer(2.2).timeout
		get_viewport().get_texture().get_image().save_png("C:/Users/shy/桌面/Godot/_shot_forest_far.png")
	get_tree().quit(0)
