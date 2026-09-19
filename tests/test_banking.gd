extends TestCase
## The account and the cash machine (D-048): a ledger that says when, a
## statement in words, money sent by text through the account, and the
## machine that moves cash in and out of it.

var _deeds: Array[String] = []
var _rejected: Array[String] = []


func before_each() -> void:
	_deeds = []
	_rejected = []
	Events.player_deed.connect(_on_deed)
	Events.action_rejected.connect(_on_rejected)


func after_each() -> void:
	Events.player_deed.disconnect(_on_deed)
	Events.action_rejected.disconnect(_on_rejected)
	Localization.set_locale("en")
	Game.saves.delete_slot("test_banking")


func _on_deed(kind: String, _data: Dictionary) -> void:
	_deeds.append(kind)


func _on_rejected(_proposal: Dictionary, code: String) -> void:
	_rejected.append(code)


func _start(background: String = "bg_returning") -> void:
	Game.new_game(background, 7)
	Game.pause_time(true)
	Localization.set_locale("en")
	var model := ScriptedDialogueModel.new()
	model.available = false
	Game.dialogue.model = model
	Game.player.wallet.ledger.clear()


## Inside the corner shop, standing next to the cash machine.
func _at_the_machine() -> void:
	var map := Game.current_map()
	assert_ok(Game.move_player(DistrictMap.cell_to_world(map.anchor_of("loc_corner_shop"))))
	assert_ok(Game.interact_at(map.buildings["loc_corner_shop"]["door"]))
	assert_ok(Game.move_player(DistrictMap.cell_to_world(Vector2i(2, 4))))


# --- the ledger -----------------------------------------------------------------------------------

func test_the_ledger_says_when() -> void:
	var wallet := Wallet.new()
	wallet.add_to_bank(10, "wage:job_dockhand")
	assert_eq(wallet.ledger[0]["at"], -1, "no clock, no time")
	var now := [500]
	wallet.stamp = func() -> int: return now[0]
	wallet.add_cash(5, "quest")
	now[0] = 620
	wallet.spend(3, "buy:item_beer")
	assert_eq(wallet.ledger[1]["at"], 500)
	assert_eq(wallet.ledger[2]["at"], 620)


func test_the_game_stamps_the_ledger_with_its_own_clock() -> void:
	_start()
	Game.clock.total_minutes = 12345
	Game.player.wallet.add_to_bank(110, "wage:job_dockhand")
	assert_eq(Game.player.wallet.ledger.back()["at"], 12345)


func test_money_can_leave_the_account_only_from_the_account() -> void:
	var wallet := Wallet.new()
	wallet.cash = 500
	wallet.bank = 40
	assert_eq(wallet.transfer_out(50, "transfer:npc_ida").code, "insufficient_bank", "cash does not count")
	assert_eq(wallet.transfer_out(0).code, "bad_amount")
	assert_eq(wallet.transfer_out(-5).code, "bad_amount")
	assert_ok(wallet.transfer_out(15, "transfer:npc_ida"))
	assert_eq(wallet.bank, 25)
	assert_eq(wallet.cash, 500)
	assert_eq(wallet.ledger.back()["kind"], "transfer")
	assert_eq(wallet.ledger.back()["amount"], -15)


func test_an_older_ledger_without_times_still_loads() -> void:
	var wallet := Wallet.new()
	wallet.from_dict({"cash": 5, "bank": 6, "ledger": [{"amount": 3, "kind": "bank", "reason": "quest"}]})
	assert_eq(wallet.ledger.size(), 1)
	assert_false(wallet.ledger[0].has("at"), "left as it was")


# --- the statement --------------------------------------------------------------------------------------

