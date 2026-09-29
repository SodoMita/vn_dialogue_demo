shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, blend_mix, shadows_disabled, specular_disabled;

// Y-locked billboard for VN sprite quads (Sprite3DQuad).
//
// The vertex stage rebuilds the model-view matrix so the quad always faces
// the camera while rotating ONLY around the world Y axis - a portrait stands
// upright like a person turning, never tilting with the camera pitch. This
// is the Godot 4 billboard pattern (compose MODELVIEW_MATRIX from a chosen
// world basis at the model origin) with a yaw-locked basis instead of the
// full camera basis. The node's own rotation is ignored on purpose; scale is
// taken from the model matrix, and yaw_offset_deg adds a facing offset (a
// copied source transform feeds its yaw in here).

uniform sampler2D albedo_tex : source_color, filter_linear;
uniform vec4 modulate : source_color = vec4(1.0);
uniform float yaw_offset_deg = 0.0;
// Optional hard clip so soft sprite edges still write depth (0 = off).
uniform float alpha_scissor = 0.0;

void vertex() {
	// Model origin and scale in world space.
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), 1.0);
	// Camera position in world space (INV_VIEW_MATRIX column 3).
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	// Yaw that turns the quad's +Z toward the camera, Y axis only.
	float yaw = atan(cam.x - origin.x, cam.z - origin.z) + radians(yaw_offset_deg);
	float s = sin(yaw);
	float c = cos(yaw);
	// Basis: +X and +Z rotated around Y, world up untouched.
	mat3 rot = mat3(
		vec3(c, 0.0, -s),
		vec3(0.0, 1.0, 0.0),
		vec3(s, 0.0, c));
	mat4 bill = mat4(
		vec4(rot[0] * scale.x, 0.0),
		vec4(rot[1] * scale.y, 0.0),
		vec4(rot[2], 0.0),
		vec4(origin, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * bill;
	MODELVIEW_NORMAL_MATRIX = mat3(VIEW_MATRIX) * rot;
}

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	ALBEDO = tex.rgb * modulate.rgb;
	ALPHA = tex.a * modulate.a;
	if (alpha_scissor > 0.0 && ALPHA < alpha_scissor) {
		discard;
	}
}
