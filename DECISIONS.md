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

## D-018 — An interior is a DistrictMap; interaction is one rule entry point

**Decision.** The inside of a building is authored in `data/interiors.json` and
built into an ordinary `DistrictMap` whose floor is the building's location.
`PlayerState.interior` says which map the player is on, and `Game.current_map()`
returns it. Interaction goes through two calls: `Game.interaction_at(cell)`
describes what is on a cell (for the prompt) and `Game.interact_at(cell)` acts,
returning a `Result`. The cell must touch the player's; the thing is found on
the map (door, interior exit, object) and its rule decides.

**Why.** Reusing the map type means drawing, chunking, routes, NPC bodies and
the movement rule work indoors with no second code path. One entry point keeps
the layering rule obvious: the HUD shows what `InteractionText` makes of the
result, and nothing in presentation decides whether a door opens.

**Rules chosen.** Your own home opens at any hour. Other private homes refuse
(`private`); invitations are M3/M4 material. Shops and civic places refuse
outside their authored hours (`closed`). A counter serves only if the
simulation has someone whose workplace it is, there, working; a person on a
break does not serve. Sleeping needs rest at or below 0.75 and wakes at 07:00.

**No save migration.** A save from before interiors has no `interior` field,
and every such save was made outdoors, so the empty default is correct.


## D-019 — Art direction: LimeZu's "Modern" pixel-art series, 32 px

**Decision.** The world and its people are drawn with LimeZu's Modern series
(itch.io): *Modern Interiors* (includes the character generator), *Modern
Exteriors* and *Modern Office*, at the 32×32 size, which matches
`DistrictMap.CELL_PIXELS`. Other packs are added only if they sit in the same
style. The game stays 2D; 3D (Kenney, KayKit, Quaternius) was looked at and
declined by the user (2026-09-18).

**Why.** It is the only affordable set found that covers modern everyday life
indoors and out in one consistent style, with a generator for many distinct
adult people. It fits the existing 2D seams (`RegionTiles`, `CharacterFigure`)
without reworking M2. Non-itch sources and non-pixel 2D were surveyed; nothing
comparable turned up.

**Licence.** Paid versions (from about $1.50 / $2.50 each): use in commercial
and non-commercial projects, editing allowed, credit to LimeZu required, no
resale or redistribution of the assets. Consequences: the credits screen must
name LimeZu; the raw pack files must not be committed anywhere others can download them.
The free version's licence is not stated on the page, so only the paid files
are used.

**Not decided yet.** Where the pack files live (a git-ignored `art/vendor/`
folder is the likely answer, since the GitHub remote may be public) and how tiles map onto
`RegionTiles` — both belong to the import step, after the user has bought the
packs.

## D-020 — People are LimeZu generator layers, chosen, never stored

**Decision.** `CharacterFigure` draws four layers from LimeZu's character
generator (body, eyes, outfit, hair) when the art is installed. Which layers a
person wears is computed by `CharacterSprites.look_for(id, palette)`: the id
picks the outfit and hair *style* (one hash per layer), and the palette NpcLook
already produces (authored for recognisable people, generated for everyone
else) picks the closest *colour variant* and the body's skin tone. Nothing new
is saved. The art lives in git-ignored `art/vendor/limezu/`, built by
`tools/import_limezu.py` from the purchased packs with a manifest, because the
licences forbid redistribution and an export cannot list `res://` folders.

**Why.** It keeps every existing look meaningful: an authored `look` in
`npcs.json` still says "red shirt, grey hair", and the sprite honours it. One
rule serves the player and every NPC. Four draw calls per visible person is
negligible; nothing composites images at runtime, which the headless test
renderer cannot do.

**Adults only.** The importer never copies the children's layers
(`*_kids`), and a test fails if any imported layer name mentions a kid. Also
left out: fantasy skins, animal-ear hair and the burglar mask, so a random
stranger never wears a costume.

