extends Node

@export var out_path: String = "/home/user/route_graph_runtime.png"

func _ready():
	print("CaptureRouteGraph: starting...")
	# Give RouteGraphView time to init (it does async bake)
	for i in range(5):
		await get_tree().process_frame

	var panel = get_node_or_null("RouteGraphPanel")
	if panel == null:
		panel = get_tree().root.find_child("RouteGraphPanel", true, false)
	if panel == null:
		push_error("RouteGraphPanel not found")
		get_tree().quit(1)
		return

	if panel.has_method("show_graph"):
		panel.show_graph()
		print("CaptureRouteGraph: show_graph called")

	# Wait for atlas baking (headless uses dummy, so fast)
	for i in range(20):
		await get_tree().process_frame

	# Try to get viewport image
	var vp: Viewport = get_viewport()
	await get_tree().process_frame
	var img: Image = vp.get_texture().get_image()
	if img == null:
		push_error("Failed to get viewport image, trying to create dummy")
		img = Image.create(1280, 720, false, Image.FORMAT_RGBA8)
		img.fill(Color("#0A0F1E"))

	print("CaptureRouteGraph: got image %dx%d" % [img.get_width(), img.get_height()])

	# In headless, viewport may be empty, but we can still render mesh manually?
	# For now just save what we have
	var save_path: String = out_path
	var err: int = img.save_png(save_path)
	if err != OK:
		print("Failed PNG, trying webp to %s" % save_path)
		save_path = "/home/user/route_graph_runtime.webp"
		err = img.save_webp(save_path)
		if err != OK:
			push_error("Failed to save image")
			get_tree().quit(1)
			return

	print("CaptureRouteGraph: saved to %s" % save_path)

	# Also save inside docs
	var docs_png: String = "res://docs/route_graph_runtime.png"
	img.save_png(docs_png)
	var docs_webp: String = "res://docs/route_graph_runtime.webp"
	img.save_webp(docs_webp)
	print("Also saved to %s and %s" % [docs_png, docs_webp])

	# Also try to save a debug text of nodes
	var view = get_node_or_null("RouteGraphPanel/Margin/VBox/GraphContainer/RouteGraphView")
	if view == null:
		view = get_tree().root.find_child("RouteGraphView", true, false)
	if view != null:
		print("Nodes: %d" % view.nodes.size())
		for n in view.nodes:
			print("  %s type=%s in=%d out=%d x=%d y=%d" % [n.id, n.type, n.inputs.size(), n.outputs.size(), n.x, n.y])

	get_tree().quit(0)
