extends Node
@export var out_path: String = "/home/user/route_graph_runtime.png"
func _ready():
	print("CaptureRouteGraph: starting...")
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
		print("show_graph")
	for i in range(25):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	for i in range(10):
		await get_tree().process_frame
	var view = get_node_or_null("RouteGraphPanel/Margin/VBox/GraphContainer/RouteGraphView")
	if view == null:
		view = get_tree().root.find_child("RouteGraphView", true, false)
	if view != null:
		print("Nodes: %d" % view.nodes.size())
		# Fit all: set zoom 0.7 and pan to show from x=0 to x=1800
		view.target_zoom = 0.7
		view.zoom = 0.7
		view.target_pan = Vector2(350, 250)
		view.pan = Vector2(350, 250)
		view._update_shader_params()
		print("Set zoom 0.7 pan 350,250")
		for i in range(30):
			await get_tree().process_frame

	var vp: Viewport = get_viewport()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	var img: Image = vp.get_texture().get_image()
	if img == null:
		push_error("Failed to get viewport image")
		img = Image.create(1920, 1080, false, Image.FORMAT_RGBA8)
		img.fill(Color("#0A0F1E"))
	print("Got image %dx%d" % [img.get_width(), img.get_height()])
	var save_path = out_path
	img.save_png(save_path)
	print("Saved to %s" % save_path)
	var docs_png = "res://docs/route_graph_runtime.png"
	img.save_png(docs_png)
	var docs_webp = "res://docs/route_graph_runtime.webp"
	img.save_webp(docs_webp)
	print("Also saved to docs")
	print("Waiting 12s for grim...")
	for i in range(180):
		await get_tree().process_frame
	get_tree().quit(0)
