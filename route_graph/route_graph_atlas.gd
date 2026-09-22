class_name RouteGraphAtlas extends RefCounted
## Rasterizes labels, symbols and thumbnails into one RGBA atlas + UV table.
## Solid colours live as 8x8 swatches; glyphs are packed with 1px padding so
## bilinear sampling does not bleed. Works headless (CPU Image, no Viewport).


const FONT_SIZE := 13
const TITLE_SIZE := 14
const PAD := 1
const SWATCH := 8
const CIRCLE := 16
const THUMB_W := 48
const THUMB_H := 32

const COLORS := {
	"white": Color(1, 1, 1, 1),
	"bg": Color(0.035, 0.045, 0.09, 0.92),
	"border": Color(0.22, 0.24, 0.32, 1),
	"gold": Color(0.83, 0.68, 0.36, 1),
	"cue": Color(0.14, 0.18, 0.32, 1),
	"dialogue": Color(0.07, 0.10, 0.18, 1),
	"choice": Color(0.16, 0.12, 0.08, 1),
	"condition": Color(0.08, 0.14, 0.16, 1),
	"mutation": Color(0.12, 0.08, 0.16, 1),
	"goto": Color(0.10, 0.10, 0.14, 1),
	"end": Color(0.16, 0.06, 0.06, 1),
	"title": Color(0.10, 0.12, 0.22, 1),
	"edge": Color(0.55, 0.58, 0.66, 1),
	"edge_choice": Color(0.83, 0.68, 0.36, 1),
	"edge_condition": Color(0.45, 0.78, 0.82, 1),
	"port_in": Color(0.55, 0.78, 0.95, 1),
	"port_out": Color(0.93, 0.78, 0.42, 1),
	"dim": Color(0.0, 0.0, 0.0, 0.45),
	"text": Color(0.92, 0.92, 0.95, 1),
	"text_muted": Color(0.75, 0.75, 0.80, 1),
}


var image: Image
var texture: ImageTexture
var size: Vector2i = Vector2i(512, 512)
var uvs: Dictionary = {} ## name -> Rect2 (0-1)
var pixel_rects: Dictionary = {} ## name -> Rect2i
var _cursor := Vector2i(PAD, PAD)
var _shelf_h: int = 0
var _font: Font
var _ts: TextServer
var _font_rid: RID


func bake(graph: RouteGraph, thumbs: Dictionary = {}, font: Font = null) -> ImageTexture:
	_font = font
	if _font == null and ResourceLoader.exists("res://assets/fonts/DejaVuSerif.ttf"):
		_font = load("res://assets/fonts/DejaVuSerif.ttf")
	_prepare_font()
	size = Vector2i(512, 512)
	image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	uvs.clear()
	pixel_rects.clear()
	_cursor = Vector2i(PAD, PAD)
	_shelf_h = 0

	for key: String in COLORS.keys():
		_pack_swatch("swatch_%s" % key, COLORS[key])

	_pack_circle("circle_in", COLORS.port_in)
	_pack_circle("circle_out", COLORS.port_out)
	_pack_circle("circle_choice", COLORS.edge_choice)
	_pack_arrow("arrow")

	var labels: Dictionary = {}
	for n: RouteGraph.RouteNode in graph.nodes:
		_remember_label(labels, n.title)
		_remember_label(labels, _ellipsis(n.body, 42))
		if not n.annotation.is_empty():
			_remember_label(labels, n.annotation)
		for p: RouteGraph.RoutePort in n.inputs:
			_remember_label(labels, p.label)
		for p: RouteGraph.RoutePort in n.outputs:
			_remember_label(labels, p.label)
	for e: RouteGraph.RouteEdge in graph.edges:
		if not e.label.is_empty():
			_remember_label(labels, _ellipsis(e.label, 36))
	_remember_label(labels, "in")
	_remember_label(labels, "out")
	_remember_label(labels, "true")
	_remember_label(labels, "else")

	for text: Variant in labels.keys():
		_pack_label(str(text))

	var thumb_keys: Dictionary = {}
	for n: RouteGraph.RouteNode in graph.nodes:
		if not n.bg_key.is_empty():
			thumb_keys[n.bg_key] = true
		if not n.sprite_key.is_empty():
			thumb_keys[n.sprite_key] = true
	for key: Variant in thumb_keys.keys():
		_pack_thumb(str(key), thumbs.get(str(key), null))

	_crop_to_used()
	texture = ImageTexture.create_from_image(image)
	return texture


