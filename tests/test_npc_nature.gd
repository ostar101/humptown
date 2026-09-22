extends TestCase
## Npc.nature and Npc.deals (M8 D-082): what kind of person someone is, not
## how they feel about the player, and the shop ids they deal from. Data
## only this step — nothing reads these fields yet.


func test_default_nature_when_unauthored() -> void:
	var npc := Npc.from_data({"id": "npc_x", "name": "X", "home": "loc_x", "schedule": "sched_x"})
	assert_eq(npc.nature, Npc.DEFAULT_NATURE)


func test_authored_nature_is_read() -> void:
	var npc := Npc.from_data({
		"id": "npc_x", "name": "X", "home": "loc_x", "schedule": "sched_x",
		"nature": {"lawfulness": 0.1, "greed": 0.9, "risk": 0.8, "discretion": 0.7},
	})
	assert_eq(npc.nature["lawfulness"], 0.1)
	assert_eq(npc.nature["greed"], 0.9)
	assert_eq(npc.nature["risk"], 0.8)
	assert_eq(npc.nature["discretion"], 0.7)


func test_a_partial_nature_backfills_the_rest_with_defaults() -> void:
	var npc := Npc.from_data({
		"id": "npc_x", "name": "X", "home": "loc_x", "schedule": "sched_x",
		"nature": {"lawfulness": 0.0},
	})
	assert_eq(npc.nature["lawfulness"], 0.0)
	assert_eq(npc.nature["greed"], Npc.DEFAULT_NATURE["greed"])
	assert_eq(npc.nature["risk"], Npc.DEFAULT_NATURE["risk"])
	assert_eq(npc.nature["discretion"], Npc.DEFAULT_NATURE["discretion"])


func test_deals_default_empty() -> void:
	var npc := Npc.from_data({"id": "npc_x", "name": "X", "home": "loc_x", "schedule": "sched_x"})
	assert_eq(npc.deals, [] as Array[String])


func test_deals_are_read() -> void:
	var npc := Npc.from_data({
		"id": "npc_x", "name": "X", "home": "loc_x", "schedule": "sched_x",
		"deals": ["shop_a", "shop_b"],
	})
	assert_eq(npc.deals, ["shop_a", "shop_b"] as Array[String])


# --- DataRegistry validation -------------------------------------------------

var data: DataRegistry


func before_each() -> void:
	data = DataRegistry.new()
	data.load_all()


func test_the_authored_npcs_have_a_valid_nature() -> void:
	assert_eq(data.validate_references(), [] as Array[String])


func test_an_out_of_range_nature_axis_is_reported() -> void:
	data.tables["npcs"]["npc_ida"]["nature"] = {"lawfulness": 1.5}
	var text := "\n".join(data.validate_references())
	assert_true(text.contains("nature axis 'lawfulness' is out of range"), text)


func test_an_unknown_nature_axis_is_reported() -> void:
	data.tables["npcs"]["npc_ida"]["nature"] = {"charm": 0.5}
	var text := "\n".join(data.validate_references())
	assert_true(text.contains("unknown nature axis 'charm'"), text)


func test_a_non_numeric_nature_axis_is_reported() -> void:
	data.tables["npcs"]["npc_ida"]["nature"] = {"greed": "a lot"}
	var text := "\n".join(data.validate_references())
	assert_true(text.contains("nature axis 'greed' is not a number"), text)


func test_a_deal_naming_an_unknown_shop_is_reported() -> void:
	data.tables["npcs"]["npc_rauno"]["deals"] = ["shop_that_does_not_exist"]
	var text := "\n".join(data.validate_references())
	assert_true(text.contains("npc 'npc_rauno' deals from unknown shop 'shop_that_does_not_exist'"), text)


func test_a_deal_naming_a_real_shop_is_accepted() -> void:
	var some_shop: String = data.ids("shops")[0]
	data.tables["npcs"]["npc_rauno"]["deals"] = [some_shop]
	assert_eq(data.validate_references(), [] as Array[String])
