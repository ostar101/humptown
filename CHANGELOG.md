# Changelog

All notable changes to Humptown. Format loosely follows Keep a Changelog;
versions are milestones rather than releases until there is something to release.

## [Unreleased] — Milestone 2: the world you can see and walk

### Added
- `data/maps.json` and `DistrictMap`: region layouts authored as rectangles
  (ground areas, buildings with doors, open-air places, exits), rasterised into
  a ground + structure grid with blocking, location lookup, anchors and
  reachability. Harbourside is mapped; every location in it has a place.
- `ChunkStreamer`: pure chunk-residency logic with hysteresis
- `RegionView` scene: draws a map one chunk node at a time around a focus,
  with collision on solid tiles and invisible walls at the map edge
- `RegionTiles`: a code-painted placeholder atlas behind a one-file seam
- `RegionPreview` developer scene with panning, zoom and a `--screenshot` mode
- `DataRegistry` checks maps place only their own region's locations and exit
  only to real regions
- `test_region_map`: 25 tests, including refusal paths and a content test that
  every mapped location is reachable from the spawn
- `World` scene: the region, the player's body and the camera, y-sorted
- `PlayerBody` (walk/run, collision against solid tiles and map edges),
  `PlayerCamera` (smoothed follow, slight lead, pulls back when running),
  `CharacterFigure` (a code-drawn person with four facings and a walk cycle)
- `Game.move_player()`: rules accept or refuse each cell the body enters and
  derive the player's location from the map; `Game.player_start_position()`
- Input actions `move_*` (WASD, arrows, left stick) and `run` (Shift, pad B)
- `DevCapture`: `--screenshot` and `--walk` for any scene
- `test_player_movement`: 12 tests, three of them driving a real body with
  physics

### Changed
- The test runner fails a test during which the engine logs an error, and
  awaits coroutine tests. Previously a crashing test was reported as passed.
- `PlayerState.position` is now the position on the region map

### Fixed
- `SimViewer` failed to compile under the strict warning settings (untyped
  `slice()` element in the scheduled-events panel)

## [0.1.0] — 2026-09-17 — Milestone 1: foundation and simulation spine

The world runs. Nothing is drawn yet, and everything that is claimed is tested.

### Added

**Foundation**
- Godot 4.5 project targeting the GL Compatibility renderer for low-end hardware
- Autoloads: `Log` (leveled, with secret redaction), `Events` (typed bus),
  `Settings` (persisted, keys excluded), `Game` (composition root)
- `Result` for operations that can be legitimately refused, `SafeJson` for input
  we do not control, `RngStreams` for named deterministic randomness

**Time**
- `GameClock` on a real Gregorian calendar, with continuous ticking for play and
  batched advancement for sleep and travel
- `WorldEventQueue`: a deterministic min-heap of scheduled world events, so
  things happen off-screen without being simulated

**World**
- `WorldState`, `Region`, `Location`; regions unlock through story, money,
  reputation, contacts, items, knowledge or skill, and each may differ
- `DataRegistry` loading validated JSON content with cross-reference checking

**People**
- `Npc`, `NpcRegistry`, `NpcNeeds`, and `NpcSchedule` as a pure function of time
- `SimLod` and `NpcDirector`: four simulation tiers, budgeted, with the awake set
  walked directly, candidates indexed by region, and resolved positions cached
  until the routine block ends
- Story NPCs protected from incidental death; ordinary deaths carry a cause

**Society**
- `RelationshipGraph`: directed, five dimensions, sparse
- `KnowledgeNetwork`: facts with provenance, gossip that spreads along social
  ties, losing confidence and gaining distortion with each retelling
- `Reputation`: derived per scope from what people actually believe, with groups
  reading the same act differently

**The player**
- `PlayerState`, `Wallet` (cash and bank), weight-based `Inventory`
- `Stats`: attributes, condition meters, persistent injuries
- `Skills`: use-based progression to level 99, with diminishing returns that
  make grinding a trivial task pointless

**AI**
- Provider abstraction with OpenAI, Anthropic, Google and OpenRouter adapters,
  built as pure request-builders and response-parsers
- `LlmRouter` for cheap/main routing and response caching
- `LlmBudget`: daily cap, rate limiting, circuit breaker
- `NullProvider` as a first-class offline mode
- `SecretStore`: encrypted local key storage, never in settings, saves or logs

**Persistence and presentation**
- `SaveManager` with verified writes that cannot destroy the previous save
- `SaveMigrations` with a versioned chain, in place before it is needed
- `Localization` from JSON; English complete, Finnish partial by design
- `SimViewer`: a debug screen showing the clock, the population, their routines,
  the event queue and the knowledge network

**Content**
- Harbourside plus two locked regions, 19 locations, 10 inhabitants with
  relationships, 8 shared routines, 4 distinct character backgrounds

**Verification**
- 259 tests, 5766 assertions, across 14 suites
- A benchmark measuring the real per-minute loop at 50 to 3000 inhabitants

### Notes

- Schedules were rewritten mid-milestone to use `@home` / `@work` tokens after
  the first version proved unscalable past a handful of people (see D-011)
- The director originally scanned the whole population every minute; the
  benchmark caught it, and per-minute cost is now flat in total population
