shader_type spatial;
render_mode skip_vertex_transform, unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled;

// Each instance keeps a fixed spot; this slides them backward and wraps them inside
// a 240 m band around the train, so no per-instance CPU work is needed.
uniform float scroll = 0.0;
uniform float stretch = 1.0;
uniform float opacity = 0.22;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float z = mod(origin.z + 120.0 + scroll, 240.0) - 120.0;
	vec3 world = VERTEX * vec3(1.0, 1.0, stretch);
	world += vec3(origin.x, origin.y, z);
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
}

void fragment() {
	ALBEDO = vec3(0.75, 0.82, 0.95);
	ALPHA = opacity;
}
