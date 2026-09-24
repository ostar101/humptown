class_name PhoneWindow
extends CanvasLayer
## The phone (D-045): its own window, shaped like one, not a page of the
## menu. Messages and Contacts for now; more apps join the bottom bar as they
## are built. It reads the phone and never writes it, except through
## `Game.send_text()`, `Game.answer_message()` and `Game.read_thread()`, which
## decide. Time stands still while it is open, so a reply to a text arrives
## after it is put away.

signal closed()
## The player pressed Call on a thread; the world opens the call (D-050).
signal call_requested(npc_id: String)

enum Page { THREADS, THREAD, CONTACTS, CALENDAR, BANK, MAP }

const PREVIEW_CHARS := 30

var _page: Page = Page.THREADS
var _npc := ""
var _time_was_paused := false

@onready var _root: Control = $Root
@onready var _rows: VBoxContainer = %Rows
@onready var _title: Label = %Title
@onready var _clock: Label = %Clock
@onready var _back: Button = %Back
@onready var _tab_messages: Button = %TabMessages
@onready var _tab_contacts: Button = %TabContacts
@onready var _tab_calendar: Button = %TabCalendar
@onready var _tab_bank: Button = %TabBank
@onready var _tab_map: Button = %TabMap
@onready var _close: Button = %Close
@onready var _compose: HBoxContainer = %Compose
@onready var _line: LineEdit = %Line
@onready var _send: Button = %Send
@onready var _call: Button = %Call
@onready var _notice: Label = %Notice


func _ready() -> void:
	_root.visible = false
	_close.pressed.connect(close)
	_back.pressed.connect(func() -> void: show_page(Page.THREADS))
	_tab_messages.pressed.connect(func() -> void: show_page(Page.THREADS))
	_tab_contacts.pressed.connect(func() -> void: show_page(Page.CONTACTS))
	_tab_calendar.pressed.connect(func() -> void: show_page(Page.CALENDAR))
	_tab_bank.pressed.connect(func() -> void: show_page(Page.BANK))
	_tab_map.pressed.connect(func() -> void: show_page(Page.MAP))
	_send.pressed.connect(_send_line)
	_call.pressed.connect(_press_call)
	_line.text_submitted.connect(func(_text: String) -> void: _send_line())
	Events.phone_message.connect(_on_phone_message)


func _exit_tree() -> void:
	if Events.phone_message.is_connected(_on_phone_message):
		Events.phone_message.disconnect(_on_phone_message)


## Opens the phone if the player has one. Returns whether it opened.
func open() -> bool:
	if _root.visible:
		return true
	if not Game.is_running() or not Game.has_phone():
		return false
	_time_was_paused = Game.clock.paused
	Game.pause_time(true)
	_root.visible = true
	show_page(Page.THREADS)
	return true


func close() -> void:
	if not _root.visible:
		return
	_root.visible = false
	Game.pause_time(_time_was_paused)
	closed.emit()


func is_open() -> bool:
	return _root.visible


func page() -> Page:
	return _page


func show_page(page_to_show: Page, npc_id: String = "") -> void:
	_page = page_to_show
	_npc = npc_id
	if _page == Page.THREAD:
		Game.read_thread(_npc)
	_render()
	_focus_first()


func open_thread(npc_id: String) -> void:
	show_page(Page.THREAD, npc_id)


## Writes into the box and sends it, as the player would. Returns the result.
func type_and_send(text: String) -> Result:
	_line.text = text
	return _send_line()


## Rings the person whose thread is open. Whether they pick up is judged
## first; if not, the note under the thread says why. Returns the verdict.
func press_call() -> Result:
	return _press_call()


func _press_call() -> Result:
	var may := Game.can_call(_npc)
	if may.is_err():
		show_notice(Localization.t("ui.phone.call." + may.code))
		return may
	call_requested.emit(_npc)
	return may


