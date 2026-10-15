shader_type canvas_item;
// Tache cartoon du lance-caca : grosses taches marron arrondies avec un reflet clair,
// surtout vers les bords de l'écran (le centre reste à peu près lisible).
// amount : 1 = tache fraîche, 0 = disparue (animé par hud.gd). seed : change la disposition.

uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform float seed = 0.0;
uniform vec4 color : source_color = vec4(0.45, 0.27, 0.11, 1.0);
uniform vec4 shine : source_color = vec4(0.8, 0.62, 0.42, 1.0);

float hash(float n) {
	return fract(sin(n * 12.9898 + seed * 78.233) * 43758.5453);
}

void fragment() {
	vec2 aspect = vec2(SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, 1.0);
	vec2 uv = UV * aspect;
	float blob = 0.0;
	float light = 0.0;
	for (int i = 0; i < 9; i++) {
		float fi = float(i);
		// Centres répartis, poussés vers les bords.
		vec2 c = vec2(hash(fi), hash(fi + 17.0));
		c = mix(c, step(0.5, c), 0.35) * aspect;
		float r = mix(0.06, 0.16, hash(fi + 31.0));
		float d = length(uv - c) / r;
		// Bord ondulé pour un aspect « éclaboussure ».
		float wobble = 0.12 * sin(atan(uv.y - c.y, uv.x - c.x) * 6.0 + fi);
		float inside = 1.0 - smoothstep(0.92 + wobble, 1.0 + wobble, d);
		blob = max(blob, inside);
		// Reflet : petite ellipse claire en haut à gauche de chaque tache.
		float h = length((uv - c + vec2(r * 0.35, r * 0.35)) / vec2(r * 0.32, r * 0.18));
		light = max(light, (1.0 - smoothstep(0.7, 1.0, h)) * inside);
	}
	vec3 col = mix(color.rgb, shine.rgb, light * 0.8);
	COLOR = vec4(col, blob * amount * 0.92);
}