**Fallback.** With no manifest, `look_for` returns `{}` and the figure is the
code-painted one from D-014. Tests pass either way.

**Colour matching note.** Layer colours are the mean of the front frame's
non-outline pixels. LimeZu's black hair is drawn blue-grey, so the importer
records blue-tinted hair as black; otherwise black hair came out brown.

## D-021 — Ground tiles and buildings: curated LimeZu, real where it fits

**Decision.** `RegionTiles` now blits real LimeZu tiles for `PAVEMENT`,
`ROAD`, `ROAD_LINE`, `FLOOR`, `WALL` and `ROOF`, and falls back to the D-014
code-painted tile wherever no real file is curated. `_real_file(terrain, v)`
is the whole seam; `tools/import_limezu_tiles.py` prepares the files it points
to, cropped or copied from the purchased packs into git-ignored
`art/vendor/limezu/tiles/`. `GRASS`, `WATER`, `SAND` and `DOCK` stay
code-painted, and so do the interior objects (`DOOR`, `COUNTER`, `SHELF`,
`BED`, `TABLE`, `SIGN`).

**Why ground and shop-front art were left out.** LimeZu's terrain sheets
(grass, water, sand) are built as edge-aware autotiles — dirt paths cutting
through grass, shorelines — meant for a level editor that picks a piece by its
neighbours. `RegionTiles` picks one of four variants per cell from a hash, with
no idea what is next door; used that way, autotile edge pieces produce
scattered triangles of the wrong terrain, not a border. Building fronts are
similarly unusable generically: the exterior pack's wall art is dozens of
named, themed shopfronts (bakery, gun store, condo), not a plain wall a
building of any size can be tiled with. Making either look right is a real
feature — neighbour-aware tiling, or per-building authored facades — not a
tile swap, so it is left for later rather than shipped half-working.

**What did fit, and why.** Sidewalk and asphalt singles, the Room Builder's
floor and wall swatches, and one roof shingle sheet are genuinely
self-contained flat tiles with no neighbour dependence, so the existing
per-cell model uses them exactly as it used the painted ones.

**Composited, not four separate files.** `WALL`'s four variants are not
random flavours; `coords_for()` gives each one a fixed meaning (facade,
facade-with-window, plinth, interior top-down). Rather than pre-bake a
windowed and a darkened copy, `_blit_real()` draws the window
(`_paint_window()`, shared with the code-painted fallback so that drawing
exists once) and darkens (`_darken()`) on top of the one real wall tile at
build time. `ROAD_LINE` is the one real composite baked in advance, at import
time: LimeZu's line-marking pieces are transparent decals meant to sit over
plain asphalt, so the importer composites a dash onto a plain tile once.

**Fallback.** Exactly like D-020: missing files mean `_build()` calls
`_paint()`, so the game and `test_region_tiles` pass with or without the art.

## D-022 — Buildings theme by kind; street furniture as decoration; player jitter fixed

**Decision.** Three independent fixes/additions, done together because the
user asked for them together:

1. **Building themes.** `Location.kind` (home/shop/bar/civic/work) picks a
   *theme* for a building's WALL, ROOF and DOOR (`RegionTiles.THEME_BY_KIND`).
   `DistrictMap.building_kind` (loc_id -> kind) is filled in by
   `WorldState.build_from()`, which is the only place that has both the map
   and the locations; `DistrictMap` itself stays geometry-only and does not
   know what a "kind" is. WALL and ROOF get one extra atlas row per themed
   pair (`RegionTiles.THEMED_ROWS`), holding that theme's real tile at the
   same columns the plain row uses; an untracked or unthemed kind (home, and
   anything `THEME_BY_KIND` does not list) draws the ordinary row, so most
   buildings need no extra art. DOOR has no extra row: it reuses its own
   row's variants 1-3, since a door was always drawn at variant 0 before.
   `tools/import_limezu_tiles.py` now exports one wall colour and one roof
   sheet per theme; "bar" has no roof file of its own and reads "home"'s
   (a red roof suits both). The code-painted fallback (`_paint()`) is themed
   too, from small colour tables, so a machine without the art still shows
   different buildings differently.
