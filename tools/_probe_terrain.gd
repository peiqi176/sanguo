extends Node
## 地形剖面探针：确认岛屿下沉是否真的把边缘压到水面以下。
## 输出几个关键点的世界高度、以及高度图的分布，用来判断"边缘硬切"到底是谁的问题。

func _ready() -> void:
	var p = Terrain.params
	print("[T] world_size=%.1f  max_height=%.1f  water_level=%.1f" % [
		p.world_size, p.max_height, p.water_level])
	print("[T] island_r=%.1f  center_factor=%.2f  inner=%.2f  outer=%.2f  ocean_depth=%.3f" % [
		p.island_radius, p.island_center_factor, p.island_falloff_inner,
		p.island_falloff_outer, p.ocean_depth])

	var samples: Array = [
		Vector3(0, 0, 0), Vector3(100, 0, 100), Vector3(200, 0, 200),
		Vector3(0, 0, 100), Vector3(200, 0, 100), Vector3(100, 0, 0), Vector3(100, 0, 200),
		Vector3(40, 0, 40), Vector3(160, 0, 160), Vector3(84, 0, 84),
	]
	for s in samples:
		print("[T] h(%6.1f,%6.1f) = %7.2f m   %s" % [
			s.x, s.z, Terrain.get_height(s.x, s.z),
			"水下" if Terrain.get_height(s.x, s.z) < p.water_level else "陆地"])

	# 高度直方图（按高度图原始比例）
	var img: Image = Terrain.heightmap_img
	var sz: int = img.get_width()
	var lo: float = 9.0
	var hi: float = -9.0
	var under: int = 0
	var total: int = 0
	var wl_ratio: float = p.water_level / p.max_height
	for y in range(0, sz, 2):
		for x in range(0, sz, 2):
			var v: float = img.get_pixel(x, y).r
			lo = minf(lo, v)
			hi = maxf(hi, v)
			total += 1
			if v < wl_ratio:
				under += 1
	print("[T] 高度图比例范围 %.3f ~ %.3f（水位比例 %.3f）" % [lo, hi, wl_ratio])
	print("[T] 水下像素占比 %.1f%%" % (100.0 * float(under) / float(maxi(total, 1))))
	get_tree().quit(0)
