class_name RouteGraphAtlas
# Atlas baker - single texture holding glyphs + icons + white pixel
# Fragment shader does 1 fetch, no loops/branches
# Baking uses SubViewport + Labels to rasterize text (robust)

var texture: Texture2D
var image: Image
var uvs: Dictionary = {} # key -> Rect2 uv normalized
var sizes: Dictionary = {} # key -> Vector2 pixel size
var white_uv: Rect2
var shape_uvs: Dictionary = {} # "FLOW", "STORY", "CHOICE", "BOOL" -> Rect2 uv

const ATLAS_W: int = 2048
const ATLAS_H: int = 2048
const PADDING: int = 4
const ICON_SIZE: int = 32

var _font: FontFile

func _init():
	_font = load("res://assets/fonts/DejaVuSerif.ttf") as FontFile

func bake_with_sizes(entries: Array) -> void:
	if DisplayServer.get_name() == "headless":
		_create_dummy()
		return

	# Create viewport for baking
	var vp: SubViewport = SubViewport.new()
	vp.size = Vector2i(ATLAS_W, ATLAS_H)
	vp.transparent_bg = true
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.msaa_2d = Viewport.MSAA_DISABLED
	vp.msaa_3d = Viewport.MSAA_DISABLED

	var root: Node2D = Node2D.new()
	vp.add_child(root)

	# Add to tree via deferred to avoid "Parent node is busy setting up children"
	var tree_root: Window = Engine.get_main_loop().root as Window
	if tree_root == null:
		_create_dummy()
		vp.queue_free()
		return

	# Use call_deferred to avoid blocked error
	tree_root.add_child.call_deferred(vp)
	# Wait for deferred add
	await Engine.get_main_loop().process_frame
	# Ensure vp is inside tree
	if not vp.is_inside_tree():
		# try again next frame
		await Engine.get_main_loop().process_frame
		if not vp.is_inside_tree():
			_create_dummy()
			return

	var cursor_x: int = 0
	var cursor_y: int = 0
	var row_h: int = 0

	cursor_x = 4 + 4*(ICON_SIZE + PADDING)
	row_h = ICON_SIZE

	var labels: Array = []

	for e in entries:
		var key: String = e.key
		var txt: String = e.text
		var sz: int = e.size
		if txt == "" or uvs.has(key):
			continue

		var lbl: Label = Label.new()
		lbl.text = txt
		if _font:
			lbl.add_theme_font_override("font", _font)
		lbl.add_theme_font_size_override("font_size", sz)
		lbl.add_theme_color_override("font_color", Color(1,1,1,1))

		var w: int = 0
		var h: int = 0
		if _font:
			var text_size: Vector2 = _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz)
			w = int(ceil(text_size.x)) + 8
			h = int(ceil(text_size.y)) + 8
		else:
			w = txt.length()*sz*0.6 + 8
			h = sz + 8

		if w <= 0 or h <= 0:
			lbl.queue_free()
			continue

		if cursor_x + w + PADDING > ATLAS_W:
			cursor_x = 0
			cursor_y += row_h + PADDING
			row_h = 0
		if cursor_y + h + PADDING > ATLAS_H:
			push_warning("Atlas overflow, skipping %s" % txt)
			lbl.queue_free()
			continue

		lbl.position = Vector2(cursor_x, cursor_y)
		lbl.size = Vector2(w, h)
		root.add_child(lbl)

		labels.append({"label": lbl, "key": key, "x": cursor_x, "y": cursor_y, "w": w, "h": h})

		cursor_x += w + PADDING
		row_h = max(row_h, h)

	# Wait for render
	await Engine.get_main_loop().process_frame
	await Engine.get_main_loop().process_frame
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await Engine.get_main_loop().process_frame

	# Capture image
	if not vp.is_inside_tree():
		_create_dummy()
		return

	var tex: ViewportTexture = vp.get_texture()
	if tex == null:
		_create_dummy()
		vp.queue_free()
		return

	image = tex.get_image()
	if image == null:
		_create_dummy()
		vp.queue_free()
		return

	image.convert(Image.FORMAT_RGBA8)

	image.set_pixel(0,0, Color(1,1,1,1))
	image.set_pixel(1,0, Color(1,1,1,1))
	image.set_pixel(0,1, Color(1,1,1,1))
	image.set_pixel(1,1, Color(1,1,1,1))
	white_uv = Rect2(0.0, 0.0, 2.0/ATLAS_W, 2.0/ATLAS_H)

	var icon_start_x: int = 4
	for i in range(4):
		var kind: String = ["FLOW","STORY","CHOICE","BOOL"][i]
		var sx: int = icon_start_x + i*(ICON_SIZE + PADDING)
		_draw_shape_at(kind, sx, 0, ICON_SIZE)
		var uv: Rect2 = Rect2(float(sx)/ATLAS_W, 0.0, float(ICON_SIZE)/ATLAS_W, float(ICON_SIZE)/ATLAS_H)
		shape_uvs[kind] = uv

	uvs.clear()
	sizes.clear()
	for item in labels:
		var key: String = item.key
		var x: int = item.x
		var y: int = item.y
		var w: int = item.w
		var h: int = item.h
		uvs[key] = Rect2(float(x)/ATLAS_W, float(y)/ATLAS_H, float(w)/ATLAS_W, float(h)/ATLAS_H)
		sizes[key] = Vector2(w,h)

	texture = ImageTexture.create_from_image(image)

	vp.queue_free()

