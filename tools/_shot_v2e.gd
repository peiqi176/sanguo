extends Node
## 调试：相机定位 + 高度图更新是否生效

const TerrainBrush = preload("res://scripts/mapeditor/TerrainBrush.gd")

var _ed = null

func _ready() -> void:
	_ed = load("res://scenes/MapEditor.tscn").instantiate()
	add_child(_ed)
	await get_tree().create_timer(3.0).timeout
	var ws: float = Terrain.params.world_size
	var sz: int = Terrain.heightmap_img.get_width()
	var hc: Vector2 = TerrainBrush.world_to_pixel(Vector3(190, 0, 100), ws, sz)
	var hr: float = TerrainBrush.world_radius_to_pixel(14.0, ws, sz)
	var rect: Rect2i = TerrainBrush.apply(Terrain.heightmap_img, hc, hr, 1.30, TerrainBrush.Mode.RAISE, 0.0)
	Terrain.heightmap_tex.update(Terrain.heightmap_img)
	print("[DBG] 笔刷矩形 ", rect, "  中心高度 %.2fm" % Terrain.get_height(190, 100))
	var cam: Node3D = _ed.get_node_or_null("CameraController")
	print("[DBG] cam=", cam)
	if cam != null:
		print("[DBG] 有 _distance: ", "_distance" in cam, "  有 focus_on: ", cam.has_method("focus_on"))
		if cam.has_method("focus_on"):
			cam.focus_on(Vector3(190, 0, 100))
		if "_distance" in cam:
			cam.set("_distance", 36.0)
		await get_tree().create_timer(1.8).timeout
		print("[DBG] _target=", cam.get("_target"), "  cam全局位置=", (cam as Node3D).global_position)
		get_viewport().get_texture().get_image().save_png("C:/Users/shy/桌面/Godot/_shot_rock_close.png")
		print("[SHOT] saved")
	get_tree().quit(0)
