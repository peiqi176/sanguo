extends MeshInstance3D
## Water — 带波纹动画的水面

var _time: float = 0.0
var _water_material: ShaderMaterial = null

func _ready() -> void:
	_create_water()

func _create_water() -> void:
	# 水面网格
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(60, 60)  # 加大到 60x60 覆盖更多河流
	plane.subdivide_width = 32
	plane.subdivide_depth = 32
	mesh = plane

	# 水面着色器：双层波纹 + fresnel + UV滚动
	var shader: Shader = Shader.new()
	shader.code = """
shader_type spatial;
uniform vec4 water_color : source_color = vec4(0.25, 0.45, 0.65, 0.85);
uniform float wave_speed = 1.2;
uniform float wave_height = 0.18;
uniform float wave_freq = 0.25;
uniform float ripple_strength = 1.0;  // 涟漪强度（外部可调）
uniform float uv_scroll = 0.3;        // UV 滚动速度

varying vec3 world_pos;
varying vec2 scroll_uv;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	scroll_uv = UV + vec2(TIME * uv_scroll, TIME * uv_scroll * 0.7);
	
	// 主波纹层（大而慢）
	float wave1 = sin(world_pos.x * wave_freq + TIME * wave_speed) * cos(world_pos.z * wave_freq + TIME * wave_speed * 0.7);
	// 次波纹层（小而快，让水面有细碎波纹）
	float wave2 = sin(world_pos.x * wave_freq * 3.0 + TIME * wave_speed * 2.5) * cos(world_pos.z * wave_freq * 2.7 + TIME * wave_speed * 1.8);
	VERTEX.y += wave1 * wave_height * ripple_strength + wave2 * wave_height * 0.25 * ripple_strength;
}

void fragment() {
	vec3 view_dir = normalize(VIEW);
	vec3 normal = normalize(NORMAL);
	float fresnel = pow(1.0 - max(dot(view_dir, normal), 0.0), 3.0);
	vec3 deep_color = water_color.rgb * 0.5;
	vec3 shallow_color = water_color.rgb * 1.3;
	vec3 final_color = mix(deep_color, shallow_color, fresnel);
	
	// 叠加 UV 滚动的高光条纹（让水面有流动感）
	float shimmer = sin(scroll_uv.x * 40.0) * 0.08 + 0.05;
	final_color += vec3(shimmer) * ripple_strength;
	
	ALBEDO = final_color;
	ALPHA = water_color.a;
	METALLIC = 0.15;
	ROUGHNESS = 0.08;
	SPECULAR = 0.7;
}
"""
	_water_material = ShaderMaterial.new()
	_water_material.shader = shader
	material_override = _water_material

func _process(delta: float) -> void:
	_time += delta
