extends RefCounted
## One RGBA atlas for the route graph: a white texel, port icons, and baked labels.
## Glyph scale multiplies texel density. The side grows to fit; callers do not pick a capacity.
## Glyphs are blitted from the font cache. No SubViewport and no add_child — those
## paths failed when this overlay was constructed off the tree.


const ATLAS_W := 1024
const ATLAS_H := 1024
const WHITE := 8
const MIN_SIDE := 64
const MAX_SIDE := 4096

var _side := ATLAS_W

var texture: Texture2D
var _uvs: Dictionary = {}
var _sizes: Dictionary = {}
var _bytes: PackedByteArray = PackedByteArray()
var _font: Font


func uv_of(key: String) -> Rect2:
	return _uvs.get(key, white_uv())


func size_of(key: String) -> Vector2:
	return _sizes.get(key, Vector2(8, 8))


func white_uv() -> Rect2:
	return _uvs.get("__white", Rect2())


func shape_uv(kind: String) -> Rect2:
	return _uvs.get("shape:" + kind, white_uv())


var glyph_scale := 1.0
var use_mipmaps := false
var _base_image: Image


## glyph_scale is how many texels each on-map pixel of a symbol gets (1–4).
## The atlas side grows to fit; it is not a user setting. size_of() stays in
## graph pixels so the mesh layout does not change — only the texel density does.
func bake(entries: Array, scale: float = 1.0) -> void:
	glyph_scale = clampf(scale, 1.0, 4.0)
	_font = load("res://assets/fonts/DejaVuSerif.ttf")
	var side := ATLAS_W
	var fit := false
	while side <= MAX_SIDE:
		fit = _pack(entries, side, side >= MAX_SIDE)
		if fit:
			break
		side *= 2
	_upload_texture()


func set_mipmaps(on: bool) -> void:
	if on == use_mipmaps and texture != null:
		return
	use_mipmaps = on
	if _base_image != null:
		_upload_texture()


func _pack(entries: Array, side: int, warn: bool) -> bool:
	_side = side
	_uvs = {}
	_sizes = {}
	_bytes = PackedByteArray()
	_bytes.resize(side * side * 4)
	_fill(0, 0, WHITE, WHITE, Color.WHITE)
	var center := Vector2(float(WHITE) * 0.5 / float(side), float(WHITE) * 0.5 / float(side))
	var eps := 0.5 / float(side)
	_uvs["__white"] = Rect2(center.x - eps, center.y - eps, eps * 2.0, eps * 2.0)
	_sizes["__white"] = Vector2(WHITE, WHITE)
	var shape_px := maxi(16, int(round(16.0 * glyph_scale)))
	_draw_shapes(shape_px)
	var pad := maxi(4, int(round(4.0 * glyph_scale)))
	var pen_x := pad
	var pen_y := 4 + shape_px + pad
	var row_h := 0
	var overflow := false
	for entry in entries:
		var key := str(entry.get("key", ""))
		if key == "":
			continue
		var label := str(entry.get("text", ""))
		var font_size := maxi(1, int(round(float(entry.get("size", 14)) * glyph_scale)))
		var measured := _measure(label, font_size)
		var w := maxi(4, int(ceil(measured.x)) + pad * 2)
		var h := maxi(4, int(ceil(measured.y)) + pad)
		if pen_x + w + 2 > side:
			pen_x = pad
			pen_y += row_h + pad
			row_h = 0
		if pen_y + h + 2 > side:
			overflow = true
			if warn:
				push_warning("route graph atlas full, skipping '%s'" % key)
			_uvs[key] = white_uv()
			_sizes[key] = Vector2(4, 4)
			continue
		_draw_text(label, font_size, pen_x + pad, pen_y + 2)
		_uvs[key] = Rect2(float(pen_x) / float(side), float(pen_y) / float(side), float(w) / float(side), float(h) / float(side))
		# Logical size: the quad stays the same on the map, the UV covers more texels.
		_sizes[key] = Vector2(w, h) / glyph_scale
		pen_x += w + pad
		row_h = maxi(row_h, h)
	return not overflow


func _upload_texture() -> void:
	_base_image = Image.create_from_data(_side, _side, false, Image.FORMAT_RGBA8, _bytes)
	var image := _base_image
	if use_mipmaps:
		image = _base_image.duplicate()
		image.generate_mipmaps()
	texture = ImageTexture.create_from_image(image)


func _draw_shapes(shape_px: int = 16) -> void:
	var kinds: Array[String] = ["FLOW", "STORY", "CHOICE", "BOOL"]
	var gap := maxi(4, int(round(4.0 * glyph_scale)))
	var x := WHITE + gap
	for kind in kinds:
		_draw_shape(kind, x, 4, shape_px)
		_uvs["shape:" + kind] = Rect2(float(x) / float(_side), 4.0 / float(_side), float(shape_px) / float(_side), float(shape_px) / float(_side))
		_sizes["shape:" + kind] = Vector2(16, 16)
		x += shape_px + gap


