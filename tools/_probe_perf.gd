extends Node
## 帧时间探针：确认新加的地表装饰（3000+ Sprite3D）没把帧率拖垮。
## 必须关 vsync + 不锁帧，否则测出来永远 60fps。

var _main = null

func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_main = load("res://scenes/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().create_timer(2.5).timeout

	var n: int = 180
	var t0: int = Time.get_ticks_usec()
	for i in range(n):
		await get_tree().process_frame
	var t1: int = Time.get_ticks_usec()
	var ms: float = float(t1 - t0) / float(n) / 1000.0
	var sprites: int = 0
	var meshes: int = 0
	var stack: Array = [_main]
	while not stack.is_empty():
		var nd: Node = stack.pop_back()
		if nd is Sprite3D:
			sprites += 1
		elif nd is MeshInstance3D:
			meshes += 1
		for c in nd.get_children():
			stack.append(c)
	print("[PERF] 平均帧时 %.2f ms → %.1f fps | Sprite3D %d / MeshInstance3D %d | draw calls %d" % [
		ms, 1000.0 / maxf(ms, 0.001), sprites, meshes,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))])
	get_tree().quit(0)
