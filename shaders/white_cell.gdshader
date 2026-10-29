shader_type spatial;
// Lumpy, wobbling leukocyte.
render_mode specular_schlick_ggx;

uniform vec3 albedo : source_color = vec3(0.93, 0.87, 0.82);
uniform vec3 rim_glow : source_color = vec3(0.55, 0.45, 0.7);
uniform float seed = 0.0;
uniform float hurt = 0.0;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.17, 0.13));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash3(i), hash3(i + vec3(1.0, 0.0, 0.0)), f.x),
			mix(hash3(i + vec3(0.0, 1.0, 0.0)), hash3(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0.0, 0.0, 1.0)), hash3(i + vec3(1.0, 0.0, 1.0)), f.x),
			mix(hash3(i + vec3(0.0, 1.0, 1.0)), hash3(i + vec3(1.0, 1.0, 1.0)), f.x), f.y),
		f.z);
}

varying float bump;

void vertex() {
	float t = TIME * 0.7 + seed;
	float n = noise3(VERTEX * 2.3 + vec3(t, seed, -t * 0.5));
	float n2 = noise3(VERTEX * 6.0 + vec3(seed * 3.0));
	bump = n;
	VERTEX += NORMAL * ((n - 0.5) * 0.55 + (n2 - 0.5) * 0.12);
}

void fragment() {
	vec3 c = mix(albedo * 0.75, albedo, bump);
	c = mix(c, vec3(1.0, 0.3, 0.3), hurt);
	ALBEDO = c;
	ROUGHNESS = 0.45;
	SPECULAR = 0.4;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	EMISSION = rim_glow * fres * 0.9 + vec3(0.12, 0.08, 0.1) + vec3(1.0, 0.2, 0.2) * hurt * 0.8;
}
