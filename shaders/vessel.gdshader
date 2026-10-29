shader_type spatial;
// Wet, veiny vessel wall seen from the inside. Pulses with the heartbeat.
render_mode cull_disabled, specular_schlick_ggx;

uniform vec3 base_color : source_color = vec3(0.70, 0.07, 0.07);
uniform vec3 dark_color : source_color = vec3(0.26, 0.0, 0.025);
uniform vec3 vein_color : source_color = vec3(0.16, 0.0, 0.07);
uniform vec3 glow_color : source_color = vec3(1.0, 0.16, 0.1);
uniform float beat = 0.0;

varying vec3 cyl;

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

void vertex() {
	// Seamless around the tube: sample noise on a cylinder.
	float a = UV.x * 6.2831853;
	cyl = vec3(cos(a) * 1.7, sin(a) * 1.7, UV.y);
	// NORMAL points inwards, so subtracting it expands the wall on each beat.
	VERTEX -= NORMAL * beat * 0.16;
}

void fragment() {
	vec3 p = cyl;
	float n1 = noise3(p * 2.6);
	float n2 = noise3(p * 6.5 + vec3(3.1));
	float n3 = noise3(p * 15.0 + vec3(7.7));
	float n4 = noise3(p * 34.0 + vec3(1.3));
	float tissue = n1 * 0.5 + n2 * 0.28 + n3 * 0.15 + n4 * 0.07;

	float r1 = 1.0 - abs(noise3(p * vec3(1.6, 1.6, 0.7) + vec3(11.0)) * 2.0 - 1.0);
	float r2 = 1.0 - abs(noise3(p * vec3(4.0, 4.0, 1.6) + vec3(23.0)) * 2.0 - 1.0);
	float veins = smoothstep(0.9, 0.98, r1) + smoothstep(0.93, 0.99, r2) * 0.6;
	veins = clamp(veins, 0.0, 1.0);

	// Screen-space bump mapping from the tissue height: wet, lumpy walls.
	float h = tissue * 0.9 + veins * 0.35;
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	float dhdx = dFdx(h);
	float dhdy = dFdy(h);
	vec3 rr1 = cross(dpdy, NORMAL);
	vec3 rr2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, rr1);
	vec3 grad = sign(det) * (dhdx * rr1 + dhdy * rr2);
	NORMAL = normalize(abs(det) * NORMAL - grad * 0.9);

	vec3 col = mix(dark_color, base_color, smoothstep(0.25, 0.8, tissue));
	col = mix(col, vein_color, veins * 0.8);
	ALBEDO = col;
	ROUGHNESS = mix(0.12, 0.45, n3);
	SPECULAR = 0.8;
	// Faint self-glow so the walls never go fully black, brighter on each beat.
	EMISSION = glow_color * (0.05 + beat * 0.12) * (0.35 + tissue) * (1.0 - veins * 0.6);
}
