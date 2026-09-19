extends Node
## Global typed event bus. Autoload singleton: Events
##
## Systems talk to each other through here rather than holding references to
## one another. This keeps the dependency graph shallow and lets the debug
## overlay, the phone, the quest system and the knowledge network all react
## to the same world event without any of them knowing about the others.
##
## Rule: only the execution layer emits world-mutating events. Presentation
## listens and never emits.

# --- Time -------------------------------------------------------------------
signal minute_passed(total_minutes: int)
signal hour_passed(hour: int)
signal day_passed(day_index: int)
## Emitted once after a batched jump (sleep/travel) has fully resolved.
signal time_skipped(from_minutes: int, to_minutes: int)

# --- World ------------------------------------------------------------------
signal region_entered(region_id: String)
signal region_exited(region_id: String)
signal location_entered(actor_id: String, location_id: String)
signal location_exited(actor_id: String, location_id: String)
signal world_event_fired(event: Dictionary)

# --- NPC --------------------------------------------------------------------
signal npc_spawned(npc_id: String)
signal npc_despawned(npc_id: String)
signal npc_tier_changed(npc_id: String, tier: int)
signal npc_activity_changed(npc_id: String, activity: String)
signal npc_died(npc_id: String, cause: String)

# --- Social -----------------------------------------------------------------
signal relationship_changed(from_id: String, to_id: String, dimension: String, delta: float)
signal fact_learned(knower_id: String, fact_id: String, source_id: String)
signal reputation_changed(scope: String, delta: float)

# --- Player -----------------------------------------------------------------
signal money_changed(cash: int, bank: int)
signal inventory_changed()
signal skill_xp_gained(skill_id: String, amount: float)
signal skill_level_up(skill_id: String, level: int)
signal condition_changed(meter: String, value: float)
## Health reached zero: the player woke up somewhere (D-041).
signal player_collapsed(woke_at: String, bill: int)
## The player's job changed: hired ("" when they quit), or let go (D-042).
signal job_changed(job_id: String)
signal job_lost(job_id: String, reason: String)
## Something the player did that Godot decided and carried out, for quests
## to count (D-044): kind and what it was about.
signal player_deed(kind: String, data: Dictionary)
## A quest or errand moved: started, advanced, done, failed, errand_taken,
## errand_done.
signal quest_updated(quest_id: String, status: String)
## Someone wrote to the player's phone (D-045); the player read a thread; a
## number was added.
signal phone_message(npc_id: String, message_id: int)
signal phone_read(npc_id: String)
signal phone_contact_added(npc_id: String)
## A meeting moved: accepted, reminder, kept, missed, stood_up (D-047).
signal meeting_updated(meeting_id: int, status: String)
## A place joined the player's map: `how` is "visited" or "told" (D-049).
signal place_learned(location_id: String, how: String)
## Someone saw the player commit a crime (D-051); a witness told the police.
signal crime_committed(fact_id: String, location_id: String)
signal crime_reported(fact_id: String, reporter_id: String, officer_id: String)
## The police decided to summon the player (D-052); what they did about a case
## ("none" | "warning" | "fine" | "arrest", `forced` when the player did not
## come in); the player spent a night in the cells.
signal summons_issued(summons_id: int)
signal police_action(outcome: String, officer_id: String, fine: int, forced: bool)
signal player_arrested(officer_id: String, released_at: int)

# --- Dialogue / LLM ---------------------------------------------------------
signal dialogue_started(npc_id: String)
signal dialogue_ended(npc_id: String)
signal dialogue_line(speaker_id: String, text: String)
signal llm_request_started(request_id: String, purpose: String)
signal llm_request_finished(request_id: String, ok: bool, meta: Dictionary)
signal llm_unavailable(reason: String)
## An LLM-proposed world change that validation refused. Debug mode shows these.
signal action_rejected(proposal: Dictionary, result_code: String)

# --- Meta -------------------------------------------------------------------
signal game_loaded()
signal game_saved(slot: String)
signal settings_changed(key: String)
signal locale_changed(locale: String)
