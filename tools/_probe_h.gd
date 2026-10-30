extends SceneTree
func _init():
	var T = load("res://scripts/core/Terrain.gd").new()
	var p = T.default_params()
	p.seed = 12345
	p.world_size = 168.0
	p.island_center_factor = 0.5
	p.island_radius = 168.0 * 0.95
	T.generate(p)
	var img = T.heightmap_img
	var mn = 1e9
	var mx = -1e9
	var sum = 0.0
	var n = 0
	for y in range(0, 256, 2):
		for x in range(0, 256, 2):
			var h = img.get_pixel(x, y).r * p.max_height
			mn = min(mn, h); mx = max(mx, h); sum += h; n += 1
	print("[H] 全图 %.2f .. %.2f  平均 %.2f" % [mn, mx, sum / n])
	# 中心区域（基地所在）波幅
	var step = p.world_size / 255.0
	var worst = 0.0
	for y in range(40, 216):
		for x in range(40, 216):
			var h0 = img.get_pixel(x, y).r * p.max_height
			var h1 = img.get_pixel(x + 1, y).r * p.max_height
			worst = max(worst, abs(h1 - h0))
	print("[H] 中心区相邻格最大高差 %.3f m（格宽 %.2f m）坡度 %.1f°" % [worst, step, rad_to_deg(atan(worst / step))])
	# 沿一条 40m 直线的高差
	var prev = null
	var arr = []
	for i in range(0, 60):
		arr.append(snappedf(img.get_pixel(80 + i, 128).r * p.max_height, 0.1))
	print("[H] 一行 60 格（%.0f m）高度: " % (60 * step), arr.slice(0, 20))
	quit()
