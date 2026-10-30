extends Node
## 尖峰周期探针：纯基线跑 600 帧，打印每个 >25ms 尖峰的时刻，找周期。

var _main = null

func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_main = load("res://scenes/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().create_timer(2.5).timeout
	var t_start: int = Time.get_ticks_msec()
	var n: int = 600
	var t0: int = Time.get_ticks_usec()
	var worst: float = 0.0
	var spikes: Array = []
	for i in range(n):
		var f0: int = Time.get_ticks_usec()
		await get_tree().process_frame
		var ms: float = float(Time.get_ticks_usec() - f0) / 1000.0
		if ms > 25.0:
			spikes.append([Time.get_ticks_msec() - t_start, ms])
		worst = maxf(worst, ms)
	var total: float = float(Time.get_ticks_usec() - t0) / 1000.0
	print("[SPIKE] 600帧平均 %.2f ms (%.1f fps)，最差 %.1f ms，尖峰数 %d" % [
		total / float(n), 1000.0 * float(n) / total, worst, spikes.size()])
	for s in spikes:
		print("[SPIKE]   t=%.2fs  %.1fms" % [float(s[0]) / 1000.0, s[1]])
	get_tree().quit(0)
