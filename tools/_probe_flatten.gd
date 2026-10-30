extends Node
## 探针：验证 FLATTEN 收敛速度（用户反馈"平整没有作用"后的量化检查）
## 模拟编辑器手感：strength=0.55，60fps 每帧 apply 一次，1 秒（60 帧）后
## 笔刷中心的凸起必须被压平 90% 以上才算"有作用"。

const TerrainBrush = preload("res://scripts/mapeditor/TerrainBrush.gd")

func _ready() -> void:
	var img := Image.create(256, 256, false, Image.FORMAT_RF)
	img.fill(Color(0.0, 0.0, 0.0, 1.0))
	# 造一个凸起：中心 +0.3（原始域）
	for y in range(96, 160):
		for x in range(96, 160):
			img.set_pixel(x, y, Color(0.3, 0, 0, 1))
	var mh: float = 16.0
	var strength: float = 0.55
	var dt: float = 1.0 / 60.0
	var dh: float = strength * dt / mh
	var center := Vector2(128, 128)
	var target: float = 0.0
	for frame in range(60):
		TerrainBrush.apply(img, center, 30.0, dh, 3, target)  # 3 = FLATTEN
	var h: float = img.get_pixel(128, 128).r
	var ok: bool = h < 0.03
	print("[PROBE-FLATTEN] 60 帧后中心高度 %.4f（起始 0.3）→ %s" % [h, "✅ 压平" if ok else "❌ 还是没压平"])
	get_tree().quit(0 if ok else 1)
