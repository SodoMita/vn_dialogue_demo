class_name RouteGraphLayout extends RefCounted
## Layered left-to-right DAG layout (Sugiyama-style).
## Longest-path layers, barycenter crossing reduction, then port slots.


const NODE_WIDTH := {
	"cue": 168.0,
	"dialogue": 232.0,
	"choice": 220.0,
	"condition": 196.0,
	"mutation": 188.0,
	"goto": 150.0,
	"end": 120.0,
}

const H_GAP := 88.0
const V_GAP := 28.0
const PORT_PAD := 18.0
const TITLE_H := 22.0


static func apply(graph: RouteGraph) -> void:
	if graph.nodes.is_empty():
		return
	_size_nodes(graph)
	_assign_layers(graph)
	_reduce_crossings(graph)
	_place(graph)
	_place_ports(graph)


static func _size_nodes(graph: RouteGraph) -> void:
	for n: RouteGraph.RouteNode in graph.nodes:
		var w: float = NODE_WIDTH.get(n.kind, 220.0)
		var ports: int = maxi(n.inputs.size(), n.outputs.size())
		var h: float = 56.0 + float(maxi(0, ports - 1)) * 16.0
		if not n.body.is_empty():
			h += 18.0
		if n.kind == "dialogue":
			h = maxf(h, 80.0)
		n.size = Vector2(w, h)


static func _assign_layers(graph: RouteGraph) -> void:
	var incoming: Dictionary = {}
	var outgoing: Dictionary = {}
	for n: RouteGraph.RouteNode in graph.nodes:
		incoming[n.id] = []
		outgoing[n.id] = []
	for e: RouteGraph.RouteEdge in graph.edges:
		(incoming[e.to_id] as Array).append(e.from_id)
		(outgoing[e.from_id] as Array).append(e.to_id)

	var roots: Array = []
	for n: RouteGraph.RouteNode in graph.nodes:
		if (incoming[n.id] as Array).is_empty():
			roots.append(n.id)
	if roots.is_empty() and not graph.first_id.is_empty():
		roots.append(graph.first_id)
	if roots.is_empty() and not graph.nodes.is_empty():
		roots.append(graph.nodes[0].id)

	var layer_of: Dictionary = {}
	var queue: Array = []
	for r: Variant in roots:
		layer_of[r] = 0
		queue.append(r)
	var guard := 0
	while not queue.is_empty() and guard < graph.nodes.size() * 8:
		guard += 1
		var id: String = str(queue.pop_front())
		var base: int = int(layer_of[id])
		for dest: Variant in outgoing.get(id, []):
			var next_layer: int = base + 1
			if not layer_of.has(dest) or int(layer_of[dest]) < next_layer:
				layer_of[dest] = next_layer
				queue.append(dest)

	# Unreachable nodes (e.g. unused else) sit on layer 0.
	var max_layer := 0
	for n: RouteGraph.RouteNode in graph.nodes:
		n.layer = int(layer_of.get(n.id, 0))
		max_layer = maxi(max_layer, n.layer)

	# Pull sinks that only exist as terminals as far right as their preds.
	for _i in 4:
		for e: RouteGraph.RouteEdge in graph.edges:
			var src: RouteGraph.RouteNode = graph.get_node(e.from_id)
			var dst: RouteGraph.RouteNode = graph.get_node(e.to_id)
			if src == null or dst == null:
				continue
			if dst.layer <= src.layer:
				dst.layer = src.layer + 1
				max_layer = maxi(max_layer, dst.layer)

	graph.set_meta("max_layer", max_layer)


static func _reduce_crossings(graph: RouteGraph) -> void:
	var layers: Dictionary = {}
	for n: RouteGraph.RouteNode in graph.nodes:
		if not layers.has(n.layer):
			layers[n.layer] = []
		(layers[n.layer] as Array).append(n)

	var keys: Array = layers.keys()
	keys.sort()
	for k: Variant in keys:
		var arr: Array = layers[k]
		arr.sort_custom(func(a: RouteGraph.RouteNode, b: RouteGraph.RouteNode) -> bool: return a.id < b.id)

	var preds: Dictionary = {}
	var succs: Dictionary = {}
	for n: RouteGraph.RouteNode in graph.nodes:
		preds[n.id] = []
		succs[n.id] = []
	for e: RouteGraph.RouteEdge in graph.edges:
		(preds[e.to_id] as Array).append(e.from_id)
		(succs[e.from_id] as Array).append(e.to_id)

	for _pass in 8:
		for li: int in keys.size():
			var arr: Array = layers[keys[li]]
			var order_of: Dictionary = {}
			if li > 0:
				var prev: Array = layers[keys[li - 1]]
				for i: int in prev.size():
					order_of[(prev[i] as RouteGraph.RouteNode).id] = i
			for n: RouteGraph.RouteNode in arr:
				var acc := 0.0
				var c := 0
				for p: Variant in preds[n.id]:
					if order_of.has(p):
						acc += float(order_of[p])
						c += 1
				n.order = int(round(acc / float(c))) if c > 0 else n.order
			arr.sort_custom(func(a: RouteGraph.RouteNode, b: RouteGraph.RouteNode) -> bool:
				if a.order == b.order:
					return a.id < b.id
				return a.order < b.order
			)
			for i: int in arr.size():
				(arr[i] as RouteGraph.RouteNode).order = i


static func _place(graph: RouteGraph) -> void:
	var layers: Dictionary = {}
	var layer_width: Dictionary = {}
	for n: RouteGraph.RouteNode in graph.nodes:
		if not layers.has(n.layer):
			layers[n.layer] = []
			layer_width[n.layer] = 0.0
		(layers[n.layer] as Array).append(n)
		layer_width[n.layer] = maxf(float(layer_width[n.layer]), n.size.x)

	var keys: Array = layers.keys()
	keys.sort()
	var x := 40.0
	for k: Variant in keys:
		var arr: Array = layers[k]
		arr.sort_custom(func(a: RouteGraph.RouteNode, b: RouteGraph.RouteNode) -> bool: return a.order < b.order)
		var y := 40.0
		for n: RouteGraph.RouteNode in arr:
			n.position = Vector2(x, y)
			y += n.size.y + V_GAP
		x += float(layer_width[k]) + H_GAP


static func _place_ports(graph: RouteGraph) -> void:
	for n: RouteGraph.RouteNode in graph.nodes:
		_slot_ports(n.inputs, n.size, false)
		_slot_ports(n.outputs, n.size, true)


static func _slot_ports(ports: Array, size: Vector2, is_output: bool) -> void:
	var count := ports.size()
	if count == 0:
		return
	var usable: float = maxf(16.0, size.y - PORT_PAD * 2.0)
	var x: float = size.x if is_output else 0.0
	for i: int in count:
		var t: float = 0.5 if count == 1 else float(i) / float(count - 1)
		var y: float = PORT_PAD + t * usable
		(ports[i] as RouteGraph.RoutePort).offset = Vector2(x, y)
