class_name Sprite3DQuad extends MeshInstance3D
## A VN portrait standing in a 3D scene: a quad that faces the camera by
## rotating only around the world Y axis (vertex shader, see
## sprite_3d_billboard.gdshader). Placement is the node transform - set it
## directly or copy it from an existing object with
## [method copy_transform_from]. Created and driven by the StageDirector's
## `#sprite3d=` / `#place3d=` tags; also usable as a plain node.


const BILLBOARD_SHADER := preload("res://scenes/motion/sprite_3d_billboard.gdshader")

## World-space height in meters; the width follows the texture aspect.
@export var world_height: float = 1.8:
	set(value):
		world_height = maxf(value, 0.001)
		_rebuild_mesh()

## Anchor the quad's origin at its bottom edge, so a transform copied from a
## character root (at the feet) stands the portrait on the ground.
@export var bottom_anchored: bool = true:
	set(value):
		bottom_anchored = value
		_rebuild_mesh()

@export var texture: Texture2D = null:
	set(value):
		texture = value
		_apply_texture()

@export var modulate: Color = Color(1, 1, 1, 1):
	set(value):
		modulate = value
		_push_uniform("modulate", value)

## Facing offset in degrees, applied on top of the Y-locked billboard yaw.
## [method copy_transform_from] feeds a source object's yaw in here, so the
## node transform is fully honoured even though the shader re-aims the quad.
@export var yaw_offset_deg: float = 0.0:
	set(value):
		yaw_offset_deg = value
		_push_uniform("yaw_offset_deg", value)

## Hard alpha clip for depth writing against other 3D geometry (0 disables).
@export var alpha_scissor: float = 0.0:
	set(value):
		alpha_scissor = value
		_push_uniform("alpha_scissor", value)

var _quad: QuadMesh
var _material: ShaderMaterial


func _init() -> void:
	_material = ShaderMaterial.new()
	_material.shader = BILLBOARD_SHADER
	material_override = _material
	_quad = QuadMesh.new()
	mesh = _quad
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_rebuild_mesh()


func _rebuild_mesh() -> void:
	if _quad == null:
		return
	var aspect := 1.0
	if texture != null and texture.get_height() > 0:
		aspect = float(texture.get_width()) / float(texture.get_height())
	_quad.size = Vector2(world_height * aspect, world_height)
	# QuadMesh centers on the origin by default; standing quads want their
	# origin at the feet.
	_quad.center_offset = Vector3(0.0, world_height * 0.5 if bottom_anchored else 0.0, 0.0)


func _apply_texture() -> void:
	_push_uniform("albedo_tex", texture)
	_rebuild_mesh()


func _push_uniform(param: String, value: Variant) -> void:
	if _material != null:
		_material.set_shader_parameter(param, value)


## Adopt a marker's placement: position and facing only. Scale is ignored
## (a scaled marker or a transformed parent must not resize the portrait -
## [member world_height] sets the size). Used by `#place3d=copy=` and
## StageActors marker placement.
func copy_placement_from(source: Node3D) -> void:
	var gt := source.global_transform
	global_position = gt.origin
	yaw_offset_deg = rad_to_deg(gt.basis.get_euler().y)


## Legacy: position AND scale are copied
## onto this node, and the source's yaw becomes the billboard facing offset
## (the shader owns the aim, so yaw travels through the uniform).
func copy_transform_from(source: Node3D) -> void:
	var gt := source.global_transform
	global_position = gt.origin
	scale = gt.basis.get_scale()
	yaw_offset_deg = rad_to_deg(gt.basis.get_euler().y)