## A note under the thread, for what the phone has to say about what was just tried.
func show_notice(text: String) -> void:
	_notice.text = text
	_notice.visible = true


## What the small note under the thread says, "" when it says nothing.
func notice_text() -> String:
	return _notice.text if _notice.visible else ""


## What is on the page, one entry per row, its labels joined by "|".
func row_texts() -> Array[String]:
	var out: Array[String] = []
	for row in _rows.get_children():
		if row is Button:
			out.append((row as Button).text.replace("\n", "|"))
			continue
		if row is Label:
			out.append((row as Label).text)
			continue
		if row is MapView:
			continue
		var parts: Array[String] = []
		for child in row.get_children():
			if child is Label and (child as Label).visible:
				parts.append((child as Label).text)
		out.append("|".join(parts))
	return out


## The answers offered under the thread, in words.
func answer_labels() -> Array[String]:
	var out: Array[String] = []
	for button in _answer_buttons():
		out.append(button.text)
	return out


## Presses an answer by what it does: "accept" or "decline". Returns whether
## there was such a button.
func press_answer(choice: String) -> bool:
	for button in _answer_buttons():
		if str(button.get_meta("choice", "")) == choice:
			button.pressed.emit()
			return true
	return false


func press_thread(npc_id: String) -> bool:
	for row in _rows.get_children():
		if row is Button and str((row as Button).get_meta("npc", "")) == npc_id:
			(row as Button).pressed.emit()
			return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	if not _root.visible:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _page == Page.THREAD:
			show_page(Page.THREADS)
		else:
			close()
	elif event.is_action_pressed("phone"):
		get_viewport().set_input_as_handled()
		close()


func _on_phone_message(npc_id: String, _message_id: int) -> void:
	if not _root.visible:
		return
	if _page == Page.THREAD and npc_id == _npc:
		Game.read_thread(_npc)   # it arrived while you were looking at it
	_render()


func _answer_buttons() -> Array[Button]:
	var out: Array[Button] = []
	for row in _rows.get_children():
		if row is HBoxContainer:
			for child in row.get_children():
				if child is Button:
					out.append(child as Button)
	return out


func _render() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_clock.text = Game.clock.format_time()
	_back.visible = _page == Page.THREAD
	_compose.visible = _page == Page.THREAD
	_notice.visible = false
	_tab_messages.button_pressed = _page == Page.THREADS or _page == Page.THREAD
	_tab_contacts.button_pressed = _page == Page.CONTACTS
	_tab_calendar.button_pressed = _page == Page.CALENDAR
	_tab_bank.button_pressed = _page == Page.BANK
	_tab_map.button_pressed = _page == Page.MAP
	match _page:
		Page.THREADS:
			_title.text = Localization.t("ui.phone.messages")
			_render_threads()
		Page.THREAD:
			_title.text = PhoneText.npc_name(_npc)
			_render_thread()
		Page.CONTACTS:
			_title.text = Localization.t("ui.phone.contacts")
			_render_contacts()
		Page.CALENDAR:
			_title.text = Localization.t("ui.phone.calendar")
			_render_calendar()
		Page.BANK:
			_title.text = Localization.t("ui.phone.bank")
			_render_bank()
		Page.MAP:
			_title.text = Localization.t("ui.phone.map")
			_render_map()


func _render_threads() -> void:
	var threads := Game.phone.threads()
	for npc_id in threads:
		var row := Button.new()
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.clip_text = true
		row.set_meta("npc", npc_id)
		var unread := Game.phone.unread_count(npc_id)
		var who := PhoneText.npc_name(npc_id)
		if unread > 0:
			who += " · " + Localization.t("ui.phone.unread", {"n": unread})
		var preview := PhoneText.preview(npc_id)
		if preview.length() > PREVIEW_CHARS:
			preview = preview.substr(0, PREVIEW_CHARS - 1) + "…"
		row.text = who + "\n" + preview
		row.pressed.connect(open_thread.bind(npc_id))
		_rows.add_child(row)
	if threads.is_empty():
		_rows.add_child(_note(Localization.t("ui.phone.no_messages")))


