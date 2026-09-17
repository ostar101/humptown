class_name Wallet
extends RefCounted
## Cash and a bank account, in whole currency units (cents are noise here).
##
## Cash can be stolen and spent anywhere; bank money is safe but leaves a
## record and is not accepted by everyone. That difference is the only
## reason two pots exist.

var cash: int = 0
var bank: int = 0
## Running log of the last transactions, for the phone's banking view.
var ledger: Array[Dictionary] = []

const LEDGER_LIMIT := 60


func total() -> int:
	return cash + bank


func can_afford(amount: int, cash_only: bool = false) -> bool:
	return (cash if cash_only else total()) >= amount


func add_cash(amount: int, reason: String = "") -> void:
	cash += amount
	_record(amount, "cash", reason)
	Events.money_changed.emit(cash, bank)


func spend(amount: int, reason: String = "", cash_only: bool = false) -> Result:
	if amount < 0:
		return Result.failure("negative_amount")
	if not can_afford(amount, cash_only):
		return Result.failure("insufficient_funds", "needs %d" % amount)
	var from_cash := mini(cash, amount)
	cash -= from_cash
	var remainder := amount - from_cash
	if remainder > 0:
		bank -= remainder
	_record(-amount, "cash" if remainder == 0 else "mixed", reason)
	Events.money_changed.emit(cash, bank)
	return Result.success(amount)


func deposit(amount: int) -> Result:
	if amount <= 0 or cash < amount:
		return Result.failure("insufficient_cash")
	cash -= amount
	bank += amount
	_record(amount, "deposit", "")
	Events.money_changed.emit(cash, bank)
	return Result.success(amount)


func withdraw(amount: int) -> Result:
	if amount <= 0 or bank < amount:
		return Result.failure("insufficient_bank")
	bank -= amount
	cash += amount
	_record(amount, "withdraw", "")
	Events.money_changed.emit(cash, bank)
	return Result.success(amount)


func _record(amount: int, kind: String, reason: String) -> void:
	ledger.append({"amount": amount, "kind": kind, "reason": reason})
	if ledger.size() > LEDGER_LIMIT:
		ledger.remove_at(0)


func to_dict() -> Dictionary:
	return {"cash": cash, "bank": bank, "ledger": ledger}


func from_dict(d: Dictionary) -> void:
	cash = int(d.get("cash", 0))
	bank = int(d.get("bank", 0))
	var entries: Array[Dictionary] = []
	for e in d.get("ledger", []):
		entries.append(e)
	ledger = entries
