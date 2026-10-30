extends Node
## 自测：造一张"中间有座山"的地图存盘 → 用 custom 模式进游戏，验证高度真的被读进来。
## 用法：godot --headless --path . --quit-after 120 res://tools/_selftest_custom.tscn

func _ready() -> void:
	var p = Terrain.default_params()
	Terrain.generate(p)
	var img: Image = Terrain.heightmap_img
	var sz: int = img.get_width()
	var c: float = float(sz) * 0.5
	for py in range(sz):
		for px in range(sz):
			var d: float = Vector2(float(px) - c, float(py) - c).length()
			if d < float(sz) * 0.12:
				img.set_pixel(px, py, Color(0.95, 0.0, 0.0, 1.0))
	Terrain.heightmap_tex.update(img)

	var dir: String = "user://maps/_selftest/"
	DirAccess.make_dir_recursive_absolute(dir)
	var f: FileAccess = FileAccess.open(dir + "height.raw", FileAccess.WRITE)
	f.store_32(sz)
	f.store_32(sz)
	f.store_buffer(img.get_data())
	f.close()
	var meta: Dictionary = {
		"version": 1, "name": "_selftest",
		"terrain": {"max_height": p.max_height, "water_level": p.water_level, "world_size": p.world_size, "seed": p.seed},
		"objects": [], "players": [],
	}
	var jf: FileAccess = FileAccess.open(dir + "map.json", FileAccess.WRITE)
	jf.store_string(JSON.stringify(meta))
	jf.close()
	print("[SELFTEST] 测试地图已写出（中心山体 h=0.95 → %.1f m）" % (0.95 * p.max_height))
	GameManager.game_settings_override = {"map_mode": "custom", "map_saved_name": "_selftest"}
	get_tree().change_scene_to_file("res://scenes/Main.tscn")