func _render_thread() -> void:
	var open_message := {}
	var thread := Game.phone.thread(_npc)
	if thread.is_empty():
		_rows.add_child(_note(Localization.t("ui.phone.thread_empty")))
	for message in thread:
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		var mine: bool = message["from"] == "player"
		var meta := Label.new()
		meta.theme_type_variation = &"MutedLabel"
		meta.text = "%s · %s" % [Localization.t("ui.phone.you") if mine else PhoneText.npc_name(_npc),
			PhoneText.stamp(int(message["minute"]))]
		var text := Label.new()
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.text = PhoneText.render(message)
		if mine:
			meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		box.add_child(meta)
		box.add_child(text)
		_rows.add_child(box)
		if Game.phone.is_open(message):
			open_message = message
	if not open_message.is_empty():
		var answers := HBoxContainer.new()
		answers.alignment = BoxContainer.ALIGNMENT_END
		for choice in ["accept", "decline"]:
			var button := Button.new()
			button.text = Localization.t("ui.phone." + choice)
			button.set_meta("choice", choice)
			button.pressed.connect(_answer.bind(int(open_message["id"]), choice))
			answers.add_child(button)
		_rows.add_child(answers)
	if Game.phone.waiting_for(_npc) > 0:
		_rows.add_child(_note(Localization.t("ui.phone.waiting")))


func _render_contacts() -> void:
	var ids: Array = Game.phone.contacts.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return PhoneText.npc_name(a) < PhoneText.npc_name(b))
	for npc_id: String in ids:
		var row := Button.new()
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.clip_text = true
		row.set_meta("npc", npc_id)
		var occupation := PhoneText.occupation(npc_id)
		row.text = PhoneText.npc_name(npc_id) + ("\n" + occupation if occupation != "" else "")
		row.pressed.connect(open_thread.bind(npc_id))
		_rows.add_child(row)
	if ids.is_empty():
		_rows.add_child(_note(Localization.t("ui.phone.no_contacts")))


## The district as the player knows it, then what they know of, by name.
func map_view() -> MapView:
	for row in _rows.get_children():
		if row is MapView:
			return row as MapView
	return null


func _render_map() -> void:
	var known := Game.player.known_places
	var world := Game.world
	var map := world.map_for(Game.player.region)
	var kinds := {}
	var elsewhere: Array[String] = []
	var here: Array[String] = []
	for location_id: String in known:
		var location := world.get_location(location_id)
		if location != null:
			kinds[location_id] = location.kind
		if map != null and (map.buildings.has(location_id) or map.places.has(location_id)):
			here.append(location_id)
		else:
			elsewhere.append(location_id)
	if map != null:
		var you := Vector2i(-1, -1)
		var inside := Game.player.interior_base()
		if inside != "" and map.buildings.has(inside):
			you = (map.buildings[inside]["rect"] as Rect2i).get_center()
		elif Game.player.interior == "":
			you = DistrictMap.world_to_cell(Game.player.position)
		var view := MapView.new()
		view.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_rows.add_child(view)
		var on_this_map := {}
		for location_id in here:
			on_this_map[location_id] = known[location_id]
		view.show_district(map, on_this_map, kinds, _map_numbers(here), you)
	else:
		_rows.add_child(_note(Localization.t("ui.map.unmapped")))
	var numbers := _map_numbers(here)
	var listed: Array[String] = []
	listed.append_array(here)
	listed.append_array(elsewhere)
	listed.sort_custom(func(a: String, b: String) -> bool: return InteractionText.place_name(a) < InteractionText.place_name(b))
	for location_id in listed:
		var line := Label.new()
		line.theme_type_variation = &"MutedLabel"
		var number := ("%d · " % numbers[location_id]) if numbers.has(location_id) else ""
		line.text = "%s%s · %s" % [number, InteractionText.place_name(location_id), Localization.t("ui.map." + str(known[location_id]))]
		_rows.add_child(line)