func uv_rect(name: String) -> Rect2:
	return uvs.get(name, uvs.get("swatch_white", Rect2(0, 0, 1, 1)))


func has(name: String) -> bool:
	return uvs.has(name)


func label_key(text: String) -> String:
	return "label:%s" % text


func thumb_key(name: String) -> String:
	return "thumb:%s" % name


func _prepare_font() -> void:
	_ts = TextServerManager.get_primary_interface()
	_font_rid = RID()
	if _font != null and _font.has_method("get_rids"):
		var rids: Array = _font.get_rids()
		if not rids.is_empty() and rids[0] is RID:
			_font_rid = rids[0]
		# Touch metrics so FreeType actually rasterizes.
		_font.get_height(FONT_SIZE)


func _remember_label(into: Dictionary, text: String) -> void:
	if text.is_empty():
		return
	into[text] = true


func _pack_swatch(name: String, color: Color) -> void:
	var img := Image.create(SWATCH, SWATCH, false, Image.FORMAT_RGBA8)
	img.fill(color)
	_blit(name, img)


func _pack_circle(name: String, color: Color) -> void:
	var img := Image.create(CIRCLE, CIRCLE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var r := float(CIRCLE) * 0.5 - 0.5
	var c := Vector2(r, r)
	for y in CIRCLE:
		for x in CIRCLE:
			var d: float = Vector2(float(x) + 0.5, float(y) + 0.5).distance_to(c)
			var a: float = clampf(r - d + 0.5, 0.0, 1.0)
			if a > 0.0:
				var col := color
				col.a *= a
				img.set_pixel(x, y, col)
	_blit(name, img)


func _pack_arrow(name: String) -> void:
	var w := 12
	var h := 10
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in h:
		var t: float = (float(y) + 0.5) / float(h)
		var half: float = (0.5 - absf(t - 0.5)) * float(w)
		for x in w:
			if float(x) <= half:
				img.set_pixel(x, y, COLORS.white)
	_blit(name, img)


func _pack_label(text: String) -> void:
	var key := label_key(text)
	if uvs.has(key):
		return
	var img := _rasterize_string(text, FONT_SIZE, COLORS.text)
	_blit(key, img)


func _pack_thumb(key: String, source: Variant) -> void:
	var name := thumb_key(key)
	if uvs.has(name):
		return
	var img := Image.create(THUMB_W, THUMB_H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.06, 0.07, 0.12, 1))
	var src: Image = _image_from(source)
	if src != null:
		src = src.duplicate()
		src.convert(Image.FORMAT_RGBA8)
		src.resize(THUMB_W, THUMB_H, Image.INTERPOLATE_BILINEAR)
		img.blit_rect(src, Rect2i(0, 0, THUMB_W, THUMB_H), Vector2i.ZERO)
	_blit(name, img)


func _image_from(source: Variant) -> Image:
	if source == null:
		return null
	if source is Image:
		return source
	if source is Texture2D:
		return (source as Texture2D).get_image()
	if source is String and FileAccess.file_exists(source):
		var img := Image.new()
		if img.load(source) == OK:
			return img
	return null


func _rasterize_string(text: String, font_size: int, color: Color) -> Image:
	if _font != null and _font_rid.is_valid() and _ts != null:
		var drawn := _rasterize_with_text_server(text, font_size, color)
		if drawn != null:
			return drawn
	return _rasterize_bitmap(text, color)


