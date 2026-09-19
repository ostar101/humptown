class_name BankText
extends RefCounted
## The words for the account (D-048): the phone's statement and the cash
## machine's balance. The wallet's ledger keeps codes; this says them.

## Ledger kinds that touch the account. Cash spent and earned in hand never
## appears on a statement.
const ON_STATEMENT: Array[String] = ["bank", "mixed", "deposit", "withdraw", "transfer"]


## "Account €240 · Cash €35"
static func balance_line() -> String:
	if not Game.is_running():
		return ""
	return Localization.t("ui.atm.balance", {"bank": Game.player.wallet.bank, "cash": Game.player.wallet.cash})


## The account's entries, newest first, as {"amount", "text", "when"}.
static func statement() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not Game.is_running():
		return out
	var ledger := Game.player.wallet.ledger
	for i in range(ledger.size() - 1, -1, -1):
		var entry: Dictionary = ledger[i]
		if not ON_STATEMENT.has(str(entry.get("kind", ""))):
			continue
		var at := int(entry.get("at", -1))
		out.append({"amount": int(entry.get("amount", 0)), "text": describe(entry),
			"when": PhoneText.stamp(at) if at >= 0 else ""})
	return out


## "+€110 · Wages · The Harbour"
static func line(entry: Dictionary) -> String:
	var amount := int(entry["amount"])
	return "%s€%d · %s" % ["+" if amount >= 0 else "−", absi(amount), str(entry["text"])]


## What one ledger entry was for.
static func describe(entry: Dictionary) -> String:
	var kind := str(entry.get("kind", ""))
	if kind == "deposit" or kind == "withdraw":
		return Localization.t("ui.bank." + kind)
	var reason := str(entry.get("reason", ""))
	var head := reason.get_slice(":", 0)
	var tail := reason.get_slice(":", 1) if reason.contains(":") else ""
	match head:
		"wage":
			var job := Game.data.get_entry("jobs", tail)
			return Localization.t("ui.bank.wage", {"place": InteractionText.place_name(str(job.get("workplace", "")))})
		"buy", "sell":
			var item := Game.data.get_entry("items", tail)
			return Localization.t("ui.bank." + head, {"item": Localization.t(str(item.get("name_key", tail)))})
		"errand":
			var errand := Game.quests.errand(tail)
			return Localization.t("ui.bank.errand", {"title": Localization.t(str(errand.get("name_key", tail)))})
		"transfer":
			return Localization.t("ui.bank.transfer", {"name": PhoneText.npc_name(tail)})
		"clinic", "quest":
			return Localization.t("ui.bank." + head)
	return Localization.t("ui.bank.other")
