extends Node
## 森林拼层数据侧检查：画完打印笔刷中心的实际权重

const SplatBrush = preload("res://scripts/mapeditor/SplatBrush.gd")
const TerrainBrush = preload("res://scripts/mapeditor/TerrainBrush.gd")

var _ed = null

func _ready() -> void:
	_ed = load("res://scenes/MapEditor.tscn").instantiate()
	add_child(_ed)
	await get_tree().create_timer(3.0).timeout
	var ws: float = Terrain.params.world_size
	var c: Vector2 = TerrainBrush.world_to_pixel(Vector3(95, 0, 130), ws, Terrain.SPLAT_SIZE)
	SplatBrush.apply(Terrain.splat_img, c, TerrainBrush.world_radius_to_pixel(13.0, ws, Terrain.SPLAT_SIZE), SplatBrush.Layer.FOREST, 1.0)
	Terrain.refresh_splat_texture()
	var w: Color = SplatBrush.weights_at(Terrain.splat_img, int(c.x), int(c.y))
	print("[PROBE] 笔刷中心权重 R=%.2f G=%.2f B=%.2f A=%.2f" % [w.r, w.g, w.b, w.a])
	print("[PROBE] splat_tex尺寸=%d 材质绑定=%s" % [Terrain.splat_tex.get_width(), "是" if Terrain.splat_tex != null else "无"])
	var cam: Node3D = _ed.get_node_or_null("CameraController")
	if cam != null:
		if cam.has_method("focus_on"):
			cam.focus_on(Vector3(95, 0, 130))
		if "_distance" in cam:
			cam.set("_distance", 10.0)
		await get_tree().create_timer(1.8).timeout
		get_viewport().get_texture().get_image().save_png("C:/Users/shy/桌面/Godot/_shot_forest_close.png")
	get_tree().quit(0)