func _draw_shape(kind: String, ox: int, oy: int, s: int) -> void:
	var c := Color.WHITE
	if kind == "FLOW":
		for y in s:
			var t := float(y) / float(s - 1)
			var x0 := int(absf(t - 0.5) * float(s))
			for x in range(x0, s):
				_set_px(ox + x, oy + y, c)
	elif kind == "STORY":
		var radius := float(s) * 0.5 - 0.5
		var center := Vector2(radius, radius)
		for y in s:
			for x in s:
				if Vector2(x, y).distance_to(center) <= radius:
					_set_px(ox + x, oy + y, c)
	elif kind == "CHOICE":
		_fill(ox + 2, oy + 2, s - 4, s - 4, c)
	else:
		var mid := float(s - 1) * 0.5
		for y in s:
			for x in s:
				if absf(float(x) - mid) + absf(float(y) - mid) <= mid:
					_set_px(ox + x, oy + y, c)


func _measure(text: String, font_size: int) -> Vector2:
	if _font == null or text == "":
		return Vector2(maxf(8.0, text.length() * font_size * 0.55), font_size + 4.0)
	var sz: Vector2 = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	return Vector2(sz.x + 2.0, maxf(sz.y, _font.get_height(font_size)))


func _draw_text(text: String, font_size: int, ox: int, oy: int) -> void:
	if _font == null or text == "":
		return
	var pen := 0.0
	var baseline := float(oy) + _font.get_ascent(font_size)
	var glyph_size := Vector2i(font_size, 0)
	for i in text.length():
		var glyph: int = _font.get_glyph_index(font_size, text.unicode_at(i), 0)
		if glyph == 0:
			pen += font_size * 0.34
			continue
		var advance: Vector2 = _font.get_glyph_advance(0, font_size, glyph)
		_font.render_glyph(0, glyph_size, glyph)
		var tex_idx: int = _font.get_glyph_texture_idx(0, glyph_size, glyph)
		if tex_idx < 0:
			pen += advance.x
			continue
		var src: Image = _font.get_texture_image(0, glyph_size, tex_idx)
		var uv: Rect2 = _font.get_glyph_uv_rect(0, glyph_size, glyph)
		var off: Vector2 = _font.get_glyph_offset(0, glyph_size, glyph)
		if src != null and uv.size.x >= 1.0 and uv.size.y >= 1.0:
			var rect := Rect2i(int(floor(uv.position.x)), int(floor(uv.position.y)), int(ceil(uv.size.x)), int(ceil(uv.size.y)))
			rect = rect.intersection(Rect2i(Vector2i.ZERO, src.get_size()))
			var dest := Vector2i(int(floor(float(ox) + pen + off.x)), int(floor(baseline + off.y)))
			_blit_glyph(src, rect, dest)
		pen += advance.x


func _blit_glyph(src: Image, rect: Rect2i, dest: Vector2i) -> void:
	# Dynamic fonts store coverage in the LA8 alpha byte. Image.get_pixel()
	# reports that byte as 0, so the coverage is read from the raw buffer.
	var src_bytes := src.get_data()
	var src_w := src.get_width()
	var la8 := src.get_format() == Image.FORMAT_LA8
	var bpp := 2 if la8 else 4
	var alpha_offset := 1 if la8 else 3
	if src_bytes.size() < (rect.position.y + rect.size.y) * src_w * bpp:
		return
	for y in rect.size.y:
		var dy := dest.y + y
		if dy < 0 or dy >= _side:
			continue
		for x in rect.size.x:
			var dx := dest.x + x
			if dx < 0 or dx >= _side:
				continue
			var si := ((rect.position.y + y) * src_w + rect.position.x + x) * bpp + alpha_offset
			if si < 0 or si >= src_bytes.size():
				continue
			var src_a := float(src_bytes[si]) / 255.0
			if src_a <= 0.004:
				continue
			var di := (dy * _side + dx) * 4
			var dst_a := float(_bytes[di + 3]) / 255.0
			var out_a := src_a + dst_a * (1.0 - src_a)
			var dst_r := float(_bytes[di]) / 255.0
			var dst_g := float(_bytes[di + 1]) / 255.0
			var dst_b := float(_bytes[di + 2]) / 255.0
			var out_r := (src_a + dst_r * dst_a * (1.0 - src_a)) / out_a
			var out_g := (src_a + dst_g * dst_a * (1.0 - src_a)) / out_a
			var out_b := (src_a + dst_b * dst_a * (1.0 - src_a)) / out_a
			_bytes[di] = int(clampf(out_r * 255.0, 0.0, 255.0))
			_bytes[di + 1] = int(clampf(out_g * 255.0, 0.0, 255.0))
			_bytes[di + 2] = int(clampf(out_b * 255.0, 0.0, 255.0))
			_bytes[di + 3] = int(clampf(out_a * 255.0, 0.0, 255.0))


func _fill(x: int, y: int, w: int, h: int, color: Color) -> void:
	for yy in h:
		for xx in w:
			_set_px(x + xx, y + yy, color)


func _set_px(x: int, y: int, color: Color) -> void:
	if x < 0 or y < 0 or x >= _side or y >= _side:
		return
	var i := (y * _side + x) * 4
	_bytes[i] = int(clampf(color.r * 255.0, 0.0, 255.0))
	_bytes[i + 1] = int(clampf(color.g * 255.0, 0.0, 255.0))
	_bytes[i + 2] = int(clampf(color.b * 255.0, 0.0, 255.0))
	_bytes[i + 3] = int(clampf(color.a * 255.0, 0.0, 255.0))
