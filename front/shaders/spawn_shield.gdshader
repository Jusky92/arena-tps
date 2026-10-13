shader_type spatial;
// Bulle de protection d'apparition : contour lumineux (effet Fresnel), lignes de
// balayage qui montent, et clignotement quand la protection se termine.
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

uniform vec4 color : source_color = vec4(0.3, 0.9, 1.0, 1.0);
// 1.0 = protection pleine, 0.0 = terminée (piloté par le script du joueur).
uniform float strength : hint_range(0.0, 1.0) = 1.0;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	float scan = smoothstep(0.75, 1.0, sin(local_pos.y * 22.0 - TIME * 6.0) * 0.5 + 0.5);
	float hex = abs(sin(local_pos.x * 18.0) * sin(local_pos.y * 18.0 + local_pos.z * 10.0));
	float pattern = fresnel * 0.9 + scan * 0.12 + step(0.92, hex) * 0.06;
	// Clignote quand il reste peu de temps.
	float blink = strength < 0.3 ? 0.55 + 0.45 * sin(TIME * 30.0) : 1.0;
	float pulse = 0.85 + 0.15 * sin(TIME * 4.0);
	ALBEDO = color.rgb * pattern * pulse * blink * strength * 1.6;
}
