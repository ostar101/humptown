extends TestCase
## The scheduler that lets the world act outside the player's region.

var queue: WorldEventQueue


func before_each() -> void:
	queue = WorldEventQueue.new()


func test_drains_in_time_order_regardless_of_insertion_order() -> void:
	queue.schedule(300, "third")
	queue.schedule(100, "first")
	queue.schedule(200, "second")
	var fired := queue.drain_due(500)
	assert_eq(fired.size(), 3)
	assert_eq(fired[0].kind, "first")
	assert_eq(fired[1].kind, "second")
	assert_eq(fired[2].kind, "third")


func test_same_time_events_keep_insertion_order() -> void:
	# Determinism matters: two events at the same minute must resolve in a
	# fixed order or saves stop reproducing.
	queue.schedule(100, "a")
	queue.schedule(100, "b")
	queue.schedule(100, "c")
	var fired := queue.drain_due(100)
	assert_eq(fired[0].kind, "a")
	assert_eq(fired[1].kind, "b")
	assert_eq(fired[2].kind, "c")


func test_future_events_stay_queued() -> void:
	queue.schedule(100, "now")
	queue.schedule(900, "later")
	assert_eq(queue.drain_due(100).size(), 1)
	assert_eq(queue.size(), 1)
	assert_eq(queue.peek_time(), 900)


func test_peek_on_empty_queue() -> void:
	assert_eq(queue.peek_time(), -1)
	assert_true(queue.is_empty())


func test_cancelled_events_never_fire() -> void:
	var id := queue.schedule(100, "doomed")
	queue.cancel(id)
	queue.schedule(110, "survivor")
	var fired := queue.drain_due(200)
	assert_eq(fired.size(), 1)
	assert_eq(fired[0].kind, "survivor")


func test_cancelling_the_next_event_advances_peek() -> void:
	var id := queue.schedule(100, "doomed")
	queue.schedule(200, "next")
	queue.cancel(id)
	assert_eq(queue.peek_time(), 200)


func test_schedule_in_is_relative() -> void:
	queue.schedule_in(1000, 30, "later")
	assert_eq(queue.peek_time(), 1030)


func test_negative_delay_is_clamped_to_now() -> void:
	queue.schedule_in(1000, -50, "oops")
	assert_eq(queue.peek_time(), 1000)


func test_payload_survives() -> void:
	queue.schedule(10, "meeting", {"npc": "npc_rauno", "where": "loc_harbour"})
	var fired := queue.drain_due(10)
	assert_eq(fired[0].payload["npc"], "npc_rauno")


func test_pending_is_time_sorted_without_draining() -> void:
	queue.schedule(300, "c")
	queue.schedule(100, "a")
	queue.schedule(200, "b")
	var pending := queue.pending()
	assert_eq(pending.size(), 3)
	assert_eq(pending[0].kind, "a")
	assert_eq(pending[2].kind, "c")
	assert_eq(queue.size(), 3, "peeking must not consume")


func test_survives_a_save_round_trip() -> void:
	queue.schedule(100, "a", {"x": 1})
	queue.schedule(50, "b")
	var cancelled := queue.schedule(75, "c")
	queue.cancel(cancelled)

	var restored := WorldEventQueue.new()
	restored.from_dict(queue.to_dict())
	var fired := restored.drain_due(1000)
	assert_eq(fired.size(), 2, "the cancelled event stays cancelled")
	assert_eq(fired[0].kind, "b")
	assert_eq(fired[1].payload["x"], 1)


func test_heap_holds_under_volume() -> void:
	# Gossip and scheduling can queue a lot at once; ordering must not drift.
	for i in range(200):
		queue.schedule((i * 7919) % 500, "e%d" % i)
	var fired := queue.drain_due(1000)
	assert_eq(fired.size(), 200)
	var previous := -1
	for event in fired:
		assert_true(event.at >= previous, "events came out of order")
		previous = event.at