func _rasterize_with_text_server(text: String, font_size: int, color: Color) -> Image:
	var measured: Vector2 = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var w: int = maxi(1, int(ceil(measured.x)) + 2)
	var h: int = maxi(1, int(ceil(maxf(measured.y, _font.get_height(font_size)))) + 2)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var pen := Vector2(1.0, _font.get_ascent(font_size) + 1.0)
	var sized := Vector2i(font_size, 0)
	for i: int in text.length():
		var code := text.unicode_at(i)
		var glyph: int = _ts.font_get_glyph_index(_font_rid, font_size, code, 0)
		var adv: Vector2 = _ts.font_get_glyph_advance(_font_rid, font_size, glyph)
		if glyph == 0:
			pen.x += maxf(adv.x, 6.0)
			continue
		var tex_rid: RID = _ts.font_get_glyph_texture_rid(_font_rid, sized, glyph)
		var uv: Rect2 = _ts.font_get_glyph_uv_rect(_font_rid, sized, glyph)
		var off: Vector2 = _ts.font_get_glyph_offset(_font_rid, sized, glyph)
		if tex_rid.is_valid() and uv.size.x > 0.0 and uv.size.y > 0.0:
			var sheet: Image = RenderingServer.texture_2d_get(tex_rid)
			if sheet != null:
				var region := Rect2i(Vector2i(uv.position.round()), Vector2i(uv.size.ceil()))
				region = region.intersection(Rect2i(Vector2i.ZERO, sheet.get_size()))
				if region.size.x > 0 and region.size.y > 0:
					var dest := Vector2i(int(round(pen.x + off.x)), int(round(pen.y + off.y)))
					_blend_tinted(img, sheet, region, dest, color)
		pen.x += adv.x
	return img


func _blend_tinted(dst: Image, src: Image, region: Rect2i, dest: Vector2i, tint: Color) -> void:
	var dw := dst.get_width()
	var dh := dst.get_height()
	for yy in region.size.y:
		var dy: int = dest.y + yy
		if dy < 0 or dy >= dh:
			continue
		for xx in region.size.x:
			var dx: int = dest.x + xx
			if dx < 0 or dx >= dw:
				continue
			var px: Color = src.get_pixel(region.position.x + xx, region.position.y + yy)
			if px.a <= 0.0:
				continue
			var col := Color(tint.r, tint.g, tint.b, tint.a * px.a)
			var bg: Color = dst.get_pixel(dx, dy)
			dst.set_pixel(dx, dy, bg.blend(col))


func _rasterize_bitmap(text: String, color: Color) -> Image:
	var w: int = maxi(1, text.length() * 6 + 1)
	var h := 9
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var x := 1
	for i: int in text.length():
		_blit_ascii(img, text.unicode_at(i), x, 1, color)
		x += 6
	return img


func _blit_ascii(img: Image, code: int, x: int, y: int, color: Color) -> void:
	var g: int = _glyph5(code)
	for col in 5:
		for row in 7:
			if (g >> (row * 5 + col)) & 1:
				var px: int = x + col
				var py: int = y + row
				if px >= 0 and py >= 0 and px < img.get_width() and py < img.get_height():
					img.set_pixel(px, py, color)


