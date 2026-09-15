shader_type spatial;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic;
uniform float tail_energy = 0.0;
uniform float brake_energy = 0.0;
uniform float reverse_energy = 0.0;
uniform vec2 tail_z_range = vec2(-2.30, -2.05);
uniform vec2 tail_y_range = vec2(0.75, 1.06);
uniform vec2 tail_abs_x_range = vec2(0.50, 0.98);

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
	// Every Polygon vehicle has different lamp geometry. Runtime code supplies
	// ranges measured from each individual body mesh rather than applying the
	// police car's coordinates to the entire fleet.
	float rear = smoothstep(tail_z_range.x, tail_z_range.x + 0.035, model_position.z) * (1.0 - smoothstep(tail_z_range.y - 0.035, tail_z_range.y, model_position.z));
	float lamp_height = smoothstep(tail_y_range.x, tail_y_range.x + 0.035, model_position.y) * (1.0 - smoothstep(tail_y_range.y - 0.035, tail_y_range.y, model_position.y));
	float lamp_side = smoothstep(tail_abs_x_range.x, tail_abs_x_range.x + 0.035, abs(model_position.x)) * (1.0 - smoothstep(tail_abs_x_range.y - 0.035, tail_abs_x_range.y, abs(model_position.x)));
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
