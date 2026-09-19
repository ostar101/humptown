class_name ShopRules
extends RefCounted
## Whether a purchase or a sale may happen (D-039). Pure: the caller gathers
## the facts, this answers with a Result, and nothing changes on a refusal.
##
## Buying — facts: serving (someone is behind the counter), sells, stock,
## quantity, price (each), money (what the player can pay with, cash and
## card), free_weight, weight (each). Refusals: nobody_serving, bad_quantity,
## not_sold_here, out_of_stock, not_enough_money, too_heavy.
##
## Selling — facts: serving, buys, owned, quantity, price (each), till.
## Refusals: nobody_serving, bad_quantity, not_owned, not_bought_here,
## till_short.

## More than this in one go is not shopping.
const MAX_QUANTITY := 20


static func judge_buy(facts: Dictionary) -> Result:
	var quantity := int(facts.get("quantity", 0))
	if not bool(facts.get("serving", false)):
		return Result.failure("nobody_serving")
	if quantity < 1 or quantity > MAX_QUANTITY:
		return Result.failure("bad_quantity")
	if not bool(facts.get("sells", false)):
		return Result.failure("not_sold_here")
	if int(facts.get("stock", 0)) < quantity:
		return Result.failure("out_of_stock")
	var total := int(facts.get("price", 0)) * quantity
	if int(facts.get("money", 0)) < total:
		return Result.failure("not_enough_money")
	if float(facts.get("weight", 0.0)) * quantity > float(facts.get("free_weight", 0.0)) + 0.0001:
		return Result.failure("too_heavy")
	return Result.success({"total": total})


static func judge_sell(facts: Dictionary) -> Result:
	var quantity := int(facts.get("quantity", 0))
	if not bool(facts.get("serving", false)):
		return Result.failure("nobody_serving")
	if quantity < 1 or quantity > MAX_QUANTITY:
		return Result.failure("bad_quantity")
	if int(facts.get("owned", 0)) < quantity:
		return Result.failure("not_owned")
	if not bool(facts.get("buys", false)) or int(facts.get("price", 0)) <= 0:
		return Result.failure("not_bought_here")
	var total := int(facts.get("price", 0)) * quantity
	if int(facts.get("till", 0)) < total:
		return Result.failure("till_short")
	return Result.success({"total": total})
