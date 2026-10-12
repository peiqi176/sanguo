extends StaticBody3D
class_name ResourceNode
## ResourceNode — 资源点（森林=木、铁矿=石、农田=粮）
## 农夫右键采集，可枯竭

@export var resource_type: String = "wood"  # wood/stone/food
@export var amount: float = 1000.0
@export var gather_rate: float = 5.0  # 每秒采集量

var _selection_ring: MeshInstance3D = null

func _ready() -> void:
	GameManager.resource_nodes.append(self)
	_create_visual()

func _create_visual() -> void:
	var sprite: Sprite3D = Sprite3D.new()
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.shaded = false
	sprite.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var adef: Dictionary = DataLoader.get_asset_def("resource_nodes", resource_type)
	if not adef.is_empty():
		var tex: Texture2D = DataLoader.get_sprite_texture("resource_nodes", resource_type)
		if tex:
			sprite.texture = tex
		var s: float = float(adef.get("scale", 1.5))
		sprite.scale = Vector3(s, s, s)
		sprite.position.y = float(adef.get("offset_y", 0.5))
	add_child(sprite)

func gather(unit: Unit, delta: float) -> void:
	if amount <= 0:
		_exhausted()
		return
	var gathered: float = min(gather_rate * delta, amount)
	amount -= gathered
	# 农夫背包机制简化：累加到单位
	if not unit.has_meta("carrying"):
		unit.set_meta("carrying", { "type": resource_type, "amount": 0.0 })
	var carrying: Dictionary = unit.get_meta("carrying")
	carrying["amount"] += gathered
	# 满载则返回仓库
	if carrying["amount"] >= 12.0:
		unit.state = Unit.State.RETURNING

func _exhausted() -> void:
	GameManager.resource_nodes.erase(self)
	queue_free()

