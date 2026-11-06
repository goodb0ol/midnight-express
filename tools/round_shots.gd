extends Node
## Windowed HUD check: plays a raid's main beats and saves screenshots to captures/.
##   godot --path . res://tools/round_shots.tscn --resolution 1280x720

const OUT_DIR := "res://captures/"

var main: Main
var director: RoundDirector


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	FileAccess.open(OUT_DIR + ".gdignore", FileAccess.WRITE)
	main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	director = main.round_director
	await get_tree().create_timer(1.0).timeout
	await _shot("round_01_title")
	await get_tree().create_timer(2.0).timeout
	await _shot("round_02_raid_start")
	await _yeet_one()
	await _yeet_one()
	await get_tree().create_timer(0.1).timeout
	GameEvents.score_awarded.emit(120, "40 M OF AIRTIME")
	await get_tree().create_timer(0.25).timeout
	await _shot("round_03_score_popup")
	main.local_player.input_source.yaw = 0.0
	await get_tree().create_timer(0.3).timeout
	await _shot("round_04_tags_behind")
	director.time_left = 6.3
	await get_tree().create_timer(0.3).timeout
	await _shot("round_05_raid_warning")
	main.local_player.input_source.yaw = Main.PLAYER_SPAWN_YAW
	director.time_left = 0.05
	await get_tree().create_timer(0.7).timeout
	await _shot("round_06_raid_hits")
	await get_tree().create_timer(1.0).timeout
	await _shot("round_07_raid_hits_late")
	await get_tree().create_timer(1.4).timeout
	await _shot("round_08_results")
	print("shots finished, window %s" % str(get_window().size))
	get_tree().quit()


func _yeet_one() -> void:
	var stowaway: TestDummy = null
	for body in director.stowaway_bodies():
		if body is TestDummy:
			stowaway = body
			break
	if stowaway == null:
		return
	stowaway.receive_bonk(TestDummy.MAX_HP, Vector3.FORWARD, main.local_player)
	await get_tree().physics_frame
	await get_tree().physics_frame
	for body in director.stowaway_bodies():
		if body is Ragdoll:
			body.on_left_train()


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(OUT_DIR + file + ".png"))