func test_the_statement_is_the_account_and_says_what_each_was() -> void:
	_start()
	var wallet := Game.player.wallet
	Game.clock.total_minutes = 5 * GameClock.MINUTES_PER_DAY + 16 * 60
	wallet.add_to_bank(110, "wage:job_dockhand")
	wallet.add_cash(15, "sell:item_beer")           # cash: not on a statement
	wallet.cash = 100
	wallet.spend(12, "buy:item_sandwich")            # paid in cash: not on a statement
	wallet.transfer_out(50, "transfer:npc_rauno")
	wallet.deposit(20)
	wallet.withdraw(30)
	wallet.bank = 500
	wallet.cash = 0
	wallet.spend(9, "clinic")                        # all from the account
	var lines: Array[String] = []
	for entry in BankText.statement():
		lines.append(BankText.line(entry))
	assert_eq(lines, [
		"−€9 · Clinic bill", "+€30 · Cash taken out", "+€20 · Cash put in",
		"−€50 · Sent to Rauno Virta", "+€110 · Wages · The Harbour",
	] as Array[String], "newest first, only what touches the account")
	assert_eq(BankText.statement()[0]["when"], "%s" % PhoneText.stamp(Game.clock.total_minutes))
	assert_eq(BankText.balance_line(), "Account €%d · Cash €%d" % [wallet.bank, wallet.cash])


func test_every_kind_of_reason_has_words() -> void:
	_start()
	var described := {
		"buy:item_beer": "Bought Beer", "sell:item_beer": "Sold Beer", "quest": "Reward",
		"errand:errand_pirjo_groceries": "Errand:", "something odd": "Other",
	}
	for reason: String in described:
		var text := BankText.describe({"kind": "bank", "reason": reason})
		assert_true(text.begins_with(str(described[reason])), "%s -> %s" % [reason, text])
	assert_eq(BankText.describe({"kind": "deposit", "reason": ""}), "Cash put in")


# --- money by text ---------------------------------------------------------------------------------------

func _text_and_wait(npc_id: String, line: String) -> void:
	assert_ok(Game.send_text(npc_id, line), line)
	Game.clock.total_minutes += 60
	await Game.phone_director.process_due()


func test_a_debt_can_be_paid_by_transfer() -> void:
	_start("bg_in_debt")
	var day0 := Game.clock.day_index()
	Game.clock.total_minutes = day0 * GameClock.MINUTES_PER_DAY + 12 * 60
	Game.phone_director.add_contact("npc_rauno")
	Game.npcs.get_npc("npc_rauno").activity = "idle"
	Game.player.wallet.bank = 400
	Game.player.wallet.cash = 3
	await _text_and_wait("npc_rauno", "Here's 150 euros.")
	assert_true(Game.quests.active.has("q_rauno_debt"), "half is not all")
	await _text_and_wait("npc_rauno", "Here's 150 euros.")
	assert_eq(Game.quests.finished.get("q_rauno_debt"), "done", "and the debt is settled by phone")
	assert_eq(Game.player.wallet.bank, 100)
	assert_eq(Game.player.wallet.cash, 3, "not a coin of it was cash")
	assert_eq(_deeds.count("gave_money"), 2)


func test_too_large_a_transfer_is_not_a_gift() -> void:
	_start()
	Game.clock.total_minutes = Game.clock.day_index() * GameClock.MINUTES_PER_DAY + 12 * 60
	Game.phone_director.add_contact("npc_pirjo")
	Game.npcs.get_npc("npc_pirjo").activity = "idle"
	Game.player.wallet.bank = 50000
	await _text_and_wait("npc_pirjo", "Here's 5000 euros.")
	assert_eq(Game.player.wallet.bank, 50000)
	assert_eq(_rejected, ["invalid_amount"] as Array[String])


# --- the cash machine ---------------------------------------------------------------------------------------

func test_the_corner_shop_has_a_cash_machine() -> void:
	_start()
	assert_false(Game.atm_here(), "not out on the street")
	_at_the_machine()
	assert_true(Game.atm_here())
	var what := Game.interaction_at(Vector2i(1, 4))
	assert_eq(what["kind"], "atm")
	assert_eq(InteractionText.prompt_for(what), "Use the cash machine")
	assert_eq(Game.interact_at(Vector2i(1, 4)).value["kind"], "atm")


