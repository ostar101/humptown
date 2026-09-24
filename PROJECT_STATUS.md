# Project status

**Updated:** 2026-09-24
**Milestone:** M6 — Consequences — **complete in code (0.6.0)**. M5 complete (0.5.0). M5 complete in code (0.5.0). **M8 — A town worth walking — complete (all twelve planned steps).** Plan at `C:\Users\miika\.claude\plans\peli-tuntuu-hieman-tyls-lt-prancy-hamming.md`. Sessions A, B and C all done. **Downtown + walkable upper floors — complete, with three residents and a kiosk.** Plan at `C:\Users\miika\.claude\plans\parallel-swimming-hummingbird.md`, all seven steps done (D-091 to D-094); D-095/D-096 (past the plan's own scope, the user's own repeated "continue" with no further detail each time) added residents and a shop.
**Build:** green. 1166 tests, 37332 assertions with the LimeZu art installed,
~54 s. No leak warnings at exit.
**Engine:** Godot 4.5.1 stable, GL Compatibility renderer.

---

## Next task

**Newest (D-106) — an errand in every district** (Anna-Liisa's bread, Paula's
milk) and a test that every errand's item is sold in its giver's district.
1166 green.

**Before that (D-105) — nobody is sent anywhere while it is shut.** The D-104
test widened to opening hours found 13 people inside the Anchor/Furnace
hours before opening every weekend; three schedules fixed. **Rule: a
schedule may only send someone to a place while it is open, except their
home and their own workplace** — `test_nobody_is_sent_anywhere_while_it_
is_shut` enforces it. 1165 green.

**Before that (D-104) — closed days.** Five shops were open with nobody working
on some day of the week. `Location.closed_days` (0 = Sunday) +
`is_closed_on()` + weekday-aware `is_open_at()`; the door refuses
`closed_today`; meetings/summons check tomorrow. Pharmacy and pawn shop
shut weekends, corner shop Sundays; Kaisla (Emma, Sundays) and the kiosk
(Tomi, Sundays) staffed instead. Staffing now tested for every shop and
day; nobody's schedule sends them to a place on its closed day. 1165 green.
**Note:** the suite took ~91 s this session on a loaded machine — HEAD
measured the same, so it is the machine, not the tests.

**Before that (D-103) — eight people stop commuting to Harbourside.** D-088
put six Old Town and two Eastfield people on `sched_local_idle` /
`sched_student_day`, which name Harbourside places, so they spent every
day there. Four regional schedules (`sched_oldtown_idle`/`_student`,
`sched_eastfield_idle`/`_student`) and a test over **every** NPC's week
(`test_nobody_spends_their_ordinary_week_outside_their_own_district`).
**Rule going forward: a schedule that names a place belongs to that
place's region; reuse across regions only through `@home`/`@work`.**
1160 green.

**Before that (D-102) — Finnish: ä/ö restored in the first 99 keys (11 were
wrong), Eastfield is "Itäpelto" everywhere.** 1159 green.

**Before that (D-101) — Downtown's signs, an errand, Finnish names.** A notice
and a road sign like every other district; `errand_raili_juice` (the first
errand outside Harbourside — Old Town/Eastfield could have one each the
same way); Finnish strings for the region and all eight Downtown locations.
1159 green (assertions −13: one per Finnish gap closed).

**Before that (D-100) — Downtown in the dialogue prompt.** `DialoguePrompt.
REGION_PHRASE` had no `downtown`, so its residents got the bare fallback.
Added, and `test_every_region_has_its_own_phrase` now walks every region in
`regions.json`, so a future region cannot miss it. 1159 green.

**Before that (D-099) — Downtown's pocket park, `sched_downtown_idle`, four
more residents.** `loc_downtown_green` (park, public, meeting_place,
`[50, 39, 20, 12]`, Harbour Park's trees/benches in `PlaceArt`) gives people
at home somewhere to spend the afternoon and Downtown an all-day meeting
place. `sched_downtown_idle`: street → kiosk → park → Late Desk 18–20 →
home. Raili (68) and Lauri (51, tower A) in flats A; Marja (44, tower B)
and her nephew Tomi (23) in flats B — four to a block now, tied to each
other by relationships. 1158 green (assertions 36092). Benchmark vs HEAD
±2%. **Downtown: 7 locations on the street, 8 residents, a kiosk, a bar, a
park.**

**Before that (D-098) — Downtown gets a bar, the Late Desk.** A sixth building,
`loc_downtown_bar` (kind `bar`, the shared `bar_` storefront art, 8×13, door
column 4 — the same footprint as the Lantern), east of the kiosk on the same
street level; open 16:00–02:00 and a `meeting_place`, like the Lantern.
`shop_downtown_bar` sells beer, wine, vodka, coffee, juice, cigarettes.
`int_downtown_bar` is the Lantern's own layout. `sched_downtown_bar` is
`sched_night_bar_old` with `loc_market` swapped for `loc_downtown_kiosk`.
Venla Kallio (28, `occ_barkeep`, no new occupation) keeps it and shares
Iiro's flat in `loc_downtown_flats_b`; she knows Taina and Iiro. No job for
the player — the Lantern has none either. Name checked against `npcs.json`
first. The two loop-based checks in `test_regions.gd` gained her and the
shop; 1158 green (assertions 33047 → 33744). Screenshot confirmed the art.
**Downtown now: six buildings, four residents, a kiosk and a bar.** Still
open, still the user's call: more households, and Sessions D+ (civic art,
home variants, romance, sex work).

**Before that (D-097) — a floor key is never a place.** D-091's deferred
follow-up became reachable once D-095 put Saana to work in a climbable
tower: upstairs, people at the building were drawn but refused as
`nobody_there`, a follower was moved to `"loc_downtown_tower_a#2"` (not a
Location), and the phone lost its "you are here" pin. `DistrictMap.
building_of()` (floor_key's inverse) and `PlayerState.interior_base()` now
stand in for `player.interior` wherever it is compared with a location id
— **the rule from here on: `interior` is only a key for
`WorldState.interior_for()`; anything asking *where* uses
`interior_base()`.** Everyone at a building is in the room on whichever
floor the player is on (deliberate, matches `NpcBodies`). 3 new tests in
`test_stairs.gd`, 1158 green. Benchmark back to back with HEAD: noise in
both directions, nothing here runs per minute. Worth trying in play: ask
someone to follow you into tower A on a weekday, climb, talk to Saana on
floor 2. **What comes next is unchanged and still the user's call** — see
D-096 below (more downtown households, a bar, Sessions D+).

**Before that (D-096) — a fifth building: the kiosk.** `loc_downtown_kiosk`, a
new ground-level building (not a repurposed tower) wearing the shared
`shop`/`bar`/`civic`/`work` storefront art, same street level as every
other downtown door. `shop_downtown_kiosk` sells the usual small-shop
stock (coffee, a sandwich, cigarettes, water, juice, a lighter, a bandage).
`occ_shopkeeper` already existed and needed no new occupation.
`sched_downtown_shop` is `sched_shop_day` with `loc_cafe_kaisla` swapped
for `loc_downtown_street`, the same substitution D-095 already made for
`sched_downtown_office`. Taina Lehto (41) runs it and shares a home with
Saana — D-088's own precedent for two NPCs sharing one flat, not a new
shape. **This time the id was checked for collisions before authoring**,
unlike D-095's `npc_eero` mistake. 1155 tests still green (33020
assertions, was 32323). **Downtown now has geography, walkable upper
floors, three residents and one shop. Still open, still the user's call:**
more households in the two apartment blocks, a second shop or a bar, and
the rest of the Sessions D+ list (civic art, home variants, romance, sex
work).

