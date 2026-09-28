class_name ActorDefinition extends Resource
## One character, defined once in the editor. Short staging tags
## (#show=maya:smile@left) read everything else from here: which sprite keys
## are its looks, how tall it stands, where its feet are, and which
## animations #anim= can play.

## Actor ID used in tags ("maya"). Must be an identifier; "left"/"right"
## are reserved for the two legacy portrait slots.
@export var id: String = ""
## Short looks resolve to "<sprite_prefix>_<look>" (defaults to id).
@export var sprite_prefix: String = ""
## Look used when #show creates the actor without one: a registered sprite
## key ("maya") or a short look ("smile"). Invalid -> the show is rejected.
@export var default_appearance: String = ""
## Place used when #show creates the actor without @place.
@export var default_place: String = "center"
## Optional scene body instead of a sprite quad/rect (its root is the body).
@export var scene: PackedScene
## 3D: standing height in world units. 2D: fraction of the stage height.
@export var height_3d: float = 1.7
@export var height_2d: float = 0.95
## Feet pivot as a fraction of the sprite height from the top (1 = bottom).
@export_range(0.0, 1.0) var feet_anchor: float = 1.0
## Animations #anim= plays. Track paths are relative to the body node
## (use "." for the body itself). 2D bodies are TextureRects (px), 3D
## bodies are Sprite3DQuads (world units) - hence two libraries.
@export var animations_2d: AnimationLibrary
@export var animations_3d: AnimationLibrary
## For scene bodies: path (inside the scene) of its AnimationPlayer or
## AnimationTree. Empty -> a player is created for the libraries above.
@export var animation_player: NodePath


func prefix() -> String:
	return sprite_prefix if sprite_prefix != "" else id
