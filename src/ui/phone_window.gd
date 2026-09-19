class_name PhoneWindow
extends CanvasLayer
## The phone (D-045): its own window, shaped like one, not a page of the
## menu. Messages and Contacts for now; more apps join the bottom bar as they
## are built. It reads the phone and never writes it, except through
## `Game.answer_message()` and `Game.read_thread()`, which decide. Time stands
## still while it is open.

signal closed()

enum Page { THREADS, THREAD, CONTACTS }

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
@onready var _close: Button = %Close


func _ready() -> void:
	_root.visible = false
	_close.pressed.connect(close)
	_back.pressed.connect(func() -> void: show_page(Page.THREADS))
	_tab_messages.pressed.connect(func() -> void: show_page(Page.THREADS))
	_tab_contacts.pressed.connect(func() -> void: show_page(Page.CONTACTS))
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


func _on_phone_message(_npc_id: String, _message_id: int) -> void:
	if _root.visible:
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
	_tab_messages.button_pressed = _page != Page.CONTACTS
	_tab_contacts.button_pressed = _page == Page.CONTACTS
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
	for message in Game.phone.thread(_npc):
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


func _render_contacts() -> void:
	var ids: Array = Game.phone.contacts.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return PhoneText.npc_name(a) < PhoneText.npc_name(b))
	for npc_id: String in ids:
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		var who := Label.new()
		who.text = PhoneText.npc_name(npc_id)
		who.add_theme_font_size_override("font_size", 20)
		var work := Label.new()
		work.theme_type_variation = &"MutedLabel"
		work.text = PhoneText.occupation(npc_id)
		work.visible = work.text != ""
		box.add_child(who)
		box.add_child(work)
		_rows.add_child(box)
	if ids.is_empty():
		_rows.add_child(_note(Localization.t("ui.phone.no_contacts")))


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
	else:
		_close.grab_focus()
