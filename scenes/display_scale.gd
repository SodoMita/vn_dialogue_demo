extends RefCounted
## Shared window scale for the game and the panic page.
## The layout stays 1280x720. A larger window draws that layout with more
## pixels (canvas_items) instead of stretching a low-resolution picture.


const DESIGN := Vector2i(1280, 720)
const FONTS: Array[String] = [
	"res://assets/fonts/DejaVuSerif.ttf",
	"res://assets/fonts/DejaVuSerif-Bold.ttf",
]


## How much a window enlarges the design canvas. Below the design size, leave
## it at 1 so a narrow window reflows instead of shrinking the chrome.
static func keep_ratio(window_size: Vector2) -> float:
	if window_size.x < 1.0 or window_size.y < 1.0:
		return 1.0
	var fit := minf(window_size.x / float(DESIGN.x), window_size.y / float(DESIGN.y))
	return fit if fit > 1.0 else 1.0


static func read_settings() -> Dictionary:
	if not FileAccess.file_exists("user://settings.json"):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://settings.json"))
	return parsed if parsed is Dictionary else {}


## Pin the layout to the design size and give the extra pixels to the window.
## Headless has no window; mutating the layout there breaks orientation tests.
static func apply_window(tree: SceneTree, w: int, h: int) -> void:
	if w < 1 or h < 1 or tree == null:
		return
	if DisplayServer.get_name() == "headless":
		return
	var root := tree.root
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	root.content_scale_size = DESIGN
	root.use_font_oversampling = true
	DisplayServer.window_set_size(Vector2i(w, h))
	sharpen(tree, keep_ratio(Vector2(w, h)))


## Rasterize fonts at the display density. A FontFile oversampling of 0 follows
## the viewport, which RichTextLabel often ignores, so stretched text stays a
## blurry, pixelated bitmap. Ceil so a 1.5x window downsamples a 2x glyph.
static func sharpen(tree: SceneTree, amount: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var over := 0.0
	if amount > 1.01:
		over = ceilf(amount)
	if tree != null:
		tree.root.oversampling_override = over
	for path: String in FONTS:
		var font := load(path) as FontFile
		if font != null and not is_equal_approx(font.oversampling, over):
			font.oversampling = over
