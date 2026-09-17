# Project status

**Updated:** 2026-09-17
**Milestone:** M1 — Foundation and simulation spine — **complete**
**Build:** green. 259 tests, 5766 assertions, ~0.4 s.
**Engine:** Godot 4.5.1 stable, GL Compatibility renderer.

---

## Next task

**Start M2: the world you can see and walk.** In this order:

1. A `Region` scene that loads a district's tilemap, with the chunk/streaming
   seam in place from the start (retrofitting streaming is painful).
2. `PlayerController` — movement, the angled top-down camera, collision.
3. `NpcBody` — a visual body attached when an NPC is promoted to `ACTIVE` and
   released on demotion. `NpcDirector` already emits `npc_tier_changed`; hook
   the pooling to that signal, do not poll.
4. Interaction system: doors, shop counters, objects worth touching.
5. Replace `scenes/boot.tscn`'s handoff so the main scene is the world, and put
   `SimViewer` behind developer mode.

Before writing scene code, read `ARCHITECTURE.md` on the layering rule.
Presentation reads state and emits input intent; it does not mutate the world.

---

## What exists

| Area | State |
|---|---|
| Project setup, renderer, autoloads | done |
| Log, Events, Settings, Result, SafeJson, RngStreams | done |
| `GameClock` — real calendar, continuous and batched advance | done |
| `WorldEventQueue` — deterministic scheduled events | done |
| `WorldState`, `Region`, `Location`, varied unlock requirements | done |
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

**Not started, by design:** rendering, player controller, camera, dialogue UI,
live LLM calls, quests, phone, combat, crime and police. See `ROADMAP.md`.

---

## Size

- 45 source files, 5836 lines in `src/`
- 2750 lines of tests across 14 suites
- 10 authored NPCs, 19 locations, 3 regions, 8 schedules, 4 backgrounds

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

**Git:** history is local. No remote is configured — the development
environment had no linked GitHub account, so nothing has been pushed. To
publish:

```bash
git remote add origin git@github.com:<you>/humptown.git
git push -u origin main
```
