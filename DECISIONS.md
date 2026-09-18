# Architecture decisions

One entry per decision worth defending later. Newest last. Never edit a
decision in place — supersede it with a new one.

---

## D-001 — Godot 4.5 with GDScript

**Decision.** Godot 4.5.x, GDScript only, no C# and no GDExtension for now.

**Why.** GDScript compiles instantly, has no toolchain, and every contributor
can read it. The simulation work here is dictionary and integer manipulation,
not number-crunching; the benchmark shows a three-thousand-person town costing
a fraction of a frame. If a genuine hot spot appears later, GDExtension can
replace one class without touching the rest.

**Cost accepted.** GDScript's type inference gives up on `Variant` returns, so
annotations are needed in places one would rather not bother. Warnings are
treated as errors precisely to keep that honest.

---

## D-002 — GL Compatibility renderer

**Decision.** `renderer/rendering_method = "gl_compatibility"`, 2D MSAA off,
physics at 30 Hz.

**Why.** The stated target is an i3-class CPU with integrated graphics. The
Forward+ renderer assumes a discrete GPU; Compatibility targets exactly the
hardware in the brief, and a 2D JRPG loses nothing by it. This is a decision
to make now, because switching renderers after a hundred scenes exist is a
different and much worse job.

---

## D-003 — Four autoloads, everything else injected

**Decision.** `Log`, `Events`, `Settings`, `Game` are autoloads. No others.

**Why.** Autoloads are convenient and they are also global mutable state. Four
is enough: logging and settings are genuinely cross-cutting, the event bus is
how systems avoid holding references to each other, and `Game` is the
composition root where the world is assembled. Everything else is constructed
by `Game` and handed its dependencies, which is what makes the systems
testable in isolation.

---

## D-004 — Content is JSON, not Godot resources

**Decision.** Authored content lives in `data/*.json`, loaded and validated by
`DataRegistry`. Not `.tres`.

**Why.** Three reasons, in order of how much they matter. JSON diffs cleanly
in git, so a content change is reviewable. It needs no editor import step, so
headless tests load exactly what the game loads rather than a re-exported
approximation. And it can be generated or bulk-edited by tools, which matters
once the town is larger than a person wants to click through.

**Cost accepted.** No editor inspector for content, and no type safety until
load. Mitigated by validating every table on load and by
`validate_references()`, which catches the cross-file breakage that actually
happens.

---

## D-005 — Schedules are pure functions; position is computed, not simulated

**Decision.** `NpcSchedule.resolve(weekday, minute_of_day)` reads and writes no
state. Dormant NPCs are never ticked; their location is derived on demand and
cached until the routine block ends.

**Why.** This is the single decision that makes a large persistent population
affordable on weak hardware. The alternative — every NPC as a scene with an
agent that thinks on a timer — is what makes ambitious simulation games stutter.
The benchmark shows per-minute cost flat from 50 to 3000 inhabitants.

**Consequence to respect.** Anything that wants an NPC to be somewhere the
routine does not put them must go through an explicit `Override` with a time
window, not by writing `npc.location`. Overrides are how events bend a life
without corrupting the function.

---

## D-006 — API keys in an encrypted local file, and the honest threat model

**Decision.** Keys live in `user://secrets.dat`, encrypted with a passphrase
derived from `OS.get_unique_id()`. They never touch `settings.json`, saves,
logs or the repository. `Log.redact()` exists for anything that might be one.

**Why, and what this does not do.** The player owns the machine and the key is
theirs, so the game must be able to decrypt it unattended — which means a
determined local attacker can too. Claiming otherwise would be dishonest. What
this genuinely prevents is *accidental disclosure*: a key committed to git, a
save file sent to a friend, a `settings.json` pasted into a bug report, a
screenshot of a log. Those are the ways keys actually leak, and they are all
closed.

**Considered and rejected.** Windows DPAPI would be stronger but needs a
GDExtension for one file, and would still decrypt unattended for the same
reason. Not worth the dependency at this stage.

---

## D-007 — Providers are pure; transport is separate

**Decision.** `LlmProvider` subclasses only build requests and parse replies.
`LlmClient` owns all HTTP, retries, timeouts and deduplication.

**Why.** It makes the entire LLM stack testable with no network and no API key,
which is why 46 tests cover every wire format and error path on every run. It
also makes adding a provider one small file with no engine coupling. The
alternative — each provider doing its own HTTP — means the only way to test a
parser is to call a paid API.

---

## D-008 — Reputation is derived from knowledge, never stored as a number

**Decision.** No global notoriety value. Standing in a scope is computed from
what that scope's members actually believe, weighted by confidence and diluted
by how few of them have heard.

**Why.** The brief asks that a secret crime not affect public reputation. With a
stored counter that requires special cases everywhere something might be
witnessed, and one missed case silently breaks the promise. Deriving it means
secrecy works by construction: if nobody learned the fact, there is nothing to
derive from.

**Cost accepted.** Computing a standing walks the members of a scope. Cached and
invalidated on `fact_learned`, which is rare.

---

## D-009 — Migrations exist before there is anything to migrate

**Decision.** `SaveMigrations` ships at version 1 with an empty step table and a
test asserting every registered version has a reachable path.

