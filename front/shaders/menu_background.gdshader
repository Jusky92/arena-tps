shader_type canvas_item;
// Fond animé des menus : halos colorés, grille néon en perspective qui défile, lignes de balayage.

uniform vec4 base_color : source_color = vec4(0.027, 0.035, 0.06, 1.0);
uniform vec4 grid_color : source_color = vec4(0.18, 0.89, 0.92, 1.0);
uniform vec4 glow_a : source_color = vec4(0.95, 0.27, 0.78, 1.0);
uniform vec4 glow_b : source_color = vec4(0.18, 0.89, 0.92, 1.0);
uniform float horizon = 0.58;
uniform float speed = 0.35;

void fragment() {
	vec2 uv = UV;
	vec3 col = base_color.rgb;

	// Halos lumineux.
	col += glow_a.rgb * 0.16 * smoothstep(0.85, 0.0, distance(uv, vec2(0.86, 0.12)));
	col += glow_b.rgb * 0.12 * smoothstep(0.9, 0.0, distance(uv, vec2(0.08, 0.95)));
	col += glow_a.rgb * 0.25 * smoothstep(0.012, 0.0, abs(uv.y - horizon)) ;

	// Grille au sol en perspective.
	if (uv.y > horizon) {
		float depth = (uv.y - horizon) / (1.0 - horizon);
		float z = 1.0 / (depth + 0.04);
		vec2 g = vec2((uv.x - 0.5) * z * 2.2, z + TIME * speed * 4.0);
		vec2 f = abs(fract(g) - 0.5);
		float line = smoothstep(0.46, 0.5, max(f.x, f.y));
		col += grid_color.rgb * line * 0.28 * depth;
	}

	// Lignes de balayage et vignette.
	col *= 0.95 + 0.05 * sin(FRAGCOORD.y * 1.4);
	col *= 1.0 - 0.35 * pow(distance(uv, vec2(0.5)), 2.0);
	COLOR = vec4(col, 1.0);
}
