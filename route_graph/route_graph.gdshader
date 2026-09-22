shader_type canvas_item;
render_mode unshaded, blend_mix;

// Single-pass atlas sampler. CPU uploads a quad/triangle soup whose UVs
// address baked labels, symbols and colour swatches. Pan/zoom is a uniform
// transform so the mesh is rebuilt only when the graph itself changes.
uniform vec2 u_pan = vec2(0.0);
uniform float u_zoom = 1.0;
uniform vec2 u_origin = vec2(0.0);

void vertex() {
	VERTEX = (VERTEX - u_origin) * u_zoom + u_origin + u_pan;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (c.a < 0.01) {
		discard;
	}
	COLOR = c;
}
