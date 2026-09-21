# Project status

**Updated:** 2026-09-21
**Milestone:** M6 — Consequences — **complete in code (0.6.0)**. M5 complete (0.5.0). M5 complete in code (0.5.0).
**Build:** green. 892 tests, 10269 assertions with the LimeZu art installed,
~17 s. No leak warnings at exit.
**Engine:** Godot 4.5.1 stable, GL Compatibility renderer.

---

## Next task

**Newest (D-064):** buildings keep the ground they stand on, so roof corners show grass, not paving (roof collision verified and tested). **Before that (D-063):** the event feed moved to the bottom right as plain text, no panel; bag lines say "added to your bag".

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
WASD/arrows, Shift runs, E (or Space) interacts, I opens the bag, J the quest log, P the phone (the cash machine is in the corner shop), F3 the
developer overlay; your bed saves. Harbourside's
two edge exits (top, x=42-45; right, y=31-34) refuse today since Old Town and
Eastfield have no map yet (M7). `developer_mode: true` in
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

- 123 source files in `src/`
- 52 test suites
- 10 authored NPCs, 22 locations, 3 regions (1 mapped), 6 interiors, 8 schedules, 4 backgrounds, 4 shops, 14 items, 4 jobs, 4 quests, 3 errands

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
