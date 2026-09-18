# Project status

**Updated:** 2026-09-18
**Milestone:** M2 — The world you can see and walk — **in progress** (step 1 of 5 done)
**Build:** green. 284 tests, 5884 assertions, ~1.3 s.
**Engine:** Godot 4.5.1 stable, GL Compatibility renderer.

---

## Next task

**Continue M2 at step 2: `PlayerController`.** Step 1 (region map + chunk
streaming) is done. Remaining, in order:

2. `PlayerController` — movement, the angled top-down camera, collision.
   Collide against physics layer 1 (`RegionTiles.COLLISION_LAYER`). Call
   `RegionView.focus_on(camera centre)` every frame; it is free when the chunk
   has not changed. Turn on `y_sort_enabled` on the region root, each chunk
   node and the `Structures` layer so the player walks behind roofs — the
   layers were kept separate for exactly this. Movement is presentation
   emitting intent; the player's `location` in `PlayerState` should change
   through `Game`, using `DistrictMap.location_at()`.
3. `NpcBody` — pooled visual body for `ACTIVE` NPCs, driven by
   `npc_tier_changed`. Place bodies with `DistrictMap.anchor_of(location)`;
   every harbourside location has one.
4. Interaction: doors (door cells are solid now, interact from the anchor cell
   below), shop counters, objects.
5. Main scene becomes the world; `SimViewer` goes behind developer mode.

To look at the map now: `godot --path . res://scenes/debug/region_preview.tscn`
(arrows pan, wheel zooms). `-- --screenshot=<path>` saves a frame and quits.

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

**Not started, by design:** player controller, camera, dialogue UI,
live LLM calls, quests, phone, combat, crime and police. See `ROADMAP.md`.

---

## Size

- 50 source files in `src/`
- 15 test suites
- 10 authored NPCs, 19 locations, 3 regions (1 mapped), 8 schedules, 4 backgrounds

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

Re-measured 2026-09-18 on the user's Windows machine after M2 step 1: numbers
there run ~30-40% above the table (different hardware), and the pre-change
commit measured the same on that machine, so no regression.

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
   "the same crowd is always animated" once there are bodies. Fix when M2 makes
   it observable; prioritise by distance and existing tier for stability.
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
