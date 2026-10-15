shader_type canvas_item;
// Voile du joueur invisible : bords de l'écran teintés qui ondulent doucement.
uniform vec4 tint : source_color = vec4(0.45, 0.78, 1.0, 1.0);
uniform float strength = 1.0;

void fragment() {
	vec2 uv = UV - 0.5;
	float d = length(uv * vec2(1.5, 1.0));
	float edge = smoothstep(0.42, 0.85, d);
	float wave = 0.5 + 0.5 * sin(TIME * 3.0 + (uv.x - uv.y) * 16.0);
	COLOR = vec4(tint.rgb, edge * (0.32 + 0.22 * wave) * strength);
}
