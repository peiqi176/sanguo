extends RefCounted
## SpriteProjector —— 等距立绘 × 透视相机的投影对齐（全项目唯一实现）
##
## 为什么必须有这个：
##   立绘是"等距俯视 3/4 视角"画的（能同时看到物件正面和顶面，俯角 30~45°）。
##   如果把这张图当竖直广告牌立起来、再让 45° 俯角的透视相机去斜看：
##     ① 图里那块"水平"的台基/地面被竖起来 → 屏幕上变成一块斜插进地里的板；
##     ② 整个平面被透视压缩 cos(俯角) ≈ 0.707 → 物件发矮、发胖、往后倒。
##   这就是 2026-10-24 之前"建筑像悬空斜板、资源点像浮在地上的斜切板"的根因。
##
## 正确做法：让纸面**垂直于相机视线**（绕自身 X 轴后倒 90°-俯角），
##   再把"内容底边"按旋转矩阵精确推回地面原点。
##
## ⚠️ 这不是可选项，也不是"美术风格"：它是傲世三国那一代 2.5D 的标准渲染方式。
##    任何"画成等距俯视"的立绘（建筑 / 资源点 / 村庄 / 大型装饰）都必须走这里。
##    唯一的例外是**单位**（人/马）——它们用 BILLBOARD_ENABLED 全向广告牌，
##    天然垂直于视线，不需要（也不能）手动倾斜，否则一转相机就露馅。
##
## 数学推导（为什么补偿量是这三项）：
##   内容底边在 sprite 局部坐标里是 (0, -hb, 0)（hb = 中心到内容底边的距离）。
##   先绕 X 轴转 -lean（后倒），再绕 Y 轴转 yaw（对齐相机方位角）：
##     Rx(-lean): (0, -hb, 0) → (0, -hb·cosL, +hb·sinL)
##     Ry(yaw):   (x, y, z) → (x·cosY + z·sinY, y, -x·sinY + z·cosY)
##   合成后 = ( hb·sinL·sinY, -hb·cosL, hb·sinL·cosY )
##   要让它落回原点，position 取反即可。

const CameraController = preload("res://scripts/core/CameraController.gd")

## 把一张 Sprite3D 调成"垂直于相机视线 + 底边贴地"。
##   sprite  已设置 texture / pixel_size / scale 的 Sprite3D
##   hb      内容底边到图中心的距离（米）。用 DataLoader.get_sprite_anchor_y(cat, id, scale) 量。
##           传 0 时只做姿态对齐、不做贴地补偿（用于中心对称的特效图）。
##   extra   额外位移（例如放置虚影要叠加"footprint 中心偏移"），直接加在补偿量上。
static func align(sprite: Sprite3D, hb: float, extra: Vector3 = Vector3.ZERO) -> void:
	if sprite == null:
		return
	var lean: float = deg_to_rad(90.0 - CameraController.DEFAULT_PITCH_DEG)
	var yaw: float = deg_to_rad(CameraController.DEFAULT_YAW_DEG)
	sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	sprite.rotation = Vector3(-lean, yaw, 0.0)
	sprite.position = Vector3(
		-hb * sin(lean) * sin(yaw),
		hb * cos(lean),
		-hb * sin(lean) * cos(yaw)) + extra