func test_cash_goes_in_and_comes_out_only_at_the_machine() -> void:
	_start()
	Game.player.wallet.cash = 100
	Game.player.wallet.bank = 20
	assert_eq(Game.atm_deposit(50).code, "not_at_atm")
	assert_eq(Game.atm_withdraw(10).code, "not_at_atm")
	assert_eq(Game.player.wallet.cash, 100, "nothing moved")
	_at_the_machine()
	assert_ok(Game.atm_deposit(60))
	assert_eq([Game.player.wallet.cash, Game.player.wallet.bank], [40, 80])
	assert_ok(Game.atm_withdraw(30))
	assert_eq([Game.player.wallet.cash, Game.player.wallet.bank], [70, 50])
	assert_eq(Game.atm_deposit(500).code, "insufficient_cash")
	assert_eq(Game.atm_withdraw(500).code, "insufficient_bank")
	assert_eq(Game.atm_deposit(0).code, "insufficient_cash")
	assert_eq(_rejected, ["not_at_atm", "not_at_atm", "insufficient_cash", "insufficient_bank", "insufficient_cash"] as Array[String])
	assert_eq(Game.player.wallet.ledger.back()["kind"], "withdraw")


func test_the_window_moves_money_and_says_so() -> void:
	_start()
	Game.player.wallet.cash = 100
	Game.player.wallet.bank = 20
	_at_the_machine()
	var window: AtmWindow = (load("res://scenes/ui/atm_window.tscn") as PackedScene).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(window)
	Game.pause_time(false)
	window.open()
	assert_true(Game.clock.paused, "time stands still at the machine")
	assert_eq(window.balance_text(), "Account €20 · Cash €100")
	assert_ok(window.deposit(50))
	assert_eq(window.balance_text(), "Account €70 · Cash €50")
	assert_eq(window.message(), "Put €50 in the account.")
	assert_err(window.withdraw(1000))
	assert_eq(window.message(), "There is not that much in the account.")
	assert_ok(window.withdraw(30))
	assert_eq(window.message(), "Took €30 out.")
	window.close()
	assert_false(Game.clock.paused)
	window.free()


func test_the_all_button_moves_everything() -> void:
	_start()
	Game.player.wallet.cash = 75
	Game.player.wallet.bank = 20
	_at_the_machine()
	var window: AtmWindow = (load("res://scenes/ui/atm_window.tscn") as PackedScene).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(window)
	window.open()
	var all: Button = window.get_node("%DepositRow").get_children().back()
	all.pressed.emit()
	assert_eq([Game.player.wallet.cash, Game.player.wallet.bank], [0, 95])
	window.close()
	window.free()


# --- the phone's bank ------------------------------------------------------------------------------------

func test_the_phone_shows_the_account_and_its_history() -> void:
	_start()
	Game.player.wallet.bank = 240
	Game.player.wallet.cash = 35
	var window: PhoneWindow = (load("res://scenes/ui/phone_window.tscn") as PackedScene).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(window)
	assert_true(window.open())
	window.show_page(PhoneWindow.Page.BANK)
	assert_eq(window.row_texts(), ["Account €240|Cash in hand €35", "Nothing on the account yet."] as Array[String])
	Game.player.wallet.transfer_out(50, "transfer:npc_rauno")
	window.show_page(PhoneWindow.Page.BANK)
	var rows := window.row_texts()
	assert_eq(rows[0], "Account €190|Cash in hand €35")
	assert_true(rows[1].begins_with("−€50 · Sent to Rauno Virta|"), rows[1])
	window.close()
	window.free()


func test_the_ledger_and_its_times_are_saved() -> void:
	_start()
	Game.clock.total_minutes = 8000
	Game.player.wallet.bank = 100
	Game.player.wallet.transfer_out(10, "transfer:npc_ida")
	assert_ok(Game.save_game("test_banking"))
	assert_ok(Game.load_game("test_banking"))
	Game.pause_time(true)
	var entry: Dictionary = Game.player.wallet.ledger.back()
	assert_eq(entry["reason"], "transfer:npc_ida")
	assert_eq(entry["at"], 8000)
	Game.player.wallet.add_cash(1, "quest")
	assert_gt(int(Game.player.wallet.ledger.back()["at"]), 0, "and the game still stamps after loading")