func _create_dummy() -> void:
	image = Image.create(ATLAS_W, ATLAS_H, false, Image.FORMAT_RGBA8)
	image.fill(Color(0,0,0,0))
	image.set_pixel(0,0, Color(1,1,1,1))
	image.set_pixel(1,0, Color(1,1,1,1))
	image.set_pixel(0,1, Color(1,1,1,1))
	image.set_pixel(1,1, Color(1,1,1,1))
	white_uv = Rect2(0,0, 2.0/ATLAS_W, 2.0/ATLAS_H)
	for k in ["FLOW","STORY","CHOICE","BOOL"]:
		shape_uvs[k] = white_uv
	texture = ImageTexture.create_from_image(image)
	uvs["IN"] = white_uv
	uvs["OUT"] = white_uv
	sizes["IN"] = Vector2(20,12)
	sizes["OUT"] = Vector2(20,12)

func _draw_shape_at(kind: String, ox: int, oy: int, sz: int) -> void:
	if image == null:
		return
	var cx: float = ox + sz*0.5
	var cy: float = oy + sz*0.5
	for py in range(sz):
		for px in range(sz):
			var x: float = ox + px
			var y: float = oy + py
			var inside: bool = false
			match kind:
				"FLOW":
					var p1x: float = cx - 6
					var p1y: float = cy - 8
					var p2x: float = cx + 10
					var p2y: float = cy
					var p3x: float = cx - 6
					var p3y: float = cy + 8
					inside = _point_in_triangle(x,y, p1x,p1y, p2x,p2y, p3x,p3y)
				"STORY":
					var dx: float = x - cx
					var dy: float = y - cy
					inside = dx*dx + dy*dy <= 64.0
				"CHOICE":
					var dx: float = x - cx
					var dy: float = y - cy
					inside = abs(dx) <= 7 and abs(dy) <= 7
				"BOOL":
					var dx: float = x - cx
					var dy: float = y - cy
					inside = abs(dx) + abs(dy) <= 8
			if inside:
				image.set_pixel(ox+px, oy+py, Color(1,1,1,1))

func _point_in_triangle(px: float, py: float, x1: float, y1: float, x2: float, y2: float, x3: float, y3: float) -> bool:
	var d1: float = (px - x2)*(y1 - y2) - (x1 - x2)*(py - y2)
	var d2: float = (px - x3)*(y2 - y3) - (x2 - x3)*(py - y3)
	var d3: float = (px - x1)*(y3 - y1) - (x3 - x1)*(py - y1)
	var has_neg: bool = (d1 < 0) or (d2 < 0) or (d3 < 0)
	var has_pos: bool = (d1 > 0) or (d2 > 0) or (d3 > 0)
	return not (has_neg and has_pos)

func get_uv(key: String) -> Rect2:
	if uvs.has(key):
		return uvs[key]
	return white_uv

func get_size(key: String) -> Vector2:
	if sizes.has(key):
		return sizes[key]
	return Vector2(10,10)
