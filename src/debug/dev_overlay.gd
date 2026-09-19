class_name DevOverlay
extends CanvasLayer
## The developer overlay (D-038): what the model layer is costing and doing,
## and how each line of a conversation was handled — the plan's list, in one
## corner: tokens, latency, cost, cache hits, selected memories, intent
## readings, what the rules did, rejected proposals, fallbacks and errors.
##
## F3 toggles it, in debug builds or with `developer_mode` on; a released
## game shows players nothing of this. It reads, never writes, and refreshes
## a few times a second only while it is showing. Debug text: English, not
## localised.

const REFRESH_SECONDS := 0.5
const KEEP := 6

var _panel: PanelContainer
var _text: Label
var _since := 0.0
## Recent model calls: {purpose, ok, model, latency_ms, prompt_tokens,
## completion_tokens, cached, error}, newest last.
var _calls: Array[Dictionary] = []
var _purposes: Dictionary = {}   # request id -> purpose name
## Recent refusals anywhere in the game: "code (kind/intent)".
var _rejections: Array[String] = []


func _ready() -> void:
	layer = 50
	_panel = PanelContainer.new()
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.offset_left = -520.0
	_panel.offset_right = -12.0
	_panel.offset_top = 12.0
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.09, 0.82)
	style.set_content_margin_all(10.0)
	_panel.add_theme_stylebox_override("panel", style)
	_text = Label.new()
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Consolas", "DejaVu Sans Mono", "Menlo", "monospace"])
	_text.add_theme_font_override("font", mono)
	_text.add_theme_font_size_override("font_size", 13)
	_text.add_theme_color_override("font_color", Color(0.86, 0.9, 0.86))
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(496, 0)
	_panel.add_child(_text)
	add_child(_panel)
	visible = false
	Events.llm_request_started.connect(_on_request_started)
	Events.llm_request_finished.connect(_on_request_finished)
	Events.action_rejected.connect(_on_rejected)


static func allowed() -> bool:
	return OS.is_debug_build() or bool(Settings.get_value("developer_mode", false))


func toggle() -> void:
	visible = not visible and allowed()
	if visible:
		refresh()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_F3:
		toggle()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible:
		return
	_since += delta
	if _since >= REFRESH_SECONDS:
		_since = 0.0
		refresh()


func refresh() -> void:
	_text.text = render(snapshot())


func shown_text() -> String:
	return _text.text


## Everything the overlay shows, gathered in one place.
func snapshot() -> Dictionary:
	var talking := Game.dialogue.is_talking()
	var npc_id := Game.dialogue.conversation.npc_id if talking else ""
	var context := Game.dialogue.prompt_context(npc_id) if talking else {}
	return {
		"llm": Game.llm.stats() if Game.llm != null else {},
		"calls": _calls,
		"turns": Game.dialogue.turn_log,
		"talking_to": npc_id,
		"memories": context.get("memories", []),
		"knows": context.get("knows", []),
		"rejections": _rejections,
	}


## The overlay's text from a snapshot. Pure, so it can be tested and read.
static func render(s: Dictionary) -> String:
	var out: Array[String] = []
	var llm: Dictionary = s.get("llm", {})
	out.append("LLM  %s  main=%s  cheap=%s  mode=%s  %s" % [
		llm.get("provider", "none"), _or_dash(llm.get("main_model", "")), _or_dash(llm.get("cheap_model", "")),
		llm.get("routing_mode", "?"), "available" if llm.get("available", false) else "offline"])
	out.append("     requests %d (today %d/%d)  tokens %d in / %d out  cost ~$%.4f" % [
		int(llm.get("requests_session", 0)), int(llm.get("requests_today", 0)), int(llm.get("daily_cap", 0)),
		int(llm.get("prompt_tokens", 0)), int(llm.get("completion_tokens", 0)), float(llm.get("est_cost_usd", 0.0))])
	out.append("     cache hits %d (%d entries)  circuit %s  failures in a row %d" % [
		int(llm.get("cache_hits", 0)), int(llm.get("cache_entries", 0)), llm.get("circuit", "?"),
		int(llm.get("consecutive_failures", 0))])
	var calls: Array = s.get("calls", [])
	if not calls.is_empty():
		out.append("CALLS")
		for call: Dictionary in calls:
			out.append("  %-9s %-18s %5d ms  %4d/%-4d %s" % [
				str(call.get("purpose", "?")), str(call.get("model", "")).left(18), int(call.get("latency_ms", 0)),
				int(call.get("prompt_tokens", 0)), int(call.get("completion_tokens", 0)),
				"cached" if call.get("cached", false) else ("ok" if call.get("ok", false) else "ERROR " + str(call.get("error", "")))])
	var turns: Array = s.get("turns", [])
	if not turns.is_empty():
		out.append("TURNS")
		for turn: Dictionary in turns.slice(maxi(turns.size() - KEEP, 0)):
			var read := "%s by %s" % [turn.get("intent", "?"), turn.get("read_by", "?")]
			if str(turn.get("read_fallback", "")) != "":
				read += " (%s)" % turn["read_fallback"]
			var reply := str(turn.get("reply_by", "?"))
			if str(turn.get("reply_fallback", "")) != "":
				reply += " (%s)" % turn["reply_fallback"]
			out.append("  \"%s\"" % turn.get("line", ""))
			out.append("    meant %s · rules %s · reply %s" % [
				read, "REFUSED " + str(turn["rejected"]) if str(turn.get("rejected", "")) != "" else "ok", reply])
			if str(turn.get("happened", "")) != "":
				out.append("    happened: %s" % turn["happened"])
	if str(s.get("talking_to", "")) != "":
		out.append("MEMORY of %s" % s["talking_to"])
		var memories: Array = s.get("memories", [])
		for memory in memories:
			out.append("  - %s" % memory)
		if memories.is_empty():
			out.append("  (none)")
		for fact in s.get("knows", []):
			out.append("  knows: %s" % fact)
	var rejections: Array = s.get("rejections", [])
	if not rejections.is_empty():
		out.append("REJECTED")
		for rejection in rejections:
			out.append("  %s" % rejection)
	return "\n".join(out)


static func _or_dash(value: Variant) -> String:
	return str(value) if str(value) != "" else "-"


func _on_request_started(request_id: String, purpose: String) -> void:
	_purposes[request_id] = purpose


func _on_request_finished(request_id: String, ok: bool, meta: Dictionary) -> void:
	var call := meta.duplicate()
	call["ok"] = ok
	call["purpose"] = _purposes.get(request_id, "?")
	_purposes.erase(request_id)
	_calls.append(call)
	while _calls.size() > KEEP:
		_calls.remove_at(0)


func _on_rejected(proposal: Dictionary, code: String) -> void:
	_rejections.append("%s (%s%s)" % [code, proposal.get("kind", "?"),
		"/" + str(proposal["intent"]) if proposal.has("intent") else ""])
	while _rejections.size() > KEEP:
		_rejections.remove_at(0)
