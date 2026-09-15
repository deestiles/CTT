shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D source_texture : source_color, filter_linear_mipmap_anisotropic;
uniform vec3 warm_light : source_color = vec3(1.0, 0.58, 0.22);
uniform float emission_energy : hint_range(0.0, 8.0) = 0.0;

void fragment() {
	vec4 tex = texture(source_texture, UV);
	ALBEDO = tex.rgb;
	ROUGHNESS = 0.48;
	SPECULAR = 0.35;
	// The supplied window prop remains the visible surface. Its authored atlas
	// detail stays intact while the whole inset receives a broad stylized glow.
	EMISSION = warm_light * emission_energy * (0.55 + tex.rgb * 0.45);
}
