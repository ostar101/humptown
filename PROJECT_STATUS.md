# Project status

**Updated:** 2026-09-18
**Milestone:** M2 — The world you can see and walk — **in progress** (steps 1–5 of 5 done; the rest of M2's list is unscheduled, see below)
**Build:** green. 365 tests, 6908 assertions with the LimeZu art installed
(6560 without), ~4-5 s.
**Engine:** Godot 4.5.1 stable, GL Compatibility renderer.

---

## Next task

**Step 5 is done (D-023).** `Boot.destination_scene()` sends everyone to
`world.tscn`; `Settings.developer_mode` (default off) is the only way to
`sim_viewer.tscn` now. Region exits are walked, not pressed:
`Game.move_player()` checks `DistrictMap.exit_at(cell)` and either travels
(unlocked, mapped destination) or refuses like a blocked cell would. Only
Harbourside has a map, so Old Town and Eastfield refuse today — authoring
them is M7 ("Old Town and Eastfield. Travel."), not this milestone.

**Homes now use LimeZu's actual house art, whole (D-024), not generic tiles.**
The user judged the generic per-cell buildings (D-021/D-022) ugly and asked
to look at how LimeZu's own art is meant to be used. It is not built from
reusable generic pieces at all — each house is one hand-drawn image with a
pitched roof, a porch, a balcony. `BuildingArt` uses one whole, for a
building whose `rect` is exactly its 8x13-cell size; `data/maps.json`'s six
similarly-sized homes were resized to fit (`loc_tuomas_flat`'s plot is too
narrow, so it alone keeps the generic look). Shops, civic buildings and the
bar are still the D-021/D-022 generic per-cell art — no equivalent whole-shop
LimeZu asset was found generic enough to reuse across different buildings;
see D-024 for what was tried and ruled out.

**Next: whatever's left of M2's list, not yet split into steps** — day/night
lighting; title screen, background selection, character creation, the
opening. These are UI-shaped, not engine-shaped, so plan the steps once you
look at them rather than guessing here. M2's "done when" (start a character,
walk Harbourside, watch routines, sleep to morning) needs the title/character
flow before it's true even though the world itself is walkable now.

**The art is local only.** The user bought Modern Interiors and Modern
Exteriors (Modern Office not yet) and downloaded Serene Village (CC-BY 4.0).
The zips sit in the project root (git-ignored as `*.zip`). The 32 px sheets
are extracted to `art/_limezu_source/` (has `.gdignore`, so Godot skips its
~30 000 files). Four importers build `art/vendor/limezu/` from it:
`python tools/import_limezu.py` (character layers, D-020),
`python tools/import_limezu_tiles.py` (ground/wall/roof tiles + building
themes, D-021/D-022), `python tools/import_limezu_props.py` (street
furniture, D-022) and `python tools/import_limezu_buildings.py` (whole-house
sprites, D-024); run all four, then `godot --headless --path . --import`.
Both `art/` folders are git-ignored: the licences forbid redistribution.
Without them the game and the tests fall back to the code-painted art (street
props just don't appear — they have no fallback, see D-022). Credit LimeZu
(`CREDITS.md`). `Character Generator 2.0 Setup.exe` in the root is the user's
LimeZu tool; it has not been run.

Done so far: region map + chunk streaming (step 1); player body, camera and
movement rules (step 2); pooled NPC bodies (step 3, D-017); interiors, doors,
counters, beds, signs, the `interact` action and the HUD (step 4, D-018);
art direction, the character/tile import pipeline, building themes, street
furniture and the movement-jitter fix (D-019 through D-022); the world as the
main scene, `SimViewer` behind developer mode, and region exits/travel
(step 5, D-023); whole-house sprites for homes (D-024, corrected in D-025).

**Interaction, briefly.** `Game.interaction_at(cell)` describes,
`Game.interact_at(cell)` acts (D-018). Buying and selling at counters is M4;
today a counter only tells you whether someone is serving. "Who is here" is
answered from the simulation (`NpcRegistry`), never from the bodies, which lag
it (D-017).

**Running it.** `godot --path .` (the project itself: `boot.tscn` now goes
straight to `world.tscn`) or `godot --path . res://scenes/world/world.tscn`
directly — WASD/arrows, Shift runs, E (or Space) interacts. Walking onto
either of Harbourside's two edge exits (top, near x=36-40; right, near
y=26-34) refuses today (`region_locked`/`region_unmapped`) since Old Town and
Eastfield have no map yet. Set `developer_mode: true` in
`user://settings.json` (or via `Settings.set_value`) to boot into `SimViewer`
instead. `-- --screenshot=<path> [--advance=minutes] [--at=x,y]
[--interact=dx,dy] [--walk=x,y,seconds]` saves a frame and quits (any scene
that calls `DevCapture.maybe_capture` — `SimViewer` does not). At the 07:00
start everyone is indoors; `--advance=180 --at=40,33` shows the harbour
mid-morning, and `--advance=120 --at=9,26 --interact=0,-1` walks into the
corner shop. The map alone: `res://scenes/debug/region_preview.tscn`.

**Test runner.** A test fails if the engine logs an error during it (D-015),
and tests may `await`. Physics tests speed time up 8x (D-016); restore
`Engine` settings in `after_each` if you write another.

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
| `CharacterSprites`, `StreetProps` — real LimeZu people and street furniture | done |
| `WorldView`, `PlayerBody`, `PlayerCamera`, `CharacterFigure`, `Game.move_player` (region exits too) | done |
| `NpcBodies` (pooled `NpcBody`), `NpcLook`, `DistrictMap.find_path` | done |
| Interiors, `Game.interact_at`, `Hud`, `InteractionText`, `interact` action | done |
| `Boot` — world by default, `SimViewer` behind `developer_mode` | done |
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

- 62 source files in `src/`
- 24 test suites
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
