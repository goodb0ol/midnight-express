shader_type spatial;
render_mode skip_vertex_transform, unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled, fog_disabled;

// A ribbon of light kept at a fixed distance from the camera, like the sky itself. The
// plane's UV becomes angle (around the viewer) and height.
uniform float strength = 1.0;

void vertex() {
	float angle = UV.x * 5.6 + 1.4;
	float wave = sin(UV.x * 26.0 + TIME * 0.22) * 0.05 + sin(UV.x * 61.0 - TIME * 0.35) * 0.018;
	float radius = 1500.0 * (1.0 + wave);
	float low = 90.0 + 70.0 * sin(UV.x * 9.0 + TIME * 0.1);
	float high = low + 420.0 + 120.0 * sin(UV.x * 17.0 - TIME * 0.16);
	vec3 offset = vec3(cos(angle) * radius, mix(high, low, UV.y), sin(angle) * radius);
	vec3 camera = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	VERTEX = (VIEW_MATRIX * vec4(camera + offset, 1.0)).xyz;
	NORMAL = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
}

void fragment() {
	float curtain = 0.55 + 0.45 * sin(UV.x * 190.0 + sin(UV.x * 37.0 + TIME * 0.5) * 4.0);
	float rise = 1.0 - UV.y;
	float edge = smoothstep(0.0, 0.06, UV.x) * smoothstep(1.0, 0.94, UV.x);
	float fade = pow(1.0 - rise, 1.6) * smoothstep(0.0, 0.1, rise);
	vec3 tint = mix(vec3(0.1, 1.0, 0.5), vec3(0.6, 0.15, 1.0), smoothstep(0.1, 0.8, rise));
	ALBEDO = tint;
	ALPHA = clamp(curtain * fade * edge * strength * 0.5, 0.0, 1.0);
}
