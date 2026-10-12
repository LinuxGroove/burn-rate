extends Node
## Prints the size of models by name: godot --headless --path . tools/probe_models.tscn -- Name1 Name2 ...
func _ready() -> void:
	for n in OS.get_cmdline_user_args():
		var ps := Kit.scene(n)
		if ps == null:
			print(n, ": missing")
			continue
		var node: Node3D = ps.instantiate()
		var b := Kit.aabb_of(node)
		var anims := []
		for ap in node.find_children("", "AnimationPlayer", true, false):
			anims.append_array(ap.get_animation_list())
		print("%s: pos %s size %s %s" % [n, b.position, b.size, anims if anims.size() > 0 else ""])
		node.free()
	get_tree().quit()
