shader_type canvas_item;

uniform float strength : hint_range(0.0, 4.0) = 2.0;

void fragment() {
	vec2 ps = TEXTURE_PIXEL_SIZE;
	vec4 c  = texture(TEXTURE, UV);
	vec4 t  = texture(TEXTURE, UV + vec2(0.0,  -ps.y));
	vec4 b  = texture(TEXTURE, UV + vec2(0.0,   ps.y));
	vec4 l  = texture(TEXTURE, UV + vec2(-ps.x,  0.0));
	vec4 r  = texture(TEXTURE, UV + vec2( ps.x,  0.0));
	vec4 blur = (t + b + l + r) * 0.25;
	COLOR = clamp(c + (c - blur) * strength, vec4(0.0), vec4(1.0));
}
