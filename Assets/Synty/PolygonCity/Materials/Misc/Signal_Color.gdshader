shader_type spatial;

// Traffic-signal emission by lens HUE. Polygon City bakes the red/amber/green
// lens glass into the mesh; we classify saturated pixels by hue and light the one
// matching the current state. Self-locating across signal meshes and both gantry
// heads. `emit_zmask` masks out a mid-arm street-name sign on the gantry.

uniform sampler2D source_texture : source_color, filter_linear_mipmap_anisotropic;
uniform int signal_state = 0;            // 0 red, 1 amber, 2 green
uniform float boost = 6.0;
uniform float emit_zmask = 0.0;          // 1 = only emit near the two arm ends
uniform float zmask_low = 1.5;
uniform float zmask_high = 4.7;

varying vec3 mp;

void vertex() {
	mp = VERTEX;
}

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

void fragment() {
	vec4 s = texture(source_texture, UV);
	ROUGHNESS = 0.55;
	vec3 hsv = rgb2hsv(s.rgb);
	float hue = hsv.x * 360.0;
	float sat = hsv.y;
	float val = hsv.z;
	// A lens pixel: strongly coloured and not pure black.
	// Lens glass is strongly saturated but DARK; the yellow housing is bright, so
	// cap the value to reject the housing.
	float lens = smoothstep(0.45, 0.65, sat) * smoothstep(0.015, 0.04, val) * (1.0 - smoothstep(0.30, 0.45, val));
	float red_m = lens * (1.0 - smoothstep(7.0, 13.0, hue));
	// Amber lens hue ~15; keep well below the yellow housing (~50).
	float amber_m = lens * smoothstep(9.0, 16.0, hue) * (1.0 - smoothstep(26.0, 40.0, hue));
	float green_m = lens * smoothstep(75.0, 95.0, hue) * (1.0 - smoothstep(165.0, 185.0, hue));
	float zm = 1.0;
	if (emit_zmask > 0.5) {
		zm = clamp(step(mp.z, zmask_low) + step(zmask_high, mp.z), 0.0, 1.0);
	}
	float all = clamp(red_m + amber_m + green_m, 0.0, 1.0) * zm;
	ALBEDO = mix(s.rgb, s.rgb * 0.35, all);
	float active = signal_state == 0 ? red_m : (signal_state == 1 ? amber_m : green_m);
	vec3 col = signal_state == 0
		? vec3(1.0, 0.03, 0.02)
		: (signal_state == 1 ? vec3(1.0, 0.5, 0.03) : vec3(0.05, 1.0, 0.2));
	EMISSION = col * active * boost * zm;
}
