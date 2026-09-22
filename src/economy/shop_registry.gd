class_name ShopRegistry
extends RefCounted
## Every shop's shelves and till, and what things cost there (D-039).
##
## What a shop is comes from `data/shops.json`: where it is, what it stocks
## and how many, its markup, which kinds of thing it buys back and at what
## fraction of their value, and the cash it keeps in the till. What it has
## *now* lives here and is saved. At midnight every shop restocks to its
## usual shelves and its till is squared to its usual float — the owner banks
## the day's takings or tops the till up — so no shop can be bled dry or
## grow without limit.
##
## This holds the state and does the arithmetic; whether a sale may happen
## is `ShopRules`' call, and doing it is `Game`'s.

var _data: DataRegistry = null
## shop id -> {"stock": {item id: count}, "till": int,
##             "haggled": {item id: {"won": bool, "discount": float}}}
## `haggled` is today's haggling (D-040), cleared at midnight.
var _state: Dictionary = {}


func setup(data: DataRegistry) -> void:
	_data = data
	_state = {}
	for shop_id in data.ids("shops"):
		_state[str(shop_id)] = _fresh(str(shop_id))


## The shop at a location, or "".
func shop_at(location_id: String) -> String:
	if _data == null:
		return ""
	for shop_id in _data.ids("shops"):
		if str(_data.get_entry("shops", shop_id).get("location", "")) == location_id:
			return str(shop_id)
	return ""


func definition(shop_id: String) -> Dictionary:
	return _data.get_entry("shops", shop_id) if _data != null else {}


## The shop this person keeps (M8 D-084), or "" — a shop reached by dealing
## with them wherever they are, not by walking up to a counter.
func shop_of(npc_id: String) -> String:
	if _data == null:
		return ""
	for shop_id in _data.ids("shops"):
		if str(_data.get_entry("shops", shop_id).get("keeper", "")) == npc_id:
			return str(shop_id)
	return ""


## "legal" (default), "grey" or "illicit" — `DealRules`' business, not this
## class's; kept here only as a plain read of the shop's own data.
func legality(shop_id: String) -> String:
	return str(definition(shop_id).get("legality", "legal"))


## What the shop sells, in the order its data lists it.
func items_for_sale(shop_id: String) -> Array[String]:
	var out: Array[String] = []
	for item_id in definition(shop_id).get("stock", {}):
		out.append(str(item_id))
	return out


func sells(shop_id: String, item_id: String) -> bool:
	return definition(shop_id).get("stock", {}).has(item_id)


func stock_of(shop_id: String, item_id: String) -> int:
	return int(_state.get(shop_id, {}).get("stock", {}).get(item_id, 0))


func till(shop_id: String) -> int:
	return int(_state.get(shop_id, {}).get("till", 0))


## Whether the shop buys this item from the player at all: its kind is one
## the shop deals in, and it is worth something.
func buys(shop_id: String, item_id: String) -> bool:
	var item := _data.get_entry("items", item_id) if _data != null else {}
	return not item.is_empty() and int(item.get("value", 0)) > 0 \
		and definition(shop_id).get("buys", []).has(str(item.get("kind", "")))


## What one of this item costs the player here, after today's haggling.
func buy_price(shop_id: String, item_id: String) -> int:
	var markup := float(definition(shop_id).get("markup", 1.0))
	return price(_value(item_id), markup * (1.0 - discount(shop_id, item_id)))


## The discount won on this item today, 0 when none.
func discount(shop_id: String, item_id: String) -> float:
	var deal: Dictionary = haggled(shop_id).get(item_id, {})
	return float(deal.get("discount", 0.0)) if bool(deal.get("won", false)) else 0.0


## Today's haggling at this shop: {item id: {"won", "discount"}}.
func haggled(shop_id: String) -> Dictionary:
	return _state.get(shop_id, {}).get("haggled", {})


func record_haggle(shop_id: String, item_id: String, won: bool, won_discount: float) -> void:
	var state: Dictionary = _state[shop_id]
	if not state.has("haggled"):
		state["haggled"] = {}
	(state["haggled"] as Dictionary)[item_id] = {"won": won, "discount": won_discount if won else 0.0}


## What the shop pays the player for one of this item.
func sell_price(shop_id: String, item_id: String) -> int:
	var buyback := float(definition(shop_id).get("buyback", 0.0))
	return int(floor(_value(item_id) * buyback)) if buyback > 0.0 else 0


## A value times a factor, in whole units, never below one.
static func price(value: int, factor: float) -> int:
	return maxi(int(round(value * factor)), 1)


# --- changes, made by Game once the rules allow them -------------------------------

func sold(shop_id: String, item_id: String, quantity: int, paid: int) -> void:
	var state: Dictionary = _state[shop_id]
	var stock: Dictionary = state["stock"]
	stock[item_id] = maxi(int(stock.get(item_id, 0)) - quantity, 0)
	state["till"] = int(state["till"]) + paid


func bought(shop_id: String, item_id: String, quantity: int, paid: int) -> void:
	var state: Dictionary = _state[shop_id]
	# What it also sells goes on the shelf; anything else it sends on.
	if sells(shop_id, item_id):
		var stock: Dictionary = state["stock"]
		stock[item_id] = int(stock.get(item_id, 0)) + quantity
	state["till"] = maxi(int(state["till"]) - paid, 0)


## Midnight: shelves back to their usual counts (never taking away what the
## player sold them), the till back to its usual float.
func restock() -> void:
	for shop_id in _state:
		var state: Dictionary = _state[shop_id]
		var usual: Dictionary = definition(shop_id).get("stock", {})
		var stock: Dictionary = state["stock"]
		for item_id in usual:
			stock[item_id] = maxi(int(stock.get(item_id, 0)), int(usual[item_id]))
		state["till"] = int(definition(shop_id).get("till", 0))
		state["haggled"] = {}


func to_dict() -> Dictionary:
	return {"shops": _state.duplicate(true)}


## Restores saved shelves and tills over the data's shops: a shop the save
## does not mention starts fresh, and a saved shop that no longer exists in
## the data is dropped.
func from_dict(d: Dictionary) -> void:
	var saved: Dictionary = d.get("shops", {})
	for shop_id in _state:
		if not saved.has(shop_id):
			continue
		var raw: Dictionary = saved[shop_id]
		var stock := {}
		var raw_stock: Dictionary = raw.get("stock", {})
		for item_id in raw_stock:
			if _data.has_entry("items", str(item_id)):
				stock[str(item_id)] = maxi(int(raw_stock[item_id]), 0)
		var haggles := {}
		var raw_haggles: Dictionary = raw.get("haggled", {})
		for item_id in raw_haggles:
			var deal: Dictionary = raw_haggles[item_id]
			haggles[str(item_id)] = {"won": bool(deal.get("won", false)),
				"discount": clampf(float(deal.get("discount", 0.0)), 0.0, HaggleRules.MAX_DISCOUNT)}
		_state[shop_id] = {"stock": stock, "till": maxi(int(raw.get("till", 0)), 0), "haggled": haggles}


func _fresh(shop_id: String) -> Dictionary:
	var shop := definition(shop_id)
	var stock := {}
	var usual: Dictionary = shop.get("stock", {})
	for item_id in usual:
		stock[str(item_id)] = int(usual[item_id])
	return {"stock": stock, "till": int(shop.get("till", 0)), "haggled": {}}


func _value(item_id: String) -> int:
	return int(_data.get_entry("items", item_id).get("value", 0)) if _data != null else 0
