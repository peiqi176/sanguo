extends RefCounted
class_name WaterPlane
## 整图水面 —— 游戏场景（Main）与地图编辑器（EditorScene）共用，所见即所得。
##
## 覆盖全地形的一张大平面：地形低于 water_level 处自然显水（河流/湖泊由高度图雕刻）。
## 水深着色/岸边泡沫/波纹全在 shader 里，喂同一张高度图 + 同一套映射即可与地形对齐。

## 三档水色：岸边浅滩偏青绿（能看见河床的沙），中段青蓝，深水近墨蓝。
## 老版本只用 fresnel 在"深/浅"两色间插值 —— 那是"看角度"，不是"看水深"，
## 所以整条河永远是一块均匀的蓝板子，完全没有 AoE4 那种由浅入深的层次。
const SHADER_CODE: String = """
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque;

uniform sampler2D heightmap;      // 数据图，不加 source_color
uniform float max_height = 16.0;
uniform float world_size = 200.0;
uniform float water_level = -2.0;

uniform vec4 shallow_color : source_color = vec4(0.115, 0.345, 0.330, 1.0);
uniform vec4 mid_color : source_color = vec4(0.095, 0.280, 0.380, 1.0);
uniform vec4 deep_color : source_color = vec4(0.042, 0.110, 0.190, 1.0);

uniform float wave_speed = 1.1;
uniform float wave_height = 0.10;
uniform float wave_freq = 0.25;
uniform float foam_width = 0.16;    // 岸边泡沫带宽度（米）。⚠ 0.85→0.55→0.16：0.55m 时
                                    // 一个 0.3m 平均深的小坑有 70% 面积水深不足、全算泡沫，
                                    // 实测整坑被泡沫刷成奶白（PIL 采样定位）。只留真正水线。
uniform float flow_dir_x = 1.0;     // 流向（河流的波纹沿这个方向跑）
uniform float flow_dir_z = 0.35;

varying vec3 world_pos;

float hash12(vec2 p){
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p){
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// 水面下方地形高度（世界 Y）。用来算"水深"。
// ⚠ UV 必须与地形 shader 完全同公式：u = x/ws, v = 1 - z/ws（CPU 侧 Terrain.get_height 同款）。
// 历史 bug：这里曾写 u = x/ws + 0.5、v = 0.5 - z/ws —— 整体偏移半张图，
// clamp 后永远采到地图边缘一列像素。对战图边缘是海洋 (-14m)，水深恒为"深水"、
// 岸边泡沫从未真正出现过（被 clamp 掩盖）；平地编辑器边缘是陆地 → alpha=0 → 水面整个隐形。
float terrain_h(vec2 wxz){
	vec2 uv = vec2(wxz.x / world_size, 1.0 - wxz.y / world_size);
	return texture(heightmap, clamp(uv, vec2(0.0), vec2(1.0))).r * max_height;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float w1 = sin(world_pos.x * wave_freq + TIME * wave_speed) * cos(world_pos.z * wave_freq + TIME * wave_speed * 0.7);
	float w2 = sin(world_pos.x * wave_freq * 3.0 + TIME * wave_speed * 2.5) * cos(world_pos.z * wave_freq * 2.7 + TIME * wave_speed * 1.8);
	// 平面在 Godot 4 里是水平的，向上是局部 +Y
	VERTEX.y += w1 * wave_height + w2 * wave_height * 0.25;
}

void fragment() {
	float th = terrain_h(world_pos.xz);
	float depth = max(water_level - th, 0.0);

	// ---- 按水深着色（水位 -2m 后常见水深 0~2m，梯度相应压缩）----
	vec3 c = mix(shallow_color.rgb, mid_color.rgb, smoothstep(0.05, 1.5, depth));
	c = mix(c, deep_color.rgb, smoothstep(1.5, 5.0, depth));

	// ---- 波纹法线：两层滚动噪声 + 沿流向拉长 ----
	vec2 flow = vec2(world_pos.x * flow_dir_x + world_pos.z * flow_dir_z,
					 world_pos.z * flow_dir_x - world_pos.x * flow_dir_z);
	vec2 n_uv = flow * 0.09;
	float t = TIME * 0.22;
	float n1 = vnoise(n_uv * 3.0 + vec2(t * 1.3, t * 0.7));
	float n2 = vnoise(n_uv * 7.5 - vec2(t * 0.9, t * 1.6));
	float nx = (n1 - 0.5) * 0.55 + (n2 - 0.5) * 0.32;
	float nz = (n2 - 0.5) * 0.55 + (n1 - 0.5) * 0.32;
	vec3 wn = normalize(vec3(nx, 1.0, nz));
	NORMAL = normalize(mix(NORMAL, normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz), 0.55));

	// ---- 菲涅尔：掠射角偏亮（天光反射），强度 0.30→0.18 太亮会盖过水色 ----
	vec3 view_dir = normalize(VIEW);
	float fres = pow(1.0 - max(dot(view_dir, normalize(NORMAL)), 0.0), 3.5);
	c = mix(c, vec3(0.55, 0.68, 0.76), 0.18 * fres);

	// ---- 岸边泡沫：水深小于 foam_width 时出现，随时间轻微涌动（强度 0.85→0.7）----
	float band = 1.0 - smoothstep(0.0, foam_width, depth);
	float wobble = vnoise(vec2(world_pos.x, world_pos.z) * 2.4 + vec2(TIME * 0.5, TIME * 0.35));
	float foam = band * (0.45 + 0.55 * wobble);
	c = mix(c, vec3(0.93, 0.96, 0.97), clamp(foam * 0.55, 0.0, 0.55));

	// ---- 透明度：浅水透、深水不透；陆地边缘完全淡出，避免和岸边硬切 ----
	// 基础 alpha 0.60→0.74：0.5m 的小坑仍有 26% 亮沙底透出 + 镜面高光，
	// 实测整坑糊成奶白（_shot_water_close.png）。压住透出量 + 收敛高光后才读得出"水"。
	float alpha = mix(0.74, 0.965, smoothstep(0.0, 2.2, depth));
	alpha = max(alpha, foam * 0.8);
	alpha *= smoothstep(0.0, 0.10, depth);
	ALBEDO = c;
	ALPHA = alpha;
	METALLIC = 0.05;
	// ⚠ 相机俯角 45° ≈ 太阳仰角 45°：平静水面会把整片日光镜面反射进镜头，
	// 实测 SPEC 0.75/0.40 时整坑糊成奶白（一面广域日光镜）。压到 0.12 让
	// 水色本身主导，天光亮感只靠上面的 fresnel 混色。
	ROUGHNESS = mix(0.38, 0.16, fres);
	SPECULAR = 0.12;
}
"""

