shader_type spatial;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic;
uniform float tail_energy = 0.0;
uniform float brake_energy = 0.0;
uniform float reverse_energy = 0.0;

varying vec3 model_position;

void vertex() {
	model_position = VERTEX;
}

void fragment() {
	vec4 base = texture(albedo_texture, UV);
	ALBEDO = base.rgb;
	ROUGHNESS = 0.62;
	METALLIC = 0.08;
	// Polygon City bakes the lamp lenses into the body mesh. Restrict emission
	// to rear, lamp-height polygons and select the authored red/white pixels.
	float rear = 1.0 - smoothstep(-1.15, -0.72, model_position.z);
	// Mesh inspection places the authored rear lenses at z -2.26..-2.09 and
	// y 0.81..1.01. SOURCE_COLOR sampling is linear, so thresholds must also
	// be linear rather than copied from the sRGB atlas values.
	float lamp_height = smoothstep(0.70, 0.80, model_position.y) * (1.0 - smoothstep(1.02, 1.12, model_position.y));
	float lamp_side = smoothstep(0.30, 0.48, abs(model_position.x));
	float red_pixel = smoothstep(0.12, 0.32, base.r) * (1.0 - smoothstep(0.10, 0.24, base.g)) * (1.0 - smoothstep(0.12, 0.27, base.b));
	float tail = rear * lamp_height * lamp_side * red_pixel;
	// The reverse section is an inner subsection of each authored lamp cluster.
	// Reusing the red-lens mask ensures white body panels can never illuminate.
	float inner_x = smoothstep(0.62, 0.68, abs(model_position.x)) * (1.0 - smoothstep(0.76, 0.83, abs(model_position.x)));
	float lower_y = smoothstep(0.77, 0.81, model_position.y) * (1.0 - smoothstep(0.87, 0.93, model_position.y));
	float reverse_lamp = tail * inner_x * lower_y;
	vec3 night_tail = vec3(0.62, 0.006, 0.002) * tail * tail_energy;
	vec3 active_brake = vec3(1.0, 0.018, 0.004) * tail * brake_energy;
	EMISSION = night_tail + active_brake + vec3(0.78, 0.9, 1.0) * reverse_lamp * reverse_energy;
}
