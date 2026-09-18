# Changelog

All notable changes to Humptown. Format loosely follows Keep a Changelog;
versions are milestones rather than releases until there is something to release.

## [Unreleased] — Milestone 2: the world you can see and walk

### Decided
- Art direction: LimeZu's Modern pixel-art series at 32 px, staying 2D (D-019)
- People are drawn from LimeZu's character-generator layers, chosen per person
  from their id and palette; adults only; code-painted fallback (D-020)
- Pavement, road, floor, wall and roof are real LimeZu tiles; ground terrain
  (grass/water/sand/dock) and interior objects stay code-painted because
  LimeZu draws them as edge-aware autotiles or per-shop facades that this
  atlas's per-cell model cannot place correctly (D-021)
- A building's wall, roof and door look different by its `Location.kind`
  (shop/bar/civic/work); street furniture (lamps, trash cans, hydrants) on
  pavement next to a road; both real-art-only, code-painted fallback themed
  too for wall/roof/door; interiors do not theme yet (D-022)

### Added
- `tools/import_limezu.py`: builds the local, git-ignored `art/vendor/limezu/`
  (character layers + manifest) from the purchased packs
- `CharacterSprites`: picks a person's body, eyes, outfit and hair layers and
  the sheet frame for a facing; `CharacterFigure` draws them when present
- `test_character_sprites`: 7 tests, runnable with or without the art
- `tools/import_limezu_tiles.py`: builds the local, git-ignored
  `art/vendor/limezu/tiles/` (pavement, road, road line, floor, wall, roof)
  from the purchased packs
- `RegionTiles._real_file()`: the curated (terrain, variant) → tile mapping;
  `_blit_real()` composites the window and the top-down darkening onto the
  real wall tile so that drawing exists in one place for real and painted art
- `test_region_tiles`: 11 tests covering the curated mapping, theming and the darken helper
- `CREDITS.md`
- `tools/import_limezu_props.py`: builds the local, git-ignored
  `art/vendor/limezu/props/` (lamp, trash can, hydrant) from the purchased packs
- `StreetProps`: deterministic, collision-free placement of street furniture
  on pavement next to a road; `test_street_props`: 4 tests
- `DistrictMap.building_kind` / `kind_at()`; `RegionTiles.THEME_BY_KIND`,
  `THEMED_ROWS`, `DOOR_VARIANT_BY_THEME` give a themed building's WALL, ROOF
  and DOOR their own atlas rows/variants, real-art and code-painted alike

### Fixed
- The player's sprite stuttered slightly while moving: physics runs at a
  fixed 30 Hz but the display renders faster, so `physics/common/
  physics_interpolation` is now on project-wide, with
  `PlayerBody.place_at()` resetting it on teleport so spawning/loading/
  entering a building doesn't visibly glide from the old position
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
- NPC bodies: `NpcBodies` pools a `NpcBody` per ACTIVE/FOCUS person who is
  outdoors in the shown region, driven by `npc_tier_changed`,
  `location_entered`, `time_skipped` and `game_loaded` — never polled. People
  indoors have no body until interiors exist (D-017).
- `DistrictMap.find_path()` (AStarGrid2D, built once per map, no corner
  cutting), `standing_cell()` (a per-person spot at a place), `edge_cell()`,
  `is_building()`
- `NpcLook` and an optional authored `look` on NPCs; every named and story NPC
  has one, background people get a stable generated outfit
- `DevCapture`: `--advance=minutes` and `--at=x,y`
- `test_npc_bodies`: 15 tests
- Interiors: `data/interiors.json` authors the inside of each enterable
  building as a small `DistrictMap` (walls built around the edge, one door,
  furniture as `solids`, a `staff` spot). Six so far: the player's flat, the
  corner shop, Kaisla, the Anchor, the clinic and the police post.
- `DistrictMap`: terrains `floor`, `counter`, `shelf`, `bed`, `table`, `sign`;
  `objects` (counter, bed, sign) used from a neighbouring cell;
  `building_with_door()`, `object_at()`, `entry_cell()`, `is_interior()`
- `Game.interaction_at()` (describe) and `Game.interact_at()` (act): doors
  refuse `locked`, `private` and `closed`; counters serve only when the
  simulation has someone working there; your own bed sleeps you to 07:00 in
  one batched jump, with rest drifting as sleep; signs read. Every refusal
  emits `action_rejected`. `Game.current_map()`, `Game.staff_serving()`.
- `PlayerState.interior` (saved; absent in older saves, which means outside)
- `interact` input action (E, Space, pad A); `Hud` scene with a prompt that
  names the key and a timed message line; `InteractionText` for the wording
- NPC bodies inside: the people in the building you are in are shown, and
  whoever works there stands at the staff spot
- The camera centres a map smaller than the view (a room) instead of pinning
  it to a corner
- `DevCapture`: `--interact=dx,dy`
- `test_interaction`: 21 tests

### Changed
- The test runner fails a test during which the engine logs an error, and
  awaits coroutine tests. Previously a crashing test was reported as passed.
- `PlayerState.position` is now the position on the region map
- `PlayerBody.facing_for()` moved to `CharacterFigure.facing_for()`; the old
  name forwards
- `WorldView.show_current_region()` is now `show_current_area()`: it shows
  whichever map the player is on
- The player's hourly condition drift uses what they are doing (sleep while
  sleeping) instead of always idle

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