**Before that (D-095) — two people move into Downtown.** One new occupation
(`occ_clerk`), two jobs (`job_downtown_tower_a`/`_b`, weekday 08:00–17:00),
one new schedule (`sched_downtown_office`, copied from `sched_clinic_day`'s
shape since Downtown has no shop/bar of its own yet for a schedule to
name). Saana Virtanen lives in `loc_downtown_flats_a` and works
`loc_downtown_tower_a`; Iiro Mäkelä lives in `loc_downtown_flats_b` and
works `loc_downtown_tower_b` — each their own job's employer, matching
`npc_veikko`'s own dockhand precedent. Both homes gained an `owner` field
like every other resident's home. **Caught by the suite, not by
inspection**: the first name chosen for the second NPC, "Eero", collided
with an existing `npc_eero` — `new_game()` failed outright and cascaded
into ~90 unrelated-looking failures across half the suite, all downstream
of the same root cause; renamed to Iiro. No new tests — the existing
per-district weekly-walk check and content-reference checks absorbed both
people for free (assertions 31116 → 32323). 1155 tests still green.
**Downtown's shops, and its other two buildings' own residents, remain
unbuilt — still the user's call, same as the rest of the Sessions D+ list
(civic art, home variants, romance, sex work).**

**Before that (D-091 to D-094) — the downtown plan, closed.**
`C:\Users\miika\.claude\plans\parallel-swimming-hummingbird.md`, all seven
steps done. D-094 — sixteen interiors, the floor/stairs mechanic proven on
real content, closing the downtown plan. Every floor of all four downtown
towers gets an interior (2+4+4+6 = 16 entries in `data/interiors.json`),
generated from one reused 6×6 template so sixteen near-identical entries
can't drift out of sync by hand — every floor but the top has a `table`
solid and a `stairs` object at the same local cell; the top floor has
neither, just the required door, already read as `"stairs_down"` above
floor 1 (D-091). **Only the two office towers are actually climbable this
pass** (`semi_public`, matching `loc_worksite`/`loc_garage`'s walk-in-lobby
precedent) — proven end to end, floor by floor, up and back down, in
`tests/test_stairs.gd`. The two apartment blocks stay `private` (D-093:
nobody lives there yet) and correctly refuse a stranger before the
interior lookup is ever reached, even though their own sixteen-entry share
of interiors is authored and schema-validated exactly like the towers'.
2 new tests, 1155 green (was 1153). No benchmark — interiors cost nothing
per simulated minute. **This closes the whole downtown plan (D-091–D-094).
Still to come, named and deliberate: no shops, jobs, NPCs or residents
anywhere in Downtown; the five call sites D-091 named that assume
`player.interior` is a bare location id remain unfixed, and still unreached
by anything this pass built.** Worth trying in play: walk from Harbourside's
west edge or Old Town's north edge into Downtown, climb either tower to its
top and back, confirm the two apartment blocks refuse a stranger at the
door. What comes after Downtown (more content there, or the next item on
Sessions D+'s own list — romance, sex work, civic art) is the user's call.

**Before that (D-093) — downtown opens, geography before population (Session E
step 5).** A fourth region, `downtown`, neighbouring `old_town` and
`harbourside` (11 and 15 minutes); a 96×72 map with four towers sharing one
street level (tallest starting highest, so the skyline reads as varied
heights rather than a staggered row) — two apartment blocks
(`loc_downtown_flats_a`/`b`, `downtown_2`/`downtown_4` art via
`BY_LOCATION`) and two office towers (`loc_downtown_tower_a`/`b`,
`downtown_4`/`downtown_6`). Harbourside and Old Town each gained a third
exit on their only free edge. **No shops, jobs, NPCs or interiors yet** —
deliberate, matching this session's own scope. Benchmark re-run back to
back against the pre-downtown commit: within a few percent either way, no
regression. 1153 tests green (was 1152). **Next: step 6 — interiors on all
four buildings, floor 2+ on the taller three, and a real `stairs` object —
the first time D-091's floor mechanic runs on real content.**

**Before that (D-092) — downtown's tower art, pre-baked (Session D step 4,
closing Session D).** `tools/import_limezu_downtown.py` stacks LimeZu's
modular ground/middle/roof pieces into three fixed-height PNGs at import
time (`downtown_2`/`downtown_4`/`downtown_6` — 2/4/6 walkable floors) rather
than teaching the engine to composite tiles at runtime — zero changes to
`BuildingArt`/`RegionTiles`/`ArtShape`, each baked file is an ordinary
`BuildingArt.BUILDINGS` entry, door column 3 of 7 (measured, matching
`police_1.png`'s own convention). No map or region references them yet.
1152 tests still green (30972 assertions, up from 30948 — the existing
per-kind `BuildingArt` tests now also cover the three new keys). **Session D
is done. Next: Session E — author the `downtown` region itself (a new
entry in `data/regions.json`, a 96×72 map, four buildings using this art,
and the interiors + `stairs` objects that make D-091's mechanic real on a
real building for the first time.**

**Before that (D-091) — walkable upper floors, the mechanic (Session D, steps
1–3 of the downtown plan).** `DistrictMap.storey` (named to dodge GDScript's
built-in `floor()`; authored as JSON `"floor"`, default 1), `OBJECT_KINDS +=
"stairs"`, `DistrictMap.floor_key(location_id, storey)` (bare id on the
ground floor, `"id#N"` above it — a strict, non-colliding extension of the
value space `player.interior` already lived in, so **no v14 migration and no
new `PlayerState` field**, a deliberate reversal of what M8's own closing
note guessed this would need). `WorldState.build_from()` keys `interiors` by
that composite; `DataRegistry._interior_floor_problems()` enforces a
contiguous floor run per building. `Game._change_floor()` climbs/descends;
the ground floor's own door is untouched, floor>1's same door cell now reads
as `"stairs_down"`. Proven against a synthetic two-floor fixture on
`loc_corner_shop` — no real building has an upper floor yet, that is
downtown's own job, next. 8 new tests, 1152 green (was 1144). **Next: step
4, art plumbing (`tools/import_limezu_downtown.py`, three new `BuildingArt`
keys) — end of Session D — then Session E authors downtown itself.**

**Before that (D-090) — the first play-through's findings, and three design calls
settled.** The user has played (first time since M4) and found no big bugs, only
small ones, which they will report together later — **wait for that list**.
Fixed now, from what they did report: waking in the clinic after sleeping and
"injured" with no fight (one loop: health never recovered, hunger rose fast
asleep, the HUD called any low health "hurt" — now rest mends up to what open
wounds allow, hunger asleep is slower, and it says "Weak" without a wound);
enemies who always escaped when losing (now rolled against the player's
agility, and yielding is likelier); grudges that restarted for ever (one holder,
one warning, over for good once fought, ignored or made up). Design, as the
user asked: dealer heat fades (`CrimeDirector.heat`), knowledge fades by
severity and firsthand-ness (`KnowledgeNetwork.fade`), and an unpaid debt goes
summons-to-talk → threat → last warning → the enforcer **hunts** the player
when out (09–22, not at home/police/clinic) — the one exception to "no fights
in the street", recorded in CLAUDE.md. Payable in parts to creditor or
collector. 15 new tests, 1144 green, no leak. Worth checking in play: fail
Rauno's debt (bg_in_debt, 14 days) and walk the harbour on day 9+.

**Before that (D-089) — a review pass, no new features.** The user asked for the
whole project to be read through for bugs. Eight fixed, each with a test that
fails on the old code (11 new tests, 1129 green): OpenAI reasoning models
(`gpt-5`, `o*`) were sent a temperature they reject with a 400 — every call
would have failed; `content: null` from OpenAI/OpenRouter became the spoken
text `<null>`; `Game.unload()` left `_last_retier` and seven other per-life
flags behind (loading an earlier save stalled the periodic retier); the
dialogue box's goodbye timer could close the *next* conversation, and a slow
reply could leave input blocked in it; grudges never ended even once the
holder liked the player again (the docstring said they did); a sleeping
person counted as watching a deal; a dealt shop showed Haggle/Pocket that
could only refuse; `SaveManager.save()` deleted the old save before the
rename that replaces it. Anthropic's adapter was checked against the current
API and is right as it is. **Seen but deliberately not changed** (tuning
calls for whoever next plays it, listed at the end of D-089): dealer `heat`
never fades, `KnowledgeNetwork.facts` only grows, a failed debt can never be
paid late. `ORIGINAL_PLAN.md`/`.txt` in the root are the user's own
untracked files, left untracked. What comes next is still the user's call —
and still, first, a play-through by a person.

**Before that — M8 step 12 (D-088) — closes M8's planned scope:** 30 new NPCs (50 total, was 20), authored against the `nature`/`deals` schema D-082 froze, living in the sixteen existing non-player homes (one or two to a home — four of the original twenty already shared one, so this was the established shape, not a new one), working at existing workplaces, on existing schedules — nothing added to `locations.json` or `schedules.json`. Median age 46 → 34.5, computed and guarded by a new `test_the_town_has_young_adults_too`. "A couple of real dealers" reads as already satisfied by Rauno and Kimmo (D-084); no third shop was built. A handful of new "in-betweens who look away" (moderate-to-low `lawfulness`, high `discretion`, no shop), and a fence **in nature only** — `npc_ville`, Kimmo's cousin, `{lawfulness: 0.25, greed: 0.75, discretion: 0.7}`, no `deals` array — a character who reads right before the mechanic exists, same as Aarne and Kimmo did before their own shops landed. **One real bug fixed**: `DialoguePrompt.system_text()` hardcoded every NPC as living "in Harbourside, the harbour district" regardless of where they actually lived — true for nobody in Old Town or Eastfield, a bug since M7 (D-072) that no dialogue-model test had ever caught. `DialogueDirector.prompt_context()` gained `now.region`; `DialoguePrompt.REGION_PHRASE` gives each region the same apposition shape Harbourside always had. **One near-miss**: `npc_petri` was first authored as a second police officer, breaking twelve tests across `test_fights.gd`/`test_police.gd`/`test_theft.gd` built on `CrimeDirector.officers()` returning exactly one person — fixed by giving him a different story (left the force elsewhere, renting a room from Tuomas now) rather than widening police mechanics nothing asked for. 2 new tests. 1118 tests green (was 1116). Benchmark re-run: inside this session's established noise band at every population, no regression. **This closes M8's twelve planned steps.** Sessions D+ are sequenced after but not detailed in the plan — and the plan itself says the game wants playing by a person first, since nothing from M4 onward (and now all of M8) has been seen at a keyboard, only tested and screenshotted.

**Before that (D-087) — session C step 11:** Vouching. `AskDirector.EFFECTS += "vouch"`; two new `data/asks.json` entries, `ask_vouch_rauno` and `ask_vouch_kimmo`, each put directly to the dealer (not a third party) with `requires: {"deals": true}` — a safety net `DataRegistry` now checks at load time (`ask '%s' requires dealing but '%s' deals from nothing`), since each ask is already hard-tied to one npc the way every ask is. On success (only success, not partial) the effect makes that dealer a firsthand `KnowledgeNetwork` witness of `"vouched_for"` about the player — `_vouched_for(npc_id)` in `DialogueDirector` (D-085, step 9) has read this correctly since it was written, it just never had anything to find until now. Nothing hardcodes who the vouching is *for*: the fact's own gossip spread (already built, D-085) is what "spreading along relationship edges" meant — if this dealer later talks to another dealer they're close to, the player's reputation as vouched-for can travel there with no new mechanism. `AskDirector.setup()` gained a `KnowledgeNetwork` parameter (the signature change the plan called out) — one real caller (`Game.new_game()`), no test constructs `AskDirector` directly, so the fix was one line. Proven end to end: `test_being_vouched_for_opens_the_shop_to_a_stranger` vouches with Rauno, confirms the resulting familiarity is still below `DealRules.familiarity_floor()`'s ordinary threshold, then asks him for something in a *second*, otherwise-cold conversation — no refusal, `deal_offered`, vouching the only reason it worked. 4 new tests in `tests/test_asks.gd` (this is the ask system doing one more thing, not a new one — no new test file). **One existing test needed fixing**: `test_there_has_to_be_something_to_bargain_over` assumed Rauno had nothing to ask once the debt quest was inactive, no longer true now that `ask_vouch_rauno` is always available to him — moved to Veikko, who has no authored ask at all. The same lesson as D-084's near-identical fixture break: a new always-available ask on an existing NPC quietly invalidates "nothing else here" assumptions elsewhere; only the full suite catches it. 1116 tests green (was 1112). No benchmark — nothing here runs per simulated minute. **Step 12, 30-40 new NPCs against the now-frozen `nature`/`deals` schema (a couple of real dealers, several in-betweens, a fence, mostly ordinary people, and young adults — the median age is 46 today), plus regionalising `dialogue_prompt.gd:76,88`'s hard-coded Harbourside, is next**, in this same session unless near a usage limit.

**Before that (D-086) — session B step 10, closing session B:** Consequences, landed alone as the plan asked. `CrimeDirector.CRIME_PREDICATES += "dealt_illicit"` — one predicate for all of it; `ItemRules.heat_of(item)` (new, the `damage_of`/`armour_of` pattern) carries the difference between a joint and a bag of heroin: an item's own `"heat"` if authored, else `0.4` for `kind:"drug"`, `0.5` for `kind:"weapon"`, `0.25` otherwise — every one of the 19 weapons and 16 drugs already in the game needs nothing added to `items.json`. `Reputation.DEFAULT_WEIGHTS` gains `dealt_illicit: -0.35` and `vouched_for: 0.20` (ready for step 11, nothing writes the fact yet); `SCOPE_MODIFIERS` reads both oppositely in the two scopes that care — criminals barely mind dealing (`+0.10` there), the police mind it more than almost anything (`-0.55`), and being vouched for lands hardest exactly where it happened (`criminal: +0.35`). `Game._observe_illicit_deal(shop_id, item_id)`, called from `buy()`/`sell()`, is `steal()`'s witness check transplanted: returns at once for a `"legal"` shop, otherwise calls the same `crime.watchers()`, with the keeper's `discretion` standing in for the player's stealth (`int(round(discretion × 99))` into `TheftRules.notice_chance()`) since the dealer controls how the exchange happens, not the player. **The keeper is never a witness of their own sale** — excluded from `watchers()`'s elevated `is_staff` attention (called with `staff: ""`) and filtered from the result before any roll — a dealer cannot report a deal they themselves made. Confirmed, not changed: `PoliceRules` and every `ui.msg.police_*` key are predicate-blind, so `dealt_illicit` needed no new UI string. 8 new tests in `tests/test_dealt_illicit.gd`. 1112 tests green (was 1104). No benchmark — nothing here runs per simulated minute. **This closes M8 session B.** `Npc.nature`, `DealRules`, gated shops, `ask_deal` and its consequences are all in, tested offline throughout, and none of it has been played by a person yet — worth trying before session C: ask Rauno for something at night with nobody about, then again in daylight at the harbour with Marika in sight. **Session C (steps 11-12: vouching, 30-40 new NPCs including young adults) is next, in a fresh session** per the plan's own handoff prompt — this session stops here.

**Before that (D-085) — session B step 9:** `ask_deal` — the door into the two illicit shops D-084 left unreachable. A new intent kind (`ConversationRules.KINDS`, `IntentPrompt.KIND_HELP`, `OfflineTopics` recognises "got anything"/"onko sulla mitään" and five more phrasings each, inserted after `ask_action`) that names nothing but itself — no substance, amount or price, the strongest reading of "the model proposes, Godot decides" the plan asked for. `DialogueDirector._deal_state(npc_id)` (the `gift`/`go` pattern) gathers everything `DealRules.judge()` needs: `shops.shop_of(npc_id)`, the keeper's `nature`, `Relationship` feeling, `requires_met` against `quests.active` (mirroring `AskDirector._requirements_met`), `vouched` (a `"vouched_for"` knowledge-network fact — always false today, nothing writes it until step 11, but the check is already right), `Reputation.criminal_standing()` (new: the *worst* standing across every criminal-flavoured scope, not an average), `heat` (new, and the number D-083 left open: `open_summons × 0.6 + settled_record.size() × 0.15`, clamped — a judgement call, and **not** the same thing as the per-item `heat` step 10 still owes), and `watched` (a plain scan for anyone else at the dealer's location). **A refused `wont_deal` is not a refused proposal — it costs trust instead**, the one deliberate exception to "every refusal leaves the world unchanged": asking a genuinely lawful person is a social move that can land badly, exactly the shape `"flirt"` already has when unwelcome, not an impossible action to undo. The other seven `DealRules` codes stay plain refusals. **Opening the shop needed a second door**: `Game.open_deal_shop(npc_id, shop_id)` sets `_shopping` to a shop id directly (`_dealing`/`_deal_keeper` remember it), since `shop_at()` was deliberately never taught to find a kept shop by its keeper's location (D-084) — `_current_shop_id()`/`_current_staff()` are the only two places `shop_view()`/`buy()`/`sell()` had to learn the difference; `haggle()`/`steal()` were left alone, harmlessly finding nothing for a dealt session. `Events.deal_offered` → `Game` banks the price, `WorldView._on_deal_offered` → `_begin_deal` (the `fight_requested`/`_begin_fight` pattern exactly) closes the dialogue and opens `ShopWindow.open_deal()`. **Never driven through a live model** — a hand-run `--talk=npc_rauno "--say=Got anything?"` on `ui_preview.tscn` was killed within a minute with zero output, since that debug scene is not sandboxed to the offline provider the way the test runner is (D-036) and this machine has a real key configured; everything here is proven by `tests/test_ask_deal.gd` (11 tests) against a scripted offline model instead. Two Finnish gaps this step actually had to close, not leave open: `dialogue.generic.*` lines are the one content category `test_dialogue.gd`'s `test_every_line_is_translated` requires in both languages, unlike `name_key`s. 1104 tests green (was 1093). No benchmark — nothing here runs per simulated minute. **Step 10, consequences (`dealt_illicit` crime predicate, `Reputation` weights, `Game.buy`/`sell` calling `crime.watchers`, per-item `heat` on `items.json`), lands alone**, next, in this same session unless near a usage limit.

**Before that (D-084) — session B step 8:** Gated shops. `shops.json` entries now name either `location` (every existing shop, unchanged) or `keeper` (an npc id — dealt with wherever they are, not a counter) — exactly one, checked by `DataRegistry._shop_reference_problems`, which also enforces the symmetric link: a kept shop's `keeper` must have that shop in their own `deals`. `REQUIRED_KEYS["shops"]` dropped `location` (now just `["id", "stock"]`) since it is conditional. `legality` (`"legal"` default, `"grey"`, `"illicit"`) and `requires` (`{"quest": ...}`, optional) round out the schema; both validated. `ShopRegistry.shop_of(npc_id)` is the inverse lookup, `ShopRegistry.legality(shop_id)` a plain data read — neither called by anything yet. Two illicit shops authored, both kept, both stocked from the plan's 16 raw/unprepared drug items: `shop_warehouse_stash` (`npc_rauno`, harder drugs) and `shop_scrapyard_stash` (`npc_kimmo`, cannabis and mushrooms, Eastfield's own dealer) — `deals` finally populated on these two NPCs (D-082 left it empty on everyone). **Deliberately not reachable in play yet**: `shop_at(location_id)` was *not* taught to resolve a keeper by their current position — that would let a player walk up and buy with no gate at all, exactly backwards from why `nature`/`DealRules`/`keeper` exist. `ask_deal` (step 9) is the only door once built; until then these two shops are inert, reachable only through `ShopRegistry` directly, the same "pure, unused" shape D-083 left `DealRules` in. `Game._deal_factor: Dictionary` (shop id → today's negotiated price multiplier) lives on `Game`, not saved, cleared in `new_game()`; `Game._priced_buy()` reads it (default 1.0) and now stands in for `shops.buy_price()` in `shop_view()` and `buy()` (not `sell()`). `set_deal_factor()` is public, unused by any caller yet — step 9's job. 12 new tests: `tests/test_shops.gd` (the gated-shop reads, the pricing plumbing proven against an ordinary shop since no kept shop can be opened yet, six `DataRegistry` validation cases) and two of D-082's fixtures fixed in `tests/test_npc_nature.gd` (they reassigned `npc_rauno.deals` wholesale, which now breaks `shop_warehouse_stash`'s own symmetric-link check — moved to `npc_ida`). 1093 tests green (was 1081). No benchmark — `src/economy/` and `src/data/` sit outside the tiered simulation path. **Step 9, `ask_deal` in conversation — the actual door into these two shops — is next**, in this same session unless near a usage limit.

**Before that (D-083) — session B step 7:** `DealRules` (`src/economy/deal_rules.gd`, pure, unused yet — `ask_deal` in step 9 is its first caller). `judge(facts) -> Result` runs the plan's eight-check gate in order: `not_a_dealer` (no deal covers this shop) → `wont_deal` (`legality == "illicit"` and `lawfulness > 0.6`; a `"grey"` shop never checks lawfulness) → `requires_unmet` → `dont_know_you`/`dont_trust_you` (a familiarity floor and a trust floor, both skipped — not loosened — when `vouched`) → `bad_standing` (criminal-scope reputation `< -0.2`) → `too_hot` (`heat > risk`) → `not_now` (watched and `risk < 0.7`). Success returns `{"factor", "visibility"}`, never a plain yes: `factor` from greed and closeness (familiarity + trust, priced `[0.5, 2.5]`), `visibility` as `1.0 - discretion` (never quite zero — discretion is the one `nature` axis that only costs, never gates). The two floor formulas and the two success formulas are judgement calls (documented in D-083, not locked — nothing downstream depends on the exact constants yet, only on the shape). **`heat` is a caller-supplied fact this step, not computed anywhere** — deriving it (from crime record, an open summons) is open for step 9 or 10; do not confuse it with the per-*item* `heat` the plan adds to `items.json` in step 10, which feeds a deal's visibility as a crime, not this gate. 17 new tests in `tests/test_deals.gd`: every refusal code, the happy path, vouching, a lawful person still dealing at a merely-grey shop, check ordering, and the pricing/visibility formulas' monotonicity and range. 1081 tests green (was 1064). No behaviour change — no benchmark, nothing calls this yet. **Step 8, gated shops (`keeper`/`legality`/`requires` in `shops.json`, `ShopRegistry.shop_of(npc_id)`, two authored illicit shops), is next**, in this same session unless near a usage limit.

**Before that (D-082) — session B step 6:** `Npc.nature` (four axes, `lawfulness`/`greed`/`risk`/`discretion`, each `[0, 1]`) and `Npc.deals` (a list of shop ids), data only. `src/npc/npc.gd`: `Npc.DEFAULT_NATURE`/`Npc.NATURE_AXES` consts, `from_data` merges authored axes over the defaults per-axis so a partial `nature` block still gets sane values for the rest, `deals` parsed as a plain string array. Neither is saved (`to_dict`/`from_dict` untouched) — this is authored content, not runtime state. **All 20 existing NPCs backfilled by hand** in `data/npcs.json` from their traits and bio (`never_writes_anything_down`/`asks_no_questions` → low lawfulness, high discretion; `by_the_book` → `lawfulness: 1.0`; `hears_everything`/`gossips` → low discretion — Rauno lands furthest toward a dealer, Marika furthest toward the law). `DataRegistry._npc_nature_problems` (`src/data/data_registry.gd`) validates: only the four known axis names, each numeric and in range, and every `deals` entry names a real `shops` table id. **`deals` is empty on every NPC this step** — the shops it would point at don't exist until step 8, so authoring a reference now would fail the very check meant to catch it; the shop and the NPC's `deals` entry naming it land together in that later commit. 11 new tests in `tests/test_npc_nature.gd`: defaults, partial-axis backfill, `deals` read/default, and the four validator refusal paths plus their happy-path counterparts. 1064 tests green (was 1053). Benchmark re-run (touches `src/npc/`): noisy on this machine as before (D-077) — a second back-to-back sample landed in line with the pre-change baseline, no regression. **Zero player-visible or behavioural change — the schema is now frozen for session C's 30-40 new NPCs.** `DealRules` (step 7, the first consumer of `nature`) is next, in this same session unless near a usage limit.

**Before that (D-081) — session A complete:** Examine. `src/presentation/item_facts.gd` (pure): `facts_of(item)` generates `{key, args}` facts for all 115 items — kind/weight/value, the five condition meters read off each item's own fields, damage **banded** (never a raw float), slot, armour, capacity bonus, needs-fire, leaves-behind (naming the item), and a warning line on every `kind:"drug"` item. `description_of(item)` reads the optional `item.<slug>.desc` (30 of 115 authored; `test_content_name_keys_all_have_english_strings` deliberately not extended to require one, reason in its own docstring). `ItemRules.KEEP` (was `DialogueDirector.GIFT_KEEP`) — the phone and the keys, one list of unloseable things. `ItemsWindow` gains **WORN** (left, six always-present slot rows, click an occupied one to examine it) and **EXAMINE** (right, icon/name/summary/description/facts + up to four buttons — Use, Wear, Take off, Lay on bench — each `.visible` from what is selected, not which tab is open), both visible regardless of tab. Selection survives a tab switch, clears on a fresh open. Bag-row selection is a `gui_input` handler, not a new child, so it doesn't disturb `row_texts()` or the `PanelContainer`-first-child test. **The window had to shrink**: a first pass at 1480×640 clipped off-screen against the 1280×720 viewport (caught by a screenshot, not a test) — settled at 1040×600. 23 new tests (`tests/test_item_facts.gd` ×13, `tests/test_items_window.gd` +10). 1053 tests green (was 1031). **Not built:** no clothing yet for head/body/legs (content, a later session); bench-tab and bag-picker-grid items aren't individually examinable, only Bag-tab rows and worn slots. **Session A of M8 (steps 1-5) is done.** Session B (steps 6-10, the shady spectrum: `Npc.nature`, `DealRules`, gated shops, `ask_deal`, consequences) is next, in a fresh session per the plan's own handoff prompt.

**Before that (D-080):** Equipment — six slots, `head/body/legs/feet/hand/back`, no more. `"slot": "hand"` on the 19 `kind:"weapon"` items, `item_work_boots` gets `slot:"feet"` + `armour:0.05`, `item_backpack` gets `slot:"back"` (its `capacity_bonus:10.0` finally does something). `EquipRules` (pure, `src/economy/equip_rules.gd`) judges; `PlayerState.equipment: Dictionary` (slot → item id, a pointer not a move); `Game.equip()`/`unequip()` through `_reject`. `PlayerState.reconcile_equipment()` clears a slot whose thing left the bag some other way and reapplies the capacity bonus — called on `Events.inventory_changed` and directly after equip/unequip. **The stash guard**: the capacity bonus applies to `inventory` only, never `stash` — `test_home.gd:78-79` already covered it from the stash side, `tests/test_equipment.gd` adds the equipment-side test. `wielded_weapon()` prefers the hand slot unconditionally, falls back to the old best-carried scan when it's empty or the worn thing left the bag — every existing fight test and every existing save's fights are exactly as strong as before. Armour: one multiplicative capped term at the end of `CombatRules.damage()`, defaults to 0.0. **Migration v13** (`_v12_to_v13`, `player.equipment` defaults to `{}`), fixture test alongside the feature. 18 new tests in `tests/test_equipment.gd`; 1031 tests green (was 1013).

**Before that (D-079):** `ItemsWindow` (`src/ui/items_window.gd` + `scenes/ui/items_window.tscn`) replaces `InventoryWindow` and `CraftWindow`, both deleted. Three tabs — Bag, Bench, Recipes (the recipe book moved off the bench into its own tab) — on the `%BuyTab`/`%SellTab` precedent. `I` opens on Bag, `C` on Bench; if already open, the key switches tab instead of closing (`ItemsWindow.open_on`), a deliberate UX change from the old two-window toggle-to-close behaviour. `scenes/world/world.tscn` lost `$Inventory`+`$Craft`, gained `$Items`, in this same commit. `WorldView` collapsed `_bag`/`_craft` into one `_items`; `open_inventory/open_crafting/inventory_window/craft_window` renamed `open_bag/open_bench/items_window`. Public method surface (`row_texts`, `grid_ids`, `place`, `make`, etc.) unchanged in shape — tests ported mechanically, `test_craft_window.gd` → `test_items_window.gd` (18 tests: 14 ported, +3 for the merge itself, +1 confirming a hidden tab is actually hidden after the screenshot tool showed a faint, harmless render ghost of it — `visible`/`is_visible_in_tree()` are both correctly false). 1013 tests green (was 1009: -14 old craft tests, +18 new).

**Before that (D-078):** `GameWindow` (`src/ui/game_window.gd`), a base class owning the ~25 lines `InventoryWindow` and `CraftWindow` had copy-pasted (`_root`, `_time_was_paused`, `closed`, `is_open`, closing on `ui_cancel` plus a per-window `toggle_action`, and the `"<prefix>.refused."+code` lookup as `_refusal_text`). Only these two windows converted; the other seven `CanvasLayer` windows are untouched, for later. No behaviour change — same 1009 tests, green.

**Before that (D-077):** Old Town and Eastfield are freely walkable from the start — no timetable, no cash, no contact to carry. `data/regions.json` clears every `unlock` array; `Game._travel_to_region` and `WorldState.enter_region` no longer gate on `region.unlocked`. Travel is still not free: halved from before, 9/18/13 minutes between harbourside/old_town/eastfield. `evaluate_unlock`/`try_unlock` and `Events.region_refused` stay in `WorldState` unused, for a road that may be shut later. The bus timetable sign still exists and still sets a flag when read, now flavour rather than a gate. Full rationale, the deleted/inverted tests and why in D-077 (`DECISIONS.md`). **Benchmark note:** re-measuring after this step showed numbers well above the table below at every population — but a back-to-back run against the prior commit (e2234b6) showed the same elevation, so the table below predates D-072's two new regions and needs a fresh baseline, not a fix for a regression this step caused.

**Before M8 (D-072):** Old Town and Eastfield exist — two 96x72 maps, ten people, five shops, two jobs, interiors for every building. Roads between districts are a rule (`Game._travel_to_region`): the way opens when the player has what it asks (Old Town: read the bus timetable; Eastfield: EUR 120 and Veikko's number), the walk costs `Region.travel_times`, you arrive on the road you came by. **Worth trying in play:** read the timetable at the bus stop, walk up the north road to Old Town, buy medicine at the pharmacy and a pan from Aarne, work a yard shift for Reijo. **Rest of M7 not started:** factions, the story, audio, phone-map revelation, more inhabitants, other building art for Old Town (needs an importer). **Before that (D-071):** 48 more recipes (61) and 49 more items, and `fire` recipes that take a lighter or matches. Ideas for more, not done: more clothing and bags, drinks and cocktails, a repair or upgrade line for weapons, recipes taught by people or books. **Before that (D-070):** every item has a 16x16 icon (`data/item_icons.json`, `ItemIcons`, `ItemSlot`), 52 new items (drugs, medicines, paraphernalia, weapons), a bench on **C** for putting things together (`data/recipes.json`, `CraftRules`, `Game.craft`, `CraftWindow`, save schema v12) and the best carried weapon used in fights. Worth trying in play: press C with a bud and papers in the bag; search bins for a syringe and a spoon and follow the chain. **Open questions for the user:** a way to buy drugs (dealer/black market), whether carrying or using them should be a crime, and firearms — all deliberately not built (D-070). **Before that (D-069):** bins can be searched and used to keep things (`Bins`, `data/bins.json`, save schema v11, the cupboard's window reused). **Before that (D-068):** bins at building corners, hydrants clear of doors; street furniture is now the world's (`StreetFurniture`, `DistrictMap.furniture`). **Before that (D-067):** hydrants, bins, trees, benches and the worksite collide by their art's outline. **Before that (D-066):** street lamps at the kerb, mirrored to face the road, foot collides. **Before that (D-065, all twelve art buildings plus Tuomas's flat, now a villa):** house collision follows the drawn roof's outline (physics polygons from the art plus `map.open_cells` for the rule); with art installed only. **Before that (D-064):** buildings keep the ground they stand on, so roof corners show grass, not paving (roof collision verified and tested). **Before that (D-063):** the event feed moved to the bottom right as plain text, no panel; bag lines say "added to your bag".

**Before that (D-062):** giving an item works (`give_item`, light: it leaves the bag, warms by value, is remembered; people still own nothing, so it goes nowhere). Asking people to give/take/fetch/bring stays `cannot_do` until they have belongings. Left in D-057's line: bring/take-to only after that; more animations.

**Before that (D-061):** "go to <place>" works (`ask_go`): the person is sent there as a schedule override for up to two hours, or refused for a phone line, a grudge, a shut/private/far place or a busy day. Left in D-057's line, in order: give/take (check first whether people have an inventory), bring/take-to (a two-step errand/meeting shape), then more animations. Worth trying in play: "go to Ropewalk Park" with someone free, then check they are there.

**Before that (D-060):** the police post is drawn with LimeZu's police station (7×13, own `police_1.png`; re-run `tools/import_limezu_buildings.py` and `--import`). Other swap candidates are listed in D-060. Tests green (864).

**Latest (D-059):** memory now holds the words and everything between two people (talks, calls, texts either way), openers depend on it, and the HUD has an event feed. Worth trying in play: talk, leave, come back; get a text, then talk; hand over money and watch the feed. **Before that (D-056, D-057):** live play showed replies cut off on thinking models
(fixed: room to think on every provider) and NPCs saying yes to things that
never happened. Now "follow me"/"wait here" work (`NpcDirector.followers`,
`FollowRules`, bodies keep company) and fetch/bring/go/give are refused
honestly (`cannot_do`). **Next in that line, in order:** go/come to a place
(one-off route, the schedule already walks), give/take (check first whether
people have an inventory), bring/take-to (a two-step errand/meeting shape),
then more animations: D-058 imported idle/phone/gift and mapped the rest of the sheet (sit, sleep, pickup, fight rows are read but not imported; each needs something in the world to trigger it). Manual check still
worth doing in the running game: follow through a shop door and back out, and
across a long walk. Benchmark after D-057: no change beyond noise (back to back
with the previous commit).

**M3 is done in code (0.3.0, D-035 to D-038).** Face someone and press E:
the simulation decides whether they can be talked to. Type anything. Each
line is read into an intent — by the cheap model when the player has set one
up, by words when not (`OfflineTopics`, `IntentPrompt`); `ConversationRules`
judges it; Godot applies what it allows (cash gifts, introductions,
compliments capped per conversation, apologies, flirting, insults and
threats that become witnessed facts and travel as gossip); a refusal emits
`action_rejected`; and the person answers — from the model, told what
actually happened and only what they know (`DialoguePrompt`), or from
authored lines. They remember it (`MemoryBook`, D-038): episodes written by
rule, folded into a bounded summary that the cheap model may rewrite. F3
shows the developer overlay. Title → Settings takes the player's own key.

**The one part of M3's "done when" not yet seen: a live model.** "You can
talk to Ida in your own words, she answers in character knowing only what
she should" is built and tested against a scripted model; "unplugging the
network degrades the conversation without breaking the game" is tested.
No real provider has ever been contacted — that needs the user's own key,
entered by the user in Settings (`SecretStore`, D-006), **never by Claude**.
When the user has done that, the first live conversation is worth watching
with F3 open: request fields and response parsing are the likeliest
first-contact surprises (Anthropic's were brought up to date in D-036; the
other providers' model lists were not revisited).

**M4 — Making a living** (ROADMAP.md), sequenced:

1. ~~**Shops**~~ — done (D-039). Step up to a counter with someone working
   behind it and the shop opens: Buy and Sell tabs, prices from value ×
   markup, cash then card, stock and till saved, midnight restock.
2. ~~**Haggling against the skill**~~ — done (D-040).
3. ~~**Meals and the condition loop**~~ — done (D-041). The bag on I; use
   what you carry; starving and exhaustion cost health; a collapse wakes you
   in the clinic, billed; the HUD's status corner.
4. ~~**Jobs, shifts and wages**~~ — done (D-042). The harbour, the worksite
   (casual), Kaisla's counter, the clinic; shifts as one batched step;
   standing and missed days; hired and quitting in conversation. People's
   own money is still not modelled (wages come from nowhere, gifts go
   nowhere) — later work, not M4.
5. ~~**The home as a base**~~ — done (D-043). A cupboard in the flat.
6. ~~**Basic quests and their UI**~~ — done (D-044). Four authored threads,
   one per background (the debt, the old face, the warehouse, the cover
   shift), plus errands people ask for when you offer to help; stages move on
   *deeds* Godot carried out, never on what a model said; the log on J states
   the goal and the days left, never the route.

**Nothing in M4 or M5 has been played by a person yet, only tested and
screenshotted.** Worth a play-through: work a shift, buy and haggle, offer
Pirjo help, pay Rauno back in parts, open the phone on P.

**M5 — The phone** (ROADMAP.md), sequenced:

1. ~~**The phone core**~~ — done (D-045). Its own window on P; contacts;
   messages people send when the simulation gives them a reason, held to quiet
   hours, per-kind gaps and three people a day; a text can ask something (an
   errand) and your answer is judged; saved (schema v6).
2. ~~**Writing in your own words**~~ — done (D-046). A text goes through the
   same intent, rules and effects as speech (`DialogueDirector._respond`);
   it is read when the person gets to it (awake, 07:00–22:00, sooner if idle)
   and answered as a text; cash cannot be sent by text.
3. ~~**Calendar and meeting requests**~~ — done (D-047). A fond friend
   suggests meeting tomorrow at an open public place; accepting schedules a
   reminder, the person heading over (`NpcSchedule.Override`) and the moment it
   is settled; kept or missed is read from where people stand. Not yet: the
   player proposing one, someone cancelling.
4. ~~**Map and banking**~~ — done. Banking (D-048): the ledger says when, the
   Bank tab shows the statement, money by text goes through the account, a
   cash machine in the corner shop. The map (D-049): what the player has
   learned — been to, or heard of — drawn on the phone, numbered, with the
   player on it and nobody else. The map shows what the player has learned, not the
   whole town (progressive revelation, M7); banking is the wallet's
   transaction log.
5. ~~**Calls, email, photos**~~ — done (D-050). Calls built: a conversation
   down a phone, the same road as speech, whoever is awake and not at work
   picks up. Email, photos and the criminal-contacts view are deliberately not
   built, with reasons in D-050. M5 is complete; 0.5.0.

**M6 — Consequences** (ROADMAP.md) is under way. The order was proposed to
the user (crime first) and work began on that; if they want a different order
they will say. (1) **Crime and the police** — done (D-051, D-052): theft at a shop
counter, judged against who is there; a crime exists only if someone saw it;
witnesses change their feelings, remember, and — if it matters enough to them
— tell the police later, secondhand; the police answer in proportion to what
they *believe* (nothing, a warning, a fine, an arrest), send for the player by
text, and weigh it at the desk — or, if ignored, without you and worse. Not
yet: being stopped in the street, confiscating what was taken, a court, other
crimes (assault waits for combat), a fence. (2) **Conflict resolution** — done in a first form
(D-053), and the shape was my call after the user said "continue": the
dialogue rules' reserved kinds `negotiate`/`persuade`/`ask_favor` now put an
*ask* — authored data with four graded outcomes (success, partial with a
cost, failure, backfire) from skill against difficulty on seeded dice. Two are
authored: more time from Rauno (interest, a delayed cost, on the debt) and
going easy with Marika (her leniency moves the weight of the case). More asks
are data; `deception` and `intimidation` have none to serve yet. (3)
**Turn-based combat** — done (D-054): you start a fight by saying so in
person; Attack, Heavy blow, Defend, Intimidate, Bandage, Run, Back down;
enemies are real people with builds from who they are and health that mends by
the hour; friends and officers step in; wounds last; assault is a crime by the
same machinery as theft, so the police respond to it. Not yet: people starting
fights with the player, allies, weapons and armour, death, sprites in the
window. (4) **Dynamic events** — done (D-055), and with it M6: once a day
the world asks what it already knows — who believes what of the player, who is
fond of whom, what is owed — and, with no dice and at most one step a day,
answers with a dismissal (an employer who believes something serious), a
grudge (a warning, then a time and place that, if kept, they start — the first
fights the player did not begin) or a collection (three reminders, then
someone stronger). The clinic now treats injuries. M6 is complete; 0.6.0.

**Next: M7 — Opening out** (ROADMAP.md): Old Town and Eastfield, travel,
progressive map revelation, factions with goals of their own, the main story
threads, more inhabitants, audio. It is the largest milestone and the first
with real *content* work (two maps, art, a story), so **start it by proposing
a shape and an order to the user** — and before it, **the game wants playing
by a person**: nothing from M4 to M6 has been seen at a keyboard, only tested
and screenshotted, and a play-through is the cheapest way to learn what the
tests cannot (pacing, what is confusing, what is dull). The criminal-contacts
   view waits for crime (M6).

**Known gaps worth a pass, none blocking:** interiors are still generic tiles
(the flat you wake up in included — Modern Interiors has the furniture);
the harbour quay is an empty apron; grass meets pavement at a hard line
because LimeZu has no transition art for that pair (D-031).

**The art is local only.** The user bought Modern Interiors and Modern
Exteriors (Modern Office not yet) and downloaded Serene Village (CC-BY 4.0).
The zips sit in the project root (git-ignored as `*.zip`). The 32 px sheets
are extracted to `art/_limezu_source/` (has `.gdignore`, so Godot skips its
~30 000 files). Six importers build `art/vendor/limezu/` from it — run all
six, then `godot --headless --path . --import`:

```
python tools/import_limezu.py            # character layers (D-020)
python tools/import_limezu_tiles.py      # pavement, road, walls, roofs (D-021, D-022, D-031)
python tools/import_limezu_props.py      # street furniture (D-022)
python tools/import_limezu_buildings.py  # whole buildings (D-024 to D-026)
python tools/import_limezu_places.py     # court, trees, benches, worksite (D-030)
python tools/import_limezu_terrain.py    # grass, sand, dock, shore and kerb edge sets (D-031)
```

Both `art/` folders are git-ignored: the licences forbid redistribution.
Without them the game and the tests fall back to the code-painted art (street
props and place decoration just don't appear). Credit LimeZu — the title
screen does (`CREDITS.md`). `Character Generator 2.0 Setup.exe` in the root
is the user's LimeZu tool; it has not been run.

**Interaction, briefly.** `Game.interaction_at(cell)` describes,
`Game.interact_at(cell)` acts (D-018). Buying and selling at counters is M4;
today a counter only tells you whether someone is serving. "Who is here" is
answered from the simulation (`NpcRegistry`), never from the bodies, which lag
it (D-017).

**Running it.** `godot --path .` boots to the title screen. In the world:
WASD/arrows, Shift runs, E (or Space) interacts, I opens the bag, C the bench for putting things together, J the quest log, P the phone (the cash machine is in the corner shop), F3 the
developer overlay; your bed saves. Harbourside's
two edge exits (top, x=42-45, to Old Town; right, y=31-34, to Eastfield) open
when you have what they ask (D-072); `--region=old_town|eastfield` on
`region_preview.tscn` looks at a district without walking there. `developer_mode: true` in
`user://settings.json` boots into `SimViewer` instead.

**Looking at things without a person at the window.**
`-- --screenshot=<path>` saves a frame and quits in any scene that calls
`DevCapture.maybe_capture`. In `world.tscn`: `[--advance=minutes]
[--at=x,y] [--interact=dx,dy] [--walk=x,y,seconds]` — at the 07:00 start
everyone is indoors; `--advance=180 --at=48,40` is the harbour mid-morning,
`--advance=930` is night. The map alone: `res://scenes/debug/region_preview.tscn`
with `--at=x,y --zoom=0.26`. The front end at any step:
`res://scenes/debug/ui_preview.tscn -- --screen=title|creation|opening|world
[--step=1-3] [--background=bg_dockhand] [--lines=n]`, and
`--screen=settings [--provider=anthropic] [--locale=fi]` (sandboxed: never
writes the player's settings), and `--screen=world --talk=npc_ida
"--say=Here's 50 euros." --overlay=1` for a conversation with the developer
overlay open, and `--screen=world --shop=loc_corner_shop [--selling=1]` for a
shop counter, `--screen=world --quests=1` for the quest log (pair with
`--background=bg_in_debt`), `--screen=world --phone=threads|thread|contacts` for the phone.

**Test runner.** A test fails if the engine logs an error during it (D-015),
and tests may `await`. Physics tests speed time up 8x (D-016); restore
`Engine` settings in `after_each` if you write another. The runner points
`Game.save_slot` at a test slot (D-033). `process_frame` fires *before* a
frame's `_process` calls — await it twice when a test needs one to have run
(D-034). Screens change scene through `_go()`; set `scene_changer` in a test.
The runner sandboxes settings (`Settings.persist = false`, defaults in
memory), the LLM client (`sandboxed`: offline provider only) and the secret
store (its own file) — D-036. A test that needs a model sets
`Game.dialogue.model` to a scripted one, as `test_dialogue_model` does;
`say_to_npc()` is a coroutine, so `await` it.

---

## What exists

| Area | State |
|---|---|
| Project setup, renderer, autoloads | done |
| Log, Events, Settings, Result, SafeJson, RngStreams | done |
| `GameClock` — real calendar, continuous and batched advance | done |
| `WorldEventQueue` — deterministic scheduled events | done |
| `WorldState`, `Region`, `Location`, varied unlock requirements | done |
| `DistrictMap` (maps as JSON rectangles), `ChunkStreamer` | done |
| `RegionView` + `RegionTiles` (real LimeZu tiles, themed by building kind, code-painted fallback), `RegionPreview` | done |
| `CharacterSprites`, `StreetProps`, `BuildingArt`, `PlaceArt` — real LimeZu people, street furniture, whole buildings and place decoration | done |
| `WorldView`, `PlayerBody`, `PlayerCamera`, `CharacterFigure`, `Game.move_player` (region exits too) | done |
| `NpcBodies` (pooled `NpcBody`), `NpcLook`, `DistrictMap.find_path` | done |
| Interiors, `Game.interact_at`, `Hud`, `InteractionText`, `interact` action | done |
| `Boot` → title; `SimViewer` behind `developer_mode` | done |
| Title screen, character creation (`CharacterDraft`), the opening, UI theme | done |
| `DayNight` — time-of-day tint and street lamp lights | done |
| Save point: your own bed; Continue on the title screen | done |
| `DataRegistry` — JSON content, validated, cross-referenced | done |
| `Npc`, `NpcRegistry`, `NpcSchedule`, `NpcNeeds` | done |
| `SimLod` + `NpcDirector` — four tiers, budgeted, region-indexed | done |
| `RelationshipGraph` — directed, five dimensions | done |
| `KnowledgeNetwork` — sourced facts, gossip, distortion, decay | done |
| `Reputation` — derived per scope, group-specific readings | done |
| `PlayerState`, `Wallet`, `Inventory` (weight-based) | done |
| Item icons: `ItemIcons`, `ItemSlot`, `data/item_icons.json` — 16x16, layered, recoloured | done |
| Crafting: `CraftRules`, `Game.craft`, `CraftWindow` (C), `data/recipes.json`, recipes found by holding the makings | done (61 recipes) |
| `Stats` (attributes, condition, injuries), `Skills` (use-based, 1–99) | done |
| LLM: router, budget, circuit breaker, 4 providers + offline, secret store | done; called by `say()` once the player configures it |
| Dialogue: `DialogueDirector`, `OfflineTopics`, `DialogueLines`, `DialoguePrompt`, `DialogueModel`, `DialogueBox`, `IntentPrompt`, `ConversationRules` | done |
| `MemoryBook` — what people remember of the player, bounded and summarised | done |
| `DevOverlay` (F3) — model calls, cost, intents, rules, memories, rejections | done |
| Shops: `ShopRegistry`, `ShopRules`, `HaggleRules`, `ShopWindow` — buy, sell, haggle, restock | done |
| Condition loop: `ItemRules`, `InventoryWindow` (I), collapse to the clinic, HUD status corner | done |
| Work: `data/jobs.json`, `Employment`, `WorkRules` — shifts, wages, standing, hiring by conversation | done |
| Home: the cupboard (`PlayerState.stash`, `StashWindow`) | done |
| Quests: `QuestLog`, `QuestRules`, `QuestText`, `QuestWindow` (J), `data/quests.json`, `data/errands.json` | done |
| Phone: `PhoneState`, `PhoneRules`, `PhoneDirector`, `PhoneText`, `PhoneWindow` (P) — contacts, texts both ways, errands by text | done (core, texting) |
| Meetings: `Calendar`, `MeetingRules`, `MeetingDirector`, the phone's Calendar tab | done |
| Banking: `BankText`, `AtmWindow`, the phone's Bank tab, transfers by text | done |
| Map: `MapView`, `PlayerState.known_places`, the phone's Map tab | done |
| Crime: `TheftRules`, `CrimeDirector`, "Pocket it" at counters, witnesses, reports to the police | done |
| Police: `PoliceRules`, summons by text, the desk, fines, arrest, the record | done |
| Asks: `AskRules`, `AskDirector`, `data/asks.json` — graded negotiation with a cost | done (two asks) |
| Combat: `CombatRules`, `Combat`, `FightDirector`, `CombatWindow` — turn-based, real people, lasting wounds, assault as a crime | done |
| Consequences: `ConsequenceRules`, `ConsequenceDirector` (dismissal, grudge, collection), hostile meetings, `ClinicRules` | done |
| Settings screen (language, provider, the player's key, models) | done |
| `SaveManager` + `SaveMigrations` | done |
| `Localization` — en complete, fi partial by design | done |
| `SimViewer` debug screen | done |
| Test suite + benchmark | done |

**Not started, by design:** email, photos and the
criminal-contacts view (D-050); everything in M7. See `ROADMAP.md`.

---

## Size

- 136 source files in `src/`
- 74 test suites
- 58 authored NPCs, 57 locations, 4 regions (all mapped), 35 interiors (16 are downtown's own floors), 25 schedules, 4 backgrounds, 13 shops (2 illicit, kept not walked to), 115 items, 61 recipes, 9 jobs, 4 quests, 6 errands, 4 asks (2 debt/leniency, 2 vouching)

---

## Performance baseline

Measured on the cloud dev container with `tests/benchmark.tscn`, half a game
day per run, including the periodic tier reassignment the game actually
performs. Re-run after any change under `src/npc/`, `src/time/` or `src/world/`.

```
-- spread across regions --
  people   active     local    us/minute    % of frame   skip 8h ms
      50       50        50        466.6         2.79%         0.66
     200       60       200        648.6         3.88%         2.45
    1000       60      1000       1150.5         6.89%        10.45
    3000       60      3000       2405.8        14.41%        30.96
```

Re-measured 2026-09-18 on the user's Windows machine after M2 steps 1 and 3:
numbers there run ~30-45% above the table (different hardware), and the
pre-change commit measured the same on that machine both times, so no
regression. Bodies and pathing are presentation-side and not in the benchmark.

Re-measured after D-047 (`NpcRegistry.scheduled_location_of`, off the
per-minute path), back to back with the previous commit on the same Windows
machine, which was ~12% slower than in the D-043 session: 635–642 / 853–883 /
1586–1600 / 3450–3529 µs per minute for 50 / 200 / 1000 / 3000 people, against
641–664 / 874–916 / 1604–1616 / 3577 for the commit before — no regression.

Re-measured after D-043 (a new map object kind) on the Windows machine:
567 / 796 / 1390 / 3188 µs per minute for 50 / 200 / 1000 / 3000 people —
below the D-030 numbers below, so no regression.

Re-measured again after D-030 relaid the map, back to back with the previous
commit on the same machine:

```
  people    before     after
      50     666.9     706.4   us/minute
     200     935.5    1084.2
    1000    1748.5    2051.7
    3000    3851.8    3980.0
```

3-17% dearer, from Harbourside gaining three locations (16 -> 19 in that
region): resolving where someone is walks the region's locations. The
property that matters is intact — cost per simulated minute is still flat in
total population. Worth remembering that adding places to a district is not
free, and that it is the *local* location count, not the world's, that pays.

The number that matters: cost per simulated minute is roughly flat in total
population once the local population is fixed, because dormant people are never
ticked and their positions are cached. A realistic district of ~200 residents
costs about 0.65 ms per simulated game minute — at the default one minute per
real second, that is well under one percent of a core.

The "% of frame" column is pessimistic on purpose: it compares one simulated
minute against one 60 fps frame, when that minute is really spread across
about sixty of them.

**Known scaling property.** The retier pass is O(people who could appear in the
player's region), not O(world). If one district ever holds thousands of
residents, that pass grows. The fix is more, smaller regions, which the design
wants anyway — not a cleverer director.

---

## Known issues and technical debt

2. **`NpcDirector.assign_tiers` fills `ACTIVE` in dictionary order.** With more
   than 60 people genuinely present in one region, the same 60 are always
   chosen. Not visible yet — no district is that crowded — but it will read as
   "the same crowd is always animated" once there are bodies. Bodies now
   exist, but ten residents cannot show it; fix when a district is crowded
   enough to see. Prioritise by distance and existing tier for stability.
6. **NPC bodies do not collide** with the player or each other, and two people
   whose ids hash to the same spot at a place stand on one cell. Cosmetic;
   revisit when crowds grow.
3. **Finnish translation is ~80% complete.** Deliberate: it exercises the
   fallback path and a test measures the gap. Finish it when the UI settles,
   not before.
4. **No LLM call has ever been made.** The whole path is wired and tested
   offline, but no real provider has been contacted — that needs the
   player's own key, entered by the player. Expect first-contact surprises;
   the parsers and model-specific request fields are the likeliest place.
   Only Anthropic's request fields were brought up to date (D-036); the
   other providers' suggested models were not revisited.
5. **`SimViewer` builds its UI in code.** Fine for a developer tool, wrong for
   real UI. Do not copy the pattern into M2 screens.

---

## Session continuity

```bash
# start of session
git log --oneline -15
godot --headless --path . res://tests/test_runner.tscn

# after changing simulation code
godot --headless --path . res://tests/benchmark.tscn

# after adding a new class_name
godot --headless --path . --import
```

**Git:** remote `origin` is https://github.com/ostar101/humptown.git, branch
`main`. Push at the end of every session.
