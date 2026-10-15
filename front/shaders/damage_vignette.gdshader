shader_type canvas_item;
// Vignette de dégâts du HUD : bords de l'écran teintés, centre intact.
// intensity : flash à chaque coup reçu (animé par hud.gd).
// low_health : pulsation continue quand la vie est basse (0 = pleine vie).

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float low_health : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(0.9, 0.04, 0.12, 1.0);

void fragment() {
	vec2 uv = UV - 0.5;
	uv.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x * 0.75;
	float edge = smoothstep(0.32, 0.9, length(uv));
	float pulse = low_health * (0.55 + 0.45 * sin(TIME * 5.0));
	float scan = 0.9 + 0.1 * sin(FRAGCOORD.y * 1.6);
	float a = edge * clamp(intensity + pulse * 0.55, 0.0, 1.0) * scan;
	COLOR = vec4(tint.rgb, a * tint.a);
}