2. **Street furniture.** `StreetProps` places lamps, trash cans and hydrants
   on pavement that touches a road, chosen deterministically per cell (a
   different hash than `RegionTiles._hash()`, so the two don't correlate).
   Purely decorative: no collision, no interaction, nothing saved, and no
   code-painted fallback — skipping them when the art is missing is a
   legitimate look, not a broken one. `RegionView._populate()` spawns a
   `Sprite2D` per prop straight into the chunk's y-sort root, feet-anchored
   on its cell the way `CharacterFigure` anchors a person, rather than using
   the `chunk_shown` hook (decoration this cheap does not need its own
   listener).
3. **Player jitter.** The player moves in `_physics_process()` at the
   project's fixed 30 Hz, but the display renders faster (vsync to the
   monitor), so between physics ticks the engine had nothing new to draw and
   repeated the last frame — visible as a small stutter, worse the less
   evenly 30 divides the monitor's refresh rate. Fix: `physics/common/
   physics_interpolation` is now on project-wide, which is exactly the
   engine feature for this (interpolates a physics-tied node's rendered
   transform between ticks); `PlayerBody.place_at()` calls
   `reset_physics_interpolation()` so a teleport (spawn, load, entering a
   building) does not visibly glide from the old position. NPC bodies were
   never affected — `NpcBody` moves in `_process()`, not physics, already
   updating every rendered frame.

**Why interiors stay unthemed.** An interior `DistrictMap` has no
`buildings` entry for the building it is inside (it's the space *inside*
one, not a building placed on a larger map), so `kind_at()` is always ""
there with no extra plumbing — walking into a shop still shows the plain
cream interior. Worth theming later; not done now.

**Not decided yet.** A theme for every `Location.kind` (only shop/bar/civic
have their own look; work borrows civic's). Whether interiors should theme
too, and how, if so, DistrictMap would learn its own kind.

## D-023 — M2 step 5: the world is the main scene; region exits are walked, not pressed

**Decision.** `Boot.destination_scene()` picks `world.tscn` normally and
`sim_viewer.tscn` only when `Settings.developer_mode` is true — a static,
side-effect-free function so the choice is tested without instantiating
either scene. Region travel is wired: `Game.move_player()` checks
`DistrictMap.exit_at(cell)` before treating a move as ordinary, and if the
cell is on an exit, `_travel_to_region()` checks the destination is a real,
unlocked, mapped region and either moves the player there (spawn cell) or
refuses (`region_locked` / `region_unmapped` / `region_unknown`) exactly like
a blocked cell — `WorldView` snaps the player back on any refusal, no special
case needed. `WorldView._on_player_cell_changed` calls `show_current_area()`
when the result's kind is `"travelled"`, the same way it already does for a
building's `entered`/`exited`.

**Why walking, not a button.** A door is one cell you choose to open; a
region exit is the width of the map edge — you are always going to cross it
if you keep walking, so it behaves like stepping off the edge of the map, not
like using an object.

**Content-free on purpose.** Only Harbourside has an authored `DistrictMap`;
Old Town and Eastfield exist as `Region`s (mostly locked) with no map, so
walking to either of harbourside's two exits today reliably refuses with
`region_unmapped` once unlocked, or `region_locked` before that — proven by a
test that builds a throwaway destination map and confirms the success path
too. Authoring those regions is M7 ("Old Town and Eastfield. Travel."), not
this milestone; this is the plumbing that content will plug into.

**Also fixed while touching movement:** Camera2D is auto-promoted to physics
processing by Godot itself once `physics_interpolation` (D-022) is on
project-wide — a one-line engine warning the first time it happens, not a
bug; the camera's own lead/zoom smoothing in `_process()` is unaffected.

## D-024 — Homes are LimeZu's whole villa sprite, not generic per-cell tiles

**Decision.** A building whose `rect` is exactly `BuildingArt.SPRITE_SIZE`
(8x11 cells) and whose kind has a matching entry gets one real LimeZu house
image (`RegionView._build_building_art()`) drawn over its whole footprint,
picked per building from a small set by hashing its location id for variety.
Today that is every `home`-kind building except `loc_tuomas_flat`, whose plot
is only 5 cells wide (the street's north-south road is immediately east of
it) — it keeps the generic per-cell wall/roof/door from D-021/D-022, a real
building, just plainer, not a broken one. The per-cell atlas is otherwise
untouched: this is a second, independent seam (`BuildingArt`), not a
replacement for it, because most of the map (shops, civic buildings, the
generic fallback) still needs the atlas.

**Why not the modular per-cell wall art either.** Modern Exteriors' actual
shopfront art (e.g. `Ground_Floor_Shop_Modular`) is real, detailed brick and
window art, but every piece is themed to a specific trade and none of it is a
plain, reusable wall a building of arbitrary width can be built from — the
same problem D-021 already found with the flat-roofed condo/shop art.
`Villa`, by contrast, is a single complete house image, exactly the unit this
approach needs: pick one, draw it once, done. Nothing here is a generic
building kit; it is one specific asset used well.

**Why the rect had to change, not the art.** Stretching pixel art to fit an
arbitrary building footprint visibly distorts it, so the fix is on the data
side: `data/maps.json`'s home rects were resized to 8x11 (extending upward,
away from the street, to avoid colliding with neighbours or the road) and
their doors moved to column 3 of the rect, where the art's own doorway sits.
The source `Villa_N.png` is a 9x13-cell image with an empty 9th column and,
below the doorway, porch steps that would otherwise put the visual door one
row below where `DistrictMap` requires it (on the building's own front row);
`tools/import_limezu_buildings.py` crops to the 8x11 that keeps everything
lined up and drops only those steps.

**Why the sprite's y-sort key sits below its own bottom row.** Its own
WALL/DOOR cells are still drawn underneath, for their collision, and a
`TileMapLayer` cell's y-sort key can reach the bottom of that cell — tied or
lost against the sprite's key, those plain tiles showed through the art at
the very row it most needed to cover (the doorway). Placing the sprite's key
one pixel past the building's true bottom edge guarantees it always wins
against its own tiles; the cost is that someone standing exactly on the door
cell draws behind the house instead of in front of it, which reads far
better than a hand-drawn house with a strip of grey generic wall across its
front door.

**Fallback.** No installed file (`BuildingArt.sprite_for()` returns "") means
no sprite is added, and the building looks exactly as it did after D-022 —
proven by `test_building_art`, which runs, and asserts something, either way.

**Not decided yet.** Sprites for the other kinds (shop/bar/civic/work);
whether to also resize buildings of those kinds to fit whichever art is
chosen for them, the same way home was resized here.

## D-025 — Correction to D-024: the villa keeps its full porch

**Decision.** `BuildingArt.SPRITE_SIZE` is 8x13, not 8x11: the crop in
`tools/import_limezu_buildings.py` keeps the whole `Villa_N.png` (only its
empty 9th column is dropped), and the interactive door — the `DistrictMap`
cell someone presses interact on — is the cell at the *bottom* of the porch,
one row past where the art draws the doorway, rather than the doorway's own
row. The six resized homes in `data/maps.json` grew two rows taller
(downward this time, since they already reached as far up as row 1); the
street's pavement in front of them moved down to match, and the map's
`spawn` (which sat in what became the middle of the extended
`loc_player_flat`, silently blocking the whole map from building) moved with
it.

**Why.** D-024 shipped cropping off the bottom two rows so the visual
doorway would land exactly on the building's required front row. The user
tried it and pointed out the porch was missing — correctly: those two rows
were the porch's decking and steps, not filler. Placing the interactive door
one row further out than the drawn doorway costs nothing (a person walking
up to a porch stands at its base regardless of exactly which row the door
graphic occupies) and keeps the whole porch on screen.

**Lesson for the next whole-building sprite.** Building a map that
compensates for lost pixels (like D-024's original resize) is fragile
against a fix in the *art* import step: this correction touched the map, the
importer and `BuildingArt.SPRITE_SIZE` together, and separately, resizing a
rect that is already used as a `spawn` reference needs the reference checked
too — `DistrictMap.from_data()` and `test_region_map.test_every_authored_map_builds`
report exactly this if a spawn ends up inside a building, but the fix itself
is manual.

## D-026 — Shop, bar, civic and work buildings get a whole sprite too

**Decision.** `shop`, `bar`, `civic` and `work` share a second whole-building
sprite (`BuildingArt.FILES_BY_KIND`): a flat-roofed modern storefront from
Modern Exteriors' "Post Office" set, which happens to be exactly the same
8x13-cell size as the villa (D-024/D-025). Its signage says "POST OFFICE" in
every one of its four source colour variants, which is wrong on any other
building, so `tools/import_limezu_buildings.py` repaints the sign's accent
stripe and plate flat, in a colour per kind (`SIGN_COLOURS`), the same idea
`RegionTiles.THEME_WALL_COLOR` already used for the per-cell fallback, one
level up. The six affected buildings in `data/maps.json` (`loc_corner_shop`,
`loc_cafe_kaisla`, `loc_clinic`, `loc_police_post`, `loc_anchor_bar`,
`loc_warehouse_9`) were resized to 8x13 the same way the homes were; their
new doors sit at column 4 of the rect, where this building's entrance is
(the villa's was column 3 — a different building, a different column).

**Why one shared building, not four different ones.** Every whole-building
image found elsewhere in Modern Exteriors is either a specific, named shop
(Hardware Store, the Post Office itself) with the name baked into the art —
wrong for a building that plays a different role in this town — or, like the
`Ground_Floor_*_Modular` sets D-021 already ruled out, themed pieces with no
plain, reusable wall a building of arbitrary width can be built from. This
storefront was the one clean, unbranded exception once its sign was
repainted; sharing it across four kinds, distinguished only by colour, was
judged better than leaving three of them on the flatter D-021/D-022 look.

**Homes and shops share one street, and both grew.** Every building in this
row sits on the same north-south streets as the row of homes above or below
it, so resizing both rows to 13-cell-tall buildings ran the two into each
other in the middle — first caught as a map-build failure naming the exact
blocked cell, twice (once for the homes' own spawn point in D-025, once here
for the shops overlapping the homes). The fix both times was the same shape:
shrink the shared street to the one row of pavement the doorway actually
needs, and place each row of buildings to just clear the other, rather than
guessing at a gap. `test_region_map.test_every_authored_map_builds` and
`test_mapped_regions_place_every_location_and_reach_every_door` catch this
class of mistake immediately and by name; still, expect it again the next
time two authored building rows share a corridor and one of them grows.

**anchor_bar and loc_warehouse_9 sit against the main east-west road, not a
side street**, so unlike the shops they could not extend upward into it;
they extend downward instead, past their old front row by one cell, into
what was open ground (or, for the bar, the edge of the beach — a dockside bar
backing onto the sand is not an unreasonable thing to have built anyway).

**Fallback and scope, as before.** No installed file, and both the D-021/
D-022 per-cell tiles and the door's own themed colour still work exactly as
they did before this file existed. Nothing about `RegionTiles`' seam
changed; this is `BuildingArt` gaining more entries, not a new mechanism.

**Not decided yet.** A second building per kind for repeat visual variety
(today's five villas vs one storefront per other kind); theming interiors to
match (D-022's own "not decided yet").
