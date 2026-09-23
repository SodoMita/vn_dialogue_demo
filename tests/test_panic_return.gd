extends Node
## Host that parks a runner on the root, then gets out of the way.
## The runner changes scenes; this node does not have to survive that.


func _ready() -> void:
	var runner := Node.new()
	runner.name = "PanicReturnRunner"
	runner.set_script(load("res://tests/panic_return_runner.gd"))
	get_tree().root.add_child.call_deferred(runner)
