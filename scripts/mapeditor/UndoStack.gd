extends RefCounted
## UndoStack —— 地形笔刷的撤销/重做栈（按脏矩形存差量，不存整图）
##
## 为什么不能存整图：
##   512² 的 FORMAT_RF 是 1MB/张，32 步就是 32MB。每次落笔拷一份会明显卡顿，
##   而且用户真正在意的只是"刚才那一小块"。
##
## 一次拖动的内存账：
##   起笔时 1 份 full（1MB，临时）→ 松笔时裁成 region（约 40KB）→ 丢弃 full。
##   稳态每条 40KB 左右，32 步 ≈ 1.3MB。
##
## 为什么不逐帧存：
##   拖动时每帧都调 apply()，逐帧入栈会让 32 步在 0.5 秒内被填满，
##   Ctrl+Z 一下只撤销一帧的改动，等于没法用。
##   所以：begin() 一次 → mark() 累积 union → end() 合并成一条。

const DEFAULT_MAX: int = 32

var max_steps: int = DEFAULT_MAX

var _stack: Array = []       # [{ "rect": Rect2i, "before": Image, "after": Image }]
var _redo: Array = []

var _stroke_active: bool = false
var _stroke_full: PackedByteArray = PackedByteArray()
var _stroke_size: int = 0
var _stroke_format: int = Image.FORMAT_RF
var _stroke_rect: Rect2i = Rect2i()

# ---------------------------------------------------------------- 笔画生命周期

## 起笔：只做一次整图快照（临时），松笔时会裁掉
func begin(img: Image) -> void:
	if img == null:
		return
	_stroke_full = img.get_data()
	_stroke_size = img.get_width()
	_stroke_format = img.get_format()
	_stroke_rect = Rect2i()
	_stroke_active = true

## 每帧 apply() 之后调用，累积本次笔画的脏区域
func mark(rect: Rect2i) -> void:
	if not _stroke_active:
		return
	if rect.size.x <= 0 or rect.size.y <= 0:
		return
	if _stroke_rect.size.x <= 0:
		_stroke_rect = rect
	else:
		_stroke_rect = _stroke_rect.merge(rect)

## 松笔：把这一整次拖动合并成一条撤销记录
func end(img: Image) -> bool:
	if not _stroke_active:
		return false
	_stroke_active = false

	var rect: Rect2i = _stroke_rect
	var full: PackedByteArray = _stroke_full
	var sz: int = _stroke_size
	var fmt: int = _stroke_format

	_stroke_full = PackedByteArray()
	_stroke_rect = Rect2i()

	if img == null or rect.size.x <= 0 or rect.size.y <= 0 or full.is_empty():
		return false
	# 尺寸变了（换了地图）就别拿旧的快照去切
	if sz != img.get_width() or sz != img.get_height():
		return false

	var pre: Image = Image.create_from_data(sz, sz, false, fmt, full)
	if pre == null:
		return false

	var before: Image = pre.get_region(rect)
	var after: Image = img.get_region(rect)
	if before == null or after == null:
		return false
	# 前后完全一样（比如只是点了一下没拖动）就不占栈位
	if before.get_data() == after.get_data():
		return false

	_stack.append({"rect": rect, "before": before, "after": after})
	if _stack.size() > max_steps:
		_stack.pop_front()
	_redo.clear()
	return true

## 中断笔画（切图、按 Esc 等）：丢掉临时快照，不入栈
func abort() -> void:
	_stroke_active = false
	_stroke_full = PackedByteArray()
	_stroke_rect = Rect2i()

## 只清重做链，不动撤销记录。
## 场景：编辑器同时有高度/拼图两条栈，任何一条入新记录时，
## 另一条的重做链也必须作废（否则 Ctrl+Y 会把很久以前的改动乱序翻出来）。
func clear_redo() -> void:
	_redo.clear()

# ---------------------------------------------------------------- 撤销 / 重做

func undo(img: Image) -> bool:
	if _stack.is_empty() or img == null:
		return false
	var e = _stack.pop_back()
	# 撤销 = 把 before 贴回去
	if not _blit_region(img, e["rect"], e["before"]):
		_stack.append(e)
		return false
	_redo.append(e)
	return true

func redo(img: Image) -> bool:
	if _redo.is_empty() or img == null:
		return false
	var e = _redo.pop_back()
	# 重做 = 把 after 贴回去
	if not _blit_region(img, e["rect"], e["after"]):
		_redo.append(e)
		return false
	_stack.append(e)
	return true

func _blit_region(img: Image, rect: Rect2i, region: Image) -> bool:
	if region == null:
		return false
	if region.get_width() != rect.size.x or region.get_height() != rect.size.y:
		return false
	if rect.position.x < 0 or rect.position.y < 0:
		return false
	if rect.position.x + rect.size.x > img.get_width():
		return false
	if rect.position.y + rect.size.y > img.get_height():
		return false
	img.blit_rect(region, Rect2i(Vector2i.ZERO, region.get_size()), rect.position)
	return true

# ---------------------------------------------------------------- 状态查询

func can_undo() -> bool:
	return _stack.size() > 0

func can_redo() -> bool:
	return _redo.size() > 0

func undo_count() -> int:
	return _stack.size()

func redo_count() -> int:
	return _redo.size()

func clear() -> void:
	_stack.clear()
	_redo.clear()
	abort()

## 估算占用字节数（调试/状态栏用）
func memory_bytes() -> int:
	var n: int = 0
	for e in _stack:
		var b: Image = e["before"]
		var a: Image = e["after"]
		if b != null:
			n += b.get_data().size()
		if a != null:
			n += a.get_data().size()
	for e in _redo:
		var b2: Image = e["before"]
		var a2: Image = e["after"]
		if b2 != null:
			n += b2.get_data().size()
		if a2 != null:
			n += a2.get_data().size()
	return n
