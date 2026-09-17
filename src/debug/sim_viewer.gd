extends Control
## Debug simulation viewer.
##
## Milestone 1 has no art yet, and "it compiles" is not evidence that a world
## is alive. This screen is the evidence: the clock runs, people walk to work,
## schedules bend to needs, gossip crosses the town and time skips resolve
## correctly — all visible, at a glance, before a single sprite exists.
##
## It is a developer tool, not a game screen. It will be replaced by the real
## world renderer in Milestone 2 and kept behind developer mode after that.

const REFRESH_INTERVAL := 0.25

var _clock_label: Label
var _world_label: Label
var _npc_list: RichTextLabel
var _events_label: RichTextLabel
var _status_label: Label
var _refresh_timer := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	if not Game.is_running():
		var started := Game.new_game("bg_returning")
		if started.is_err():
			_status_label.text = "Failed to start: %s (%s)" % [started.code, started.message]
			return
	_status_label.text = "World running. Speed %.0f game-min/sec." % Game.clock.minutes_per_real_second
	_refresh()


func _process(delta: float) -> void:
	_refresh_timer += delta
	if _refresh_timer < REFRESH_INTERVAL:
		return
	_refresh_timer = 0.0
	_refresh()


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	root.offset_left = 16
	root.offset_top = 12
	root.offset_right = -16
	root.offset_bottom = -12
	add_child(root)

	_clock_label = Label.new()
	_clock_label.add_theme_font_size_override("font_size", 26)
	root.add_child(_clock_label)

	_world_label = Label.new()
	_world_label.add_theme_font_size_override("font_size", 13)
	root.add_child(_world_label)

	root.add_child(_make_controls())

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 12)
	root.add_child(columns)

	_npc_list = _make_panel(columns, 2)
	_events_label = _make_panel(columns, 1)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 12)
	root.add_child(_status_label)


func _make_panel(parent: Control, stretch: int) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.scroll_active = true
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	label.size_flags_stretch_ratio = float(stretch)
	label.add_theme_font_size_override("normal_font_size", 13)
	parent.add_child(label)
	return label


func _make_controls() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var buttons := [
		["Pause", func() -> void: Game.pause_time(not Game.clock.paused)],
		["1x", func() -> void: Game.clock.minutes_per_real_second = 1.0],
		["30x", func() -> void: Game.clock.minutes_per_real_second = 30.0],
		["120x", func() -> void: Game.clock.minutes_per_real_second = 120.0],
		["+1 hour", func() -> void: Game.advance_time(60)],
		["Sleep 8h", func() -> void: Game.advance_time(480)],
		["Gossip", _seed_gossip],
		["Save", func() -> void: _report(Game.save_game("debug"), "Saved")],
		["Load", func() -> void: _report(Game.load_game("debug"), "Loaded")],
	]
	for entry in buttons:
		var button := Button.new()
		button.text = entry[0]
		button.pressed.connect(entry[1])
		row.add_child(button)
	return row


## Drops a juicy fact into the world so information propagation is visible:
## one witness now, half the harbour by evening.
func _seed_gossip() -> void:
	var witnesses: Array[String] = ["npc_tuomas"]
	var fact_id := Game.knowledge.observe_event(
		"npc_elias", "stole_from", Game.clock.total_minutes, witnesses,
		{"object": "loc_corner_shop", "severity": 0.85, "visibility": "social",
		 "location": "loc_corner_shop"})
	_status_label.text = "Seeded fact %s: Tuomas saw Elias take from the shop." % fact_id


func _report(result: Result, verb: String) -> void:
	_status_label.text = "%s." % verb if result.is_ok() else "%s failed: %s" % [verb, result.code]


func _refresh() -> void:
	if not Game.is_running():
		return
	var clock := Game.clock
	_clock_label.text = "%s   %s" % [clock.format_time(), clock.format_date()]

	var tiers := Game.director.stats()
	_world_label.text = "Region: %s   |   NPCs %d  (focus %d / active %d / background %d / dormant %d)   |   queued events %d   |   facts %d   |   AI: %s" % [
		Game.world.current_region, tiers.get("total", 0),
		tiers.get("focus", 0), tiers.get("active", 0),
		tiers.get("background", 0), tiers.get("dormant", 0),
		Game.events_queue.size(), Game.knowledge.facts.size(),
		"on" if Game.llm.is_available() else "offline",
	]

	_refresh_npcs(clock)
	_refresh_events(clock)


func _refresh_npcs(clock: GameClock) -> void:
	var lines := "[b]People[/b]\n"
	var weekday := clock.weekday()
	var ids: Array = Game.npcs.all_ids()
	ids.sort()
	for npc_id in ids:
		var npc: Npc = Game.npcs.get_npc(npc_id)
		var location_id := Game.npcs.location_of(npc_id, clock.total_minutes, weekday)
		var location: Location = Game.world.get_location(location_id)
		var place := location.display_name() if location != null else location_id
		var tier := SimLod.tier_name(npc.tier).to_lower()
		var colour := "888888"
		match npc.tier:
			SimLod.Tier.ACTIVE: colour = "7fc7ff"
			SimLod.Tier.FOCUS: colour = "ffd27f"
			SimLod.Tier.BACKGROUND: colour = "b0b0b0"
		var known := Game.knowledge.known_fact_ids(npc_id).size()
		lines += "[color=#%s]%-18s[/color] %-14s %-22s %s%s\n" % [
			colour, npc.name, tr("activity." + npc.activity), place, tier,
			"   (knows %d)" % known if known > 0 else "",
		]
	_npc_list.text = lines


func _refresh_events(clock: GameClock) -> void:
	var lines := "[b]Scheduled events[/b]\n"
	var pending := Game.events_queue.pending()
	if pending.is_empty():
		lines += "[color=#777777]nothing scheduled[/color]\n"
	for event in pending.slice(0, 18):
		var minutes_away := event.at - clock.total_minutes
		lines += "+%4d min  %-20s %s\n" % [
			minutes_away, event.kind, JSON.stringify(event.payload),
		]
	if pending.size() > 18:
		lines += "[color=#777777]... and %d more[/color]\n" % (pending.size() - 18)

	lines += "\n[b]Player[/b]\n"
	lines += "cash %d / bank %d\n" % [Game.player.wallet.cash, Game.player.wallet.bank]
	lines += "condition: %s\n" % Game.player.stats.describe()
	lines += "carrying %.1f / %.1f\n" % [Game.player.inventory.total_weight(), Game.player.inventory.capacity()]
	for entry in Game.player.skills.top_skills(4):
		lines += "  %s %d\n" % [tr("skill." + str(entry["id"])), int(entry["level"])]
	_events_label.text = lines
