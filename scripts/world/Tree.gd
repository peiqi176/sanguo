extends Node3D
## Tree — 手绘立绘交叉面片树（X-cross，傲世三国 / 帝国2代高清版的标准做法）
##
## 为什么从低多边形球树换成这个：
##   球+锥的低多边形树是"程序感"的最大来源——一眼就是几何体拼的。
##   手绘立绘 + 双交叉面片任意方位角都成立（两面互成 90°，总有一面朝向视线 45° 内），
##   配 alpha_scissor 还能投出正确的树形阴影。
##
## 视角约定（docs/美术锚点规范_v1.md 第 7 节）：立绘 = 等距俯视 3/4 前视角（俯角 32°），
## 与相机 DEFAULT_PITCH/YAW 一致；树保持竖直（不像建筑那样后仰），是经典 RTS 读法。

enum TreeType { PINE, OAK, BIRCH, DEAD }

const TEX_DIR := "res://assets/trees/"
# 每种树的目标世界高度（米）——按 png 内容 alpha 包围盒实测换算 pixel_size
const WORLD_H := {
	TreeType.PINE: 7.0,
	TreeType.OAK: 5.8,
	TreeType.BIRCH: 6.4,
	TreeType.DEAD: 4.6,
}

var tree_type: int = TreeType.PINE
var _sway_offset: float = 0.0
var _sway_amp: float = 0.0

func _ready() -> void:
	_sway_offset = randf() * TAU
	_sway_amp = randf_range(0.008, 0.02)

	var tex: Texture2D = _pick_texture()
	if tex == null:
		push_warning("[Tree] 没有树贴图（assets/trees/*.png 缺失），树将不可见")
		return

	# 内容高度（米/像素）：世界高 / 内容像素高
	var psize: float = WORLD_H.get(tree_type, 6.0) / _content_height_px(tex)
	psize *= randf_range(0.85, 1.2)

	var yaw: float = deg_to_rad(45.0)   # 与相机方位角一致，让主面正对视线
	for i in range(2):
		var sp := Sprite3D.new()
		sp.texture = tex
		sp.pixel_size = psize
		sp.shaded = true                    # 吃场景光照，否则夜里/阴影里会自发光
		sp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD   # 阈值剪裁透明 + 正确投影
		sp.alpha_scissor_threshold = 0.45
		sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		sp.rotation.y = yaw + i * PI * 0.5
		sp.flip_h = (i == 1)                # 背面镜像，两面不完全一样
		sp.position.y = psize * _content_height_px(tex) * 0.5   # 底边贴地（Sprite 居中）
		add_child(sp)

func _pick_texture() -> Texture2D:
	var name: String = ""
	match tree_type:
		TreeType.PINE: name = "pine"
		TreeType.OAK:
			# 25% 秋色变种，让树林有季节层次（AoE4 截图里秋树是点睛之笔）
			name = "autumn" if randf() < 0.25 else "oak"
		TreeType.BIRCH: name = "birch"
		TreeType.DEAD: name = "dead"
	if name == "":
		return null
	var p: String = TEX_DIR + name + ".png"
	# ResourceLoader.exists 对"编辑器还没导入的 PNG"会说谎，必须 FileAccess 兜底
	if not FileAccess.file_exists(p):
		return null
	var img: Image = Image.load_from_file(ProjectSettings.globalize_path(p))
	if img == null:
		return null
	img.generate_mipmaps()   # 远看不清锯齿的关键
	return ImageTexture.create_from_image(img)

## 内容像素高：优先用 Image 实测 alpha 包围盒，取不到就用整张图高
func _content_height_px(tex: Texture2D) -> float:
	var h: float = float(tex.get_height())
	var img: Image = tex.get_image()
	if img != null:
		if img.is_compressed():
			img.decompress()
		var bbox := img.get_used_rect()
		if bbox.size.y > 0:
			h = float(bbox.size.y)
	return h

func _process(_delta: float) -> void:
	# 微风吹动（幅度很小：交叉面片整体倾斜会把底边摇离地面，所以只晃一丝丝）
	var t: float = Time.get_ticks_msec() / 1000.0
	rotation.z = sin(t * 0.9 + _sway_offset) * _sway_amp
	rotation.x = cos(t * 1.1 + _sway_offset) * _sway_amp * 0.7
