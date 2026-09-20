## Global story state that dialogue files can read and mutate.
## Dialogue files use `using GameState` to reference these members directly.
extends Node


@export var player_name: String = "Alex"
@export var school_name: String = "Sakuragaoka High"
@export var day: int = 1

@export var met_maya: bool = false
@export var met_rook: bool = false
@export var knows_secret: bool = false


func reset() -> void:
	player_name = "Alex"
	day = 1
	met_maya = false
	met_rook = false
	knows_secret = false


## Capture every exported story variable (used by the balloon's rollback).
func snapshot() -> Dictionary:
	var data: Dictionary = {}
	for property: Dictionary in get_script().get_script_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			data[property.name] = get(property.name)
	return data


## Restore a snapshot taken with [method snapshot] (used by rollback).
func restore(data: Dictionary) -> void:
	for key: String in data:
		set(key, data[key])
