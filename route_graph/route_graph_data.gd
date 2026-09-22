class_name RouteGraph extends RefCounted
## CPU-side choice/route graph: nodes with named ports, edges, and a layered
## layout. The mesh builder turns this into a single atlas-sampled ArrayMesh.


class RoutePort:
	var name: String = ""
	var label: String = ""
	## Local offset from the node origin (top-left) after layout.
	var offset: Vector2 = Vector2.ZERO


class RouteNode:
	var id: String = ""
	var kind: String = "dialogue"
	var title: String = ""
	var body: String = ""
	var annotation: String = ""
	var tags: PackedStringArray = PackedStringArray()
	var bg_key: String = ""
	var sprite_key: String = ""
	var inputs: Array = [] ## RoutePort
	var outputs: Array = [] ## RoutePort
	var position: Vector2 = Vector2.ZERO
	var size: Vector2 = Vector2(220, 80)
	var layer: int = 0
	var order: int = 0


class RouteEdge:
	var from_id: String = ""
	var from_port: String = ""
	var to_id: String = ""
	var to_port: String = ""
	var label: String = ""
	var kind: String = "flow" ## flow | choice | condition


var nodes: Array = [] ## RouteNode
var edges: Array = [] ## RouteEdge
var node_index: Dictionary = {} ## id -> RouteNode
var first_id: String = ""
var source_path: String = ""


func clear() -> void:
	nodes.clear()
	edges.clear()
	node_index.clear()
	first_id = ""


func add_node(n: RouteNode) -> RouteNode:
	nodes.append(n)
	node_index[n.id] = n
	if first_id.is_empty():
		first_id = n.id
	return n


func get_node(id: String) -> RouteNode:
	return node_index.get(id, null)


func add_port(n: RouteNode, is_output: bool, port_name: String, port_label: String = "") -> RoutePort:
	var p := RoutePort.new()
	p.name = port_name
	p.label = port_label if not port_label.is_empty() else port_name
	if is_output:
		n.outputs.append(p)
	else:
		n.inputs.append(p)
	return p


func add_edge(from_id: String, from_port: String, to_id: String, to_port: String, label: String = "", kind: String = "flow") -> RouteEdge:
	if from_id.is_empty() or to_id.is_empty() or from_id == to_id:
		return null
	if not node_index.has(from_id) or not node_index.has(to_id):
		return null
	var e := RouteEdge.new()
	e.from_id = from_id
	e.from_port = from_port
	e.to_id = to_id
	e.to_port = to_port
	e.label = label
	e.kind = kind
	edges.append(e)
	return e


func port_position(n: RouteNode, port_name: String, is_output: bool) -> Vector2:
	var list: Array = n.outputs if is_output else n.inputs
	for p: RoutePort in list:
		if p.name == port_name:
			return n.position + p.offset
	if is_output:
		return n.position + Vector2(n.size.x, n.size.y * 0.5)
	return n.position + Vector2(0.0, n.size.y * 0.5)


func bounds() -> Rect2:
	if nodes.is_empty():
		return Rect2(0, 0, 1, 1)
	var r := Rect2(nodes[0].position, nodes[0].size)
	for n: RouteNode in nodes:
		r = r.expand(n.position)
		r = r.expand(n.position + n.size)
	return r.grow(48.0)


func ensure_end_node() -> RouteNode:
	if node_index.has("end"):
		return node_index["end"]
	var n := RouteNode.new()
	n.id = "end"
	n.kind = "end"
	n.title = "END"
	n.body = ""
	add_port(n, false, "in", "in")
	return add_node(n)
