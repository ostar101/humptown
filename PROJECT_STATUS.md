# Project status

**Updated:** 2026-09-18
**Milestone:** M2 — The world you can see and walk — **in progress** (steps 1–4 of 5 done)
**Build:** green. 345 tests, 6802 assertions with the LimeZu art installed
(6469 without), ~4 s.
**Engine:** Godot 4.5.1 stable, GL Compatibility renderer.

---

## Next task

**Next: M2 step 5 (main scene becomes the world).** Art direction is chosen
and mostly in: people (D-020) and pavement/road/floor/wall/roof (D-021) are
real LimeZu tiles; grass, water, sand, dock and the interior objects (door,
counter, shelf, bed, table, sign) are still code-painted (D-021 explains why
— they need real neighbour-aware tiling or per-building facades, not a tile
swap) and can be picked up later without touching anything else.

**The art is local only.** The user bought Modern Interiors and Modern
Exteriors (Modern Office not yet) and downloaded Serene Village (CC-BY 4.0).
The zips sit in the project root (git-ignored as `*.zip`). The 32 px sheets
are extracted to `art/_limezu_source/` (has `.gdignore`, so Godot skips its
~30 000 files). Two importers build `art/vendor/limezu/` from it:
`python tools/import_limezu.py` (character layers, D-020) and
`python tools/import_limezu_tiles.py` (ground/wall/roof tiles, D-021); run
both, then `godot --headless --path . --import`. Both `art/` folders are
git-ignored: the licences forbid redistribution. Without them the game and
the tests fall back to the code-painted art. Credit LimeZu (`CREDITS.md`).
`Character Generator 2.0 Setup.exe` in the root is the user's LimeZu tool;
it has not been run.

Done so far: region map + chunk streaming (step 1); player body, camera and
movement rules (step 2); pooled NPC bodies (step 3, D-017); interiors, doors,
counters, beds, signs, the `interact` action and the HUD (step 4, D-018);
art direction and the character/tile import pipeline (D-019, D-020, D-021).

5. Main scene becomes the world; `SimViewer` goes behind developer mode.
   Region exits (`DistrictMap.exit_at`) and region travel belong here too.
   The rest of the roadmap's M2 list (day/night lighting, title screen,
   background selection, character customisation) is not yet scheduled into
   steps; plan it after the art decision, since most of it is visual.

**Interaction, briefly.** `Game.interaction_at(cell)` describes,
`Game.interact_at(cell)` acts (D-018). Buying and selling at counters is M4;
today a counter only tells you whether someone is serving. "Who is here" is
answered from the simulation (`NpcRegistry`), never from the bodies, which lag
it (D-017).

**Running it.** `godot --path . res://scenes/world/world.tscn` — WASD/arrows,
Shift runs. The main scene is still the SimViewer until step 5.
E (or Space) interacts.
`-- --screenshot=<path> [--advance=minutes] [--at=x,y] [--interact=dx,dy]
[--walk=x,y,seconds]` saves a frame and quits (any scene that calls
`DevCapture.maybe_capture`). At the 07:00 start everyone is indoors;
`--advance=180 --at=40,33` shows the harbour mid-morning, and
`--advance=120 --at=9,26 --interact=0,-1` walks into the corner shop. The map alone:
`res://scenes/debug/region_preview.tscn`.

**Test runner.** A test fails if the engine logs an error during it (D-015),
and tests may `await`. Physics tests speed time up 8x (D-016); restore
`Engine` settings in `after_each` if you write another.

**Art is still undecided.** Tiles are painted in code (D-014). Local asset
packs found in `~/Downloads` (Sunnyside-style farm pack in
`godot-2d-topdown-template-main/Tekstuurit`, Craftpix "junkie-city"
gangsters) are side-view and of unclear licence, so they were not used.
Choosing an art direction is the user's call; ask before importing assets.

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
| `RegionView` + `RegionTiles` (code-painted atlas), `RegionPreview` | done |
| `WorldView`, `PlayerBody`, `PlayerCamera`, `CharacterFigure`, `Game.move_player` | done |
| `NpcBodies` (pooled `NpcBody`), `NpcLook`, `DistrictMap.find_path` | done |
| Interiors, `Game.interact_at`, `Hud`, `InteractionText`, `interact` action | done |
| `DataRegistry` — JSON content, validated, cross-referenced | done |
| `Npc`, `NpcRegistry`, `NpcSchedule`, `NpcNeeds` | done |
| `SimLod` + `NpcDirector` — four tiers, budgeted, region-indexed | done |
| `RelationshipGraph` — directed, five dimensions | done |
| `KnowledgeNetwork` — sourced facts, gossip, distortion, decay | done |
| `Reputation` — derived per scope, group-specific readings | done |
| `PlayerState`, `Wallet`, `Inventory` (weight-based) | done |
| `Stats` (attributes, condition, injuries), `Skills` (use-based, 1–99) | done |
| LLM: router, budget, circuit breaker, 4 providers + offline, secret store | done, **not yet called by anything** |
| `SaveManager` + `SaveMigrations` | done |
| `Localization` — en complete, fi partial by design | done |
| `SimViewer` debug screen | done |
| Test suite + benchmark | done |

**Not started, by design:** buying and selling, dialogue UI,
live LLM calls, quests, phone, combat, crime and police. See `ROADMAP.md`.

---

## Size

- 55 source files in `src/`
- 18 test suites
- 10 authored NPCs, 19 locations, 3 regions (1 mapped), 6 interiors, 8 schedules, 4 backgrounds

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

1. **Godot reports leaked ObjectDB instances at headless exit.** Harmless
   teardown noise from quitting with RefCounted objects live; the runner now
   unloads the world and waits a frame, which reduced but did not silence it.
   Worth five minutes once, not now.
2. **`NpcDirector.assign_tiers` fills `ACTIVE` in dictionary order.** With more
   than 60 people genuinely present in one region, the same 60 are always
   chosen. Not visible yet — no district is that crowded — but it will read as
   "the same crowd is always animated" once there are bodies. Bodies now
   exist, but ten residents cannot show it; fix when a district is crowded
   enough to see. Prioritise by distance and existing tier for stability.
6. **NPC bodies do not collide** with the player or each other, and two people
   whose ids hash to the same spot at a place stand on one cell. Cosmetic;
   revisit when crowds grow.
7. **HUD panels use the default theme**, with no padding. Deliberately left
   for the art pass, which should produce a UI theme alongside the tiles.
3. **Finnish translation is ~80% complete.** Deliberate: it exercises the
   fallback path and a test measures the gap. Finish it when the UI settles,
   not before.
4. **No LLM call has ever been made.** The stack is thoroughly unit-tested
   offline, but no real provider has been contacted. Expect the usual first
   contact surprises in M3; the parsers are the likeliest place.
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
