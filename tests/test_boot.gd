extends TestCase
## Boot: which scene the game hands off to. Everyone starts at the title
## screen (D-034); SimViewer is a developer tool, reached only through
## developer mode (M2 step 5).

var _developer_mode_before: bool = false


func before_each() -> void:
	_developer_mode_before = Settings.get_value("developer_mode")


func after_each() -> void:
	Settings.set_value("developer_mode", _developer_mode_before, false)


func test_normally_the_title_screen_is_the_destination() -> void:
	Settings.set_value("developer_mode", false, false)
	assert_eq(Boot.destination_scene(), Boot.TITLE)
	assert_true(ResourceLoader.exists(Boot.TITLE), "and it exists")


func test_developer_mode_reaches_the_sim_viewer_instead() -> void:
	Settings.set_value("developer_mode", true, false)
	assert_eq(Boot.destination_scene(), Boot.SIM_VIEWER)
