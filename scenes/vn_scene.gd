extends Node2D
## The demo visual novel scene. Everything visual is provided by the balloon;
## this scene just kicks the conversation off. Swap `dialogue_resource` in the
## inspector to try a different script.


@export var dialogue_resource: DialogueResource = preload("res://dialogue/intro.dialogue")
@export var start_from_cue: String = "start"


func _ready() -> void:
	Engine.get_singleton("DialogueManager").show_dialogue_balloon(dialogue_resource, start_from_cue)
