class_name DevCapture
extends RefCounted
## `-- --screenshot=<path>` support for any scene: saves one rendered frame
## and quits. How visuals are checked without anyone at the window.
##
##     godot --path . res://scenes/world/world.tscn -- --screenshot=user://w.png
##
## Optional `--walk=x,y,seconds` drives the player first, where a scene has one.


static func maybe_capture(scene: Node) -> void:
	var path := ""
	var walk := Vector3.ZERO
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot="):
			path = arg.trim_prefix("--screenshot=")
		elif arg.begins_with("--walk="):
			var parts := arg.trim_prefix("--walk=").split(",")
			if parts.size() == 3:
				walk = Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
	if path.is_empty():
		return
	_capture(scene, path, walk)


static func _capture(scene: Node, path: String, walk: Vector3) -> void:
	if walk != Vector3.ZERO and scene.has_method("player_body"):
		var body: PlayerBody = scene.call("player_body")
		body.scripted_direction = Vector2(walk.x, walk.y)
		await scene.get_tree().create_timer(walk.z).timeout
		# Stop mid-stride is fine; the frame shows the walk.
	for i in 4:
		await RenderingServer.frame_post_draw
	var error := scene.get_viewport().get_texture().get_image().save_png(path)
	Log.info("capture", "Screenshot saved", {"path": path, "error": error})
	scene.get_tree().quit()