## 建一张覆盖全图的水面挂到 parent 下。
## 参数显式传入（不隐式依赖 autoload），headless 自测/探针也能用。
static func build(parent: Node3D, heightmap_tex: Texture2D,
		world_size: float, max_height: float, water_level: float) -> MeshInstance3D:
	var water: MeshInstance3D = MeshInstance3D.new()
	var pm: PlaneMesh = PlaneMesh.new()
	# 比地形大一圈：地形边缘会沉到海平面以下（edge_falloff），
	# 水面若只铺到地形边界，就会露出方方正正的"水的直边"，像块玻璃板盖在岛上。
	pm.size = Vector2(world_size * 1.6, world_size * 1.6)
	var wsub: int = clampi(int(world_size) / 2, 32, 200)
	pm.subdivide_width = wsub
	pm.subdivide_depth = wsub
	water.mesh = pm
	# PlaneMesh 天生水平，别再转 -90°（转了就是一堵看不见的墙）
	water.rotation = Vector3.ZERO
	water.position = Vector3(world_size * 0.5, water_level, world_size * 0.5)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var shader: Shader = Shader.new()
	shader.code = SHADER_CODE
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = shader
	# 水深来自同一张高度图，必须和地形 shader 用完全相同的映射，否则泡沫带会错位。
	mat.set_shader_parameter("heightmap", heightmap_tex)
	mat.set_shader_parameter("max_height", max_height)
	mat.set_shader_parameter("world_size", world_size)
	mat.set_shader_parameter("water_level", water_level)
	water.material_override = mat
	parent.add_child(water)
	return water
