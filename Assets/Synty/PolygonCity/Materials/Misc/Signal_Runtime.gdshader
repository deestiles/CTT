shader_type spatial;

// Generic traffic-signal lens emission. Lens centres are supplied as uniforms
// (model space), computed from each signal mesh's bounding box, so this works on
// every signal variant (SM_Prop_TrafficLight, SM_Prop_LightPole_Lights, ...).

uniform sampler2D source_texture : source_color, filter_linear_mipmap_anisotropic;
uniform int signal_state = 0;                 // 0 red, 1 amber, 2 green
uniform vec3 red_center = vec3(0.0, -0.157, 0.10);
uniform vec3 amber_center = vec3(0.0, -0.465, 0.10);
uniform vec3 green_center = vec3(0.0, -0.771, 0.10);
uniform float lens_radius = 0.11;
uniform float depth_tol = 0.07;
uniform float axis = 0.0;                      // 0 = lens face on Z (mask in XY), 1 = face on X (mask in ZY)

varying vec3 mp;

void vertex() {
	mp = VERTEX;
}

float lens_mask(vec3 center) {
	// Distance within the lens face plane, and proximity to the lens depth.
	vec2 plane = axis < 0.5 ? mp.xy : mp.zy;
	vec2 cplane = axis < 0.5 ? center.xy : center.zy;
	float depth = axis < 0.5 ? mp.z : mp.x;
	float cdepth = axis < 0.5 ? center.z : center.x;
	float radial = 1.0 - smoothstep(lens_radius * 0.75, lens_radius, distance(plane, cplane));
	float deep = 1.0 - smoothstep(depth_tol, depth_tol * 1.8, abs(depth - cdepth));
	return radial * deep;
}

void fragment() {
	vec4 s = texture(source_texture, UV);
	ROUGHNESS = 0.58;
	float dr = lens_mask(red_center);
	float da = lens_mask(amber_center);
	float dg = lens_mask(green_center);
	float all = clamp(dr + da + dg, 0.0, 1.0);
	// Darken the lens glass so the lit lens reads clearly.
	ALBEDO = mix(s.rgb, s.rgb * 0.12, all);
	float active = signal_state == 0 ? dr : (signal_state == 1 ? da : dg);
	vec3 col = signal_state == 0
		? vec3(1.0, 0.03, 0.02)
		: (signal_state == 1 ? vec3(1.0, 0.45, 0.03) : vec3(0.05, 1.0, 0.2));
	EMISSION = col * active * 4.6;
}
