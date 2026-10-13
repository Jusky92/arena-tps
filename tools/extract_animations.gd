extends SceneTree
## Extrait les animations utiles du pack Quaternius "Universal Animation Library"
## (gaits.glb, CC0) vers une bibliothèque Godot compacte, sans le mannequin 3D.
##
## Utilisation (depuis front/, avec gaits.glb copié dans front/assets/_tmp/) :
##   godot --headless --path . -s res://../tools/extract_animations.gd
## (ou copier ce script dans front/ et le lancer avec -s res://extract_animations.gd)

const SOURCE := "res://assets/_tmp/gaits.glb"
const TARGET := "res://assets/characters/animations/locomotion.res"
const KEEP := [
	"Idle", "Walk", "Jog_Fwd", "Sprint", "Crouch_Idle", "Crouch_Fwd",
	"Jump_Start", "Jump", "Jump_Land", "Death01", "Hit_Chest", "Roll",
	"Pistol_Idle", "Pistol_Aim_Neutral", "Pistol_Aim_Up", "Pistol_Aim_Down", "Dance",
]


func _initialize() -> void:
	var scene: Node = load(SOURCE).instantiate()
	var player: AnimationPlayer = scene.find_child("AnimationPlayer", true, false)
	var source: AnimationLibrary = player.get_animation_library("")
	var library := AnimationLibrary.new()
	for clip in KEEP:
		var animation: Animation = source.get_animation(clip).duplicate(true)
		# On ne garde que les rotations (+ la position du bassin) : l'animation
		# s'adapte ainsi à des corps de proportions différentes.
		for i in range(animation.get_track_count() - 1, -1, -1):
			var path := str(animation.track_get_path(i))
			var type := animation.track_get_type(i)
			if type == Animation.TYPE_SCALE_3D:
				animation.remove_track(i)
			elif type == Animation.TYPE_POSITION_3D and not path.ends_with(":pelvis"):
				animation.remove_track(i)
		library.add_animation(clip, animation)
	var err := ResourceSaver.save(library, TARGET, ResourceSaver.FLAG_COMPRESS)
	print("Bibliothèque sauvegardée : ", TARGET, " (", KEEP.size(), " animations) -> ", error_string(err))
	quit()
