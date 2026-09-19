class_name AtmWindow
extends CanvasLayer
## The cash machine in the corner shop (D-048): cash into the account, cash
## out of it. `Game.atm_deposit()` and `atm_withdraw()` decide; a refusal is
## shown in plain words. Time stands still while it is open.

signal closed()

const AMOUNTS: Array[int] = [10, 50, 100]

var _time_was_paused := false

@onready var _root: Control = $Root
@onready var _balance: Label = %Balance
@onready var _deposit_row: HBoxContainer = %DepositRow
@onready var _withdraw_row: HBoxContainer = %WithdrawRow
@onready var _message: Label = %Message
@onready var _close: Button = %Close


func _ready() -> void:
	_root.visible = false
	_close.pressed.connect(close)
	_fill(_deposit_row, deposit, func() -> int: return Game.player.wallet.cash)
	_fill(_withdraw_row, withdraw, func() -> int: return Game.player.wallet.bank)


func open() -> void:
	if _root.visible or not Game.is_running():
		return
	_time_was_paused = Game.clock.paused
	Game.pause_time(true)
	_message.text = ""
	_render()
	_root.visible = true
	_close.grab_focus()


func close() -> void:
	if not _root.visible:
		return
	_root.visible = false
	Game.pause_time(_time_was_paused)
	closed.emit()


func is_open() -> bool:
	return _root.visible


func deposit(amount: int) -> Result:
	var done := Game.atm_deposit(amount)
	_report(done, "ui.atm.done_deposit")
	return done


func withdraw(amount: int) -> Result:
	var done := Game.atm_withdraw(amount)
	_report(done, "ui.atm.done_withdraw")
	return done


func balance_text() -> String:
	return _balance.text


func message() -> String:
	return _message.text


func _unhandled_input(event: InputEvent) -> void:
	if _root.visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


## The amounts as buttons, and "All" for whatever there is to move.
func _fill(row: HBoxContainer, act: Callable, available: Callable) -> void:
	for amount in AMOUNTS:
		var button := Button.new()
		button.text = "€%d" % amount
		button.pressed.connect(func() -> void: act.call(amount))
		row.add_child(button)
	var all := Button.new()
	all.text = Localization.t("ui.atm.all")
	all.pressed.connect(func() -> void: act.call(int(available.call())))
	row.add_child(all)


func _report(done: Result, key: String) -> void:
	if done.is_ok():
		_message.text = Localization.t(key, {"amount": int(done.value)})
	else:
		_message.text = Localization.t("ui.atm.refused." + done.code)
	_render()


func _render() -> void:
	_balance.text = BankText.balance_line()
