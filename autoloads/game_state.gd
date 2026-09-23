## Global story state that dialogue files can read and mutate.
## Dialogue files use `using GameState` to reference these members directly.
extends Node


@export var player_name: String = "Alex"
@export var school_name: String = "Sakuragaoka High"
@export var day: int = 1

@export var met_maya: bool = false
@export var met_rook: bool = false
@export var knows_secret: bool = false
## Fixed for the playthrough. A from-start replay uses this, not a fresh roll,
## so the same choices produce the same random results. Saves keep it inside
## each history snapshot.
@export var story_seed: int = 1
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	_reseed()
	# Dialogue Manager is a later autoload, so the first reseed cannot see it yet.
	call_deferred("_reseed")


func reset() -> void:
	player_name = "Alex"
	school_name = "Sakuragaoka High"
	day = 1
	met_maya = false
	met_rook = false
	knows_secret = false
	_reseed()


func _reseed() -> void:
	rng.seed = story_seed
	seed(story_seed)
	var manager := get_tree().root.get_node_or_null("DialogueManager")
	if manager != null and manager.has_method("reseed_randomizer"):
		manager.reseed_randomizer(story_seed)


## Capture every exported story variable (used by the balloon's rollback).
## The owned RNG stream is stored beside them so a from-current replay can continue it.
func snapshot() -> Dictionary:
	var data: Dictionary = {}
	for property: Dictionary in get_script().get_script_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var value = get(property.name)
			if value is Object:
				continue
			data[property.name] = value
	# Strings, not raw ints: a save is JSON, and a 64-bit RNG state does not survive a number.
	data["rng_state"] = str(rng.state)
	var manager := get_tree().root.get_node_or_null("DialogueManager")
	if manager != null:
		var stream = manager.get("_rng")
		if stream != null:
			data["dm_rng_state"] = str(stream.state)
	return data


## Restore a snapshot taken with [method snapshot] (used by rollback).
func restore(data: Dictionary) -> void:
	for key: String in data:
		if key == "rng_state":
			rng.state = int(data[key])
			continue
		if key == "dm_rng_state":
			var manager := get_tree().root.get_node_or_null("DialogueManager")
			if manager != null:
				var stream = manager.get("_rng")
				if stream != null:
					stream.state = int(data[key])
			continue
		set(key, data[key])
