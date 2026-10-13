extends MeshInstance3D
## Water — 带波纹动画的水面

var _time: float = 0.0
var _water_material: ShaderMaterial = null

func _ready() -> void:
	_create_water()

func _create_water() -> void:
	# 水面网格
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(40, 40)
	plane.subdivide_width = 20
	plane.subdivide_depth = 20
	mesh = plane

	# 水面着色器
	var shader: Shader = Shader.new()
	shader.code = """
shader_type spatial;
uniform vec4 water_color : source_color = vec4(0.2, 0.4, 0.6, 0.8);
uniform float wave_speed = 1.0;
uniform float wave_height = 0.15;
uniform float wave_freq = 0.3;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float wave = sin(world_pos.x * wave_freq + TIME * wave_speed) * cos(world_pos.z * wave_freq + TIME * wave_speed * 0.7);
	VERTEX.y += wave * wave_height;
}

void fragment() {
	vec3 view_dir = normalize(VIEW);
	vec3 normal = normalize(NORMAL);
	float fresnel = pow(1.0 - max(dot(view_dir, normal), 0.0), 3.0);
	vec3 deep_color = water_color.rgb * 0.6;
	vec3 shallow_color = water_color.rgb * 1.2;
	vec3 final_color = mix(deep_color, shallow_color, fresnel);
	ALBEDO = final_color;
	ALPHA = water_color.a;
	METALLIC = 0.1;
	ROUGHNESS = 0.1;
	SPECULAR = 0.5;
}
"""
	_water_material = ShaderMaterial.new()
	_water_material.shader = shader
	material_override = _water_material

func _process(delta: float) -> void:
	_time += delta