## The numbers the map marks places with, in the order of their names.
func _map_numbers(on_the_map: Array[String]) -> Dictionary:
	var ordered := on_the_map.duplicate()
	ordered.sort_custom(func(a: String, b: String) -> bool: return InteractionText.place_name(a) < InteractionText.place_name(b))
	var out := {}
	for i in ordered.size():
		out[ordered[i]] = i + 1
	return out


func _render_bank() -> void:
	var wallet := Game.player.wallet
	var account := Label.new()
	account.text = Localization.t("ui.bank.account", {"bank": wallet.bank})
	account.add_theme_font_size_override("font_size", 24)
	var cash := Label.new()
	cash.theme_type_variation = &"MutedLabel"
	cash.text = Localization.t("ui.bank.cash", {"cash": wallet.cash})
	var balance := VBoxContainer.new()
	balance.add_child(account)
	balance.add_child(cash)
	_rows.add_child(balance)
	var entries := BankText.statement()
	for entry in entries:
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		var caption := Label.new()
		caption.text = BankText.line(entry)
		caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(caption)
		if str(entry["when"]) != "":
			var moment := Label.new()
			moment.theme_type_variation = &"MutedLabel"
			moment.text = str(entry["when"])
			box.add_child(moment)
		_rows.add_child(box)
	if entries.is_empty():
		_rows.add_child(_note(Localization.t("ui.bank.empty")))


func _render_calendar() -> void:
	var now := Game.clock.total_minutes
	var job := StatusText.job()
	if job != "":
		_rows.add_child(_note(job))
	var upcoming := Game.calendar.upcoming(now)
	for meeting in upcoming:
		_rows.add_child(_meeting_row(meeting, false))
	if upcoming.is_empty():
		_rows.add_child(_note(Localization.t("ui.phone.calendar_empty")))
	var behind := Game.calendar.finished()
	if not behind.is_empty():
		_rows.add_child(_note(Localization.t("ui.phone.calendar_behind")))
		for meeting in behind.slice(0, 4):
			_rows.add_child(_meeting_row(meeting, true))


func _meeting_row(meeting: Dictionary, finished: bool) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var title := Label.new()
	title.text = PhoneText.meeting_when_where(meeting)
	title.add_theme_font_size_override("font_size", 20)
	var who := Label.new()
	who.theme_type_variation = &"MutedLabel"
	who.text = Localization.t("ui.phone.calendar_with", {"name": PhoneText.npc_name(str(meeting["npc"]))})
	if finished:
		who.text += " · " + Localization.t("ui.phone.meeting." + str(meeting["status"]))
		title.theme_type_variation = &"MutedLabel"
	box.add_child(title)
	box.add_child(who)
	return box


func _send_line() -> Result:
	var sent := Game.send_text(_npc, _line.text)
	if sent.is_ok():
		_line.text = ""
	_render()
	if sent.is_err() and sent.code != "empty":
		_notice.text = Localization.t("ui.phone.refused." + sent.code)
		_notice.visible = true
	_line.grab_focus()
	return sent


func _answer(message_id: int, choice: String) -> void:
	Game.answer_message(message_id, choice)
	_render()
	_focus_first()


func _note(text: String) -> Label:
	var note := Label.new()
	note.theme_type_variation = &"MutedLabel"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.text = text
	return note


func _focus_first() -> void:
	for row in _rows.get_children():
		if row is Button:
			(row as Button).grab_focus()
			return
	var buttons := _answer_buttons()
	if not buttons.is_empty():
		buttons[0].grab_focus()
	elif _page == Page.THREAD:
		_line.grab_focus()
	else:
		_close.grab_focus()
