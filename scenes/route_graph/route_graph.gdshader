shader_type canvas_item;
render_mode blend_mix;

uniform sampler2D atlas : filter_linear, repeat_disable;
uniform vec2 pan = vec2(0.0);
uniform float zoom = 1.0;

varying vec2 v_uv;
varying vec4 v_color;

void vertex() {
	// single-pass transform: pan + zoom, no branches
	// VERTEX is in graph local space
	vec2 t = (VERTEX + pan) * zoom;
	VERTEX = t;
	v_uv = UV;
	v_color = COLOR;
}

void fragment() {
	// 1 texture fetch, no loops, no branches.
	// Blending is the pipeline's blend_mix, not a shader branch: COLOR is
	// straight alpha (atlas coverage times vertex color). The blend unit
	// composites fragments in mesh order — edges first, then nodes.
	vec4 tex = texture(atlas, v_uv);
	COLOR = tex * v_color;
}
