# Project status

**Updated:** 2026-09-19
**Milestone:** M4 — Making a living — **in progress** (step 1 of 6 done). M3 complete in code (0.3.0).
**Build:** green. 547 tests, 8223 assertions with the LimeZu art installed,
~9.5 s. No leak warnings at exit.
**Engine:** Godot 4.5.1 stable, GL Compatibility renderer.

---

## Next task

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
2. **Haggling against the skill** (next). A "Haggle" on a purchase: the
   `haggling` skill against the shopkeeper's own and how they feel about
   the player, rolled deterministically (`RngStreams`); success takes
   5–20 % off that item for the day, failure sours them a little and closes
   haggling on it until tomorrow; either way the skill gains experience.
   Rules pure and tested, like `ShopRules`.
3. **Meals and the condition loop.** Eating and drinking from the
   inventory (items already carry `hunger`, `sleep`, `intoxication`,
   `health`); hunger and tiredness felt in effectiveness; the HUD says so.
4. **Jobs, shifts and wages.** The background's job (dockhand, …) or one
   asked for; shifts at the workplace as batched time with pay, skill
   experience and condition cost; missed shifts have consequences. People's
   own finances start here (a gift still goes nowhere, D-037).
5. **The home as a base.** A stash at home; the bed already saves.
6. **Basic quests and their UI.** Authored threads (the backgrounds' story
   hooks: the debt, the contact) plus NPC-need-driven jobs; a quest log that
   states the goal without drawing the route.

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
WASD/arrows, Shift runs, E (or Space) interacts; your bed saves. Harbourside's
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
shop counter.

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
| Shops: `ShopRegistry`, `ShopRules`, `ShopWindow` — buy, sell, restock | done |
| Settings screen (language, provider, the player's key, models) | done |
| `SaveManager` + `SaveMigrations` | done |
| `Localization` — en complete, fi partial by design | done |
| `SimViewer` debug screen | done |
| Test suite + benchmark | done |

**Not started, by design:** haggling, meals, jobs, quests (M4), phone,
combat, crime and police. See `ROADMAP.md`.

---

## Size

- 88 source files in `src/`
- 35 test suites
- 10 authored NPCs, 22 locations, 3 regions (1 mapped), 6 interiors, 8 schedules, 4 backgrounds, 4 shops, 14 items

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
