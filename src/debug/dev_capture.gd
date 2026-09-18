class_name DevCapture
extends RefCounted
## `-- --screenshot=<path>` support for any scene: saves one rendered frame
## and quits. How visuals are checked without anyone at the window.
##
##     godot --path . res://scenes/world/world.tscn -- --screenshot=user://w.png
##
## Optional, where a scene has a player: `--advance=minutes` skips game time
## first (the town at another hour), `--at=x,y` puts the player on that cell,
## `--interact=dx,dy` faces that way and presses the interact button (through
## the rules, as a player would), and `--walk=x,y,seconds` then drives them.


static func maybe_capture(scene: Node) -> void:
	var path := ""
	var walk := Vector3.ZERO
	var advance := 0
	var at := Vector2i(-1, -1)
	var interact := Vector2i.ZERO
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--advance="):
			advance = int(arg.trim_prefix("--advance="))
		elif arg.begins_with("--at="):
			var cell := arg.trim_prefix("--at=").split(",")
			if cell.size() == 2:
				at = Vector2i(int(cell[0]), int(cell[1]))
		elif arg.begins_with("--interact="):
			var towards := arg.trim_prefix("--interact=").split(",")
			if towards.size() == 2:
				interact = Vector2i(int(towards[0]), int(towards[1]))
		elif arg.begins_with("--screenshot="):
			path = arg.trim_prefix("--screenshot=")
		elif arg.begins_with("--walk="):
			var parts := arg.trim_prefix("--walk=").split(",")
			if parts.size() == 3:
				walk = Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
	if path.is_empty():
		return
	if advance > 0:
		Game.advance_time(advance)
	if at.x >= 0 and scene.has_method("player_body"):
		var player: PlayerBody = scene.call("player_body")
		player.place_at(DistrictMap.cell_to_world(at))
		Game.move_player(player.position)
		if scene.has_method("show_current_area"):
			scene.call("show_current_area")   # snaps the camera there
	if interact != Vector2i.ZERO and scene.has_method("interact"):
		var body: PlayerBody = scene.call("player_body")
		body.facing = interact
		var result: Result = scene.call("interact")
		Log.info("capture", "Interacted", {"ok": result.ok, "code": result.code})
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
