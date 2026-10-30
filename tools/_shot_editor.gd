extends Node
## 编辑器截图探针：加载地图编辑器，等就绪后存 PNG 验证平地白纸效果。

var _ed = null

func _ready() -> void:
	_ed = load("res://scenes/MapEditor.tscn").instantiate()
	add_child(_ed)
	# 等 focus_on 补间走完 + 首帧渲染
	await get_tree().create_timer(4.0).timeout
	get_viewport().get_texture().get_image().save_png("C:/Users/shy/桌面/Godot/_shot_editor.png")
	# 拉近看地面细节
	var cam: Node3D = _ed.get_node_or_null("CameraController")
	if cam != null and "_distance" in cam:
		cam.set("_distance", 18.0)
		await get_tree().create_timer(1.2).timeout
		get_viewport().get_texture().get_image().save_png("C:/Users/shy/桌面/Godot/_shot_editor_close.png")
	# 高度统计：验证全图平
	var h: Image = Terrain.heightmap_img
	var mn: float = 999.0
	var mx: float = -999.0
	for y in range(0, h.get_height(), 16):
		for x in range(0, h.get_width(), 16):
			var v: float = h.get_pixel(x, y).r
			mn = minf(mn, v)
			mx = maxf(mx, v)
	print("[SHOT] 高度域 min=%.4f max=%.4f (max_height=%.1f → %.2f~%.2f m)" % [
		mn, mx, Terrain.params.max_height, mn * Terrain.params.max_height, mx * Terrain.params.max_height])
	get_tree().quit(0)
