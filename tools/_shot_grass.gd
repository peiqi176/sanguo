extends Node
## 草地观感验证：默认草地近景（和用户截图同机位）+ 中景

var _ed = null

func _ready() -> void:
	_ed = load("res://scenes/MapEditor.tscn").instantiate()
	add_child(_ed)
	await get_tree().create_timer(3.0).timeout
	var cam: Node3D = _ed.get_node_or_null("CameraController")
	if cam != null:
		if cam.has_method("focus_on"):
			cam.focus_on(Vector3(150, 0, 150))
		if "_distance" in cam:
			cam.set("_distance", 22.0)
		await get_tree().create_timer(2.2).timeout
		get_viewport().get_texture().get_image().save_png("C:/Users/shy/桌面/Godot/_shot_grass.png")
		cam.set("_distance", 48.0)
		await get_tree().create_timer(1.6).timeout
		get_viewport().get_texture().get_image().save_png("C:/Users/shy/桌面/Godot/_shot_grass_mid.png")
	get_tree().quit(0)
