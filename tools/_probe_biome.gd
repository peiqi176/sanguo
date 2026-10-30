extends SceneTree
func _init():
	var T = load("res://scripts/core/Terrain.gd").new()
	var p = T.default_params()
	p.seed = 20261016
	p.world_size = 168.0
	p.island_center_factor = 0.5
	p.island_radius = 168.0 * 0.95
	T.generate(p)
	var b = T.biome_img
	var acc = [0.0, 0.0, 0.0]
	var n = 0
	for y in range(0, 256, 3):
		for x in range(0, 256, 3):
			var c = b.get_pixel(x, y)
			acc[0] += c.r; acc[1] += c.g; acc[2] += c.b
			n += 1
	print("[BIOME] 平均 forest=%.3f dirt=%.3f stone=%.3f" % [acc[0] / n, acc[1] / n, acc[2] / n])
	b.save_png("res://docs/_biome.png")
	var h = T.heightmap_img
	var mn = 1e9
	var mx = -1e9
	for y in range(0, 256, 3):
		for x in range(0, 256, 3):
			var v = h.get_pixel(x, y).r * p.max_height
			mn = min(mn, v); mx = max(mx, v)
	print("[BIOME] 高度 %.2f .. %.2f" % [mn, mx])
	quit()