func _glyph5(code: int) -> int:
	## Packed 5x7 bits, column-major-ish via row*5+col. Covers a readable ASCII subset.
	if code >= 97 and code <= 122:
		code -= 32
	match code:
		32: return 0
		33: return 0x041041
		45: return 0x0003E0
		46: return 0x040000
		48: return 0x0E8C5E # 0
		49: return 0x1F1246
		50: return 0x1E2222
		51: return 0x0E8A2E
		52: return 0x08F888
		53: return 0x0E8B8E
		54: return 0x0E8BDE
		55: return 0x02111F
		56: return 0x0E8ADE
		57: return 0x0F8ADE
		58: return 0x041040
		61: return 0x00F3E0
		63: return 0x04122E
		65: return 0x11513E
		66: return 0x0E8ADE
		67: return 0x0E842E
		68: return 0x0E8C5E
		69: return 0x1E861E
		70: return 0x02161E
		71: return 0x0E8C2E
		72: return 0x115F11
		73: return 0x1F1247
		74: return 0x0E8C10
		75: return 0x114A51
		76: return 0x1E8421
		77: return 0x11DDD1
		78: return 0x11CD91
		79: return 0x0E8C5E
		80: return 0x0216DE
		81: return 0x168C5E
		82: return 0x114ADE
		83: return 0x0E8B8E
		84: return 0x04211F
		85: return 0x0E8C51
		86: return 0x045451
		87: return 0x11D551
		88: return 0x115115
		89: return 0x0422A5
		90: return 0x1E222F
		95: return 0x1F0000
		_: return 0x1F111F


func _blit(name: String, src: Image) -> void:
	var w := src.get_width()
	var h := src.get_height()
	_ensure_space(w, h)
	image.blit_rect(src, Rect2i(0, 0, w, h), _cursor)
	var rect := Rect2i(_cursor, Vector2i(w, h))
	pixel_rects[name] = rect
	uvs[name] = _to_uv(rect)
	_cursor.x += w + PAD
	_shelf_h = maxi(_shelf_h, h)


func _ensure_space(w: int, h: int) -> void:
	if _cursor.x + w + PAD > size.x:
		_cursor.x = PAD
		_cursor.y += _shelf_h + PAD
		_shelf_h = 0
	while _cursor.y + h + PAD > size.y:
		_grow()


func _grow() -> void:
	var nw := size.x * 2 if size.x <= size.y else size.x
	var nh := size.y * 2 if size.x > size.y else size.y
	if nw == size.x and nh == size.y:
		nw *= 2
	var bigger := Image.create(nw, nh, false, Image.FORMAT_RGBA8)
	bigger.fill(Color(0, 0, 0, 0))
	bigger.blit_rect(image, Rect2i(Vector2i.ZERO, size), Vector2i.ZERO)
	image = bigger
	size = Vector2i(nw, nh)
	for key: Variant in pixel_rects.keys():
		uvs[str(key)] = _to_uv(pixel_rects[key])


func _crop_to_used() -> void:
	var used_w := 1
	var used_h := 1
	for key: Variant in pixel_rects.keys():
		var r: Rect2i = pixel_rects[key]
		used_w = maxi(used_w, r.position.x + r.size.x + PAD)
		used_h = maxi(used_h, r.position.y + r.size.y + PAD)
	# Keep power-of-two-ish width for nicer GPU sampling, but don't waste pages.
	used_w = mini(size.x, maxi(64, used_w))
	used_h = mini(size.y, maxi(64, used_h))
	if used_w == size.x and used_h == size.y:
		return
	var cropped := Image.create(used_w, used_h, false, Image.FORMAT_RGBA8)
	cropped.fill(Color(0, 0, 0, 0))
	cropped.blit_rect(image, Rect2i(0, 0, used_w, used_h), Vector2i.ZERO)
	image = cropped
	size = Vector2i(used_w, used_h)
	for key: Variant in pixel_rects.keys():
		uvs[str(key)] = _to_uv(pixel_rects[key])


func _to_uv(rect: Rect2i) -> Rect2:
	# Inset half a texel so bilinear filtering stays inside the packed rect.
	var inset := 0.5
	var x := (float(rect.position.x) + inset) / float(size.x)
	var y := (float(rect.position.y) + inset) / float(size.y)
	var w := maxf(0.0, (float(rect.size.x) - inset * 2.0) / float(size.x))
	var h := maxf(0.0, (float(rect.size.y) - inset * 2.0) / float(size.y))
	return Rect2(x, y, w, h)


static func _ellipsis(text: String, max_chars: int) -> String:
	if text.length() <= max_chars:
		return text
	return text.substr(0, max_chars - 1) + "…"
