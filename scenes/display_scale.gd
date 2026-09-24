extends RefCounted
## Shared window layout for the game and the panic page.
## The layout stays 1280x720. A larger window draws that layout with more
## pixels instead of stretching a low-resolution picture.


const DESIGN := Vector2i(1280, 720)


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
	DisplayServer.window_set_size(Vector2i(w, h))
