shader_type spatial;

uniform sampler2D source_texture : source_color, filter_linear_mipmap_anisotropic;
uniform int signal_state = 0;

varying vec3 model_position;

void vertex() {
	model_position = VERTEX;
}

void fragment() {
	vec4 sampled = texture(source_texture, UV);
	ALBEDO = sampled.rgb;
	ROUGHNESS = 0.58;

	// The circular lenses are recessed at z≈0.10. Their protective hoods project
	// forward to z≈0.264, so a narrow depth band is essential here.
	float lens_depth = smoothstep(0.068, 0.088, model_position.z) * (1.0 - smoothstep(0.112, 0.132, model_position.z));
	float centered_x = 1.0 - smoothstep(0.105, 0.155, abs(model_position.x + 0.002));
	float red_lens = (1.0 - smoothstep(0.102, 0.125, distance(model_position.xy, vec2(0.0, -0.1569)))) * lens_depth * centered_x;
	float amber_lens = (1.0 - smoothstep(0.102, 0.125, distance(model_position.xy, vec2(0.0, -0.4651)))) * lens_depth * centered_x;
	float green_lens = (1.0 - smoothstep(0.102, 0.125, distance(model_position.xy, vec2(0.0, -0.7709)))) * lens_depth * centered_x;
	float all_lenses = clamp(red_lens + amber_lens + green_lens, 0.0, 1.0);
	ALBEDO = mix(sampled.rgb, sampled.rgb * 0.14, all_lenses);
	float active_lens = signal_state == 0 ? red_lens : (signal_state == 1 ? amber_lens : green_lens);
	vec3 active_color = signal_state == 0 ? vec3(1.0, 0.025, 0.012) : (signal_state == 1 ? vec3(1.0, 0.42, 0.025) : vec3(0.025, 1.0, 0.16));
	EMISSION = active_color * active_lens * 4.2;
}
