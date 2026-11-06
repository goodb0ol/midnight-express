shader_type sky;

// Deep night: a dark gradient, stars and an enormous moon. No TIME here on purpose, so
// the sky is drawn once into its radiance map and never re-rendered.
uniform vec3 moon_direction = vec3(0.0, 0.4, 0.9);
uniform float moon_radius = 0.105;
uniform vec3 zenith = vec3(0.012, 0.02, 0.06);
uniform vec3 horizon = vec3(0.055, 0.085, 0.17);

float hash13(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

float blotch(vec2 p) {
	return sin(p.x * 13.0 + 1.3) * sin(p.y * 11.0 - 0.7) + 0.6 * sin(p.x * 27.0 - p.y * 19.0 + 2.1);
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float up = clamp(dir.y, 0.0, 1.0);
	vec3 color = mix(horizon, zenith, pow(up, 0.5));

	vec3 cell = floor(dir * 170.0);
	float pick = hash13(cell);
	if (pick > 0.985 && up > 0.015) {
		vec3 center = (cell + 0.5) / 170.0;
		float near = 1.0 - smoothstep(0.0, 0.0035, distance(dir, normalize(center)));
		float tone = fract(pick * 91.7);
		color += near * mix(vec3(0.75, 0.85, 1.0), vec3(1.0, 0.9, 0.75), tone) * (0.5 + 1.3 * tone);
	}

	vec3 moon = normalize(moon_direction);
	float angle = acos(clamp(dot(dir, moon), -1.0, 1.0));
	color += vec3(0.22, 0.28, 0.42) * exp(-angle * 5.5) * 0.9;
	if (angle < moon_radius + 0.004) {
		vec3 east = normalize(cross(vec3(0.0, 1.0, 0.0), moon));
		vec3 north = cross(moon, east);
		vec2 face = vec2(dot(dir, east), dot(dir, north)) / moon_radius;
		float rim = sqrt(max(1.0 - dot(face, face), 0.0));
		float seas = smoothstep(-0.1, 0.7, blotch(face));
		vec3 surface = mix(vec3(1.25, 1.28, 1.25), vec3(0.62, 0.68, 0.76), seas * 0.75);
		surface *= 0.72 + 0.28 * rim;
		color = mix(color, surface, 1.0 - smoothstep(moon_radius - 0.003, moon_radius + 0.003, angle));
	}
	COLOR = color;
}