**Why.** Save migration is never added retroactively in practice; what happens
instead is that early saves are declared unsupported. Writing the frame first
costs an afternoon and makes the first real migration a ten-line function.

---

## D-010 — A manual save is never destroyed by a failed write

**Decision.** `SaveManager` writes to a temporary file, reads it back, parses it,
and only then replaces the existing slot.

**Why.** Saving is manual and tied to places in the world, so consequences stick.
That design is only defensible if the last good save is safe. A write that fails
halfway must cost the player nothing but the save they were trying to make.

---

## D-011 — Symbolic location tokens in schedules

**Decision.** Schedule blocks may name `@home` or `@work`, resolved per NPC by
`NpcRegistry`.

**Why.** The first draft hardcoded each person's home into their routine, which
meant a near-identical schedule per inhabitant and made the data unscalable past
a handful of people. Tokens let one `sched_docks_early` serve every dockhand in
town. This was rewritten before any content depended on it, which is the cheapest
time to notice.

## D-012 — Maps are authored as rectangles in JSON and rasterised on load

**Decision.** A region's layout lives in `data/maps.json` as a list of ground
areas, buildings (footprint plus door) and open-air places, each a rectangle.
`DistrictMap` rasterises them into a two-layer cell grid. Godot `.tscn`
tilemaps painted in the editor are not the source of truth.

**Why.** It keeps D-004 intact: layouts diff cleanly, load headless, and are
validated like all other content. More importantly it ties every `Location` to
a physical place — a door cell, a street's rectangles — which NPC bodies,
interaction and the player's current location all need, and which an
editor-painted tilemap would only express implicitly. A content test proves
every location in a mapped region is placed and reachable from the spawn.

**Cost.** Rectangles are coarse. Decoration (props, fences, trees) will come as
a separate, optional list, not by making the rectangle format clever.

## D-013 — Chunks are separate nodes, streamed by a pure ChunkStreamer

**Decision.** Maps are cut into 16x16-cell chunks. `ChunkStreamer` decides
residency with Chebyshev distance and a one-chunk hysteresis margin;
`RegionView` gives each resident chunk its own node holding its tile layers.

**Why.** The brief requires region/chunk loading, and retrofitting it is
painful. Keeping the decision logic in a pure class makes it testable headless
and reusable for props and NPC pooling. A node per chunk means releasing a
chunk is one `queue_free`, taking its tiles, collision and anything parked
under it along. Hysteresis stops thrashing when the player paces a border.

## D-014 — The tile atlas is painted in code until art is chosen

**Decision.** `RegionTiles` paints its atlas procedurally at startup.

**Why.** No art has been chosen, and assets found locally were side-view packs
with unclear licences. The brief says to build systems independently of assets
and allow replacement without rewriting gameplay: `RegionTiles` is the entire
seam. Swapping in an authored atlas changes `tile_set()` and `coords_for()`
and nothing else.

## D-015 — A test during which the engine logs an error fails

**Decision.** The runner registers a `Logger` (Godot 4.5) and fails any test
during which an engine or script error was logged. Tests may be coroutines;
the runner awaits each one.

**Why.** GDScript cannot catch a runtime error: the test function just stops,
and until now the runner reported such a test as passed. That was found when
the first scene-based test crashed on every run and still showed `ok`. No
existing test was hiding an error when the check went in.

## D-016 — Player movement is reported per cell and ruled on by Game

**Decision.** `PlayerBody` moves with physics and, when it enters a new cell,
the world view calls `Game.move_player(position)`. Game refuses blocked cells
(`cell_blocked`, `region_unmapped`), otherwise records the position and
derives `PlayerState.location` from `DistrictMap.location_at()`, emitting
`location_exited` / `location_entered`. Out in town between places, the
location is empty.

**Why.** The layering rule: presentation emits intent, execution changes the
world. Reporting per cell rather than per frame keeps it to a few calls a
second. Physics keeps the body out of walls in practice; the rule still
decides, and a refused move snaps the body back to the last accepted spot.

**Physics tests** run at 8x time scale with 8x the tick rate, so each step is
still the game's own 1/30 s — the same collision behaviour, an eighth of the wait.

## D-017 — NPC bodies trail the simulation, and indoors means unseen

**Decision.** A body exists only for an ACTIVE or FOCUS person whose location
is an open-air place in the shown region, or who is walking between places.
When a routine moves someone, `NpcRegistry.move_to` changes their location at
once; `NpcBodies` hears `location_entered`, plans one route with
`DistrictMap.find_path` from where the body is (or from the door they leave),
and the body walks it. Arriving at a building or the region's edge returns the
body to the pool. After a time skip or a load, bodies are placed, not walked.

**Why.** Simulation owns where people are; presentation only shows it, so the
walk can lag the fact but never decide it. A route is planned once per
location change, never per frame, and following it is a few vector steps for
a body that is actually moving. Hiding people indoors is honest: until
interiors exist (M2 step 4) the alternative is everyone standing at their own
door all night.

**Cost.** For a few seconds the world says someone is at the shop while their
body is still on the pavement. Anything that asks "who is here" (dialogue,
interaction) must use the simulation, not the bodies. Bodies do not collide
with the player yet.

