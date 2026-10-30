extends SceneTree
func _init():
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.frequency = 1.0
	n.fractal_octaves = 1
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	var d1 := 0.0
	for x in range(0, 50):
		d1 += abs(n.get_noise_2d(float(x + 1), 0.0) - n.get_noise_2d(float(x), 0.0))
	print("[FREQ] property=1.0 每米平均变化 %.4f" % (d1 / 50.0))
	# 等价性：property=0.01 与 property=1.0 + 外部乘 0.01 是否一致
	n.frequency = 0.01
	var a: float = n.get_noise_2d(37.0, 11.0)
	n.frequency = 1.0
	var b: float = n.get_noise_2d(0.37, 0.11)
	print("[FREQ] prop=0.01@(37,11)=%.6f  vs  prop=1.0@(0.37,0.11)=%.6f  → 内部乘 frequency: %s" % [a, b, str(abs(a - b) < 1e-6)])
	quit()
