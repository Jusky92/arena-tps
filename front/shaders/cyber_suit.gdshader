shader_type spatial;
// Combinaison cyberpunk appliquée sur le corps humain Quaternius.
// Le masque (tools/generate_suit_masks.py) indique pour chaque pixel :
//   R = combinaison (0 = peau du visage)   G = zone secondaire (avant-bras, mollets, pieds)
//   B = gants / semelles                   A = liserés néon aux jonctions

uniform sampler2D skin_albedo : source_color, filter_linear_mipmap;
uniform sampler2D skin_normal : hint_normal, filter_linear_mipmap;
uniform sampler2D skin_orm : hint_default_white, filter_linear_mipmap;
uniform sampler2D suit_mask : hint_default_black, filter_linear_mipmap;

uniform vec4 primary_color : source_color = vec4(0.2, 0.22, 0.26, 1.0);
uniform vec4 secondary_color : source_color = vec4(0.5, 0.2, 0.7, 1.0);
uniform vec4 dark_color : source_color = vec4(0.06, 0.06, 0.07, 1.0);
uniform vec4 neon_color : source_color = vec4(0.3, 0.9, 1.0, 1.0);
uniform float neon_energy = 3.0;
uniform float suit_roughness = 0.42;
uniform float suit_metallic = 0.25;
// Petit motif de tissu technique (lignes fines) pour casser l'aspect uni.
uniform float weave_scale = 180.0;

void fragment() {
	vec4 mask = texture(suit_mask, UV);
	vec3 skin = texture(skin_albedo, UV).rgb;
	vec4 orm = texture(skin_orm, UV);

	vec3 suit = primary_color.rgb;
	suit = mix(suit, secondary_color.rgb, mask.g);
	suit = mix(suit, dark_color.rgb, mask.b);
	float weave = 0.94 + 0.06 * step(0.5, fract(UV.x * weave_scale + UV.y * weave_scale * 0.5));
	suit *= weave;

	float suit_amount = mask.r;
	ALBEDO = mix(skin, suit, suit_amount);
	ROUGHNESS = mix(orm.g, mix(suit_roughness, 0.8, mask.b), suit_amount);
	METALLIC = mix(0.0, suit_metallic, suit_amount);
	NORMAL_MAP = texture(skin_normal, UV).rgb;
	NORMAL_MAP_DEPTH = mix(1.0, 0.6, suit_amount);
	EMISSION = neon_color.rgb * mask.a * neon_energy * suit_amount;
}
