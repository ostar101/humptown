# Project status

**Updated:** 2026-09-19
**Milestone:** M3 — Conversation — **in progress** (steps 1–4 of 5 done). M2 complete (0.2.0).
**Build:** green. 517 tests, 7976 assertions with the LimeZu art installed,
~8.7 s. No leak warnings at exit any more.
**Engine:** Godot 4.5.1 stable, GL Compatibility renderer.

---

## Next task

**M2 is done.** Its "done when" holds: from the title screen you create a
character (background, look, name, pronouns, a two-point attribute
reshuffle), read a short opening written for that background, wake up in your
own flat, walk Harbourside while its people keep their routines, and sleep in
your bed to the next morning — which saves, so Continue on the title screen
brings you back. Day and night tint the world and light the street lamps.
The whole story is in DECISIONS.md D-019 to D-034 and the 0.2.0 changelog.

**M3 step 1 is done (D-035): talking to people, offline.** Face someone and
press E: the simulation decides whether they can be talked to, the dialogue
box opens, and typed lines are answered from authored lines by topic, in
English and Finnish. Every story NPC has their own voice; people only know
who they know; names are learned; time stands still while talking.

**M3 step 3 is done (D-036): the model behind the same `say()`.** When the
player has chosen a provider and saved their own key in the new settings
screen (title → Settings), people answer in their own words; the prompt is
a pure function of what that person is, sees, feels and believes
(`DialoguePrompt`, `DialogueDirector.prompt_context()`); a reply changes
nothing by itself; any failure falls back to the authored line. The
Anthropic provider speaks to current models (no `temperature` where it is
rejected, `effort: low`, thinking headroom, `refusal` handled). **No real
provider has been contacted yet** — the key is the player's to enter.

**M3 step 4 is done (D-037): what the player meant is a proposal.** Each
line is read — by the cheap model when there is one (`IntentPrompt`), by
words when not (`OfflineTopics`) — into an intent; `ConversationRules`
judges it (a pure function: effects or a refusal code); `DialogueDirector`
applies the effects; refusals emit `action_rejected`; the reply is told what
actually happened. Gifts of cash, compliments (capped per conversation),
insults and threats (remembered as witnessed facts that travel as gossip),
apologies, flirting, and introductions both ways all work offline too.

**Next: M3 step 5 — NPC memory with summarisation, and the developer
overlay.** The steps as planned:

1. ~~**Dialogue UI**~~ — done (D-035). As designed: a real scene in the house theme: portrait upper left,
   name, typewriter reveal, free text entry at the bottom, optional quick
   replies that never replace typing. Opened by `interact` on a person —
   which needs "who is standing on the faced cell" answered from the
   simulation (D-017: never from the bodies).
2. ~~Authored fallback lines first~~ — done with step 1.
3. ~~**Prompt assembly**~~ — done (D-036), with the settings screen and the
   Anthropic fixes.
4. ~~**Intent interpretation on the cheap model; validation in Godot**~~ —
   done (D-037).
5. **NPC memory** with summarisation, and the developer overlay (tokens,
   latency, cost, cache hits, selected memories, rejected proposals) (next).
   A conversation's transcript is transient (`Conversation`); what a person
   keeps of it should be a saved, bounded memory per NPC, summarised on the
   cheap model when one is available and by rule when not, and fed to
   `DialoguePrompt`'s `memories` key (empty today). Every `say()` result
   already carries `intent`, `happened`, `rejection`, `source` and
   `fallback_reason` for the overlay; `LlmClient.stats()` and `debug_log`
   have the rest.

A live provider needs the user's own API key, entered by the user in a
settings screen (`SecretStore`, D-006) — never by Claude. Everything above
is built and tested offline first.

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
writes the player's settings).

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
| Settings screen (language, provider, the player's key, models) | done |
| `SaveManager` + `SaveMigrations` | done |
| `Localization` — en complete, fi partial by design | done |
| `SimViewer` debug screen | done |
| Test suite + benchmark | done |

**Not started, by design:** NPC memory and the developer overlay (M3 step
5), buying and selling, quests, phone, combat, crime and police. See `ROADMAP.md`.

---

## Size

- 83 source files in `src/`
- 32 test suites
- 10 authored NPCs, 22 locations, 3 regions (1 mapped), 6 interiors, 8 schedules, 4 backgrounds

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
