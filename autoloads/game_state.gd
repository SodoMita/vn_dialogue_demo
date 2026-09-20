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
