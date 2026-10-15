shader_type canvas_item;
// Fond de l'écran de mort : voile rouge sombre, lignes de balayage et bandes
// « glitch » qui sautent de temps en temps (même esprit que le fond des menus).

uniform vec4 tint : source_color = vec4(0.22, 0.0, 0.03, 0.55);
uniform float glitch : hint_range(0.0, 1.0) = 0.35;

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	float t = floor(TIME * 8.0);
	float band = step(0.965, hash(floor(uv.y * 24.0) + t * 13.1)) * glitch;
	float scan = 0.85 + 0.15 * sin(FRAGCOORD.y * 2.2 + TIME * 30.0);
	float vignette = smoothstep(0.9, 0.2, length(uv - 0.5));
	vec3 col = tint.rgb * (1.2 - vignette * 0.4) + vec3(0.9, 0.1, 0.3) * band * 0.35;
	COLOR = vec4(col, (tint.a + band * 0.2) * scan);
}
