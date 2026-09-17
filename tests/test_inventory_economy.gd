extends TestCase
## Carrying things and paying for them.

var data: DataRegistry
var inventory: Inventory
var wallet: Wallet


func before_each() -> void:
	data = DataRegistry.new()
	data.load_all()
	inventory = Inventory.new()
	inventory.setup(data)
	inventory.base_capacity = 20.0
	wallet = Wallet.new()


# --- inventory --------------------------------------------------------------

func test_adding_and_counting() -> void:
	assert_ok(inventory.add("item_sandwich", 2))
	assert_eq(inventory.count_of("item_sandwich"), 2)
	assert_true(inventory.has("item_sandwich", 2))
	assert_false(inventory.has("item_sandwich", 3))


func test_stackables_merge() -> void:
	inventory.add("item_sandwich", 1)
	inventory.add("item_sandwich", 1)
	assert_eq(inventory.stacks.size(), 1)
	assert_eq(inventory.count_of("item_sandwich"), 2)


func test_non_stackables_do_not_merge() -> void:
	inventory.add("item_crowbar", 1)
	inventory.add("item_crowbar", 1)
	assert_eq(inventory.stacks.size(), 2)


func test_items_with_state_get_their_own_stack() -> void:
	inventory.add("item_sandwich", 1)
	inventory.add("item_sandwich", 1, {"stolen_from": "loc_corner_shop"})
	assert_eq(inventory.stacks.size(), 2, "a stolen one is not interchangeable")


func test_unknown_items_are_refused() -> void:
	assert_err(inventory.add("item_does_not_exist"), "unknown_item")


func test_weight_limit_is_enforced() -> void:
	inventory.base_capacity = 5.0
	assert_ok(inventory.add("item_crowbar", 1))     # 3.5
	assert_err(inventory.add("item_toolbox", 1), "too_heavy")
	assert_eq(inventory.count_of("item_toolbox"), 0)


func test_free_weight_tracks_contents() -> void:
	inventory.base_capacity = 10.0
	inventory.add("item_crowbar", 1)
	assert_almost(inventory.total_weight(), 3.5)
	assert_almost(inventory.free_weight(), 6.5)


func test_removing_more_than_held_fails_without_side_effects() -> void:
	inventory.add("item_sandwich", 1)
	assert_err(inventory.remove("item_sandwich", 5), "not_enough")
	assert_eq(inventory.count_of("item_sandwich"), 1)


func test_removing_drains_stacks_and_cleans_up() -> void:
	inventory.add("item_sandwich", 3)
	assert_ok(inventory.remove("item_sandwich", 3))
	assert_eq(inventory.count_of("item_sandwich"), 0)
	assert_eq(inventory.stacks.size(), 0)


func test_transfer_respects_the_destination_capacity() -> void:
	var other := Inventory.new()
	other.setup(data)
	other.base_capacity = 1.0

	inventory.add("item_toolbox", 1)
	assert_err(inventory.transfer_to(other, "item_toolbox", 1), "too_heavy")
	assert_eq(inventory.count_of("item_toolbox"), 1, "the source keeps it")
	assert_eq(other.count_of("item_toolbox"), 0)


func test_successful_transfer_moves_it() -> void:
	var other := Inventory.new()
	other.setup(data)
	inventory.add("item_sandwich", 2)
	assert_ok(inventory.transfer_to(other, "item_sandwich", 2))
	assert_eq(inventory.count_of("item_sandwich"), 0)
	assert_eq(other.count_of("item_sandwich"), 2)


func test_inventory_round_trips() -> void:
	inventory.add("item_sandwich", 2)
	inventory.add("item_crowbar", 1, {"bloody": true})
	var restored := Inventory.new()
	restored.setup(data)
	restored.from_dict(inventory.to_dict())
	assert_eq(restored.count_of("item_sandwich"), 2)
	assert_eq(restored.stacks.size(), 2)
	assert_true(restored.stacks[1].state.get("bloody", false))


# --- wallet -----------------------------------------------------------------

func test_spending_prefers_cash_then_bank() -> void:
	wallet.cash = 30
	wallet.bank = 100
	assert_ok(wallet.spend(50))
	assert_eq(wallet.cash, 0)
	assert_eq(wallet.bank, 80)


func test_cannot_overspend() -> void:
	wallet.cash = 10
	assert_err(wallet.spend(50), "insufficient_funds")
	assert_eq(wallet.cash, 10)


func test_cash_only_purchases_ignore_the_bank() -> void:
	wallet.cash = 10
	wallet.bank = 1000
	assert_err(wallet.spend(50, "bribe", true), "insufficient_funds")


func test_negative_amounts_are_refused() -> void:
	assert_err(wallet.spend(-100), "negative_amount")


func test_deposit_and_withdraw() -> void:
	wallet.cash = 100
	assert_ok(wallet.deposit(60))
	assert_eq(wallet.cash, 40)
	assert_eq(wallet.bank, 60)
	assert_ok(wallet.withdraw(30))
	assert_eq(wallet.cash, 70)
	assert_err(wallet.withdraw(1000), "insufficient_bank")


func test_ledger_is_bounded() -> void:
	wallet.cash = 100000
	for _i in range(Wallet.LEDGER_LIMIT + 20):
		wallet.add_cash(1)
	assert_eq(wallet.ledger.size(), Wallet.LEDGER_LIMIT)


func test_wallet_round_trips() -> void:
	wallet.cash = 55
	wallet.bank = 220
	wallet.spend(5, "coffee")
	var restored := Wallet.new()
	restored.from_dict(wallet.to_dict())
	assert_eq(restored.cash, 50)
	assert_eq(restored.bank, 220)
	assert_eq(restored.ledger.size(), 1)
