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

## D-027 — Fix: RegionView y-sorts itself, in code, not per embedding scene

**Decision.** `RegionView._init()` now sets `y_sort_enabled = true` on itself.
Previously this was set only in `world.tscn`'s override of the `RegionView`
instance (now removed as redundant); `scenes/debug/region_preview.tscn`
instances the same scene without the override, and never got it.

**Symptom, and why it looked like an art bug.** The user reported "there are
remnants of an old house behind the buildings" from a `region_preview`
screenshot: villas and storefronts showed the plain per-cell WALL/ROOF/DOOR
tiles (D-021/D-022's real, themed tiles, not the D-014 fallback — it only
*read* as leftover construction) with no whole-building sprite over them,
even though a debug log confirmed `BuildingArt.sprite_for()` was returning
the correct file for every one of them. The sprite nodes existed; they just
weren't drawing on top.

**Root cause.** `RegionView._build_building_art()` adds one `Sprite2D` per
qualifying building directly as its own child, once, in `show_map()`. Chunk
roots (`Chunk_X_Y`, holding the per-cell `TileMapLayer`s) are added later,
as the streamer loads them around the camera, in `_populate()` — also as
`RegionView`'s own children. Godot only compares siblings by y-position when
their *shared parent* has `y_sort_enabled` on; nested y-sort composes down
the tree, but does not start partway down it. With `RegionView` itself not
y-sorted, its direct children draw in child order, i.e. whichever was
`add_child`-ed most recently wins — so any chunk streamed in after a
building's sprite was created simply painted over it, regardless of the
sprite's carefully-placed sort key (D-024's `sort_y` comment). `world.tscn`
happened to override `y_sort_enabled` on its `RegionView` instance, which is
the only reason the real game (`world.tscn`) never showed this; the
developer-only `region_preview.tscn` did not, and did.

**Why fix it in `_init()`, not by adding the override to `region_preview.tscn`
too.** The missing override was the actual bug: nothing before this made it
part of `RegionView`'s own contract that it must be embedded with y-sort on,
so the next new scene that instances it (or a forgetful edit to an existing
one) reproduces the exact same failure silently — no test caught this,
because `test_building_art`'s integration test only checks that the sprite
*node* was created, not how it draws relative to its siblings. Setting it on
self removes the possibility of forgetting.

**Lesson.** A visual bug that survives a passing debug log pointing at the
correct data is a draw-order bug, not a logic bug — check what actually
controls sibling z-ordering (`y_sort_enabled` on the *parent*) before
re-checking the logic that already proved itself correct.

## D-028 — A whole-building sprite owns its own footprint, porch included

**Decision.** Three changes that together make a drawn building and the map
agree, after the user reported brickwork behind finished houses, doors you
could not line up with, and porches you could not walk onto:

1. **A covered building draws no per-cell tiles.** `BuildingArt.covers()` says
   whether a cell is inside a building drawn as one whole sprite;
   `RegionTiles.coords_for()` then returns `hidden_coords()` — one extra atlas
   row that is fully transparent but carries the same collision box as the
   wall it stands in for. The cells still block, still path and still collide;
   they simply draw nothing.
2. **The art dictates the door column.** `BuildingArt.door_column(kind)` is
   where that building draws its own front door (2 for the villa, 4 for the
   storefront), and `test_building_art` fails if an authored building whose
   rect matches the art puts its door anywhere else. Six homes moved a column.
3. **A porch is not part of the building.** `BuildingArt` splits the image's
   `cells` from the `footprint()` a map authors: `porch_rows` (2 for the
   villa, 0 for the storefront) are drawn by the sprite *below* the rect and
   stay ordinary walkable ground. The six villa-sized homes shrank from 8x13
   to 8x11, the sprite still draws all thirteen rows, and the two it now
   overhangs are the decking someone walks up to reach the door.

**Why the brickwork was there at all.** A pitched roof is not a rectangle:
`home_1.png`'s top row is 0-75% opaque across its eight columns and its second
row 25-100%. D-024 stamped `Terrain.ROOF` across the building's whole rect and
drew the sprite over it, so the generic red shingle showed through exactly
where the villa's roof sloped away — reading, correctly, as the ruins of an
older building behind the new one.

**Why not simply skip the cell.** Those cells are what make a building solid:
the tile's collision polygon is the physics the player walks into. Dropping
them would have meant rebuilding collision somewhere else (a body per
building) for no gain. A transparent tile keeps one rule — `coords_for()` says
what a cell looks like — and changes only the pixels.

**Why the porch is walkable and the door sits on the drawn door.** D-025 put
the interactive door at the *bottom* of the porch, so the whole rect was solid
and the porch was scenery you could not step on; the door you pressed was two
rows below the door you could see. Making the porch ordinary ground fixes both
at once, and costs only that someone standing on it draws in front of the
railing they are technically behind.

**Consequence to respect.** `footprint()`, not the image size, is what a map
authors. Anyone adding a building kind with art must give it `cells`,
`porch_rows` and `door_column`, and `test_building_art` will hold the map to
all three.

## D-029 — Street furniture is placed by what a cell is, not by a hash

**Decision.** `StreetProps` no longer scatters a kind onto any pavement cell
whose hash matches. Each kind has a reason to be where it is:

- **lamp** — the back edge of a pavement strip (`is_back_of_pavement()`:
  pavement that does not itself touch a road but neighbours pavement that
  does), at a regular `LAMP_SPACING` interval along the street rather than a
  hashed one, and only where it has the headroom not to reach over a
  carriageway.
- **hydrant** — the same back edge, far rarer, on its own offset.
- **trash** — beside a building's entrance, two cells along the pavement from
  the cell you stand on to open the door, never on it.

`RegionView._prop_sprite()` also anchors a prop by its sprite's **bottom-left
cell**, not its bottom centre, while keeping the y-sort key on the cell itself.

**Why.** The user's report was that lamps, bins and hydrants stood in the
middle of the road. Two separate causes, both real:

1. `lamp.png` is two cells wide and four tall, with the pole in its left
   column and the arm reaching right. Centring that texture on its cell put
   the pole half a cell into the neighbouring tile — so every lamp was
   literally standing off its own kerb.
2. Even correctly anchored, a four-cell-tall prop drawn rising up the screen
   covers the three cells above it. On the pavement *below* a carriageway
   there is no cell it can stand on whose light does not land on the road.
   `has_headroom()` refuses those, so a street is lit from whichever side has
   the room — which is how plenty of real streets are lit anyway.

**Why regular spacing instead of a hash.** A hashed interval clumps: the old
`spacing: 6` produced runs of three lamps and then twenty empty cells, which
reads as litter rather than lighting. `(x + y) % spacing` is regular along a
row *and* along a column, so one rule lights a horizontal and a vertical
street evenly without knowing which it is on.

**Cost accepted.** The pavement south of the main road has no lamps at all,
and bins only appear where a door's approach is genuinely pavement — today
that is the bar and the warehouse, because the shop row's doors still open
onto the carriageway. That is a map bug, fixed separately; the placement rule
is right to refuse it.

## D-030 — Harbourside relaid, and open-air places get authored art

**Decision.** `data/maps.json` is rewritten: Harbourside grows from 80x64 to
96x72 and gains a second street, and three new open-air locations —
`loc_court` (a basketball court), `loc_harbour_park` and `loc_worksite` —
are placed on it. `PlaceArt` furnishes them from
`tools/import_limezu_places.py`'s output, and `RegionView._build_place_art()`
draws it.

**Why the map had to grow.** The shop row's doors opened directly onto the
carriageway: their rect ended on row 27 and row 28 was road, so
`anchor_of()` — the cell an NPC or the player must stand on to use the door —
was in the middle of the street. Squeezing a pavement in front of them was
impossible in the old 28-row band, because two rows of 13-cell buildings plus
a villa's porch plus two streets do not fit in it. Rather than shave
buildings to fit a number chosen before any of this art existed, the band was
made the size the town actually needs:

```
 1..11  homes            12..13 porches     14..15 the residential lane
16..28  shops and the three new places      29..30 the shopfront pavement
31..34  the main street (line on 32)        35..36 pavement
37..49  the bar and the warehouse           50..51 pavement
52..57  sand and dock                       58..71 water
```

**Why a separate `PlaceArt` rather than more `BuildingArt`.** A building's art
has to agree with the map about where its door and walls are, which is why
`BuildingArt` carries a footprint, a door column and porch rows. A place is
walkable ground whatever is drawn on it, so its art is pure decoration
authored per location id, blocking nothing — the same bargain `StreetProps`
already makes. The one wrinkle is `flat`: the court's painted surface is
ground, not an object, so it sorts from its top edge and a player standing
anywhere on it is drawn on top rather than underneath.

**Content consequences.** `locations.json` gains three entries with a new
`kind` of `park`, `locale/en.json` their names, and `loc_dock_street`
connects to all three. `test_region_map` already required every location in a
mapped region to be placed and reachable, so the three had to be real places
on the grid, not scenery — which is the right constraint: a park nobody can
walk into is a painting.

**Cost accepted.** Decoration does not block, so a tree can be walked
through, exactly as a lamp post can (D-022). Worth revisiting when there is a
reason for trees to be solid; not worth a new solid terrain today. The
harbour quay is still a large empty apron, and every terrain boundary is a
hard straight line — both of those are the next job, not this one.

## D-031 — Ground terrain is real art, and meets its neighbours

**Decision.** Three related changes, all to how the ground is drawn:

1. **Real plain tiles** for `GRASS`, `SAND` and `DOCK`, from
   `tools/import_limezu_terrain.py`. This closes the part of D-021 that left
   them code-painted.
2. **Edge sets.** A terrain that has to meet a different one gets its own
   `TileSetAtlasSource` holding a 4x4 block: column 0 its western edge, column
   3 its eastern, row 0 its northern, row 3 its southern, and the four middle
   cells its open interior. `RegionTiles.edge_coords()` picks one from a
   four-neighbour test. Three sets today: the sea against a beach, the sea
   against the quay, and asphalt against a pavement kerb.
3. **The sea moves.** LimeZu's sea tileset is eight animation frames of that
   same 4x4 block, laid out one block apart, so the whole animation is
   `set_tile_animation_separation(coords, (3, 0))` and a frame count —
   Godot plays it with no code of ours per frame.

**Why edge sets are separate sources rather than more atlas rows.** Sixteen
tiles times eight frames is 128 columns; widening the shared procedural atlas
to hold them would make it around 4096 px wide, which is the texture limit on
the integrated graphics D-002 targets, for the sake of one terrain. A source
per set costs nothing and keeps the procedural atlas exactly as it was.
`RegionTiles.ground_tile()` returns `(source, column, row)` so one call
answers both halves of `set_cell()`.

**Why a four-bit mask and not Godot's terrain system.** `set_cells_terrain_connect`
wants to own the TileMapLayer's contents and works from a painted map;
Humptown rasterises its map from rectangles every load (D-012) and decides
per cell what to draw. A mask computed in `coords_for()`'s neighbour is the
same idea at a fraction of the coupling. The cost is that inner corners — a
diagonal neighbour differing while all four orthogonals match — have no tile
of their own; LimeZu draws those, and they can be added when a map has a
shape that needs them.

**Out of bounds counts as the same terrain,** so the sea runs off the edge of
the world rather than washing up against an invisible wall at the map border.

**The wrong tile, found while doing this.** `import_limezu_tiles.py` had been
importing `Sidewalk_N_10` as the pavement since D-021. In a Sidewalk set,
piece 9 is the pavement and piece 10 is the asphalt it borders — so every
pavement in town had been drawn in road grey (luminance 82 against the real
pavement's 204), which is why the streets read as one undifferentiated
expanse. All four variants now come from `Sidewalk_1_9`, the same set the
kerb pieces are cut from, because a kerb running into a differently-coloured
slab reads as a mistake.

**Also chosen by looking rather than guessing:** only `Props_Grass_9` and
above are transparent clumps — 1 to 8 are whole tiles with a patch drawn in,
which tile into a chequerboard — so one clump goes on one grass variant in
four. And the quay uses a single plank tile: the pier set's four decks differ
in which planks are darker, and picking among them per cell turned a
boardwalk into vertical stripes.

## D-032 — Day and night: a tint from the clock, and lamps that are lights

**Decision.** M2 step 6. `DayNight` is a pure function from the minute of day
to a colour, laid over the outdoor world by a `CanvasModulate` in
`world.tscn`; street lamps carry a `PointLight2D` whose energy follows how
dark that tint is. `WorldView.refresh_daylight()` applies both on every game
minute, on a time skip, on load and whenever the shown area changes. Inside a
building the tint is white and the lamps are off.

**Why a CanvasModulate and lights, rather than a darkening overlay.** A
`CanvasModulate` multiplies everything drawn in the world and leaves the HUD's
own `CanvasLayer` alone, which is exactly the split wanted. Lights are the one
thing it does not dim, so a lamp is a real light pooling on the pavement
rather than a painted glow that would itself be darkened by the night. Nothing
is stored or saved: a game loaded at 23:00 is dark because it is 23:00.

**Why lamps follow the tint and not the clock.** `lamp_energy_for(tint)` ramps
from off to full as the tint's brightness falls from 0.86 to 0.45. Tying the
lamps to the darkness instead of to their own hours means no lamp can burn in
daylight or sit dark under a night sky however the keyframes are retuned, and
a test proves it for every five minutes of the day.

**Cost.** A lamp at zero energy is *disabled*, not merely dark, so the daytime
town pays nothing for lights nobody can see. At night each resident chunk has
a handful of lights (lamps stand ten cells apart); refreshing them is once a
game minute, never per frame, which the performance rules ask for.

**The keyframes** suit the calendar the game starts on — early March at
sixty degrees north: light by seven, golden around half past six in the
evening, properly dark by nine. `test_day_night` holds them to a
per-minute change no larger than 0.02 in any channel so nothing ever flashes.

**Not done.** Windows lit from inside at night, and the region preview tool
(which shows the map, not a moment in time) stays in daylight.

## D-033 — A character is a validated draft; your own bed is the save point

**Decision.** Everything the player chooses before the world exists is a
`CharacterDraft`: a background, a name, pronouns (they/she/he), a look, and a
reshuffle of the background's attributes — at most two points taken and
given back elsewhere, none leaving [3, 8]. `Game.new_game_from(draft)`
validates it against the content before building anything, and a refused
draft builds nothing. A new life starts indoors in the player's own flat.
Sleeping in your own bed now writes the life's one save (`Game.save_slot`),
which the title screen's Continue reads.

**Why a draft and not a screen that writes PlayerState.** The creation
screens are input; the layering rule says input proposes and Godot decides.
The draft also has the rules for editing it (`lower`, `raise`), so the screen
can never display a combination `validate()` would refuse — only an
unfinished one, which Next will not pass.

**Why only a reshuffle.** The plan says a background may be customised
"within reasonable limits". Two points is enough to make a dockhand a clever
one and not enough to stop them being a dockhand; backgrounds stay distinct
starting lives rather than presets to be optimised away.

**Why the look is colours and style ids, not sprite files.** An appearance is
`{"skin": "#…", "hair": "#…", "shirt": "#…", "hair_style": "05",
"outfit_style": "12"}` — the vocabulary an NPC's authored `look` already
uses. It means the same thing with the LimeZu art installed or not (the
code-painted figure wears the colours) and survives the art being re-imported
under other file names. Where the art is installed, the colours offered are
the ones the chosen style is actually drawn in, so a swatch never promises
something the sprite cannot wear, and trousers are not offered at all
because LimeZu's outfits include them.

**Why the bed.** D-010 says saving is manual and tied to places, so that
consequences stick. Your own bed is the most natural such place, it is
already the only thing that ends a day, and it makes Continue mean something
in M2 rather than a button that never lights up. One slot, for now; more is a
settings-screen question, not an M2 one.

**Tests never save over the player's life.** The runner points
`Game.save_slot` at a test slot and deletes it at the end, and a test fails
if that ever stops being true.

## D-034 — The way in: title, creation, opening; a project-wide UI theme

**Decision.** M2's last item, as the design plan orders it:
`Title -> Choose Background -> Customise -> Confirm -> Short Opening -> Free
World`. `Boot` now hands off to `title_screen.tscn` (SimViewer stays behind
developer mode). The title and creation screens sit over `TitleBackdrop` —
Harbourside itself at dusk, drawn by the real `RegionView` from content,
without starting the simulation, the camera drifting down the main street.
The opening is a few authored lines per background, one per key press,
ending on a shared line, then a fade into the world. A project-wide `Theme`
(`scenes/ui/humptown_theme.tres`, set in `gui/theme/custom`) styles every
Control, the HUD included.

**Layout in scenes, rows from content.** PROJECT_STATUS has long said SimViewer's
built-in-code UI is not a pattern for real screens. The creation screen's
layout is entirely in its `.tscn`; the repeated pieces — a card per
background, a row per look choice and per attribute — are hidden templates
in that scene, copied and filled from content. Adding a background needs no
code.

**The theme borrows LimeZu's own UI colours.** `UI_32x32.png` is speech
bubbles, cursors and icons rather than panels, so the theme is flat
StyleBoxes in the same lavender-white and ink as those bubbles, pixel-crisp
(no anti-aliasing), with a gold focus ring so the whole front end can be
driven by keyboard. The title screen carries the LimeZu credit line
CREDITS.md asks the game itself to show.

**Scene changes are injectable.** Each screen changes scene through `_go()`,
which a test replaces with a recorder. Without that, pressing Begin in a test
would replace the test runner's own scene.

**Opening text is authored, not generated.** It is the first thing anyone
reads; it has to be right offline, on the first run, before any provider is
configured.

**A test-order hazard found on the way.** `SceneTree.process_frame` fires
*before* the frame's `_process` calls, so a test that awaits it once only
sees a `_process` pass if the runner happened to resume it after the previous
frame's. A new test awaiting a timer shifted that phase and broke an old
world-scene test; the old test now awaits two frames, which holds wherever
the runner resumes.

**Not done.** Interiors are still generic tiles (the flat you wake up in
included); a settings screen (language, AI provider) and multiple save slots
are later.

## D-035 — Talking to people works offline first; the rules decide who can be talked to

**Decision.** M3 step 1. Pressing interact while facing someone opens a
conversation: `WorldView` finds the body on the faced cell (presentation's
half), `Game.start_conversation(npc_id)` decides whether that person can be
talked to (the simulation's half), and `DialogueBox` shows it the way the
design plan describes — portrait and name upper left, words appearing a
letter at a time, free text at the bottom, a few quick replies that never
replace typing. With no model involved at all, `OfflineTopics` recognises
what a typed line is about (a greeting, a goodbye, thanks, who someone is,
what they do, a person, a place — in English and Finnish) and
`DialogueLines` answers from authored lines: every story NPC has a voice of
their own, everyone else speaks generically.

**Why offline first.** The roadmap's "done when" includes unplugging the
network without breaking the game, and the plan asks that the game remain
functional with no key, no provider and no connection. Building the whole
loop — who can be talked to, what they say, what it changes, how it looks —
against authored lines means the model, when it arrives, is an enhancement
behind the same `say()`, and offline play is the version that already works
rather than an error path.

**Who can be talked to is the simulation's call (D-017).** Someone asleep
stays asleep. Someone the simulation already has inside a building, while
their body is still walking there, is "on their way somewhere and doesn't
stop" — which is both true and a reasonable thing for a person to do.
Refusals are rejected proposals like any other and emit `action_rejected`.

**Even offline, people only know who they know.** Asked about another person,
someone answers from their own relationship to them: Ida knows Tuomas, and
says so; she has never met Joonas, and says that. It is the knowledge rule in
its smallest form, and it holds before any model is involved.

**Names are learned.** The prompt and the dialogue box call someone by name
only once the player knows it — a background contact, or someone met and
introduced (asking who they are is an introduction). Until then they are
their occupation, or simply "someone".

**Time stands still while two people talk.** The clock pauses for the
conversation and the minutes it took — one per thing said — are paid in one
step when it ends, the way sleep and travel are (D-005). Talking at all makes
both people a little more familiar with each other.

**Cost accepted.** The offline recogniser is deliberately modest: it notices
words, it does not understand sentences, and it will sometimes take a
question for small talk. It exists to be the floor, not to compete with the
model. Finnish inflection is handled by matching the first five letters of
longer place names ("satamassa" is the harbour), which is crude and enough.

## D-036 — The model speaks behind the same `say()`; what it is told is a pure function; no test can reach a provider

**Decision.** M3 step 3 of the roadmap list (prompt assembly), with what it
needs around it. `DialogueDirector.say()` asks a `DialogueModel` when one is
available and falls back to the authored line (D-035) when it is not, when
the call fails, or when nothing sayable comes back. The game's model is
`LlmDialogueModel` over `Game.llm`, so every line goes through the router,
budget, cache and circuit breaker built in M1. The base `DialogueModel` is
the offline one; tests script their own. `say()` is a coroutine now: the
dialogue box shows a quiet "…" while it waits, the clock stays paused, and a
reply that arrives after the conversation has ended is dropped.

**What the model is told is a pure function of a context dictionary.**
`DialogueDirector.prompt_context(npc_id)` gathers it from world state and
`DialoguePrompt.build(context)` turns it into an `LlmRequest`, so the prompt
is testable without any model: who they are (name, age, occupation, and a
new authored `bio` and `voice` for each story NPC), where they are and what
they are doing, the player as *they* see them (a name only if they know it;
the relationship numbers turned into feelings — the model is told "you do not
trust them", never a score), the people they know (their own relationships,
nobody else's), what they believe about the player (only their own
`KnowledgeNetwork` beliefs, each with how they came by it), memories (empty
until step 5), and the last twelve lines. The prompt is written in English
whatever the game's language; the model is told to answer in the language
the player writes in.

**The rules at the end are the anti-hallucination rule in the model's own
terms.** Speak only as yourself, out loud, one to three sentences; you know
what is written above and ordinary everyday things; never make up people,
places, events, prices or anything about the person in front of you; you
cannot hand over or promise what you do not have; never say you are an AI.

**A reply changes nothing by itself.** What a line *does* — familiarity, the
conversation ending — still comes from the player's own words through
`OfflineTopics`. The model cannot keep the player talking, grant anything or
move anyone. Turning words into proposals that Godot validates is the next
step (intent interpretation), not this one.

**What comes back is cleaned before it is shown.** Their own name as a
speaker label, stage directions in `*…*` or `(…)`, and wrapping quotes are
removed; a reply is cut at the last sentence that fits 420 characters.
Nothing left counts as a failure. Every fallback records why
(`timeout`, `refused`, `empty_reply`, `offline`, …) for the developer
overlay.

**The Anthropic provider speaks to current models.** Suggested models are
`claude-opus-5` and `claude-sonnet-5` (main) and `claude-haiku-4-5` (cheap).
Opus 5, Sonnet 5, Fable and Opus 4.7/4.8 answer `temperature` with a 400, so
it is sent only to the older families known to accept it — and never to a
model the code does not recognise, since a missing sampling parameter costs
nothing and a rejected one costs the reply. Models that take `effort` are
asked for `low` (Haiku 4.5 errors on it and gets none). Opus 5, Sonnet 5 and
Fable think by default and `max_tokens` caps thinking and answer together,
so they get 1024 tokens of headroom above the answer's budget; only what is
generated is billed. A `refusal` stop reason is a failure (`refused`, not
retried), not an empty line. The server-side `fallbacks` beta is not used:
a declined line falls back to the authored one, which is already graceful.

**The settings screen.** Reached from the title screen: language, provider,
the player's API key, the main and cheap model, routing. The key field is a
secret field; the key goes to `SecretStore` (D-006) and the field is emptied
the moment it is saved, so the screen only ever says *whether* a key is
stored. Choosing a provider fills in its suggested models unless the player
typed their own, and never leaves another provider's model behind. A status
line says whether people will answer in their own words and, if not, why
not — the same conditions `LlmClient.is_available()` checks. Once a provider
is chosen the screen says plainly that the key goes only to that provider,
that what the player says to people is sent there, and that each answer is
billed to the player's account. Changes apply at once.

**No test can reach a provider, or the player's own files.** The runner sets
`Settings.persist = false` and resets settings to their defaults in memory,
so tests neither depend on this machine's settings nor write them; sets
`LlmClient.sandboxed`, so `reconfigure()` builds only the offline provider
whatever a test configures; and gives the client a `SecretStore` at
`user://test_runner_secrets.dat`, cleared at the end. The first settings
test asserts all three, because every other settings test would otherwise
be writing over the player's own. `ui_preview --screen=settings` is
sandboxed the same way.

**Costs accepted.** No real provider has been contacted: the key is the
player's to enter, so first contact happens on their machine, and the
parsers are tested against the documented response shapes only. A prompt is
roughly 600–900 input tokens per line with no prompt caching yet — cheap at
these volumes, and caching is worth adding once the system text stops
changing turn to turn. The other providers' suggested model lists were not
revisited.

## D-037 — What the player meant is a proposal; the rules decide what it changes

**Decision.** M3 step 4. Every line the player says goes one way: an
interpreter says what the player *meant* (an intent), `ConversationRules`
judges it against the world and returns a `Result` — the effects to apply
and a plain sentence of what actually happened, or a refusal code — the
effects are applied by `DialogueDirector`, and only then does the person
answer, told what happened. A refused intent emits `Events.action_rejected`
and changes nothing; the line itself was still said, and the person reacts
to the attempt ("you don't have that on you").

**Two interpreters, one path.** With a model available, the cheap model
reads the line (`IntentPrompt`, purpose `INTENT`, so the router sends it to
the cheap model and caches it). Without one — or when it fails, or answers
with something that is not a small JSON object — `OfflineTopics` reads the
words, as before, now with more kinds. Lines plain enough that words settle
them ("hi", "thanks, bye": a greeting, thanks or goodbye in four words or
fewer) never reach the model: a model adds nothing to "hi" but cost and a
wait.

**The model never names an id.** Its answer is a kind and the person, place,
amount or name as the player said them. Godot resolves names to people and
places itself, so "Gandalf" resolves to nobody and the person says they do
not know him. The kind is checked for shape (a snake_case word, not a
sentence); nothing else in the answer is trusted.

**The vocabulary is open, the effects are not.** Kinds with rules: greet,
farewell, thanks, about_self, about_work, about_person, about_place,
introduce_self, compliment, flirt, apologize, insult, threaten, give_money.
The model may use its own word — persuade, negotiate, lie — as the plan asks
("do not restrict the player to a hardcoded list"); such a line is talk,
accepted, and changes nothing until a system exists that it could change.

**The rules, in short.** Asking who someone is introduces them; giving your
own name introduces you (a false name is yours to give, and is not learned).
Compliments warm, but one conversation can warm someone only so far
(`WARMTH_CAP`); insults and threats have no cap. An apology mends a
grievance back to even and no further. Flirting is welcome only from someone
known and liked, and cools things otherwise. Insults and threats are facts
the person witnessed, recorded in `KnowledgeNetwork` with social visibility,
so they travel along the relationship graph like any gossip; a threat also
frightens and ends the conversation. Money must be in the player's cash and
at most `MAX_GIFT` (past that it is a transaction, M4); a gift is paid,
warms by its size, and is remembered privately. NPCs have no wallets yet, so
a gift leaves the player and goes nowhere — M4 gives people money.

**The reply is told the truth.** The judged outcome reaches the reply prompt
under "What just happened", with a rule that it is true and not to be
contradicted — so a model cannot thank the player for money that never
changed hands. Authored replies have a line for every new outcome, generic
for everyone in English and Finnish.

**Costs accepted.** Two model calls per non-plain line (a cheap reading, then
the reply) roughly doubles latency against one combined call; kept apart
because the reading must be judged before the reply is written, and so the
reading can run on the cheap model. The offline reading is still words, not
understanding — "I won't give you 20 euros" reads as an offer offline — and
the rules check the wallet whoever interpreted. One intent per line: "sorry,
here's 20 euros" is a gift, not also an apology.

## D-038 — People remember the player, by rule and in bounds; a developer overlay shows the machinery

**Decision.** M3 step 5, which completes M3 in code. `MemoryBook`
(`Game.memories`, saved as the new `memories` section, schema v2) keeps, per
person, what they remember of their dealings with the player: each
conversation as an episode — when, where, and what the player did, as
phrases from the person's side ("they asked who you are, gave you 20 in
cash, and complimented you"). A conversation with nothing notable is still
remembered: "they stopped for a chat".

**Memories are written from verdicts, never from replies.**
`ConversationRules.memory_of()` turns each judged line into a phrase, and
only judged things are kept: what a model *said* — a promised discount, an
invented brother — is never a memory, so no hallucination can become
something a person remembers. This is D-037's rule applied to time.

**Hierarchical and bounded.** The last four episodes are kept whole; when
there are more than six, the oldest are folded into a summary at once, by
rule — each becomes a timeless sentence, and while the summary is longer
than 480 characters the least weighty sentence goes (a threat outlasts
small talk). When a model is available the game then asks the cheap model,
in the background and without waiting, to rewrite that summary in at most
three sentences from what the rules recorded; the rewrite is accepted only
if it answers the latest fold and contains no ids, and the rule summary
stands if it fails. A long game grows neither a prompt nor a save without
limit.

**Recalled into the prompt with time.** The summary, then the latest
episodes with how long ago they were ("Yesterday, at Lahtinen's Corner
Shop: …"), fill the prompt's "What you remember of them" section (D-036).
Relative time is rendered when the prompt is built, so a memory ages
without being rewritten.

**Separate from knowledge on purpose.** `KnowledgeNetwork` holds facts —
what someone believes happened, which can travel as gossip and distort.
The memory book holds how it went between two people, which does not
travel. An insult is both: a witnessed fact that spreads, and a memory the
insulted person keeps.

**The developer overlay.** F3 in the world, in debug builds or with
`developer_mode` on, shows: provider, models, availability, requests
against the daily cap, tokens, estimated cost, cache hits, the circuit
breaker; the last model calls by purpose with latency, tokens and errors;
the last lines of conversation with who read the intent (model or words,
and why not the model), what the rules did (or refused), what happened,
and where the reply came from; the memories and beliefs selected for the
person being talked to; and recent rejected proposals. It reads and never
writes, and refreshes only while shown. Debug text is English.

**Price estimates updated.** The overlay's cost uses `LlmBudget`'s table,
now matching current models specifically before their families (Opus 4.5+
and 5 at $5/$25 per million tokens, Fable at $10/$50, Haiku 4.5 at $1/$5).
Estimates, not a bill.

**Costs accepted.** Episodes are English phrases stored in the save, so a
memory is not re-rendered if the game's language changes — it feeds the
model's prompt, which is English anyway (D-036), and the player never reads
it outside the developer overlay. People remember only the player so far;
memories of each other are not needed until NPCs converse. The memory
rewrite is fire-and-forget: a save taken in the second it is in flight keeps
the rule summary, which is correct, just plainer.

## D-039 — Shops: shelves and tills in data and state, rules decide, a counter window shows

**Decision.** M4 step 1. A shop is data (`data/shops.json`): where it is,
what it stocks and how many of each, its markup, which kinds of thing it
buys back and at what fraction of their value, and the float in its till.
What it has *now* — stock and till — is `ShopRegistry` state
(`Game.shops`), saved as the `shops` section (schema v3). Stepping up to a
counter with someone working behind it (`staff_serving`, D-018) opens the
shop; `Game.buy()` and `Game.sell()` gather the facts, `ShopRules` (pure)
judges them, and only then do money, goods and stock move. Refusals
(`nobody_serving`, `not_sold_here`, `out_of_stock`, `not_enough_money`,
`too_heavy`, `not_owned`, `not_bought_here`, `till_short`) emit
`action_rejected` and change nothing. The `ShopWindow` shows and asks, in
the house style, with Buy and Sell tabs; it never decides.

**Prices.** An item's `value` times the shop's markup, rounded, never below
one: the corner shop sells at value, the café charges 1.2 for the cup, the
bar 1.3, the pawn shop 1.5. Shops buy back only the kinds they deal in,
only things worth something, at their buyback fraction rounded down. The
player pays cash first, then by card; a shop pays for what it buys in cash
from its till. Haggling is the next step, against the skill.

**Midnight squares everything.** Every shop restocks to its usual counts —
never taking away what the player sold it — and its till returns to its
usual float: the owner banks the takings or tops it up. So no shop can be
bled dry by selling it things, or grow without limit; and there is no
per-shop economy simulation to run between visits.

**Time stands still at the counter,** as it does while talking (D-035); each
purchase or sale is a minute, paid on leaving.

**Costs accepted.** Shopkeepers have no money of their own and the till is
not theirs: M4's job and wage steps are where people's finances start, and
a gift (D-037) still goes nowhere. A counter with no shop behind it — the
clinic, the police post — still only says who is serving. Buying does not
make the shopkeeper know you: being a customer is not an introduction.

## D-040 — Haggling against the skill: one try per item per day, rolled on the seeded stream

**Decision.** M4 step 2. In the shop window every item for sale has a
Haggle beside Buy. `Game.haggle()` sets the player's `haggling` level
against the shopkeeper's difficulty, moved by how they feel about the
player, and rolls once on the game's `haggle` random stream; `HaggleRules`
(pure) judges. Won: that item is cheaper at that shop for the rest of the
day, by 5–20 % — the further the roll fell under the odds, the better the
deal. Lost: they are a little put out (affection −0.02) and will not haggle
over that item again until tomorrow. Either way the skill practises at the
difficulty tried, more for a win. One try per item per shop per day; the
record is shop state, saved, cleared at midnight with the restock (D-039).

**Difficulty is a level, like a skill.** Anyone behind a counter holds out
a little (8); someone whose occupation lists haggling holds out more (+14);
character moves it — Ida keeps accounts and is observant (36 in all), Leena
is cheerful (17), Tuomas the barkeep is easy (8). The odds use the same
curve as `Skills.success_chance`: never below 5 %, never above 95 %. How
they feel about the player moves the odds by up to 15 points either way —
a friend gives way, someone you insulted does not.

**Why the seeded stream.** A reload replays the same haggles, so saving
before a haggle and reloading until it works is no better than haggling
once. The roll is a world event, not a dice the player can re-throw.

**Costs accepted.** Cheap things barely move: 5 % off a 3-euro coffee rounds
back to 3. Haggling is a button, not a conversation — talking a price down
in your own words is where M3's dialogue could meet the shop, later, as an
intent the same rules judge. Shopkeepers have no skill of their own to
improve; their difficulty is their trade and their character.

## D-041 — Meals and the condition loop: use what you carry, the body keeps accounts, a collapse is the floor

**Decision.** M4 step 3. The player can eat, drink and patch themselves up
from what they carry: the bag (I) lists everything with counts and weight
and a Use for food, drink and medical things; `Game.use_item()` asks
`ItemRules` (pure), uses one up, applies its meter changes from the item's
data (`hunger`, `sleep`, `intoxication`, `health`, `stress`) and passes the
minutes it takes (food 10, drink and medical 5, or the item's
`use_minutes`). Refused: `not_owned`, `not_usable`, `not_hungry` (food that
only feeds, on a stomach under 0.15), `not_hurt` (medicine that only heals,
at full health), and `busy` while talking or shopping.

**The body keeps accounts.** Hunger now fills over ten waking hours rather
than six — two or three meals a day, affordable on the wages to come.
Starving (hunger ≥ 0.95) drains health over 36 hours; exhaustion (sleep ≤
0.05) drains it over 72 and raises stress. Condition already scaled
`effectiveness()`; now it touches play: a hungry, tired or drunk haggler
has worse odds (D-040), and jobs will use it next.

**A collapse is the floor, not the end.** When health reaches zero the
player collapses and wakes at 08:00 the next morning in the clinic (home if
there is none), patched up to 0.35 health, fed, a little shaken, and billed
€60 — or whatever they have. It costs a night, money and nerve, not the
game. The collapse is noticed during a clock step but carried out after it,
so a jump in time never runs inside another; it closes any conversation or
shop first, and `Events.player_collapsed` tells the view to move and say so.

**The HUD says how you are.** A status corner: weekday and time, where you
are, your cash — and, only when it is worth saying, how you are ("Hungry ·
Tired"), one word per meter, the worse one first (`StatusText`). The HUD
listens to the events that can change it; it still decides nothing.

**Costs accepted.** Only the player eats: NPCs' needs stay the scheduler's
business (they go to lunch; they do not buy lunch). The bag is a list, not
a grid, and there is no equipping yet. The clinic's care is not an
interaction — nobody treats you while you wait; that belongs with injuries
and harm.

## D-042 — Jobs, shifts and wages: a job is data, a shift is one batched step, reliability is kept

**Decision.** M4 step 4. A job is data (`data/jobs.json`): an occupation at
a workplace, for an employer (none for casual work), on certain days
between a shift's start and end, for a wage paid to cash or the bank, teaching
certain skills at a difficulty, straining the body, and with requirements (a
flag *or* a skill level, or knowing the employer well enough). Four today:
the harbour (Veikko; a harbour pass or labour 6), the worksite (casual:
anyone, any weekday, cash), Kaisla's counter (Leena, once she knows you),
and the clinic (Sanna; medical training or first aid 6).

**The player's job is `Employment` (`Game.work`),** saved as the `work`
section (schema v4; a v3 save's `player.job_id`, which was an occupation,
moves there through a fixed table). The dockhand background starts with the
harbour job; everyone else starts without one.

**A shift is one step.** Standing at the workplace during shift hours, with
nothing else in front of you, the interact button offers "Start your shift"
and `Game.work_shift()` asks `WorkRules` (pure). You may start up to an hour
early (and wait) or late, until half the shift is gone; not on a day off,
not twice a day, not drunk, not exhausted. The rest of the shift then
passes in one batched step with the player's activity "work"; the job's
strain is paid on the body; the wage — for the part worked, scaled a little
by condition, never below half — goes to cash or the bank; the job's skills
practise at its difficulty; the employer gets a little more familiar.

**Reliability.** `standing` runs from 1 to 0: a full shift on time raises it
a little, a late start lowers it a little, a missed working day lowers it a
quarter. Missed days are counted at midnight (the day a job begins does not
count — nobody is fired on their first morning). At zero the player is let
go, the employer thinks less of them, and `Events.job_lost` says so.

**Getting hired and quitting are conversation (M3 meets M4).** Asking an
employer for work ("are you hiring?", "onko töitä?") is the intent
`ask_for_work`; `ConversationRules` judges it against the job they hire for
and its requirements: hired, `not_hiring`, `not_qualified` or
`do_not_know_you` — refusals are rejected proposals, and the person says
why. `quit_job` to your employer ends the job. The cheap model knows both
kinds; offline words do too.

**What you see.** The prompt shows the wage; the outcome says until when you
worked and where the money went, and whether you were late. The bag shows
the job, its place, days and hours.

**Costs accepted.** A shift is not played, it passes: working is a decision
with consequences, not a minigame. People have no money of their own yet —
wages come from nowhere and gifts go nowhere; an economy of accounts is
later work. One job at a time; taking a new one replaces the old.

## D-043 — The home as a base: a cupboard that keeps what you do not carry

**Decision.** M4 step 5. The player's flat has a cupboard (an object of the
new kind `stash` on the shelf there). Facing it at home opens a two-sided
window — what you carry, what you keep — and `Game.store()` / `Game.take()`
move one thing across at a time. Only in your own home (`not_at_home`, and
another home's cupboard is `not_your_stash`), only what is there
(`not_owned`), only what fits: the cupboard holds 150 kg; what you take
must fit your carrying weight (`too_heavy`), what you put away must fit the
cupboard (`stash_full`). Time stands still while it is open.

**Saved with the player.** The stash is a second `Inventory` on
`PlayerState`, written into the player section; a save from before it has
none and loads with an empty cupboard, so no schema step is needed.

**Why this is enough of a base for now.** The home already is where you
sleep and where the game is saved (D-033); with a place to keep things, a
carry limit becomes a choice rather than a wall, and buying in bulk at
the corner shop makes sense. Cooking, rent and furniture are later.

**Benchmark.** `src/world/district_map.gd` changed (a new object kind), so
the simulation benchmark was re-run: 567 / 796 / 1390 / 3188 µs per
simulated minute for 50 / 200 / 1000 / 3000 people, below the last
measurement on this machine (706 / 1084 / 2052 / 3980) — no regression.


## D-044 — Quests: threads move on deeds, errands are asked for in conversation

**Decision.** M4 step 6. A quest is data (`data/quests.json`): a giver, the
background it starts for, an ordered list of stages, an optional deadline, and
`on_done` / `on_fail` effects. A stage waits on a *deed* — something the
player did that Godot already decided and carried out — announced as
`Events.player_deed(kind, data)`: `worked_shift`, `gave_money`, `talked`,
`hired`, `bought`, `entered`, `errand_done`. A stage may want the deed once,
n times, or its amounts summing to a total; or it waits on how someone feels
about the player (re-read when a relationship changes); or it is `open`, a
thread that continues in a later milestone. `QuestRules` is pure and says when
a stage is met; `QuestLog` (`Game.quests`) holds where each one stands;
`Game` carries out what finishing or failing does (feelings, flags, cash,
items, witnessed facts) — the same route as everything else, so a quest never
writes the world by a side door.

**The model never advances a quest.** It reads words into an intent; the rules
judge it; Godot applies it; *that* is a deed; the deed is what counts. A
quest cannot be finished by persuading a model that it was.

**The four threads.** One per background: the debt (pay Rauno €300, in parts,
in 14 days — miss it and he cools and it becomes a public fact that travels as
gossip), the old face (Ida, until she is fond enough), the dockhand's
warehouse (work a shift, ask Veikko about it, then open), the trained
hand's cover shift (hired at the clinic, work it).

**Errands are the NPC-need-driven jobs.** `data/errands.json`: someone needs
an item and pays. Offering to help (`offer_help`, now a real conversation
kind, English and Finnish phrases) gets one if that person has one to give
today; they then wait on it; handing it over in conversation pays, and the
same errand comes round again after `every_days`. No LLM decides whether an
errand exists.

**The log states the goal, never the route.** `J` opens `QuestWindow`: title,
who it is from, the goal in a sentence, the count where it is a count, the
days left. No markers, no map lines. Time stands still while it is open, like
every other window. The HUD says a quest moved.

**Saved.** A `quests` section (`active`, `finished`, `errands`,
`errands_done`); schema v5. A v4 save gains an empty log rather than
starting threads halfway through a life; from_dict drops quests the data no
longer has.

**Not done, on purpose.** Errands come only from people with an entry in
`errands.json`; people's own money is still not modelled (D-042), so rewards
come from nowhere. Quest text is English-first with the Finnish gap the
project already tolerates.


## D-045 — The phone: a window of its own, and nobody texts without a reason

**Decision.** M5 step 1. The phone is a window (`P`, `PhoneWindow`) shaped
like one — a narrow frame, Messages and Contacts along the bottom, more apps
joining that bar as they are built — not a page of the menu. It exists only
if the player has `item_phone` on them (every background starts with one;
the pawn shop will buy it): without one you cannot open it, and nothing that
would have arrived is queued for you.

**Numbers.** `PhoneState.contacts`. You have someone's number once they know
you (familiarity 0.1: introduced, or talked twice), or when they hire you.
Looked at once an hour, after a conversation ends, and at the start.

**Who writes, and when.** `PhoneRules.judge_outreach` — pure, tested per
refusal code — says whether a cause may become a message: `no_phone`,
`not_a_contact`, `asleep`, `quiet_hours` (before 07:00, from 22:00),
`too_soon` (a per-kind gap: two days for an errand, one for a nudge or a
missed shift, five for a friend), `daily_cap` (three people a day). The
*causes* come from the simulation, never from a model and never at random:
a quest deadline within three days (from whoever gave it), a shift missed
(from the employer), an errand someone needs done, a fond acquaintance
checking in. Each contact gets a preferred hour each day, from a hash, so a
day's messages arrive spread out. `PhoneDirector` looks at contacts only —
never the population — once an hour and once after time was skipped, so it
costs nothing that scales with the world (`src/npc`, `src/time` and
`src/world` are untouched; the benchmark was not re-run).

**Midnight is no time to write.** A missed shift is counted at the day's
turn, so it waits in `PhoneState.pending` and is delivered at the next hour
the rules allow; held back only by the hour, sleep or the cap it waits, up to
a day, otherwise it is dropped.

**A text can ask something, and the answer is a proposal.** An errand offer
carries an action; the window offers "I'll do it" / "Not now";
`Game.answer_message()` judges it (`PhoneRules.judge_answer`: `no_phone`,
`no_such_answer`, `already_answered`, `no_longer_possible` — an errand taken
in person meanwhile), applies it through the same `QuestLog.take_errand` the
conversation route uses, and a refusal emits `Events.action_rejected`. You can
always decline.

**Words.** Messages are stored as a locale key and arguments (an item id, a
place id, a quest name key), rendered on display (`PhoneText`), so a change of
language reaches messages already received. Every line is authored, English
and Finnish; letting the cheap model *word* a message in the sender's voice is
a later step and would change wording only, never whether or when.

**Saved.** A `phone` section (contacts, messages bounded at 200 — read ones
go first and an unanswered question is never dropped — last-started times,
pending, next id); schema v6; a v5 save gets an empty phone and picks its
contacts up from who already knows the player.

**Not yet, on purpose.** Replying in your own words (the intent pipeline would
read a text the way it reads a line of speech), calls, calendar and meeting
requests, the map, banking, photos, email. The criminal-contacts view waits
for crime (M6). Sequenced in `PROJECT_STATUS.md`.


## D-046 — Texting: the same road as speech, read when they get to it

**Decision.** M5 step 2. The player may text anyone whose number they have,
starting a thread from Contacts or answering one. A text is read into an
intent, judged by `ConversationRules`, applied and answered by *exactly* the
code a spoken line goes through: `DialogueDirector.say()` and the new
`text_exchange()` are two doors onto one `_respond(convo, line, channel)`.
Nothing about what a text may change is written a second time, so a rule
learned in a conversation is learned on the phone too, and a model may read
and word a text no more freely than it may a spoken line.

**What the channel changes, and only this.** `ConversationRules` gets
`channel` in its state: cash cannot be sent by text (`not_in_person`, with its
own authored refusal — banking is a later step). The `talked` deed becomes
`texted` — a quest that wants you *in front of* someone (Ida, the corner shop)
is not satisfied by a message. The prompt tells the model it is a text and
that it cannot see the player or hand anything over. A text earns a little
less familiarity than a conversation (0.02, not 0.05) and leaves the same
kind of memory.

**Attention costs time.** A sent text waits in `PhoneState.outbox` with a
due time: five minutes, forty-five if the person is at work. When it is due
they read it only if they are awake and it is between 07:00 and 22:00
(`PhoneRules.judge_reading`); otherwise they look again half an hour later.
So a text at 3 am is answered at breakfast, and nobody replies instantly to
everything. At most three texts to one person may be unread (`PhoneRules.
judge_send`; codes `no_phone`, `not_a_contact`, `empty`, `too_long`,
`too_many_waiting`), each refusal an `action_rejected`. Reading is a
coroutine started from the per-minute step only when the outbox is not empty
— free otherwise — and guarded against being started twice while a model is
thinking. Reading a text is independent of an in-person conversation: the
conversation state is passed in, not held, so a text can be read while the
player talks to someone else, and it does not disturb it.

**Their answer is a text.** From the model when there is one, otherwise the
authored line for the topic. It is stored as literal text (an authored line
was already resolved to words, with its arguments). An answer is not a
message they *started*, so it neither uses their gap nor one of the day's
three (D-045). It arrives with the HUD's toast; if you are looking at that
thread it is read on arrival. Time stands still while the phone is open, so
replies come after it is put away.

**Saved.** `outbox` and per-message `text` in the `phone` section; a phone
saved before this loads unchanged (no schema step: the reader defaults them).

**Not yet.** Meeting requests and the calendar (step 3), banking (step 4),
calls.


## D-047 — Meetings and the calendar: kept or missed by where people stand

**Decision.** M5 step 3. A friend fond of the player (familiarity 0.25,
affection 0.2 — the same bar as checking in) may, instead of a check-in,
suggest meeting up: tomorrow, at an hour between 12:00 and 19:00 chosen by a
hash, at a place flagged `meeting_place` in `data/locations.json` (the court,
the harbour park, Kaisla's, the Anchor) that is public and *open when they
arrive and when it ends*. It comes as a text with "I'll do it" / "Not now"
(D-045), rate-limited like any other (a gap of four days, three people a day).
Nobody suggests one while another with them is open, or when it would land
within an hour of a meeting already agreed.

**Accepting is judged.** `MeetingRules.judge_accept`: `already_answered`,
`too_late` (less than half an hour's notice, or the suggestion lapsed
unanswered), `clash` (within an hour of another). Saying no is always
allowed. Accepting puts it on the `Calendar` (`Game.calendar`, saved as the
`calendar` section, schema v7) and schedules four world events, so it runs
whether or not the player is looking: a reminder an hour before (HUD line);
the person heading over half an hour before (a `schedule_override` to that
place, activity "socialising" — the first use of overrides); the moment it is
settled twenty minutes after the start; and the end, when they go back to their
day. Being saved in the event queue, all of it survives a load.

**Kept or missed is read off the simulation, never off anyone's word.**
`MeetingRules.judge_attendance`, at the settling: the player at that place
(`player.location`) and the person there by their schedule → *kept*; the
person there and the player not → *missed*; the person not there → *stood up*.
A check that fires long after its time (the player slept or skipped through
it) is *missed* whatever anyone was doing — nobody can say where they were.
Kept: a little affection, trust and familiarity, a memory for them ("met you
when you agreed to"), and the deed `met` for quests. Missed: trust and
affection fall, they remember, and they text — at a civil hour, through the
same pending queue a missed shift uses (D-045). Stood up costs the player
nothing. The `NpcRegistry` gained `scheduled_location_of()` for this: it
reads the routine and any override at a given minute whatever the person's tier,
because a check that fires in the middle of a time skip must not trust a
position the simulation has not caught up to. It is not on the per-minute
path; the benchmark was re-run against the previous commit on the same machine
and is unchanged.

**The calendar.** A third tab on the phone: your job's fixed hours, what is
agreed and coming, and the last few that are behind you, with how each went.

**Not yet, on purpose.** *The player* proposing a meeting ("want to grab a
coffee tomorrow?") — it needs a time and a place read out of a line of speech
and a person who may say no for reasons of their own; sequenced after banking.
Someone cancelling; meetings with more than one person; reminders as texts.


## D-048 — Banking: an account with a history, money by text, and a machine

**Decision.** M5 step 4, first half. The wallet's two pots (D-005) get what
makes the difference between them matter.

**The ledger says when.** Each entry gains `at`, the minute it happened,
stamped by the game's own clock (`Wallet.stamp`, set in `new_game`); a save
from before has entries without one and shows them without a time.
`Wallet.transfer_out()` is money leaving the *account* for someone — never
cash, refused (`insufficient_bank`, `bad_amount`) otherwise.

**The phone's Bank tab** shows the balance and cash in hand and a statement:
what touches the account — wages paid to it, purchases the account covered,
transfers, deposits and withdrawals — newest first, each said in words and
dated (`BankText`). Cash spent or earned in hand never appears on a statement;
that is the point of having two pots. (Close moved to the phone's header to
make room for a fourth tab.)

**Money by text goes through the account.** D-046 refused cash by text
because there are no hands on a phone. That refusal is replaced by the honest
rule: over the phone `give_money` is judged against the *account* (`player_
bank`; `not_enough_bank` refuses it, with its own authored lines), applied as
a `transfer` effect, and announced as the same `gave_money` deed a handed-over
gift is — so Rauno's debt can be paid by transfer, and a quest cannot tell the
difference and should not. Nothing else about it changed: same intent, same
rules, same limits (`MAX_GIFT`), same warmth, same memory.

**A cash machine.** The pots need somewhere to meet. `atm` is a new map
object kind, on a shelf in the corner shop (like the cupboard, D-043): facing
it opens `AtmWindow` — put in or take out €10, €50, €100 or all. `Game.
atm_deposit()` / `atm_withdraw()` decide and refuse away from a machine
(`not_at_atm`) or without the money. It is in a shop, so it is there only
while the shop is open; time stands still at it. `src/world/district_map.gd`
changed, so the benchmark was re-run: unchanged.

**Not yet.** Bills and rent, interest, loans, cards refused by some shops
(the design's "not accepted by everyone"), and theft of cash — later, with
crime (M6).


## D-049 — The map: what you have learned, and nothing else

**Decision.** M5 step 4, second half. The phone's Map tab draws the district
the way the player knows it. `PlayerState.known_places` maps a location to
"visited" or "told" and is saved with the player; the map draws only those,
and nobody but the player is on it — no one else's position, ever (D-017: who
is where is the simulation's, not something to hand the player for free).
Places been to are solid; places only heard of are outlined and faint. Each is
marked with a number and the legend below says which is which (names beside
narrow buildings clipped or collided; numbers do neither). "You" is the yellow
dot — on the building when you are inside one. Places in districts with no map
yet (Old Town, Eastfield) are listed in the legend but not drawn.

**How a place is learned.** By *being* there — every change of the player's
location (`Game._set_player_location`) marks it visited, and being there
outranks hearing of it; by being *told* — a line about a place is judged by
`ConversationRules` and gives an effect, `tell_place`, applied like any other
(so it works by text too, and a model cannot put a place on the map that the
rules did not); by an *invitation* that names it (a meeting request); by being
*hired* there. You begin knowing your home, and your workplace if you have
one. A save from before the map knows where you live. `Events.place_learned`
fires the first time a place appears and the HUD says "New on your map: …";
turning a heard-of place into a been-to one is quiet.

**Scope.** No fog *of the tiles* — the world you walk is drawn as before; this
is the phone's map, a record of knowledge, not a minimap. No routes, no
markers on other people, no "go here" (the design's rule for quests, §51, holds
for the map too). Faded, unnumbered detail such as streets between places
waits for M7's wider "progressive revelation" of Old Town and Eastfield.


## D-050 — Calls; and what the phone deliberately does not have

**Decision.** M5 step 5. A **call** is a conversation had down a phone. The
thread has a Call button; pressing it asks whether they would pick up
(`PhoneRules.judge_call`: `no_phone`, `not_a_contact`, `asleep`,
`quiet_hours`, `busy` — at work nobody picks up — and `already_talking`);
if so the phone is put away and the ordinary dialogue box opens, with the
person answering "Hello?". There is no presence check, because there is no
presence; whether they can pick up is what stands in for it. That makes a call
the fast, costly alternative to a text: an answer *now*, but only from someone
reachable, and it takes the minutes a conversation takes (paid when it ends,
D-035) instead of costing nothing.

**Same road as speech and texts.** Nothing is written a third time. The one
`_respond()` behind `say()` and `text_exchange()` (D-046) now knows three
channels: `in_person`, `call`, `text`. Cash cannot be handed over down any
phone and goes through the account (D-048). The deed is `called` — a quest
that wants you *in front of* someone is not satisfied by ringing them, nor is
a text. The prompt tells a model it is a phone call and to speak, not write.
Errand goods still change hands only in person. The conversation is passed in
rather than held, so a call cannot be confused with the person in front of
you (there is only one open at a time: `already_talking`).

**A time-pause bug, avoided.** The phone stops time while open. Starting a
call with it still open would record "paused" as the state to restore, and the
clock would stay frozen after the call. So the phone is put away first — which
hands time back — and only then does the call pause it again; a test drives
this through the real world scene.

**What the phone does not have, on purpose.**
- **Email.** It would carry rent, official notices and the like, and nothing
  in the game generates those yet. An inbox nothing writes to is a
  half-working system. It belongs with whatever first needs it: a landlord and
  bills, or the police (M6).
- **Photos.** There is no camera and nothing to photograph or to do with a
  photograph. Later, if evidence or memory-keeping earns it.
- **The criminal-contacts view.** Waits for crime (M6), as the design says.
- **Incoming calls,** and a call log. NPCs reach the player by text; ringing
  the player would need a way to answer, and a missed call is a text.
- Other things noted along the way and left: the player proposing a meeting;
  someone cancelling one; missed-call texts.


## D-051 — Crime: only what someone saw, and only what they tell

**Decision.** M6 step 1, first half. The order of M6 (crime first, then
conflict resolution, then combat, then dynamic events) was put to the user with
the offer to start on crime; this begins it. The premise is the one the design
already states and `Reputation` already enforces: *a crime nobody witnessed and
nobody heard about changes nothing.* So a crime here is not an event the world
records; it is a fact that exists only if a person perceived it.

**Theft, at the counter.** The shop window gains "Pocket it" beside Haggle and
Buy. `Game.steal()` follows the shape of haggling (D-040): the facts are
gathered, `TheftRules.judge()` decides from dice rolled on the game's seeded
stream (`theft`), so a reloaded save is seen or not the same way. Everyone in
the shop by the simulation's account — awake and *there* — has a chance of
noticing (`TheftRules.notice_chance`): someone on duty behind the counter
watches closely, a bystander less; character moves it (Ida is observant,
Pirjo cannot see far, a drunk or tired person misses more); the player's
stealth and condition move it back; never certain, never impossible. The one
on duty who notices *stops it*: the item stays and they are a witness. A
bystander who notices lets it happen and remembers. Nobody noticing: it is
simply taken, and nothing has happened. Stealth is practised either way, most
by getting away clean.

**A witness is a fact, a change of heart, and a memory.** `CrimeDirector.
record_theft()` files `stole_from` in the knowledge network with the
witnesses as firsthand knowers — so it spreads by gossip like anything else
and appears in what a model is told they believe about the player — lowers
each witness's affection and trust, and writes it in their `MemoryBook`. The
shop window says only what the player can tell: their hand was caught, or it
was not. Never who saw.

**Whether they tell the police is theirs to decide, by rule**, not by a die
(`TheftRules.report_urge`): how much it was worth (a bun is petty, a tool is
not), whether they stopped it themselves, how fond they are of the player, and
who they are (`by_the_book` tells; `discreet` and `generous_when_useful`
hold back). So the shopkeeper who caught you tells; a bystander shrugs at a
sandwich; a friend who caught you lets it go. A report is a world event 20 to
90 minutes later; when it comes, the officer learns the fact *from them* —
secondhand, less sure of it (`KnowledgeNetwork.tell`) — and an officer who saw
it herself needs no report. Officers are whoever is in a group beginning
`police`.

**Not yet — the next half (D-052).** What the police *do* with what they know:
a response proportional to it, not to what actually happened. Here they only
come to know. Also not yet: other crimes (pickpocketing, trespass, assault —
the last waits for combat), fences and stolen goods, and shopkeepers refusing
service.


## D-052 — The police: proportionate to what they believe, not to what happened

**Decision.** M6 step 1, second half. What the police do about a crime is
decided from what an officer *believes* about it — never from the world's
account of what really happened. `CrimeDirector.case_for(officer)` builds her
case from the knowledge network: each crime fact she knows about the player
that has not been dealt with, with its severity and how sure she is of it
(`PoliceRules.strength`: her confidence less how garbled it has become — 1
if she saw it, about 0.75 if a witness told her, under 0.35 for a rumour
that has been passed along a few times, which is not enough to act on
however serious it sounds).

**The answer is a weight, and the weight steps up.** `PoliceRules.
judge_response`: the worst matter as she sees it (severity × strength), a
little more for each further matter in the case, 0.10 for each earlier
offence on the record (three at most), a little for an officer who goes by
the book, and 0.25 for having ignored a summons. Under 0.12: nothing. From
0.12 a warning; from 0.30 a fine; from 0.50 an arrest. So a first petty
theft that Ida told Marika about is a warning; the same again is a fine; a
fourth is an arrest; a costly one is an arrest at once; and a fine the player
cannot pay is not waived but becomes a night in the cells.

**How it plays out.**
1. An officer comes to know a crime — a witness's report reaches her
   (D-051), or she saw it — and gets round to it in her own time (an hour;
   two for someone unhurried, like Marika): `police_assess`.
2. If what she knows warrants anything, she **sends for the player**: a
   summons, by text (they have your number; it waits for a civil hour like any
   message, and the police post goes on the map), with a day to come in. With
   no phone the summons still stands and nobody tells you — losing your phone
   has a cost.
3. **Coming in**: the police desk (the counter in the post, with an officer
   behind it) weighs the case now, on what she knows now: a warning is on the
   record and costs nothing; a fine is paid from what you have; an arrest is a
   night in the cells, let out in the morning (fed and rested — a night in the
   cells is not a starvation), and *known*: `arrested` is a fact the officer
   witnessed and it travels and reads through `Reputation` like any other. A
   matter dealt with is not held over you again; what is on the record is.
4. **Not coming in**: at the end of the day the case is weighed without you,
   worse (a warning becomes a fine, a fine an arrest), the fine is taken, and
   an arrest is carried out once time has stopped moving — the same deferral a
   collapse uses, so no world event ever moves the player mid-skip.
Only one summons per officer is open at a time; more news while it is open is
folded into the case when it is weighed.

**Saved.** A `crime` section (the record, what has been handled, the
summons), schema v8; the deadline and the pending assessments live in the
event queue and survive a load.

**Not yet.** Being stopped in the street; confiscating what was taken (the
goods are not tagged as stolen yet); a court, bail or a lawyer; officers other
than Marika (any NPC in a group beginning `police` will do); crimes other than
theft (assault waits for combat); a fence, and stolen goods at the pawn shop.
The email and criminal-contacts view that D-050 deferred still have no reason
to exist yet — this is the closest they have come.


## D-053 — Talking someone round: asks, graded, with a cost

**Decision.** M6 step 2, conflict resolution that is not only fighting. The
roadmap's phrase — partial successes, costs, debts, delayed consequences — and
the dialogue rules' own note that `persuade`, `negotiate` and `ask_favor` are
"understood but change nothing yet" say what this is: making those intents
*do* something, judged by rules like everything else, so a dispute can be
settled by talking rather than by a fight or a purchase. (The user answered
"continue" to the question of what shape it should take; this is my call and
is recorded so it can be redirected.)

**An ask is authored data** (`data/asks.json`): who it is put to, what has to
be true for there to be anything to ask (`requires`: an open quest, an open
summons), the skill it turns on, its difficulty, a cooldown, and for each of
four grades what happens — a list of effects from a small vocabulary
(`AskDirector.EFFECTS`: `feel`, `flag`, `cash`, `extend_deadline`,
`raise_requirement`, `leniency`). `DataRegistry` validates every ask against
the world (the person, the skill, the quest, all four grades, known effects).
A model reads what the player meant (`negotiate`; `persuade` and `ask_favor`
count too) and *nothing else*: which ask it is, whether it succeeds and what it
changes are decided by rules and dice.

**Four grades, not two** (`AskRules`): the player's skill against the ask's
difficulty, moved by how the person feels about them and by the player's
condition, never certain and never hopeless, rolled on the seeded `ask`
stream. **Success** gives what was asked. **Partial** gives some of it *and
costs*. **Failure** changes nothing and puts them out a little. **Backfire**
— pushing too hard — leaves things worse than before. Every try teaches the
skill, more for winning. Asking twice in a breath is refused (a cooldown,
`ask_again`, and no dice thrown), and asking where there is nothing to ask is
`no_ask`.

**Two asks, deliberately unlike each other.**
- *More time from Rauno* (the debt, D-044): success is a week more; partial is
  three days and the debt grows by €30 — interest, a *delayed* cost, carried in
  the quest's `extra_need` and shown in the log ("0 of 330"); failure loses a
  little trust; backfire loses two days and his goodwill.
- *Going easy* with Marika, once she has sent for you (D-052): her leniency —
  a number added to the weight of the case she is about to decide — falls on a
  success (a fine can become nothing), a little on a partial (a warning), not
  at all on a failure, and *rises* on a backfire (an arrest). It is spent when
  she decides. What the police believe is still what decides; the player only
  moves how it weighs.
It works in person, by text and on a call, since it is a line of speech like
any other. A reply to an ask is authored generic lines by grade, or the
model's, told what came of it.

**A bug the tests found.** "Can I pay later?" was read offline as a farewell
(it contains "later"), which would have ended the conversation; negotiating now
outranks saying goodbye in the offline reading.

**Saved.** An `asks` section (what was asked of whom, when), schema v9; quests
carry `extra_need` and the police `leniency`, in their own sections.

**Not yet.** Only two asks are authored — the mechanism, not a catalogue; the
other skills (`deception` for lying, `intimidation` for threats that work) have
no ask to serve yet; asks that give things (an advance on wages, credit at a
shop); the person *refusing to be asked* for reasons of their own beyond
disposition.


## D-054 — Combat: readable, small, and made of the same things as everything else

**Decision.** M6 step 3. The design was put to the user as a concrete proposal
and the user said "continue"; this is what was proposed, built, and is
recorded so it can be redirected. The plan's line is *turn-based JRPG combat,
familiar and readable, context-sensitive commands, a varying number of
combatants, enemies who are real people* — and no tactical simulator.

**Starting one.** You say so, in person: the intent `attack` ("I'm going to
hit you", "let's fight" — English and Finnish, and a model may read it) is
judged by `ConversationRules`; down a phone it is refused (`not_here`) — there
is no one to hit. The rules' effect is a *request*, `Events.fight_requested`;
the world begins it a frame later, when the conversation has been put away
(`Game.start_fight`: refused `already_fighting`, `nobody_there`, `asleep`,
`not_here`). Time stands still while it is on and is handed back as it was found.

**The fight** (`Combat`, over `CombatRules`; pure and scripted-dice testable).
A round is the player's move, then everyone else's. The player has **Attack,
Heavy blow, Defend, Intimidate, Bandage, Run, Back down**; a move that cannot
be made (too tired, nothing to use, no skill) is refused and costs no turn.
The chance to hit is skill and agility against theirs, moved by a guard, a
heavy swing, tired arms and the attacker's condition — never certain, never
hopeless; damage is strength, a crowbar if carried, a spread and a crit, and a
guard takes the edge off. A hard look ends it without a blow if their
resolve gives way, and hurt people give way sooner. Running is agility
against the quickest of those after you. Everything is on the same 0..1
health bar the rest of the game uses, so a fight and a bad week are the same
kind of thing. Dice come from the seeded `combat` stream; tests script them.

**Enemies are real people.** Someone's build comes from who they are: an
occupation with `labour` is stronger, one with `intimidation` (an officer) is
steadier and has done this before, a `strong` person is stronger, poor
eyesight or drink or tiredness slows them. What they do on their turn
(`CombatRules.npc_action`) comes from how they feel: fight on, brace, swing
hard if strong and fresh, and — once badly hurt — run or give in, less likely
the more resolute they are. Their health is theirs: it is kept on them and
mends by the hour, so someone you beat yesterday is not at full strength today.
**People step in**: a friend of the one you went for (affection ≥ 0.5) joins
their side, up to two; an officer who is there always does. A fight with a
constable in the room is a fight with a constable.

**What it leaves behind, worked out by `FightDirector.finish()`.**
- *The player:* health carried back; hard blows leave **wounds that last** (a
  bruise for two days, a cracked rib for five) through the existing
  `Stats.injuries`, so effectiveness stays lower while they mend; used
  bandages are gone. Losing is a collapse and a clinic bill, by the existing
  flow (D-041) — nobody dies in this step.
- *The others:* a beaten person is out cold for 45 minutes (an override, so
  they cannot be talked to); they feel differently — affection and trust
  down, fear up if you won — and remember it.
- *The law:* **assault is a crime like theft, by the same machinery.**
  Everyone awake in the place saw it; `CrimeDirector.record_crime()` (theft
  now calls it too) files `assaulted`, severity from the damage done, witnesses
  as firsthand knowers, and they report by the same rule. The police response
  (D-052) needs no change: a constable who saw it herself is certain, and
  hitting someone in front of one is not a warning.
- *Time:* a minute a round.

**The window** (`CombatWindow`): the foes, each with a coloured health bar and
a state (down, ran off, backed off) — click one to aim at it; you, with health
and stamina; the last eight things that happened, said in your language
(`CombatText`; one wording when you did it, another when it was done to you);
the commands. There is no leaving a fight by closing a window — there is
running, and there is backing down.

**Not yet.** People starting fights with the player; being attacked in the
street; allies on the player's side; weapons beyond a carried crowbar, and
armour; skills beyond the two; context actions beyond backing down (talk them
down mid-fight, surrender); death; sprites and portraits in the window;
fights that spill across places.


## D-055 — Dynamic events: what people know comes back for you

**Decision.** M6 step 4, the last of the milestone. The plan's line — *new
enemy, delayed consequence, escalation, other logical outcomes* — is met not by
a new engine but by one small daily pass, `ConsequenceDirector.run_daily()`,
run when the day turns, that asks of the world what it already knows: who
believes what of the player, who is fond of whom, what is owed. It uses only
existing systems — the knowledge network, the relationship graph, the phone,
the calendar, the event queue, and (if the player goes) a fight — and it has
no dice: a consequence is a matter of who knows what and how they feel, so it
can be read, tested and, in play, seen coming. At most one new step a day.

**A dismissal — a delayed consequence.** An employer who has come to believe
something serious of the player (`CrimeDirector.known_offences`: severity ×
how sure they are ≥ 0.30, and sure enough to act on) lets them go: the job
ends (`Events.job_lost`, reason `reputation`), they think less of the player,
and they say so by text. A sandwich is not enough; a rumour is not enough;
what the employer does not know does not count; casual work has no one to mind.

**A grudge — a new enemy.** Someone the player beat, and the friends of theirs
who know it (affection ≥ 0.5, the same test as stepping into a fight), send a
warning by text — the victim in their own voice, a friend in another's.
Officers never do; they have procedures. Two days on, if it has not been
answered, they **name a time and a place**: tomorrow at nine in the evening, at
a park, "come alone if you've got the nerve" — a *hostile meeting* on the
calendar (D-047): the player is told, not asked. If the player goes, and so does
the person, **they start it** (`Events.ambush`, and the fight (D-054) begins
with them as the aggressor: being met for a fight you were told of is not
assault, so there is no crime for the police to weigh, the feelings between you
change less, and it is remembered as "fought you, as they said they would").
If the player stays away, nothing is asked of their manners — no missed-meeting
text, no penalty. Someone still mending (health under half) does not come until
they can stand. A grudge answered by a meeting, win or lose, rests for twelve
days; one that was never answered says its piece twice and lets it lie, and may
begin again.

**A collection — an escalation.** A quest may name who is owed (`collection` in
`data/quests.json`; Rauno's debt does). Once it has been let fail, he reminds
the player three times, more firmly each, and then sends someone stronger from
his crowd — Joonas — to a meeting. The same machinery.

**Two supporting changes.** A text held back only because someone had just
written now waits, up to a day, rather than being dropped — so a confrontation
queued behind a warning is not lost. And the clinic finally *treats*: at the
desk, a nurse sees to injuries for €20 a wound (up to €60), the rest of the
healing takes a third of the time, and the player is a little better for it
today (`ClinicRules`) — the last line of the roadmap's "injuries that persist
and a clinic that treats them".

**Saved.** A `consequences` section (grudges' steps and the jobs lost),
schema v10.

**Not yet.** People starting fights out of the blue, or in the street; a
grudge that grows into a group; a dismissed employer refusing to rehire;
consequences from the player's *good* deeds coming back (favours returned,
gossip that helps); events that are not about the player at all (that is M7's
factions).


## D-056 — Models that think get room to think, on every provider

**Found on first live contact.** With OpenRouter and a Gemini Flash model,
replies came back short and cut off mid-sentence. The output cap covers
thinking and answer together, and only the Anthropic adapter (D-036) gave
thinking any headroom; the others sent the bare 160-token budget, which the
model spent thinking.

**Now.** `LlmProvider.may_reason(model)` recognises models that think by
default (Gemini 2.5/3, GPT-5, o-series, DeepSeek R1, Qwen3, Grok 4,
Claude 5 family, `thinking` variants) by name fragment, and
`LlmProvider.output_cap` adds `REASONING_HEADROOM` (1024) for them. OpenRouter
also sends `reasoning: {effort: low}`. The dialogue budget goes from 160 to
200 tokens because Finnish takes about twice the tokens of English. When a
reply still stops on the limit (`LlmResponse.hit_length_limit`),
`clean_reply` keeps the finished sentences instead of showing a half-word.

**Not done.** Direct Google `thinkingConfig` (the shape differs per model
generation; headroom is enough and cannot be rejected).


## D-057 — Promises are made of rules: walking with the player, and no empty yeses

**Found on first live play.** The player said "follow me", the person said
"sure", and nothing happened: following did not exist, so the line was talk
with no rules, and the model, which writes the reply without knowing what the
game will do, agreed. Any promise (bring, go, wait) could fail the same way.

**Decision.** A request is a proposal like any other. Three new intent kinds
(`ask_follow`, `ask_wait`, `ask_action`), read by the cheap model or by words
(English and Finnish, checked before place, work and farewell so "follow me to
the harbour" is a request), judged by `ConversationRules`, and told to the
speaker in `happened` — so the reply is written from what is true.
- **Follow** is refused (`follow_remote` by phone or text, `follow_busy` when
  their own day is due — a shift or the night — within 30 minutes,
  `follow_distrust` when trust is below -0.2 or affection below -0.3) or
  agreed, deterministically, no dice. A stranger is not held against them.
- **Wait** stops it; harmless when nobody was following.
- **`ask_action`** (fetch, bring, carry, give, go somewhere) is the honest
  refusal `cannot_do` while those are not built: the person is told nothing
  will happen and that they promised nothing. This is the general fix; the
  later verbs (D-057's "not yet") replace it one at a time.

**How it is carried out.** `npc.state["following"] = {since, until}` — not the
single `schedule_override` slot, which meetings and knock-outs already contend
for and which cannot track a moving player. `until` is the shorter of four
hours and the start of their next shift or night (`FollowRules`,
`NpcSchedule.next_start_of`), tested by absolute minute so a long skip cannot
step over it. `NpcDirector` keeps a `followers` index: it consults the state
first in `_apply_schedule`, holds followers ACTIVE through every retier (they
would otherwise be demoted and snap back to their routine), and rebuilds the
index after a load. Where they are is the player's place (`Game.follow_location`:
the building the player is in, else the open-air place, else the region's
street), moved whenever the player changes place. It ends on "wait", the time
running out, a crime or a fight, a sleeping or collapsing skip, an arrest, and
leaving the region (following across regions is not built, and travel does not
yet call `world.enter_region` — a latent issue noted, not fixed).

**Bodies** stay with the player: placed beside them, and, when the player moves
on, sent after them by one route planned only when the follower is more than
three cells behind (`NpcBodies.follow_player`), at a speed between walking and
running.

**Not yet.** Following across regions; going to a place, giving, taking,
bringing and carrying (they are `cannot_do`); animations — the imported
character sheets keep only standing, idle and walk rows (`tools/import_limezu.py`),
so nothing shows a hand-over; more than one thing promised at a time; a
reluctant person who could be talked into it (the asks of D-053 are the model
for that).

**Saved.** In each person's `state` (already in the `npcs` section), so no new
section or migration; a number read back from JSON is an `int()`.


## D-058 — The characters already had more animations; the importer was throwing them away

**Found.** The LimeZu character sheets hold about twenty animations, one per 64 px
row, in every layer (body, eyes, outfit, hair) in the same layout, so they work
for every look with no new art. The importer kept the top three rows (stand,
idle, walk) and dropped the rest to keep video memory small: a whole sheet is
~9 MB and a person wears four.

**Row map** (read off `Premade_Character_32x32_01.png` with
`tools/catalog_limezu_rows.py`; the Aseprite sources carry no tags, so this is by
eye). Facing order in every directional row is right, up, left, down; frames per
facing in brackets.

| row | y | what it is | frames |
|---|---|---|---|
| 0 | 0 | stand | 1 per facing |
| 1 | 64 | idle | 6 per facing |
| 2 | 128 | walk | 6 per facing |
| 3 | 192 | sleep (head only, plus bed props) | 6, no facing |
| 4 | 256 | sit | 3 per facing |
| 5 | 320 | sit, holding something (a device) | 3 per facing |
| 6 | 384 | phone, front only: 0-3 lift, **4-9 loop**, 10-11 away | 12 |
| 7 | 448 | reading a book, front only (book is a separate prop, frames 14-25) | 12 |
| 8 | 512 | pushing a cart (cart frames 24-47 are props) | 6 per facing |
| 9 | 576 | picking something up | 12 per facing |
| 10 | 640 | **gift**: holding something out (box props at 44-45) | 10 per facing |
| 11, 12 | 704, 768 | two long arm actions, probably lift and throw | 14 per facing |
| 13, 14 | 832, 896 | two short arm actions, probably hit and punch | 6 per facing |
| 15 | 960 | probably a stab (small weapon props at 24-47) | 6 per facing + props |
| 16-18 | 1024-1152 | probably grab a gun, hold it, shoot | 4, 6, 3 per facing |
| 19 | 1216 | hurt: red flash | 3 per facing |

Only the rows read with confidence are imported; the guesses are left until
something in the game needs them and someone has watched them play.

**Decision.** `tools/import_limezu.py` keeps a list of `ACTIONS` (now stand,
idle, walk, phone, gift) and stacks those rows into one compact atlas per layer
(1280×320, 1.6 MB, against 0.6 MB before), and the manifest gets an `actions`
table: where each sits and how long it is. `CharacterSprites.frame_rect_for`
reads it, and an action the art lacks is shown as standing, so asking is never
an error; an import from before this decision falls back to the old three rows.
`CharacterFigure.play(action, hold)` plays one — once, or a loop (`phone`,
frames 4-9) until `end_pose()` — signals `pose_finished`, and is ended by setting
off. It returns false with no art, so nothing ever waits on a picture.

**What plays.**
- **Idle:** every 2.5 s one standing person, chosen at random, does their idle
  animation once (`NpcBodies._ambient_idle`, one timer for the crowd; a standing
  body still does not process).
- **Gift:** the player holds it out when they hand someone money face to face
  (`player_deed "gave_money"`).
- **Phone:** the player's phone goes to their ear for the length of a call.
Presentation only, all of it: what the world does never waits for it.

**Not yet, and what each needs.** Sit (a chair cell and which way it faces),
sleep (a bed cell), the fight actions (a fight scene that shows bodies, D-054),
pickup/lift/carry (the bring-and-take verbs promised after D-057), reading (a
book layer), an NPC's own hand-over (they receive, they do not give, so far).
Running is still the walk cycle.

**Memory.** Each look now costs 1.6 MB per layer file loaded instead of 0.6 MB;
only files someone wears are loaded. Worth re-checking in the running game if
the cast grows.


## D-059 — Everything between two people is one memory; the feed says what happened

**Found in play.** People did not reliably remember an earlier talk and greeted
the player as a stranger every time; a person did not know they had sent a text.
Two causes. `MemoryBook` (D-038) kept only what the player *did* ("stopped for a
chat" when nothing in particular), never the words, so "do you remember what we
talked about?" had nothing to be answered from; and texts lived only in
`PhoneState`, never in anyone's memory. The opening line was always the generic
first-meeting greeting.

**One book.** Every dealing is an episode with a `channel` — `in_person`, `call`,
`text` or `event` — what was done, and an `excerpt`: the last six lines of the
actual words, each cut to 110 characters, the person as "you" and the player as
"they" (as in the prompt). Written by `DialogueDirector._settle` for talks, calls
and texts the player sends (a text and its answer are one exchange; texts within
90 minutes join), by `note_text` for what people write first
(`PhoneDirector.deliver`, the player's canned answers) and, as before, by the
crime, fight and meeting directors for deeds. Recall lists them oldest first with
how long ago and where or how, and gives the words of the latest two, so a prompt
stays bounded. The prompt says plainly that this really happened, that texts and
calls count, and that what is not written there is not remembered.

**What is remembered is speech, not fact.** The words include what a model made
someone say. That is right — they did say it — but it is kept apart from what
*happened*, which is still only what the rules judged (`things`): a promised
lifetime discount is remembered as something said, never as something done.

**Greeting.** `DialogueDirector._opening_topic` picks the opener from memory: a
text of theirs the player has not answered (`greet_texted`, within twelve hours),
spoken to earlier today (`greet_again_today`), met before (`greet_again`),
already familiar from the start (`greet_known`, familiarity 0.3), else a stranger
(`greet`). Authored lines, so no wait for a model at the door; a model-made
opening that draws on the memory is possible later.

**Saved.** In the existing `memories` section; new fields default when an old
save has none, so no migration.

**The event feed.** A short list at the top right of the HUD: money moved and
what for (`Events.money_moved`, from every wallet record), things going in or out
of the bag (`Events.item_moved`, only the player's own bag, not the cupboard),
skill levels, someone starting or stopping to walk with you, and every message
the HUD calls `notify` — new texts, meetings, quest steps, new places, a lost job,
an arrest, a collapse, the police. Six lines, each kept fourteen seconds and
faded out; passing remarks (`show_message`) stay out of it. Words are in
`FeedText`. It only shows; the rules already decided.

**Layout.** The speech window is 72 px lower, so the time and place in the top
left stay visible while someone talks.

**Not yet.** A full scrollable history of the feed; a model-written opener;
telling the feed about money and goods given *to* the player by people, when that
exists.



## D-060 — The police post is LimeZu's police station

**Found.** The post shared the grey `civic` storefront with the clinic, its sign
repainted flat. The police theme sheet (`15_Police_Station`) has a building with
POLICE across it and a badge: `Police_Station_Small_1`, 7×13 cells, door in the
bottom row, no porch.

**Decision.** `BuildingArt` gets a `police` entry and `BY_LOCATION`, which maps a
location to its own art (`art_kind`); `sprite_for` asks it, so callers keep
passing the kind. The kind stays `civic` everywhere else (map colours, themes,
rules). The post's map rect is now 7×13 and its door `[61, 28]`, column 3 of the
building, as the art draws it. `import_limezu_buildings.py` writes `police_1.png`.

**Other buildings that could be swapped later** (not done): the corner shop for a
`Market_Big` (7×12) or `Market_Medium` (7×9), the warehouse for something from the
worksite or generic-building sheets, the clinic for the hotel/hospital sheet (its
buildings are much larger). Each needs a rect and door change like this one.

## D-061 — Going somewhere alone: a one-off change to someone's day

**Found.** D-057 left "go somewhere" as `cannot_do`. It is the first of the
listed verbs that needs no new system: a person can already be sent to a place
for a while by `NpcSchedule.Override`, which meetings use.

**Decision.** A new intent kind `ask_go` ("go to the park", "mene satamaan"),
judged by `ConversationRules`. Offline it needs a place named in the line
(`OfflineTopics`, English and Finnish; "go to hell" is not an errand, and
"follow me to X" is still a follow); the cheap model puts the place in `place`,
resolved to an id by Godot as for `about_place`. Refusals, all deterministic:
`go_remote` (not by phone or text), `go_distrust` (same thresholds as follow),
`go_closed` (private, locked, another region, or shut before the trip is over —
`DialogueDirector._go_state`), `go_busy` (a meeting or summons already has them,
or under 30 minutes free), `cannot_do` (no place known). Already there is
`go_here`, no effect. Agreed: `{"do": "go", "place", "minutes"}`, applied as a
`schedule_override` (reason `go:<minute>`, activity `socialise`) for the shorter
of two hours (`FollowRules.GO_MINUTES`) and the time before their next shift or
night; afterwards they are back to the routine with nothing to clear. Someone
already following is released first. The person remembers it (`memory_of`).

**Not yet.** Fetch/bring/carry/give/take are still `cannot_do`; going to another
region; a reluctant person who could be talked into it (D-053's asks are the
model); the person coming back to tell the player (that is what bring/errands
will need).

**Saved.** The override is already in each person's `override` field.

## D-062 — Handing someone an item: a gift, and nothing more

**Found.** D-057 listed give/take as the next verb after going. Checking first,
as noted there: people have no inventory and no money of their own (nothing in
`src/npc/` holds either; cash gifts already "go nowhere", D-037). Real
belongings would be a new system, so the user was asked and chose the light
version.

**Decision.** A new intent kind `give_item`: the player hands over something
from the bag ("here, take this sandwich", "annan sinulle voileivän"). Offline
it needs a giving phrase (the ones `give_money` uses) and an item named in
either language; money is read first, so "here's 20 euros for a sandwich" is
still cash. The cheap model puts the item in a new `item` field, resolved to an
id by Godot like people and places. `ConversationRules` refuses `not_here` (by
phone or text), `no_item` (none in the bag), `keep_it` (the phone and keys,
`DialogueDirector.GIFT_KEEP`: the game does not work without them) and
`invalid_item`. Agreed: `{"do": "give_item", "item", "count": 1}` takes one
from the bag, warms them by value (`value / GIFT_CASH_PER_POINT`, at least
`GIFT_MIN_ITEM_WARMTH`, at most `GIFT_WARMTH_MAX`), and is remembered.
"Give me" / "take" (asking *them* for something) stays `cannot_do`.

**The item goes nowhere.** Like cash, it does not become theirs: nothing
records that Ida has a sandwich, she cannot hand it back, and a hungry person
is not fed by it. That is the honest limit of the light version and the reason
fetch, bring and take remain unbuilt: they need real belongings for people.

**Saved.** Nothing new; the bag is already saved.

## D-063 — The event feed sits in the bottom right, as plain text

**Asked for.** An event log in the bottom right corner, without a background,
saying what happens: "you got 50 €", "syringe added to your bag".

**Decision.** D-059's feed already existed (top right, one panel per line); it
is moved to the bottom right and drawn as outlined text with no panel, newest at
the bottom, up to eight lines for 14 seconds each. The bag lines now read "X
added to your bag" / "X removed from your bag" (with ×N when more than one), in
both languages. What it reports is unchanged: money in and out with the reason,
things in and out of the bag (not the cupboard), skill levels, someone joining
or leaving you, and every `Hud.notify` message (texts, meetings, quest steps,
new places, arrests). Anything else that should be said goes through
`Hud.log_event`. `ui_preview.tscn -- --screen=world --feed=1` shows it.

## D-064 — A building stands on the ground it was built on

**Found in play.** Paving showed in the bare top corners of every house roof,
behind the houses, with grass beyond it. `DistrictMap._stamp_building` set the
ground under every building to pavement ("a building stands on a floor"), and a
pitched roof's art is not a rectangle, so the corners the sprite leaves clear
(D-028) showed that paving.

**Decision.** The stamp no longer touches the ground: houses on grass have grass
in their corners, buildings on paved land (the warehouse) still have paving.
Nothing else reads the ground under a building. **Collision is unchanged** — the
whole footprint blocks, drawn or not — and is now covered by a test that walks
the body into a roof from behind and from the side.

**Known, not done.** The footprint is a rectangle, so the bare grass in a roof's
top corners is blocked though it looks open. Letting people walk there would
need cells that are neither building nor street (`location_at` would put the
player "inside" the house), so it waits for a reason.

## D-065 — A house collides where its roof is drawn

**Asked for.** After D-064 the bare corners of a roof were grass but still
blocked, so the body stopped at an invisible wall: "the collision should be at
the roof's outer edge".

**Decision.** The art decides, because the art is what the player sees.
- **Physics.** `RegionView` gives each whole-art building one `StaticBody2D`
  whose polygons are the outline of the sprite's opaque pixels
  (`BuildingArt.outline`, from `BitMap.opaque_to_polygons`, 1.5 px tolerance),
  clipped to the footprint (the porch stays walkable). The generic hidden tile
  under such a building no longer collides as a square (`RegionTiles`).
- **The rule.** Footprint cells the art fills only partly are `map.open_cells`
  (`BuildingArt.open_cells`, set by `RegionView`, cleared with it). `Game.move_player`
  asks `map.allows_body(cell)`, so the body may stand in the clear part of them
  and is not snapped back ("rules win"). They belong to no location
  (`location_at`), so standing in a roof corner is not being inside the house.
- **Not changed.** `is_blocked` still treats the whole footprint as blocked:
  routes, NPC bodies and interaction are as before.

**Only with the art installed,** like the drawing itself; without it there are no
open cells and the footprint is a plain rectangle (the movement tests for the
roof skip themselves then). Benchmark: no change beyond noise.

**Limits.** A route planned to a player standing in an open cell finds no path
(`find_path` refuses a blocked goal), so a follower may not come to someone in a
roof corner until they step out. Saved positions in an open cell fall back to the
anchor on load.

**D-065, addendum: every house.** The outline collision applies to every building
drawn as whole art, so it already covered all twelve (homes, shops, the bar, the
clinic, the police post, the warehouse). The one building left out was Tuomas's
flat, the only one authored at a size the art does not fit (5x9), so it was drawn
from plain tiles. It is now the same 8x11 villa as the other flats, on the same
row with the same one-cell gaps (`[31, 1, 8, 11]`, door `[33, 11]`), and so gets
the art and the collision. `test_roof_collision` checks that every building with
art has a body and every building without has none; the "wrong size keeps its
tiles" test now uses a made-up size instead of Tuomas's flat.

## D-066 — Street lamps at the kerb, head to the road, foot that collides

**Asked for.** Lamps on the pavement cell nearest the road, turned so the lamp
head is always on the road's side, with a collision at the foot of the pole.
This replaces D-029's placement (the back of the pavement, and only where a
lamp's height would not reach over the road).

**Decision.**
- **Where.** `StreetProps.kind_at`: a lamp goes on any pavement cell that touches
  the road, every `LAMP_SPACING` cells, except within `CORNER_CLEARANCE` of a
  crossing (two roads meeting) and within a cell either side of the walk from a
  door. Hydrants and bins are unchanged (back of the pavement, beside doors).
- **Which way.** The art has the pole in the left column and the head on an arm
  to the right, so beside a road running down the screen a lamp with the road on
  its left is mirrored (`flip`, `lamp_faces_left`); its light is mirrored with it.
  The kerb cell of the pavement below a road now gets lamps too: the pole rises
  over the road, as a real one seen from this angle does.
- **The foot.** Each lamp has a `Foot` `StaticBody2D`, a child of its sprite so it
  streams with its chunk: 16 x 14 px in the middle of the cell (`LAMP_FOOT`),
  raised from where the art draws the base to where the body's own feet are, or
  a walker on the cell's centre line would pass it. The rest of the lamp is still
  drawn over the walker. Only the player collides; NPC bodies do not collide with
  anything (known issue 6).

**Limit.** Beside a road that runs across the screen the arm cannot point at the
road (it would point at the viewer, and the art has no such view), so a lamp on
the pavement *above* a road has its head along the street, not over the road.
On the pavement below a road the pole rises over the carriageway, so its head
is over the road anyway. Drawing an arm toward the viewer needs new art.

## D-067 — Everything on the ground stops the body where it is drawn

**Asked for.** Collisions on all objects: hydrants, bins, and the rest.

**Decision.** `ArtShape` (new, presentation) turns an art file's opaque pixels
into collision polygons, the technique D-065 used for houses, now shared:
`BuildingArt` uses it too. Each piece says how much of its art collides, in
pixels from the bottom (`foot`), and only that part does, so a walker still
passes behind a tree's canopy or a bin's lid.
- **Street props.** Hydrants and bins: the bottom cell of the art, by outline
  (`StreetProps.KINDS[..]["foot"]`, a body under the sprite, streamed with its
  chunk). Lamps keep the rectangle foot of D-066.
- **Places.** `PlaceArt.DECORATIONS[..]["foot"]`: trees 32 px, benches and cones
  24, the worksite frame and the digger 64. The court's surface is ground and has none.

Physics only: no map cell is blocked for these, so routes and NPC bodies are as
before (NPC bodies collide with nothing, known issue 6). With the art installed,
like the drawing. The outline's points count from the corner of the clipped
part, so `ArtShape.body` offsets by `clip.position`.

## D-068 — Bins at the building's corner, hydrants clear of doors; furniture is the world's

**Asked for.** Bins and hydrants out from in front of doors, e.g. at a house's
corner.

**Decision.**
- **Bins.** One for each building, at the front corner *farthest from its door*,
  on the first pavement cell below the footprint (past the porch a home's art
  draws): `StreetFurniture.bin_cell`. Never in front of a door: a test walks
  every bin and hydrant in the real town against every door.
- **Hydrants.** Still the back edge of a pavement strip on their own offset, but
  kept `DOOR_CLEARANCE` columns and four rows from any door, and
  `HYDRANT_CLEARANCE` cells from any bin or other hydrant.
- **Where it lives.** The placement moved out of `StreetProps` (presentation)
  into `StreetFurniture` (world), pure and art-free, because a bin is going to be
  searched (D-069) and a hydrant is in the way whatever is drawn. Bins and hydrants
  are `DistrictMap.furniture`: cell -> {kind, id}; they **block their cell**
  (`is_blocked`), so routes go round them. Lamps stay computed on demand
  (`lamp_at`) and block only their foot. `StreetProps` keeps the drawing and thin
  wrappers, so the drawing code and the tests read as before.
- The check that runs for every cell is the cheap one first (the spacing sum),
  which took map building from ~50 ms back to noise.

## D-069 — The street's bins can be searched, and things left in them

**Asked for.** Bins you can look into, and put things in.

**Decision.**
- **What is in a bin** is rolled the first time the player searches it, once,
  from `data/bins.json` (`bin_street`: a weighted table of cheap things, zero to
  three rolls, capacity 30) and the seeded `bins` stream, then kept. Everything
  the player puts in stays, so a bin is also a hiding place. An *empty* bin is
  left alone for `refill_days` (3), then somebody has thrown something in; a bin
  holding anything is never topped up. `Bins` (`src/economy/`) holds the state.
- **Rules.** Press the button facing a bin on the pavement: `Game.interact_at`
  sets `open_bin` and answers `bin`. `Game.bin_put` / `bin_take` refuse
  `not_at_bin` (not standing right beside it), `bad_quantity`, `not_owned`,
  `bin_full`, `too_heavy`, each through `action_rejected`. Moves show in the
  event feed like any other bag change.
- **The window** is the cupboard's (`StashWindow`, now with a `kind`: "stash" or
  "bin"), a second instance in the world scene with the bin's own words; closing
  it ends the search. A hydrant has no interaction.
- **Saved** as the new `bins` section (schema v11, migration `_v10_to_v11`: no
  bin has been searched).

**Not built.** Nobody sees you at it and it is never a crime; people have no
belongings, so nothing of theirs is thrown away in one; nothing you find is
dirty or risky to eat; a search takes no time. The loot table is small and
cheap on purpose: it is a pocket-money find, not an economy.

## D-070 — Pictures for every item, things put together, and things to hit with

**Asked for.** Icons for a great many items (each drug and medicine, and the
tools that go with them); a Minecraft-style window for combining things — a spoon
and a bag of heroin make a spoon of brown powder, that and water make a spoon of
dark liquid; a cannabis bud and a rolling paper make a joint; and more weapons:
a puukko, a pesäpallo bat and so on.

**Decision.**
- **Icons are ours, not LimeZu's.** 16x16 pixel art written as text in
  `data/item_icons.json` (a palette of one-letter colours, named pieces of art,
  and per item the pieces stacked, each with optional colour overrides), painted
  into textures by `ItemIcons` and shown at 3x with no smoothing. Being our own,
  it is committed and needs no importer, unlike the LimeZu art. Stacking is how a
  spoon with powder, liquid or bubbles, a syringe with something in it, and three
  bags of different powders are each drawn once. `ItemIcons.problems()` is what the
  tests use: every item must have an icon, every row 16 wide, every letter in the
  palette. An item without one shows a question mark. `ItemSlot` (a button, for the
  bench) and `ItemIcons.tile()` (a picture, for lists) are the two ways to show it;
  the bag, cupboard, bins, shop, bench and fight window use them.
- **52 new items** (66 in all). New kinds `drug` (used like food: it moves the
  condition meters) and `weapon`. Three new item fields, all data: `needs_any`
  (a cigarette or joint wants a lighter or matches in the bag; refused `needs_fire`),
  `leaves` (what is left when it is used: an empty bottle, a used syringe, an empty
  baggie) and `damage` (a weapon's bonus to every blow). A raw bag of heroin, a
  bud, ground cannabis do nothing when used — they are for the bench.
  - drugs and drink: heroin, cocaine and amphetamine bags, cannabis (bud, ground,
    joint, loaded pipe), cigarettes (loose), ecstasy, LSD, mushrooms, vodka, wine
  - medicine: painkillers, strong painkillers, sleeping pills, antidepressants,
    antiseptic, plasters, naloxone, a first aid kit
  - gear: lighter, matches, papers, grinder, pipe, spoon (and three states of it),
    syringe (loaded, used), scale, water, cloth, tape, nails, bottles, baggies
  - weapons: puukko, kitchen knife, pesäpallo bat, hockey stick, hammer, iron pipe,
    screwdriver, brass knuckles, baton, axe, broken bottle, nail bat (the crowbar
    keeps its 0.06, now from data)
- **Putting things together.** `data/recipes.json` (14 to begin with), judged by
  `CraftRules` (pure) and done by `Game.craft()`: the window proposes the things
  on its grid, the rules say what they make, Godot uses things up, hands things
  over and takes the minutes. **Shapeless and exact**: what is on the grid must be
  what a recipe takes, in any place; a stray extra thing spoils it. `keeps` names
  tools that are needed but not used up (a lighter, a grinder, the water). Two
  recipes may not take the same things (`DataRegistry` checks it). Refused
  `no_recipe`, `not_owned`, `too_heavy` (the result must fit, whole), `busy`.
- **The bench** opens on **C**, anywhere, like the bag (`CraftWindow`): a 3x3 grid,
  an arrow, the result and a Make button; your bag as a grid of slots; a book of
  recipes you have found, each of which lays itself out when clicked. Laying
  things out never moves them: the bag is only touched by Make.
- **Recipes find you, as in Minecraft:** one is in the book once you have held
  everything it needs, or once you have made it. Saved in `PlayerState.known_recipes`
  (schema v12, migration `_v11_to_v12`: none known; the bench finds what the bag
  already allows when next opened). The feed says "New recipe: ...".
- **Weapons** — `FightDirector.wielded_weapon()` is the carried item with the
  most `damage`; nothing is equipped and nothing wears out. The fight window shows
  it beside your bars. (Before this, only the crowbar counted, by a constant.)
- **Where things come from.** The corner shop sells lighters, matches, papers,
  water, wine, painkillers, plasters, antiseptic and spoons; the bar vodka; the pawn
  shop the blunt things, tape, nails, a pipe, a grinder and scales, and now buys
  weapons; the street bins hold cheap paraphernalia and, rarely, a joint, a bud,
  a pill or a bag of something (a dropped wrap).

**Not built, on purpose.**
- **No way to buy drugs.** A dealer or black market is a system of its own (who
  sells, to whom, at what risk, what the police make of it) and changes what the
  game is about; it is the user's call. Until then they only turn up in bins.
- **No addiction, tolerance or overdose;** a drug only moves the meters (heroin
  costs health, stimulants cost sleep back later through the meters' own drift).
- **No crime in carrying or using anything,** and nobody reacts to a weapon in your
  bag or a needle in your hand. Assault with a weapon is the same offence as
  without.
- **No firearms.** A gun changes what a fight is (nobody dies today, D-054); ask
  before adding one. No pepper spray or thrown things either: they are actions,
  not damage bonuses, and would need a place in the fight window.
- No durability, no equip slot, no crafting skill, no stations (the bench is
  everywhere), and every recipe is hand-authored: there is no unlocking by
  teachers or books.

## D-071 — Many more recipes

**Asked for.** "Far more recipes to unlock."

**Decision.** 48 more recipes (61 in all) and 49 more items, each with an icon,
an English and a Finnish name, and somewhere to be found (`test_crafting` checks
that every ingredient can be bought, found in a bin, or made).
- **A light is a rule, not a recipe input.** `"fire": true` on a recipe means one
  lighter *or* one box of matches must be laid on the grid, and is not used up
  (`CraftRules.fire_in`, `ingredients_of`). Every cooking recipe would otherwise
  have been written twice; the spoon's heating step now works either way, and
  `rcp_spoon_cooked_matches` is gone. The data check counts a fire recipe as two
  possible grids, so it cannot clash with a plain one. Recipes need not have it:
  `keeps` still names tools (pan, water, hammer) that must be on the grid too.
- **Kitchen:** bread, cheese, ham, sausage, tomato, eggs, milk, flour, sugar, butter,
  potato, fish, juice, tea; sandwiches, a hot dog, fried eggs, an omelette,
  pancakes, baked potato, cinnamon buns, fish, coffee with milk, tea, a mixed
  drink, mulled wine. Sold at the corner shop; a frying pan, rope and bricks at
  the pawn shop.
- **Cannabis and the rest, as things to prepare, not to make from chemicals:** a
  spliff, hand-rolled cigarettes, a bong from a bottle and a pipe, cannabis tea,
  butter and brownies, mushroom tea, and wiping the spoon clean at any step.
- **First aid:** a splint, a cold compress, plasters from cloth, bandages or
  antiseptic from vodka and cloth. **Materials:** rope, sticks (from bins or a broken
  hockey stick), an emptied toolbox, nails pried out of a nail bat.
- **Things to hit with, made by hand:** a club, a nail club, a spear, a shiv, a
  sharpened stick, a taped pipe, a brick in a sock (a frying pan, a stick and a
  brick count too). The best of what you carry is in your hand.

**Not built, on purpose.** No recipe makes a drug from raw ingredients or
chemicals: the drugs you can find are only prepared and used. That line is
deliberate, not a gap.

## D-072 — Old Town and Eastfield, and the roads between the districts

**Asked for.** "The town is getting small: add the next areas from the plan."
That is the first part of M7. Asked for directly, so the shape below was my
call; the rest of M7 (factions, the story, audio, revelation of the map) is
untouched.

**Decision.**
- **Two districts, 96x72 like Harbourside, on the same tools.** `data/maps.json`
  (rectangles), the same LimeZu buildings (8x13 storefronts and civic buildings,
  8x11 villas, so each gets its drawn art and collision) and street furniture, and
  `PlaceArt` for gardens, benches, a pitch and the yard's digger. **Old Town**
  (a straight main street, a square, a garden and a market, with the pawn shop
  that was already on the books): bakery, pharmacy, a bar (the Lantern), town
  hall, library, savings bank with a cash machine, church, five homes.
  **Eastfield** (roads, sand yards, open ground): fuel station, garage, a bar (the
  Furnace), a locked old cannery, the yard, a scrapyard, a pitch, five homes.
  Both are on the same layout as Harbourside, so they read as a place at once
  but look like it. Different building art for Old Town's "older money" would
  mean a new LimeZu importer, not more data.
- **Ten people, five to a district**, and a routine of their own each so nobody
  commutes across maps (a test walks every one through a week: a person who
  ever leaves their district fails it). Old Town: Aarne (pawn), Helmi (baker),
  Tapio (pharmacist), Ilona (librarian), Oskar (the Lantern). Eastfield: Reijo
  (yard foreman), Pauliina (fuel station), Jari (garage), Marko (the Furnace),
  Kimmo (scrap). Six new occupations, eight schedules, five shops (bakery,
  pharmacy, the Lantern, the fuel station, the Furnace; the pawn shop's stock
  was already there), two jobs (a casual one at the yard for Reijo, a counter
  job at the bakery for Helmi), and every building an interior. Bios are
  Harbourside's in tone and touch it lightly (Aarne and Kimmo know Rauno).
- **The road is a rule now.** Nobody ever called `try_unlock`, so nothing but a
  test could open a district. Walking onto an exit now asks `WorldState.
  try_unlock` with the player's own means; if the way is closed
  `Events.region_refused(region, reason)` says why in a sentence (`ui.msg.locked.*`,
  never the list) and the body is put back. **Old Town** wants `heard_about_old_town`,
  which reading the bus timetable at the stop gives (an object may carry
  `sets_flag`); **Eastfield** wants €120 and Veikko's number — the two kinds of
  gate the data already asked for.
- **The walk costs what the road does.** Crossing takes `Region.travel_times`
  minutes (18 to Old Town, 25 between the two, 35 to Eastfield), passed in one
  batched step, then `world.enter_region` and a re-tiering of who is simulated
  (`Events.player_travelled`). You arrive on the road you came in by, a few
  cells in from the exit, not on the exit or at a fixed spawn
  (`DistrictMap.arrival_from`); someone walking with you stays behind, as before.
- **The benchmark had to change.** It dealt clones' homes across every district
  while keeping their workplaces, so once there were homes in three districts
  Harbourside's clones commuted between maps. Clones now live in the district of
  the person they copy. Concentrated in one district: back to the earlier numbers
  (about 1.0 / 1.9-2.1 / 4.4-4.8 ms per simulated minute at 200 / 1000 / 3000
  people). Spread across all three: about 1.7x that at 3000, because everyone in
  a neighbouring district is ticked at the background tier and all three are
  each other's neighbours; at the real population (about 20) this is noise.

**Not built.** No police or clinic outside Harbourside (Marika answers only
there); no factions, main story or district-specific quests; no travel by bus or
any means but walking; the map on the phone does not draw the new districts
(only places you have been to appear, so it fills as you go); people do not
travel between districts on their own (a routine stays in one); the cannery is
locked with nothing behind it yet.

## D-073 — Trees on grass, and no lamp at the mouth of a side street

**Found in play** (Old Town): trees standing on paving, and a lamp at the top of
the side street looking lost.
- A tree now stands on **grass only**, and `test_place_art` checks every cell of
  every tree in every district. A first try laid grass patches under trees in the
  paved square and market; in play they looked like planters in the middle of
  paving, so those trees were moved to the garden instead: the square and the
  market are paving and benches only, and the garden holds all of Old Town's trees.
- **Lamps** skip a pavement cell whose only road is one that ends at that strip
  (`StreetFurniture._only_lights_a_road_end`): the strip is already lit from the
  main road. Harbourside's lamps are unchanged (its side road merges into the
  main road, with no pavement between).

## D-074 — Light beams under the street lamps

**Asked for.** Beams of light from the street lamps in the evenings.

**Decision.** Each lamp's pool of light (D-032) now has a **beam**: a second
`PointLight2D`, a child of the lamp's light, drawn with one shared soft cone
(176x132, narrow at the lamp's head and wide and faint at the ground, feathered
along both edges, built once as an `ImageTexture`). It follows the lamp's
mirroring, and is switched on, off and dimmed by the same `lamp_energy` as the
pool (`DayNight.lamp_energy_for`), so it comes up at dusk and is gone by day;
a beam costs nothing when the lamp is off. Both lights are still one per lamp
in `lamp_lights()`; the beam is found as its child `Beam`.

**Not built.** Lamps still light through walls (no light occluders on
buildings); no flicker; the lamps' look by day is unchanged.

## D-075 — A greeting about the job is said at the job

**Found in play:** Veikko, in the Anchor, opened with "Mind the ropes."
Six people had a personal greeting written for their workplace (Ida's shop,
Veikko's harbour, Tuomas's bar, Sanna's clinic, Marika's post, Leena's cafe)
and used it wherever they stood.
- Those lines are now `greet_work`, chosen by `DialogueDirector._opening_topic`
  when the person is at their own workplace; they each got two new off-duty
  `greet` lines for everywhere else (English and Finnish).
- Anyone whose greeting is not about the job (Elias, Rauno, Pirjo, Joonas) is
  unchanged. Later greetings (met before, texted, known) were never
  place-bound.
- `test_every_job_greeting_has_an_off_duty_twin` keeps both halves together.

**Not checked / possible:** other authored lines that name a place or task
(farewells, "about work") were not audited one by one; say if any more turn up.

## D-076 — Time passing on screen

**Asked for.** A small animation when you go to sleep, so time does not just
jump; the same for a working day.

**Decision.** `TimeSkipOverlay` (`scenes/ui/time_skip_overlay.tscn`, a layer
above every window). The world has already moved on when it plays (the rules
apply a night or a shift in one step, D-042), so the picture from *before*
(`WorldView._snapshot()`, taken just before the bed or the workplace is used) is
faded to black rather than the world, a line says what is going on ("Sleeping…",
"Working your shift…") while the clock runs from when it began to when it ended
(the result now carries the shift's `minutes`), and then the real, new picture
is uncovered. About two seconds for a night, a little more for a long shift; any
key or click skips it. While it plays walking waits and the game clock is held;
a message that was waiting ("You sleep, and wake at 07:00. The day is saved.")
is shown once it is over, not lost during it.
- The same scene, without a snapshot and for its own words, covers a **walk
  between districts** ("Walking to Old Town…", D-072), **a collapse** ("Everything
  goes dark…") and **a night in the cells**; the last two show no clock.
- It only shows: nothing in `Game` changed except the shift's result gaining
  `minutes`, and `test_time_skip` checks the scene, the input hold, the wrapped
  clock and that a refused bed plays nothing. Headless runs take no snapshot.

**Not built.** No sounds; no bed-side or sunrise picture; a shift is not
animated as work (no worker sprite), only the clock; a short nap or a `use_item`
that takes minutes plays nothing.

## D-077 — Regions are freely walkable

**Asked for (M8).** The user played Humptown and found it dull: the town felt
like a corridor because Old Town and Eastfield sat behind unlock gates (read
the bus timetable, carry EUR 120 and a contact). Decided when asked: regions
are open from the start; walking between them still costs time, halved from
before.

**Decision.** `data/regions.json` no longer carries any `unlock` requirements;
`Region.from_data` already defaults `unlocked` to `unlock.is_empty()`, so all
three regions start open. `Game._travel_to_region` no longer calls
`WorldState.try_unlock` before crossing a border, and `WorldState.enter_region`
no longer refuses on `not region.unlocked` — both checks are gone, not just
unreachable, so a save with a stale `unlocked: false` from before this change
cannot relock a road either. `evaluate_unlock` and `try_unlock` stay in
`WorldState`, unused today: a road may still be shut later, and `Events.region_refused`
stays wired for that day. Travel times are halved: harbourside↔old_town 18→9,
harbourside↔eastfield 35→18, old_town↔eastfield 25→13 minutes.

**Tests.** `test_locked_regions_use_varied_unlock_mechanisms` (test_content.gd)
is deleted — no region gates any more, so the property it checked cannot hold.
`test_unlock_requires_every_condition` and `test_unlocks_use_different_mechanisms`
(test_world_npcs.gd) are deleted for the same reason: they exercised
`evaluate_unlock` against real content that no longer has requirements to
evaluate. The rest invert in place: `test_old_town_is_closed_until_you_have_heard_of_it`
→ `test_old_town_is_open_from_the_start`, `test_eastfield_wants_money_and_a_contact`
→ `test_eastfield_is_open_with_no_money_and_no_contact`,
`test_walking_onto_an_exit_to_a_locked_region_is_refused` →
`test_walking_onto_an_exit_to_an_open_region_works`, `test_entering_a_locked_region_is_refused`
→ `test_entering_any_known_region_works`. `test_a_refusal_is_said_in_words` is
deleted: nothing triggers `region_refused` today, so there is no refusal to say
in words. The bus timetable sign still exists and still sets
`heard_about_old_town` when read (kept as flavour, `test_the_bus_timetable_can_still_be_read`);
the `ui.msg.locked.*` locale keys are left in place, unused, for the same
reason the unlock functions are.

**Benchmark.** Re-run after this change: numbers on this machine run notably
above the last recorded baseline (~7000 µs/minute at 3000 people, spread,
against a ~3188 baseline), but a back-to-back run against the prior commit
(e2234b6) shows the same elevation there too — the baseline in
`PROJECT_STATUS.md` simply predates D-072's two new regions and was never
re-measured after it. This change itself causes no regression.

## D-078 — `GameWindow`, the base every modal window shares

**Why (M8 step 2).** `InventoryWindow` and `CraftWindow` are about to merge
into one `ItemsWindow` (M8 step 3). Before that merge, the ~25 lines the two
already had in common — `_root`, `_time_was_paused`, `closed`, `is_open`,
closing on `ui_cancel`, the `"ui.<prefix>.refused." + code` lookup — are
pulled into a base class, `GameWindow` (`src/ui/game_window.gd`), so the merge
starts from a smaller diff. Only these two windows are converted; the other
seven `CanvasLayer` windows (`ShopWindow`, `PhoneWindow`, `QuestWindow`, …)
are left as they are, for a later commit.

**Shape.** `GameWindow extends CanvasLayer` owns `open()`/`close()`/`is_open()`,
the pause/resume of the clock, and `_unhandled_input` for `ui_cancel` plus one
optional `toggle_action` a subclass sets in its own `_ready()` (`"inventory"`,
`"craft"`). It owns no rendering, data or focus: `open()` calls two virtual
hooks a subclass overrides — `_before_show()` (render and reset, called before
the window is shown) and `_focus_first()` (defaults to the close button).
`_refusal_text(prefix, code)` centralises the `"<prefix>.refused." + code`
lookup with its `"<prefix>.refused.other"` fallback, used by both windows'
own refusal-message builders. `_root` and `_close` are declared once in the
base with `$Root` / `%Close`, which resolves correctly in either subclass's
scene because every window scene already has a `Root` node and a
unique-named `Close` button.

**No behaviour change.** `InventoryWindow` and `CraftWindow` keep their public
method surface and every test untouched; the suite is green with the same
1009 tests before and after. This step is deliberately boring — the visible
merge is D-079.

## D-079 — One window for things: `ItemsWindow`

**Why (M8 step 3).** The bag (`I`) and the bench (`C`) were two windows that
shared a footer, a weight line and a refusal pattern, and could not both be
seen at once — you could not read what a thing does while deciding to craft
with it. `InventoryWindow` and `CraftWindow` are gone; `ItemsWindow`
(`src/ui/items_window.gd` + `scenes/ui/items_window.tscn`, `extends
GameWindow`) replaces both, as three tabs — **Bag**, **Bench**, **Recipes** —
on the `%BuyTab`/`%SellTab` toggle-button precedent already in
`shop_window.tscn`.

**The split.** The Bag tab is exactly the old bag: the row list (`_rows`),
Use buttons, the same refusal words. The Bench tab is the old bench's grid
column plus its own bag-picker grid (`_bag_grid`) side by side — you still
pick from your bag onto the 3×3 grid in one view. The recipe book, previously
a third column glued to the bench, is its own **Recipes** tab now — a
reorganisation, not new gameplay, since `book_texts()` reads the same rows
either way. `Condition`, `Job`, `Message` and `Carrying` sit outside the tab
body and stay current regardless of which tab is showing, same as before.

**`I` opens on Bag, `C` opens on Bench — and if the window is already open,
the key switches tab instead of closing it.** This is a real, deliberate
behaviour change from the old two-window design, where pressing the same key
twice closed the window (each window closed on its own toggle key via
`GameWindow.toggle_action`, D-078). `ItemsWindow` leaves `toggle_action`
unset — only `ui_cancel` (Esc) closes it now — and `WorldView.open_bag()` /
`open_bench()` both call `ItemsWindow.open_on(tab)`, which opens on that tab
if closed or just calls `show_tab(tab)` if already open. One `if`, as
intended: `open_on()` is the only place that decides.

**`world.tscn` edited in the same commit** (one-way door #5): `$Inventory`
(instancing `inventory_window.tscn`) and `$Craft` (`craft_window.tscn`) are
gone, replaced by one `$Items` instancing `items_window.tscn`. Both old
script+scene pairs are deleted in this commit too — leaving them would have
split every world-driving test into "before" and "after" failures instead of
one clean pass. `WorldView` drops `_bag`/`_craft` for one `_items:
ItemsWindow`, collapsing the three places that named both of them by hand:
the `@onready` block, the `_refresh_prompt()` OR-chain, and the two close-all
blocks in `_on_player_collapsed()`/`_on_player_arrested()`. `open_inventory()`
/`open_crafting()`/`inventory_window()`/`craft_window()` are renamed
`open_bag()`/`open_bench()`/`items_window()` — `WorldView`'s own accessor
names, not part of the preserved surface the ground truth named, so they
follow the new shape.

**Public method surface kept, as promised**: `row_texts`, `message`, `use`,
`grid_ids`, `output_id`, `can_make`, `result_text`, `bag_texts`, `book_texts`,
`place`, `take_off`, `clear`, `fill_recipe`, `make` are all on `ItemsWindow`
unchanged in shape. `open()` (inherited from `GameWindow`, no argument)
defaults to whichever tab is current — `Tab.BAG` the first time — so
`test_condition.gd`'s `bag.open()` needed only a scene path and a type
change, not a rewrite.

**Tests.** `test_craft_window.gd` is deleted; its content becomes
`tests/test_items_window.gd`, ported mechanically (`craft_window()` →
`items_window()`, `open_crafting()` → `open_bench()`), plus three new tests
for the merge itself: opening on the right tab, switching tabs without
closing, and the bag and the bench agreeing on what is carried.
`test_item_icons.gd:99` and `test_condition.gd:143` are ported the same way.
`src/debug/ui_preview.gd`'s `--bag`/`--craft` flags are unchanged from the
player's side; internally both now call through `open_bag()`/`open_bench()`/
`items_window()`.

**Not built here.** No equipment, no examine panel, no `WORN` column — those
are D-080 and D-081. The recipe book's move to its own tab is the only
visible change a player would notice; everything else is the same words in a
new container.

## D-080 — Equipment: six slots, a pointer not a move

**Why (M8 step 4).** `wielded_weapon()` scanned the whole bag for the biggest
`damage` — never wrong, but never a choice either, and `item_backpack.
capacity_bonus` sat in `data/items.json` read by nothing. Six slots close
both gaps: `head, body, legs, feet, hand, back`, no more — four for armour,
one so a fight's weapon can be a decision, one so the backpack finally does
something.

**Data.** `"slot": "hand"` on the 19 `kind: "weapon"` items (a sed pass over
`data/items.json`, verified by count before and after — the tools/frying-pan/
stick/brick items that can also land a blow keep no slot, since they are
found weapons, not equipment). `item_work_boots` gets `"slot": "feet",
"armour": 0.05`; `item_backpack` gets `"slot": "back"` alongside its existing
`capacity_bonus: 10.0`.

**`EquipRules`** (`src/economy/equip_rules.gd`, pure, the `ShopRules`
pattern): `judge_equip({owned, slot})` refuses `not_owned` / `not_equipable`;
`judge_unequip({worn})` refuses `not_worn`. Wearing something else in an
occupied slot is not a refusal — it just moves the pointer; no unequip step
first, the way changing boots does not need you to stand barefoot in between.

**`PlayerState.equipment: Dictionary`** (slot → item id), *not* `Stack.state`
— `state` forces a non-merging stack (three bandages would silently split
into three stacks) and `Inventory` has no stack identity, so "which of my two
knives" has no answer a pointer-by-item-id can't already give more simply.
A worn thing is still in `inventory` and still weighs what it always did;
equipping never moves it.

**`reconcile_equipment()`** (on `PlayerState`) does two things every time it
runs: clears any slot whose item is no longer owned (closes the leak where a
worn thing was sold, given or crafted away while still pointed to as
equipped), then reapplies the capacity bonus from whatever backpack is
currently worn. `Game._on_inventory_changed()` calls it on every
`Events.inventory_changed` — which fires for the stash and for bins too, not
only the bag, since all three are the same `Inventory` class; the guard is
cheap enough (six slots, one data lookup each) that this is not worth
narrowing. `Game.equip()`/`unequip()` also call it directly, so the capacity
bonus is current the instant a backpack goes on or comes off, not just when
the bag's contents next change.

**The stash guard, kept where the plan said it would be needed.**
`_apply_carry_capacity()` sets `inventory.bonus_capacity` — never
`stash.bonus_capacity` — because `equipment` only ever points at things a
*worn* slot can hold, and nothing wears a slot into the cupboard.
`test_home.gd:78-79` already asserted stash capacity with an unequipped
backpack sitting in the stash; `tests/test_equipment.gd`'s
`test_a_backpack_in_the_stash_does_not_widen_the_stash` asserts the same
thing from the equipment side, now that there is something that *could*
wire it up wrong.

**`wielded_weapon()` prefers the hand slot, unconditionally — not the
highest-damage option between it and the bag** (one-way door #4, kept):
equipping a weapon is now a real choice, so a deliberately-worn hammer is used
over a puukko sitting unequipped in the bag. Empty hand slot, or the worn
thing has left the bag: the fallback scan runs exactly as it always has, so
every existing fight test and every existing save's fights stay exactly as
strong as before.

**Armour**: one multiplicative, capped term at the very end of
`CombatRules.damage()` — `dealt *= 1.0 - clampf(defender.get("armour", 0.0),
0.0, ARMOUR_CAP)`, `ARMOUR_CAP := 0.6` so nothing is ever untouchable.
Defaults to `0.0`, so no existing combatant dict had to change; only
`FightDirector._player_combatant()` sums it now, from
`ItemRules.armour_of()` over whatever the player has on. NPCs do not wear
armour yet — nothing authors it for them, so their combatant dicts stay as
they were.

**Migration v13** (one-way door #2, closed now): `player.equipment` defaults
to `{}` for a save that predates it (`_v12_to_v13`, mirroring `_v11_to_v12`'s
shape exactly). Fixture test alongside the feature, `tests/test_equipment.gd
:test_an_older_save_has_nothing_equipped`, the same pattern as
`test_crafting.gd:test_an_older_save_knows_no_recipes`.

**Not built here.** No UI: no WORN column, no Wear/Take off buttons.
`Game.equip()`/`unequip()` are complete and tested through `Game` directly,
the way every other action in this codebase is tested before its window
exists. The panel that calls them is D-081, alongside examine — a player
cannot wear anything through the interface until that step lands.

## D-081 — Examine, and the WORN/EXAMINE panels that finish `ItemsWindow`

**Why (M8 step 5, the last of session A).** Nothing told the player what a
thing in their bag actually *did* — no way to read a joint's effects before
rolling one, no way to see a weapon's bite before carrying it into a fight,
and, since D-080 landed with no UI, no way to wear the boots it made
equipable. This step closes all three: `ItemFacts` generates what to say,
`ItemsWindow` gains two more panels (WORN on the left, EXAMINE on the right,
both visible on every tab) to say it and to act on it.

**`ItemFacts`** (`src/presentation/item_facts.gd`, pure, the `ItemRules`
pattern): `facts_of(item) -> Array[Dictionary]` returns `{key, args}` —
never a finished string, so the window localises every fact the same way
everything else on screen is. Generated for all 115 items: kind, weight,
value (omitted when 0 — a lot of misc items are worthless and saying so
twice is noise), then whichever of the five condition meters the item
touches (`hunger`/`sleep`/`health`/`stress`/`intoxication`, sign read off
each item's own field — no guessing), damage **banded** into light/moderate/
heavy so a raw `0.13` is never printed, where it is worn (`slot`), whether it
softens a blow (`armour`), widens the bag (`capacity_bonus`), needs a light
(`needs_any`), leaves something behind (`leaves`, naming the left-behind item
by its own `name_of()`), and one line for every `kind: "drug"` item: "You
would not want to be caught with it." `description_of(item)` reads the
optional authored sentence at `item.<slug>.desc` (the `skill.<id>.desc`
precedent, previously authored but never consumed by any code — this is its
first reader), checked with `Localization.t(key) != key` so a missing one is
never an error. **30 of 115 items are authored** (a spread across weapons,
drugs, tools, medical, documents, drink); the other 85 rely on generated
facts alone, deliberately — `test_content_name_keys_all_have_english_strings`
(`tests/test_localization.gd`) is **not** extended to require one, with the
reason written into its own docstring, since checking `name_key` and
checking an optional `.desc` are different questions.

**`ItemRules.KEEP`**, moved here from `DialogueDirector.GIFT_KEEP` — the
phone and the keys, the two things the player can never give away. One list
of "things the game does not work without", where the conventions doc always
said it should live, now that `ItemRules` is clearly the home for
cross-cutting item facts rather than just usable-item judging.

**`ItemsWindow` gains two panels, both visible regardless of tab** (`M8
step 3's` three-tab body sits between them, untouched in shape): **WORN**
(left, `custom_minimum_size 140`) is six always-present rows, one per
`EquipRules.SLOTS`, each an `ItemSlot` + a label reading the worn thing's
name or, empty, the slot's own name ("Head", "Feet", …); clicking an
occupied one calls `examine()`. **EXAMINE** (right, `custom_minimum_size
200`) shows the selected item's icon, name, a kind·weight·value summary
line (the first three `ItemFacts`, joined), the authored sentence if there
is one, every other generated fact, and up to four buttons — **Use**,
**Wear**, **Take off**, **Lay on bench** — each `.visible` set from what the
selected item actually is and whether it is owned or worn, not from which
tab is open. `_examine_icon` is one persistent `ItemSlot` built once in
`_ready()`, the `_output`/`_grid_slots` pattern already established.

**Selecting for examine is a `gui_input` handler on each bag row, not a
new child node** — `row.mouse_filter = STOP` and a left-click check inside
`gui_input`, so `row.get_child(0)` stays the `PanelContainer` from
`ItemIcons.tile()` and `item_name` stays a `Label`. Either would have broken
an existing test (`test_the_bag_and_the_shop_rows_carry_the_picture`'s
`row.get_child(0) is PanelContainer`, or `row_texts()`'s `child is Label`
scan) had the row's own children changed shape to make it clickable instead.

**Selection persists across a tab switch, clears on a fresh open**:
`show_tab()` never touches `_selected_item_id`; `_before_show()` resets it to
`""`, so examining a joint on the Bag tab and then switching to Bench to
craft with it keeps the joint in view, but reopening the window later starts
clean.

**Wear/Take off go through `Game.equip()`/`unequip()`** exactly as D-080
left them — the window adds no new rules, only a `"ui.items"`-prefixed
refusal lookup (`not_owned`, `not_equipable`, `not_worn`) alongside the
existing `"ui.bag"` and `"ui.craft"` ones. **Lay on bench** switches to the
Bench tab and calls the existing `place()` — no new rule, a shortcut through
ones that already exist.

**The window widened, then had to be pulled back in.** A first pass at
1480×640 (`Frame` offset ±740/±320) clipped both new columns off-screen
against the project's 1280×720 viewport (`project.godot`
`window/size/viewport_*`) — caught by a screenshot, not a test, since no
test asserts on-screen bounds. Settled at 1040×600 (±520/±300), `Worn` down
to 140px minimum, `Examine` to 200px, the bench's own crafting column from
340px to 240px, column separation from 22px to 14px. Fits with margin at the
project's default resolution; worth another look if the window is ever
resized for a different target resolution.

**Tests.** `tests/test_item_facts.gd` (13 tests): every item gets kind +
weight, value omitted at zero, a food feeds you, damage is banded and never
prints a raw float, a non-weapon has no damage fact, the slot and armour
facts, the backpack's capacity fact, needs-fire, leaves-behind naming the
item, the drug warning (and its absence on food), the authored sentence
round-trip, and a count check that between 25 and 39 items are authored (the
plan's "~30", with room for judgement either side but a guard against
silently doubling every item up by accident). `tests/test_items_window.gd`
gains ten more: nothing selected on a fresh open, examining shows name/
summary/description/facts, selection survives a tab switch, a fresh open
clears it, wearing and taking off through the panel, refusal when examining
something not owned, laying the examined thing on the bench switches tab and
places it, and the worn panel's own row texts.

**Not built here.** No clothing beyond the boots exists yet to fill head/
body/legs — three of six slots have nothing to put in them until M8's later
content sessions author more. Bench-tab and bag-picker-grid items are not
individually examinable (only Bag-tab rows and worn slots are); switch to
the Bag tab first, or use Lay on bench from there. No drag-and-drop; every
interaction here is a click, matching the rest of the window. This closes
M8 session A (steps 1-5); the shady spectrum (steps 6-10) is session B.

**A render ghost, checked and not a bug.** A `--bag=1` screenshot showed a
faint (≈5-10% opacity) ghost of the Bench grid and Recipe book behind the Bag
rows. `test_hidden_tabs_are_actually_hidden` confirms both `visible` and
`is_visible_in_tree()` are correctly `false` for the hidden tabs' bodies — the
game state is right. The ghost is a capture-path artifact of the GL
Compatibility renderer (`WorldView._ready()` and `ui_preview.gd` both call
`DevCapture.maybe_capture`, so the screenshot tool renders twice per run),
not something a player at a real window would see. Worth a look if it recurs
somewhere that matters more than a debug screenshot.

---

## D-082 — `Npc.nature` and `Npc.deals`: personality a rule can read, frozen now, spent later

**Why (M8 step 6, opening session B).** Every NPC has three free-text fields
(`traits`, `bio`, `voice`) that no rule ever reads, so a shady proposal gets
refused identically by a fixer and a librarian — there is no axis for the
game to tell them apart on. `nature` is that axis: **what kind of person
someone is**, not how they feel about the player — `Relationship.
disposition()` already owns the second question, so the new block gets its
own name rather than crowding that one. `deals` names the shop ids a person
deals from, so a future illicit exchange runs entirely through
`ShopRegistry` (price, stock, till, haggling, restock, saving all come free)
instead of a bespoke goods list.

**Four axes, each `[0, 1]`:** `lawfulness` (the gate on illicit trade),
`greed` (lowers the trust a deal needs, raises its price), `risk` (how much
police heat someone will wear, whether they deal with people about), and
`discretion` (how visible a deal becomes in `KnowledgeNetwork` — a chatty
dealer is a real cost even on a successful deal, and this is the one axis
that does not gate anything, which is why there are four and not three).
Defaults are `{lawfulness: 0.8, greed: 0.3, risk: 0.2, discretion: 0.5}` — an
ordinary person who will not deal — applied per-axis in `Npc.from_data`, so
an entry can author one axis and still get sane values for the rest.

**Backfilled for all 20 existing NPCs this step**, by hand, from the traits
and bio already on record — `never_writes_anything_down` and
`asks_no_questions` read as low lawfulness and high discretion; `by_the_book`
reads as `lawfulness: 1.0`; `hears_everything`/`gossips`/`talks_to_everyone`
read as low discretion; a fixer, a pawnbroker and a scrap dealer who "knows
where things came from" land furthest from the default; a constable lands at
the opposite corner. These are judgement calls, not a formula — the point of
authoring by hand is that the numbers should already feel right to anyone
who has read the bios, without inventing a scoring rule that would have to
be defended line by line.

**`deals` stays empty on every NPC this step.** The field is parsed and
validated (`DataRegistry._npc_nature_problems`: a deal must name a real
`shops` entry) but nothing is authored into it yet, because the shops it
would point at do not exist until step 8. Authoring `deals: ["shop_rauno_
pocket"]` on Rauno now, before that shop exists, would fail the very
reference check it is there to enforce — so the shop and the deal that names
it land together, in the same later commit, the way `test_asks.gd`'s
`ask_broken` fixture shows a bad reference should always be caught, never
silently accepted for one commit and fixed in the next.

**This is the one-way door the plan called out.** Renaming `nature` or
`deals`, or any of the four axis names, is free today and stops being free
the moment 30–40 more NPCs are authored against them in session C (step 12).
Nothing reads `nature` or `deals` yet — `DealRules` (step 7) is the first
consumer — so this step is exactly what it claims to be: the schema frozen,
zero behaviour change. 11 new tests in `tests/test_npc_nature.gd`: defaults,
partial-axis backfill, the four validator refusal paths (out-of-range axis,
unknown axis name, non-numeric axis, a deal naming an unknown shop) and their
happy-path counterparts. Benchmark re-run back to back on the same machine
(`Npc.gd` is under `src/npc/`): first sample ran high at the top two
populations, a second sample landed back in line with the pre-change
baseline — the same run-to-run drift on this machine already noted in
D-077, not a regression from four extra dictionary lookups at load time.

---

## D-083 — `DealRules`: the gate order for a grey or illicit deal

**Why (M8 step 7).** The plan weighed three mechanisms for the illicit trade
and recommended a hybrid: the exchange itself runs through `ShopWindow` like
any other shop, priced from data; the only new judgement is whether the
keeper will deal with the player *at all*, and on what terms. `DealRules`
(`src/economy/deal_rules.gd`, pure, the `ShopRules`/`AskRules` pattern —
facts in, a `Result` out, nothing changes on a refusal) is that judgement.
It is unused this step: `ask_deal` (step 9) is its first caller. Writing it
now, against synthetic facts, means the eight-check order and every refusal
code are settled and tested before anything in the game depends on them.

**The order is the design**, unchanged from the plan's table: `not_a_dealer`
(no deal covers this shop) → `wont_deal` (`legality == "illicit"` and
`lawfulness > 0.6` — a shop that is merely `"grey"` never checks lawfulness
at all, so a by-the-book pawnbroker can still fence, just not deal drugs) →
`requires_unmet` (the shop's own authored gate, checked by the caller) →
`dont_know_you` / `dont_trust_you` (skipped entirely when `vouched`, not
loosened) → `bad_standing` (criminal-scope `Reputation` below `-0.2`) →
`too_hot` (`heat > risk`) → `not_now` (someone is watching and `risk < 0.7`).
Earlier checks always win: `test_checks_run_in_order_not_a_dealer_first`
sets every other fact to its worst value and confirms `not_a_dealer` is
still what comes back.

**The two floors and the two success numbers are formulas I chose**, since
the plan named the shape ("familiarity below a greed/lawfulness-shaped
floor", "trust below a risk/greed-shaped floor") but not the arithmetic:
`familiarity_floor = 0.6 − greed×0.4 + lawfulness×0.3` (greed lowers how
well a dealer needs to know you, lawfulness raises it back even in someone
greedy) and `trust_floor = 0.6 − greed×0.3 − risk×0.3` (a dealer's own risk
tolerance also lowers how much trust they need, the way a cautious one would
not take the chance). Success returns `{"factor", "visibility"}`, never a
plain yes: `price_factor = clamp(1.0 + greed×0.6 − closeness×0.3, 0.5, 2.5)`
(closeness averages familiarity and trust, trust floored at zero so
distrust never becomes a discount) and `visibility_for(discretion) =
clamp(1.0 − discretion, 0.05, 1.0)` — discretion **is** the inverse of
visibility, the one axis of `nature` that never gates anything, only costs;
never quite zero, so even the most discreet dealer leaves some trace in
`KnowledgeNetwork` once step 9 wires the write. These constants are a
starting point, not a locked contract — nothing downstream depends on their
exact values yet, only on the shape (`Result` with those two keys on
success).

**`heat`, the player's current standing with the police in [0, 1] the way
this step defines it, is not computed anywhere yet.** `DealRules.judge`
takes it as a caller-supplied fact, same as every other input; something
step 9 or 10 will derive it from (recent crime record, an open summons) is
an open question for that step, not this one — this step only needed a
number in a known range to gate against `risk`. Not to be confused with the
per-*item* `heat` the plan adds to `items.json` in step 10, which feeds a
deal's *visibility* as a crime, not this gate.

17 new tests in `tests/test_deals.gd`: the eight refusal codes, the happy
path, vouching skipping both feeling floors, a lawful person still dealing
at a merely-grey shop, check ordering, and the `price_factor`/
`visibility_for` formulas' monotonicity and range. No benchmark — nothing
calls this yet, so nothing simulated changed.

---

## D-084 — Gated shops: `keeper` instead of `location`, and why a kept shop has no counter yet

**Why (M8 step 8).** `shops.json` shops were always places: `REQUIRED_KEYS`
demanded `location`, and `ShopRegistry.shop_at()` is the only door in. An
illicit dealer does not run a storefront, so a shop now names either a
`location` (walked up to, exactly as before — every existing shop
untouched) or a `keeper` (an npc id — dealt with wherever they are,
step 9's business, not this one's). **Exactly one, never both, never
neither**: `_shop_reference_problems` (`src/data/data_registry.gd`) checks
`location.is_empty() == keeper.is_empty()` and reports either violation the
same way `test_a_shop_with_both_location_and_keeper_is_reported` and
`..._with_neither_...` both exercise. `location` moved out of
`REQUIRED_KEYS["shops"]` (now just `["id", "stock"]`) since it is no longer
unconditional.

**The symmetric link, both ways, kept honest by validation alone.** A
kept shop's `keeper` must be a real npc, and that npc's own `deals` must
name the shop back (`_shop_reference_problems`) — the same discipline
`ask_broken` proved out for `asks.json` in D-053: a dangling reference is a
loaded-content error, not a runtime surprise. This is also why `deals`
stayed empty on every NPC in D-082 (step 6) — `shop_warehouse_stash` and
`shop_scrapyard_stash` are the first shops to exist, so this is the first
commit where `npc_rauno.deals` and `npc_kimmo.deals` can be filled in
without failing their own check.

**`ShopRegistry.shop_of(npc_id)`** is the inverse lookup (`keeper == npc_id`
across the table), for whatever in step 9 needs to turn "the person the
player is talking to" into "the shop they deal from" — `ask_deal`'s own
job, not built here. **`legality(shop_id)`** is a plain read of the shop's
own `"legality"` field (`"legal"` default, `"grey"` or `"illicit"`),
validated against exactly those three strings; kept on `ShopRegistry`
rather than `DealRules` because it is data, not judgement.

**Two illicit shops, both kept, both stocked from the plan's sixteen drug
items** (the nine raw, unprepared forms — bags, buds, pills, tabs — a
player then works up at the bench, D-070/071; the seven already-prepared
forms like a rolled joint or a loaded syringe are not something a dealer
hands over ready-made). `shop_warehouse_stash` (`npc_rauno`, harder and
party drugs — heroin, cocaine, amphetamine, opioid pills, ecstasy, LSD,
matching a fixer who "arranges things ... that arrive without paperwork")
and `shop_scrapyard_stash` (`npc_kimmo`, cannabis and mushrooms — the
softer half, and Eastfield's own dealer rather than a second Harbourside
one). Markup 2.2 and 1.8 respectively — an illicit premium above anything
in `data/shops.json` today (`shop_pawn`'s 1.5 was the previous high) —
before `DealRules`' own `price_factor` (D-083) has any say. Neither buys
anything back; that is fencing, `shop_pawn`'s territory already, not this
step's.

**A kept shop has no counter to step up to yet, on purpose.**
`shop_at(location_id)` was **not** taught to resolve a keeper by their
current position — that would let a player walk up to Rauno wherever he
stands and buy heroin with no gate at all, which is exactly backwards: the
whole reason `nature`, `DealRules` and `keeper` exist is so a kept shop is
reached *through* a judgement, not *instead of* one.
`test_a_kept_shop_has_no_location_and_is_unreachable_by_shop_at` pins this
down. `ask_deal` (step 9) is the only door once it is built; until then
these two shops are inert data, reachable only through `ShopRegistry`
directly (as the tests do) — the same "pure, called by nothing yet" shape
D-083 left `DealRules` in.

**`Game._deal_factor: Dictionary`** (shop id → today's negotiated price
multiplier from a successful `ask_deal`) lives on `Game`, not
`ShopRegistry`, and is **not saved** — cleared in `new_game()` alongside
`_shopping`/`_shop_deals`, exactly the reasoning the plan gave: threading a
session-only number through `ShopRegistry.to_dict()` would drag a save
migration behind a value that is meant to be struck fresh in conversation
every time, never carried over. `Game._priced_buy(shop_id, item_id)` reads
it (default `1.0`, no change) and now stands in for every direct
`shops.buy_price()` call in `shop_view()` and `buy()` — `sell()` is
untouched, since a deal's price is what a dealer charges you, not yet a
buyback rate. `set_deal_factor()` is public and unused by any caller this
step; `test_a_deal_factor_moves_the_price_the_buyer_sees_and_pays` and
`test_no_deal_factor_leaves_the_price_exactly_as_it_was` prove the plumbing
against an ordinary shop, since no kept shop can be opened yet to prove it
against one directly. **When to clear a struck factor** (on leaving the
counter? at midnight, like haggling?) is left for step 9 to decide once
there is a real caller to make that call meaningfully.

12 new tests, split across `tests/test_shops.gd` (the gated-shop registry
reads, the pricing plumbing, and six `DataRegistry` validation cases) and
two fixed in `tests/test_npc_nature.gd` (D-082's fixtures reassigned
`npc_rauno`'s `deals` wholesale, which broke the moment `shop_warehouse_
stash` needed that exact list to stay intact — moved to `npc_ida`, who
keeps no shop of her own). 1093 tests green (was 1081). No benchmark —
`src/economy/` and `src/data/` are outside the tiered simulation path this
project's benchmark rule cares about.

---

## D-085 — `ask_deal`: the door into a kept shop, and why a refusal can still cost something

**Why (M8 step 9).** D-083 built `DealRules` pure and unused; D-084 built two
illicit shops reachable by nothing. This step is the door: a new intent
kind, `ask_deal`, that gathers exactly the facts `DealRules` needs, reads
its verdict, and — on success — opens the shop it names. **The model's
entire contribution is the word `ask_deal`.** It never names a substance, a
quantity or a price; `IntentPrompt.KIND_HELP` says so explicitly
("without naming a thing, an amount or a price"), the strongest reading of
the architecture rule the plan called for. `OfflineTopics` recognises it
from `"got anything"` (English) and `"onko sulla mitään"` (Finnish, plus
four more phrasings each), inserted in `ORDER` right after `ask_action` and
before `negotiate`, per the plan.

**`_deal_state(npc_id)`** (`DialogueDirector`) is the `gift`/`go` pattern
once more: built only when `intent.kind == "ask_deal"`, and only it knows
how to turn the world into the eleven facts `DealRules.judge()` takes —
`shops.shop_of(npc_id)` for which shop, the keeper's `nature` axes
untouched, `Relationship.familiarity`/`trust` for feeling, `requires_met`
against `quests.active` (the exact pattern `AskDirector._requirements_met`
already uses for the same `{"quest": ...}` shape), and three genuinely new
readings:

- **`vouched`** — knowledge, not a flag, exactly as the plan specified: does
  this person know a `"vouched_for"` fact about the player. Nothing writes
  that fact yet (M8 step 11), so this always reads false today; the check
  is already correct and needs no further change when it does.
- **`standing`** — `Reputation.criminal_standing()` (new, `src/social/
  reputation.gd`): the *worst* standing across every scope `_scope_kind`
  already calls `"criminal"` (a group id containing crew/gang/criminal),
  not an average — one bad name among criminals is what a dealer weighs,
  not a blended score across ones that never heard.
- **`heat`** — the one number D-083 left explicitly open ("a caller-supplied
  fact, not computed anywhere yet"). Defined here, finally, as a plain
  formula over what `CrimeDirector` already tracks: `open_summons_count ×
  0.6 + settled_record.size() × 0.15`, clamped to `[0, 1]`. A judgement
  call, not derived from anything deeper — worth revisiting once heat has
  more than one consumer. **Not the same number** as the per-*item* `heat`
  D-084 named for step 10; that one feeds a deal's *visibility* as a crime,
  this one gates whether the deal happens at all.
- **`watched`** — anyone else standing where the dealer is, a plain scan of
  `NpcRegistry`, not `CrimeDirector.watchers()`'s dice-and-notice-chance
  machinery: `DealRules` only wants a yes/no against the dealer's own
  `risk`, not who specifically would notice or how surely.

**A refused `wont_deal` is not a refused proposal — it is a success with a
cost**, the one deliberate departure from "every refusal is
`Result.failure`, the world unchanged." Asking a genuinely lawful person
(`legality == "illicit"` and `lawfulness > 0.6`) is a real social move that
can land badly, exactly the shape `"flirt"` already has when unwelcome:
`ConversationRules.judge()` falls through to `Result.success` with a
`{"do": "feel", "dimension": "trust", "delta": -0.05 × lawfulness}` effect
and topic `"wont_deal"`, never returning early. The other seven `DealRules`
codes (`not_a_dealer`, `requires_unmet`, `dont_know_you`, `dont_trust_you`,
`bad_standing`, `too_hot`, `not_now`) stay ordinary `Result.failure`s —
asking a stranger, or asking at a bad moment, is not an offence the way
propositioning a straight-laced person about drugs is. `topic_for_refusal`
carries a comment explaining exactly why `"wont_deal"` is missing from its
match, so the absence reads as a decision, not a gap.

**Opening the shop needed a second door, not a stretched first one.**
`Game.open_shop()` and everything downstream of it (`buy`, `sell`,
`shop_view`, `haggle`, `steal`) key off `_shopping` holding a **location**,
resolved through `shops.shop_at()` — and D-084 deliberately never taught
`shop_at()` to find a kept shop by where its keeper happens to be standing,
because that would open a gated shop with no gate. `Game.open_deal_shop
(npc_id, shop_id)` is the second door: it sets `_shopping` to the **shop
id** directly and a new `_dealing`/`_deal_keeper` pair remembers it got
there that way. `_current_shop_id()` and `_current_staff()` are the only
two places that had to learn the difference — `shop_view()`, `buy()` and
`sell()` now call them instead of `shop_at(_shopping)`/`staff_serving
(_shopping)` directly, and behave exactly as before for every ordinary
shop (`_dealing` false is the whole of the old path). `haggle()` and
`steal()` were **not** taught the difference — haggling makes no sense
once `DealRules`' own `factor` has already priced the visit, and stealing
from someone meeting you face to face for a discreet deal does not fit
what `TheftRules` models; both simply find no shop and no staff for a
dealt session and refuse harmlessly through checks that already exist,
rather than being specially blocked. `close_shop()` erases the struck
factor and clears `_dealing`/`_deal_keeper`: asking again is asking again,
never a standing invitation.

**`Events.deal_offered(npc_id, shop_id, factor)`** is the `fight_requested`
pattern exactly. `Game` listens only to bank the factor
(`set_deal_factor`) — it does not open anything itself, the same
separation `_on_follow_requested` keeps from `_on_fight_requested`.
`WorldView._on_deal_offered` → `call_deferred("_begin_deal", …)` is
`_on_fight_requested` → `_begin_fight` verbatim: the conversation is let
finish before anything is torn down under the line that asked for it, then
`_dialogue.close()` and `_shop.open_deal(npc_id, shop_id)` (a new
`ShopWindow` entry point beside `open()`, sharing everything after the
`Game` call through a small `_open_with(Result)` helper).

**Never driven through a live model.** `--talk=npc_rauno "--say=Got
anything?"` on `ui_preview.tscn` was tried once, by hand, to sanity-check
the wiring end to end — and killed within a minute, no output, because that
debug scene is not sandboxed to the offline provider the way `tests/
test_runner.tscn` is (D-036): it runs against whatever the player's own
`Settings`/`SecretStore` say, and this machine has a real key configured.
Every claim above is proven by `tests/test_ask_deal.gd` (11 tests) against
a `ScriptedDialogueModel` with `available = false`, offline throughout —
consistent with "no live LLM call has ever been made" (PROJECT_STATUS.md)
staying true through this step too. 1104 tests green (was 1093). No
benchmark — nothing touched here runs per simulated minute.

---

## D-086 — Consequences: `dealt_illicit`, item `heat`, and the keeper who never tells

**Why (M8 step 10, closing session B).** The plan asked for this step to
land alone, and it is small on purpose: one predicate, one pair of
`Reputation` weights, one call site duplicated from `steal()`, and one pure
default-by-kind function — no new system, just wiring the ones D-082
through D-085 already built into `CrimeDirector`'s existing machinery.

**One predicate, not one per commodity.** `CrimeDirector.CRIME_PREDICATES
+= "dealt_illicit"` — a bag of heroin and a joint are the same *kind* of
offence; what makes one worse is `ItemRules.heat_of(item)` (new,
`src/economy/item_rules.gd`, the `damage_of`/`armour_of` pattern exactly):
an item's own `"heat"` if authored, else `0.4` for any `kind: "drug"`,
`0.5` for `kind: "weapon"`, `0.25` for everything else. Every one of the 19
weapons and 16 drugs already in the game gets a sensible default with
nothing added to `items.json` — the plan's own arithmetic (19 + 16 = 35)
confirmed this needed no authoring pass, only the function.

**`Reputation` reads `dealt_illicit` and `vouched_for` oppositely in the
two scopes that actually care.** `DEFAULT_WEIGHTS["dealt_illicit"] =
-0.35` (between `stole_from`'s -0.45 and `assaulted`'s -0.60 — a real
offence, not the worst one), `["vouched_for"] = 0.20`. `SCOPE_MODIFIERS`:
criminals barely mind dealing (`"criminal": {"dealt_illicit": 0.10}` — a
positive relative to the default, the same shape `"arrested": 0.05`
already has there) and the police mind it more than almost anything
(`"police": {"dealt_illicit": -0.55}`, next to `"arrested": -0.5`). Being
vouched for lands hardest exactly where the vouching happened —
`"criminal": {"vouched_for": 0.35}` outweighs the default, since trust from
one of their own means more than a stranger's word means anywhere. Nothing
writes a `"vouched_for"` fact yet (M8 step 11); the weight is ready for it.

**`Game._observe_illicit_deal(shop_id, item_id)`**, called from both `buy()`
and `sell()` after the transaction completes, is `steal()`'s witness check
transplanted: it returns at once for a `"legal"` shop (every ordinary
purchase, unchanged, proven by `test_a_legal_shop_is_never_watched_for_it`)
and otherwise calls the *same* `CrimeDirector.watchers()` `steal()` already
uses. **The keeper's `discretion` stands in for the player's stealth** —
`int(round(discretion × 99))` feeds `TheftRules.notice_chance()`'s
`stealth_level` argument exactly where a skill level would go, since it is
the *dealer* who controls how the exchange happens here, not the player.
**The keeper is filtered out of who gets asked to notice, and never
granted the elevated "watching their own counter" attention `is_staff`
gives a shopkeeper** — `watchers()` is called with `staff: ""`, then the
keeper's own id is dropped from the result before any roll is drawn. A
dealer does not witness, and cannot report, their own sale;
`test_the_keeper_alone_leaves_no_trace` and the `dealt_illicit` case in
`test_a_witnessed_deal_is_a_crime_the_keeper_never_reports` both prove it.
A caught deal is recorded as `crime.record_crime("dealt_illicit", …,
caught: false, …)` — nobody stops a deal in the act the way a shopkeeper
stops a theft; being seen is the whole of the consequence here.

**Confirmed, not changed: `PoliceRules` and every `ui.msg.police_*` key are
predicate-blind**, exactly as the plan asked to verify. `PoliceRules`
works only from `{"severity", "strength"}` pairs and never reads a
predicate string; grepping `src/ui/` for `predicate` turns up nothing that
builds a locale key from one. `dealt_illicit` needed no new UI string to
avoid rendering as a raw key on screen — the existing `ui.msg.police_
forced.warning`/`.fine` already cover every predicate there is.

8 new tests in `tests/test_dealt_illicit.gd`: `heat_of`'s defaults and
override, the two `Reputation` tables' shape, an unwitnessed deal leaving
nothing, a missed roll leaving nothing, a caught deal recorded correctly
with the keeper excluded, and a legal shop never watched at all. 1112
tests green (was 1104). No benchmark — nothing here runs per simulated
minute. **This closes M8 session B** (steps 6–10): `Npc.nature`, `DealRules`,
gated shops, `ask_deal` and its consequences are all in, tested offline
throughout, and none of it has been played by a person yet — worth trying
at a keyboard before session C: ask Rauno for something at night with
nobody about, then again in daylight at the harbour with Marika in sight,
per the plan's own verification note.

---

## D-087 — Vouching: an ask that writes knowledge, not a flag

**Why (M8 step 11, opening session C).** D-085's `_vouched_for(npc_id)`
already reads the `KnowledgeNetwork` correctly and has done since step 9 —
it has just never had anything to find. This step is the writer: a third
authored `AskDirector.EFFECTS` verb, `"vouch"`, and the one new `requires`
key the plan asked for, `{"deals": true}`.

**The ask is put directly to the dealer, not to a third party.** Two new
`data/asks.json` entries, `ask_vouch_rauno` and `ask_vouch_kimmo`, each
`requires: {"deals": true}` — a safety net more than a functional gate,
since each is already hard-tied to one specific `npc` the way every ask is
(`AskDirector.offer()` matches on `ask.npc == npc_id`); `DataRegistry`
now checks it at load time regardless
(`ask '%s' requires dealing but '%s' deals from nothing`,
`tests/test_asks.gd`'s `test_an_ask_requiring_dealing_must_be_put_to_a_
dealer`), so authoring a `requires: {"deals": true}` ask for someone who
never will deal is a caught content bug, not a silently-dead ask. On
success, the effect makes **that same dealer** a firsthand witness of
`"vouched_for"` about the player: `_knowledge.observe_event(PlayerState.
ID, "vouched_for", now, [npc_id], {"visibility": "social", "severity":
0.5})`. Nothing hardcodes who the vouching is *for* — the fact's own
`visibility` and `KnowledgeNetwork`'s existing gossip spread
(`_schedule_tellings`, along `RelationshipGraph.close_contacts`) are what
the plan meant by "buys spreading along relationship edges": if this
dealer later talks to another dealer they are close to, the player's
reputation as vouched-for can travel there too, with no new mechanism.
Only a full **success** vouches — **partial** just warms trust a little,
matching the shape `ask_rauno_time` already has for its own two winning
grades (`test_only_a_full_win_vouches`).

**`AskDirector.setup()` gained a `KnowledgeNetwork` parameter**, exactly
the signature change the plan called out. `asks.setup(...)` has exactly
one real caller (`Game.new_game()`) and no test constructs `AskDirector`
directly (verified by search before making the change), so the fix was
one line, not the sweep the plan's own note warned might be needed.

**Proven end to end, tying step 9 back in**:
`test_being_vouched_for_opens_the_shop_to_a_stranger` vouches with Rauno
under a background with no other reason to know him, ends the
conversation, confirms the resulting familiarity is still below
`DealRules.familiarity_floor(0.75, 0.1)` — Rauno's own greed and
lawfulness, called directly rather than duplicated — and then asks him for
something in a *second*, otherwise-cold conversation: no refusal, topic
`deal_offered`. Vouching is the only reason it succeeds. 4 new tests in
`tests/test_asks.gd` (kept there rather than a new file — this is the ask
system doing one more thing, not a new one). 1116 tests green (was 1112).
No benchmark — nothing here runs per simulated minute.

**One existing test needed fixing, the D-084/D-082 pattern again.**
`test_there_has_to_be_something_to_bargain_over` asserted Rauno had
nothing to ask once the debt quest was inactive — true before this step,
false now that `ask_vouch_rauno` is always available to anyone talking to
him. Moved that half of the test to Veikko, who has no authored ask at
all, debt or not. The lesson from D-084's near-identical fixture break
holds: authoring a new always-available ask for an existing story NPC is
exactly the kind of change that quietly invalidates an "and there is
nothing else here" assumption elsewhere, and the only defence is running
the whole suite, not just the new tests.

---

## D-088 — Thirty new people, and Harbourside stops being the only place anyone lives

**Why (M8 step 12, closing M8's planned scope).** Twenty NPCs with a median
age of 46 read as a retirement town, not a place with a future. This step
is content, not mechanism: 30 new people authored against the schema
D-082 froze in session B, and one real bug in how the model was told where
it was.

**Homes, not new locations.** Every `kind: "home"` location already has
exactly one `owner` — but four of the twenty original NPCs already shared
a home with another (Ida and Elias, Veikko and Joonas, Sanna and Pirjo,
Marika and Leena), so a shared flat or a boarding room was already the
established shape, not a new one. All 30 new people live in the sixteen
existing non-player homes, one or two to a home, as family, boarders or
both — nothing added to `data/locations.json`, and none of the eleven
workplaces gained a new building either: everyone works, or does not, at a
place that already exists. Occupations come from the existing sixteen in
`data/occupations.json`, schedules from the existing fifteen in
`data/schedules.json` — the `@home`/`@work` token design (D-011) is
exactly what makes reusing them for a different person, in a different
region, cost nothing.

**The archetypes the plan asked for, without a new shop mechanic to serve
them.** "A couple of real dealers" reads as already satisfied by Rauno and
Kimmo (D-084) — this step adds no third kept shop, which would have meant
repeating the schema-validation and `DealRules` wiring work session B
already finished for a marginal narrative gain. What it does add: several
"in-betweens who look away" (`npc_miika`, `npc_topi`, `npc_eero`,
`npc_jussi`, `npc_ismo` — moderate-to-low `lawfulness`, higher
`discretion`, no shop of their own) and **a fence in nature only**,
`npc_ville` — Kimmo's cousin at the scrapyard, `{lawfulness: 0.25, greed:
0.75, discretion: 0.7}`, described in his bio as someone who "knows a
buyer for anything" with no `deals` array and no shop behind him. A
character who reads right before the mechanic exists is cheaper to build
than the mechanic, and was already this project's approach to Aarne and
Kimmo themselves before D-084 gave Kimmo an actual shop — fencing stolen
goods stays a named idea for a later pass (D-084's own note), not
mechanised here.

**Ages: median 46 to 34.5, computed and checked, not eyeballed.** 20
existing plus 30 new is 50 NPCs, ages 19 to 71, no duplicate id or name.
`test_the_town_has_young_adults_too` (`tests/test_content.gd`) counts
everyone under 30 and asserts more than ten — a guard against this
demographic drifting back unnoticed in a later session, the way D-082's
`nature` schema needed guarding once it existed. Every entry's `age` is
explicit; `test_every_npc_is_an_adult` (unchanged) still enforces `>= 17`
on all fifty.

**A second police officer nearly happened, and the fix was to not have
one.** `npc_petri` was first authored as `occ_officer` in the
`police_harbour` group — a second working officer at the post, which
seemed like reasonable flavour for a town this size. It broke twelve
tests across `test_fights.gd`, `test_police.gd` and `test_theft.gd`, all
of them built on `CrimeDirector.officers()` returning exactly one person:
a report going to two officers instead of one, a summons issued by the
wrong one, a case's `known_offences` count doubling. The honest fix was
not chasing twelve tests through a change nothing asked for — it was
recognising Marika is deliberately the harbour's only officer
(`ui.msg.police_*`, the whole `PoliceRules` case-weighing design, assumes
exactly one desk) and giving Petri a different story instead: left the
force elsewhere, for reasons he does not discuss, now renting a room from
Tuomas and still noticing what an officer would. Same character, same
traits, no group membership — `test_fights.gd`/`test_police.gd`/
`test_theft.gd` all green again with no change to any of the three files
themselves. **A second officer is a real idea for later** (the roadmap's
own M6 notes list "other crimes," "a fence," more of the police system as
open); it should be built as a deliberate widening of `CrimeDirector`, not
discovered as a side effect of a name and an occupation in a content pass.

**The model was told it lived in Harbourside no matter where it actually
was.** `DialoguePrompt.system_text()` hardcoded *"in Harbourside, the
harbour district of a small Finnish port town"* for every NPC — harmless
while only Harbourside had people, a real bug the moment Old Town and
Eastfield did (M7, D-072) and never caught, because M7 shipped no new
dialogue-model tests. Fixed now, since 20 of the 50 NPCs (Old Town and
Eastfield's original ten plus twenty of this step's thirty) would
otherwise have told the model they lived somewhere they have never been.
`DialogueDirector.prompt_context()` gained `now.region` (`_world.
region_of(npc.location)`); `DialoguePrompt.REGION_PHRASE` maps each of the
three regions to the same apposition shape Harbourside always had ("Old
Town, the old quarter of the same small Finnish port town"; "Eastfield,
the industrial edge of the same small Finnish port town"), falling back to
the bare "a small Finnish port town" for anything stranger. The other
hardcoded fallback, `now.place`'s `"somewhere in Harbourside"` default,
became the region-agnostic `"somewhere in town"` — it only ever fires when
location lookup itself fails, but a Harbourside-specific guess was never
right for that case either. `test_someone_elsewhere_is_told_where_they_
actually_are` (new, `tests/test_dialogue_model.gd`) proves an Old Town
resident's prompt says Old Town and never says harbour district.

2 new tests, 30 new people, 1 real bug fixed that M7 shipped and nothing
had caught until a full roster made it visible. 1118 tests green (was
1116). Benchmark re-run (content touches `src/npc/`-adjacent data, per
house rule): numbers landed inside this session's own established noise
band (D-077, D-082) at every population size, both layouts — no
regression. **This is M8's last planned step.** Sessions D+ — downtown
with skyscrapers, walkable upper floors, romance, sex work as an economy —
are sequenced after M8 entirely and not detailed in this plan; the plan
itself never wrote a session-D handoff prompt the way sessions B and C
got one.

## D-089 — A review pass: eight bugs, none of them in a system's own logic

**Why.** The user asked for the whole project to be read through for bugs
and for what could work better. Nothing from M4 onward has been played at a
keyboard, so the pass looked hardest where tests are thinnest: the seams
between systems, the provider adapters no live call has ever exercised, and
state that outlives one conversation or one life. Every fix below has a
test that fails on the code before it.

**The providers, before first contact.** OpenAI's reasoning models (`gpt-5*`,
`o1`/`o3`/`o4`) take only the default temperature and answer any other with a
400; `gpt-5` was in the adapter's own suggested list and would have failed
every call. `LlmProvider.rejects_temperature()` now leaves it out for them,
on OpenAI and through OpenRouter — the same "a missing sampling parameter
costs nothing" rule the Anthropic adapter already had (D-036). Both
Chat-Completions adapters also read `content: null` — a reply that spent its
whole budget thinking, or a refusal — through `str()`, which in Godot makes
the literal text `<null>`: an NPC would have said it aloud. One shared
`LlmProvider.parse_chat_completion()` now reads null as no text (so an
authored line stands in), reads a `refusal` as a `refused` failure, and
tolerates `usage: null`. The Anthropic adapter was checked against the
current API (model ids, `output_config.effort`, temperature only on the older
families, `stop_reason: "refusal"`) and needed nothing. A cached answer is
now a copy (`LlmResponse.copy()`), so the request id and latency `send()`
stamps on it no longer overwrite the stored one or the first caller's.

**State that outlived what it belonged to.** `Game.unload()` reset every
system but not Game's own per-session flags. `_last_retier` is the one that
bit: play on past a save, go back to it, and the periodic retier stopped
until the clock caught up with the abandoned life's minute. All eight flags
are reset now. `DialogueBox` closed itself a moment after a goodbye with a
timer that closed whatever was open when it fired — close the box by hand
and talk to someone else within two seconds, and the new conversation was
shut. A reply still thinking when the box closed also left `_waiting` set,
refusing input in the next conversation until the old reply came back. A
per-conversation `_session` counter guards both.

**Rules that did not say what their docstrings said.**
`ConsequenceDirector._may_hold()` was documented as "not the player's own
friend by now" and checked no such thing: someone the player had since made
up with still warned and named a time and a place every twelve days, for
ever. `ConsequenceRules.made_up()` — affection toward the player at the same
bar as a friend stepping into a fight (`FightDirector.JOIN_AFFECTION`) — now
ends it. Only grudges; a creditor's debt is not forgiven by liking you.
`DialogueDirector._someone_else_about()` counted a sleeping person as
watching a deal, where `CrimeDirector.watchers()` — which decides who could
report it — already skipped sleepers; the two now agree.

**Smaller.** A dealt shop (D-085) showed Haggle and Pocket, both of which
could only ever answer "nobody is serving"; `shop_view()` now carries
`dealing` and the window offers Buy alone. `_place_name()`'s fallback still
said "somewhere in Harbourside" — the one D-088 missed. `SaveManager.save()`
deleted the old save before renaming the new one into place, so a failed
rename (a file held by a virus scanner) left the player with nothing under
the slot's name; the old one is now set aside as `.bak`, put back if the
rename fails, and read by `_read_file()` if a crash lands between the two.

**Seen, not changed — worth deciding deliberately.** `_heat_level()` counts
`crime.record.size() × 0.15` and the record never fades, so after five or six
settled cases every dealer is `too_hot` for good; fading it by age is a tuning
decision, left to whoever next plays the dealing. `KnowledgeNetwork.
forget_stale()` drops beliefs but never the facts nobody holds any more, so
`facts` only grows; harmless at today's rates. A collection has no end once a
debt quest fails — nothing lets the player pay it off late.

## D-090 — What playing showed: waking in the clinic, grudges that never end, a debt that hunts you

**Why.** The user played and reported, in their words: sleeping often ends in
the clinic; the player is often "injured" without having fought; an enemy
runs away just as the player is winning, then forgets the fight and keeps
challenging and texting "I haven't forgotten what you did" without end. And
three design calls from the review (D-089) were settled: make dealer heat
natural, make the knowledge network hold up in a long game, and make an
unpaid debt a real threat — a summons to talk, threats of harm, and in the end
the collector coming to find the player.

**The clinic and the phantom injury were one loop.** Health never came back
on its own — only a bandage, the clinic or a collapse raised it. Hunger rose
by 1/14 an hour asleep, so a night after a light supper woke the player
starving, and starving costs health. Below 0.6 health the HUD said "Hurt"
("Loukkaantunut") whatever the cause. A collapse left health at 0.35: "hurt"
again, and the next hungry night ended at the clinic again. Now a body that
is fed (hunger under 0.8) and not exhausted mends: a third of full health over
a night, a quarter over a waking day, but only up to `Stats.health_cap()` —
what open wounds allow, each taking off what it took when dealt, so a cracked
rib is not slept off before it heals. Hunger asleep is 1/24 an hour. And the
HUD says "Weak"/"Very weak" ("Heikko") for low health with no wound, keeping
"Hurt" for when something was done to you.

**The enemy who always got away.** `CombatRules.npc_action` sent someone
under 0.3 health running on 70% of their give-up share, and `Combat` let them
go every time — the player's own escape is rolled against the quickest foe's
agility; theirs was not rolled at all. Now running is a third of the give-up
share (backing down is likelier) and is rolled against the player's agility
(`foe_cannot_flee`: "tries to run, and you cut them off").

**Grudges end.** A grudge used to be the victim plus every friend who knew, each
with its own warnings; it "rested" twelve days after a fight or after going
unanswered, then began again from the same old fact, for ever — that was the
endless "I haven't forgotten". Now: one holder per blow — the victim, or only
if they cannot (the law, gone) one friend; one warning; two named times and
places; and then it is over for good, in `settled_facts` — had out in any
fight between them (`on_fought`, win or lose), let go if never answered, or
made up (D-089). A new blow is a new fact and may start a new one.

**Dealer heat cools.** `CrimeDirector.heat(today)`: an open summons 0.6, each
case the police know and have not dealt with 0.2, and each settled case by its
outcome (warning 0.15, fine 0.25, arrest 0.4) halving every seven days.
Replaces `record.size() × 0.15`, which only ever grew.

**Knowledge wears.** `KnowledgeNetwork.fade(now)`, daily, replaces
`forget_stale`: every belief's confidence halves over `half_life_days` =
(4 + 56 × severity²) days, three times as long when seen firsthand; below 0.1
it is forgotten; a fact nobody holds is dropped. Trivia goes in days, a theft
seen in about three months, a beating the victim took in about eight. Nothing
else changed to make this so — reputation, the police's evidence, a dealer's
vouching, who holds a grudge and gossip itself all read `confidence`, so all
of them cool the same way. Incremental (`Belief.faded_at`), so fading daily
equals fading once, and saves carry it. `Reputation` is invalidated after.

**The debt, redesigned.** A failed debt now remembers what was paid and the
interest (`QuestLog.lapsed`): Rauno's €300 with €100 paid and €50 interest is
€250 owed. Every three days (the phone's own gap for a demand, so none is
held back and lost): a summons to come and talk — a *meeting* at six in the
evening, told not asked, `purpose: "collection"`, neither warm nor a fight;
then a threat of harm; then a last warning naming who will come. Face to face
he opens with the money ("€250. Where is it?") and the model is told the
situation. Then the enforcer (Joonas) **hunts**: hourly, 09–22, if the player
is out at a named place — not at home, the police post or the clinic, and not
busy — he sets off, arriving 20–60 minutes later; if the player is still
findable he walks up and starts it (`Events.ambush`), otherwise he looks
again. Losing (or backing down) he takes the cash the player carries towards
the debt and leaves it four days; seen off, six; fled, nothing settled. Money
handed or sent to Rauno *or* Joonas counts, in parts; paid in full it is over
for good (`settled_debts`), with a "we're square" text on its own short-gap
message kind so it is never held back. This is the one exception to D-055's
"never in the street", at the user's request; CLAUDE.md says so.

**Saves.** New fields default when missing (`lapsed`, `settled_facts`,
`settled_debts`, `purpose`, `faded`); a pre-D-090 collection is read as far
along as its warnings and meetings took it, owing the quest's full sum. No
schema bump: nothing changed shape, only gained optional fields.

**A leak caught on the way.** Giving `DialogueDirector` a reference to
`ConsequenceDirector` closed a cycle (consequences → phone → dialogue →
consequences) of `RefCounted`s that is never freed — the suite's exit showed
"38 resources still in use". It holds two `Callable`s instead.

---

## D-091 — Walkable upper floors: a building's own floors are just more interiors, no new field, no migration

**Why.** M8's own closing note sequenced "downtown, with skyscrapers and
walkable upper floors" after it, sized by the user's own choice of scope for
this session: the floor/stairs mechanic first (this entry), the district
itself after (`tools/import_limezu_downtown.py`, then the region). Full plan
at `C:\Users\miika\.claude\plans\parallel-swimming-hummingbird.md`. That
closing note guessed the mechanic would need "a richer `PlayerState.interior`
... and a v14 migration". It does not, and this entry records why, so a
later reader does not re-litigate it.

**The insight.** `player.interior` was never typed as "a location id" — it
is an opaque `String` `WorldState.interior_for()` looks up in a dict. A
floor is just another entry in that same dict, addressed by a slightly
richer key: `DistrictMap.floor_key(location_id, storey)` returns the bare
`location_id` for the ground floor (storey ≤ 1, exactly what every building
already used) and `"<location id>#<floor>"` above it. A location id can
never itself contain `#`, so the two value spaces never collide, and nothing
already saved (which only ever holds `""` or a bare location id) needs
reshaping — that is the whole reason no v14 migration exists for this.
`PlayerState.interior` keeps its shape; the floor-change function
(`Game._change_floor`) sets it to a composed key exactly the way
`_enter_building` already sets it to a plain one.

**`DistrictMap` gains one field, `storey: int = 1`** (named to dodge
GDScript's built-in `floor()` global — this project treats warnings as
errors, and a member var shadowing a global is exactly the kind of thing
that trips), read from the authored JSON key `"floor"` (natural for a
content author to type; the internal name and the authoring key are allowed
to differ). Every one of the 17 interiors authored before this step is
silently floor 1 — no data migration for what already exists.

**The `stairs` object needs no new authored field.** Every interior already
has one required, wall-embedded, always-reachable door cell (`exit_door`).
On the ground floor it means "leave to the region"; reinterpreted above
floor 1, the same cell means "go down one floor" — `Game.interaction_at`
reports it as `"exit"` on the ground floor, `"stairs_down"` above it, and
`interact_at` branches accordingly. Ascending is the one genuinely new
interactable (`OBJECT_KINDS += "stairs"`), and defining it as "always one
floor up, from wherever it's authored" needs no per-object data either —
`_add_object()`'s existing `{id, kind, text_key, sets_flag}` shape is
untouched, and its furniture-reachability validation already applies to a
`stairs` object exactly as it does to a `counter` or an `atm`.

**`DataRegistry._interior_floor_problems()`** (new, run once over the whole
`interiors` table rather than per-entry) replaces the accidental uniqueness
the old dict-collision gave "for free" (two interiors sharing `interior_of`
silently let the last one loaded win, undetected) with an explicit rule:
distinct floors per building, and the set of floors must be a contiguous run
from 1 — no floor 3 authored without a floor 2 beneath it.

**Named follow-up, deliberately not fixed here** (nothing in this session's
own scope reaches it): five call sites compare `player.interior` to a real
location id by exact string equality — `Game._findable()`, the stash gate in
`Game._move_between()`, `Game.buy`/`sell`'s shop lookups, the phone's "you
are here" pin (`phone_window.gd`), and "is this NPC in the room"
(`dialogue_director.gd`). None of them ever see a composite key this pass,
because downtown authors no home, staffed shop, stash or scheduled NPC above
floor 1. The day a future pass does, those five sites need a
`player.interior_base()`-style helper (strip the `#N` suffix) instead of raw
equality — cheap when it is needed, wasted effort now.

**This "no migration" conclusion has a shelf life.** It holds exactly as
long as `player.interior`'s only job is "an opaque key into
`WorldState.interior_for()`". The day a future feature needs *structured*
per-player floor state — remembering which floor of which building for
every building visited, not just the one stood on now — that is a real
schema change and would need its own v14.

Proven against a synthetic two-floor fixture attached to `loc_corner_shop`
at runtime (`tests/test_stairs.gd`, 6 tests; 2 more in
`tests/test_region_map.gd` cover `storey`'s round trip and that `stairs`
validates like `atm`) — no real building has an upper floor yet, so nothing
about the mechanic depends on downtown's own content existing. 8 new tests,
1152 green (was 1144). No behaviour change for any existing building: every
ground floor still keys by its bare location id, exactly as before this
step.

---

## D-092 — Downtown's towers: pre-baked art, not a compositing engine

**Why.** `5_Floor_Modular_Building_Singles_32x32` (confirmed present under
`art/_limezu_source/`) is genuinely modular — a ground cap, a repeatable
middle window band and a roof cap, meant to be stacked for a building of any
height. Every existing `BuildingArt.BUILDINGS` entry assumes the opposite:
one whole, fixed-size image per building, matched exactly against a map's
authored `rect` (`sprite_for()` returns `""`, silently, on any size
mismatch — D-060's own standing trap). Teaching the runtime to composite
tiles would touch three systems that all currently assume "one image per
building" as a load-bearing invariant: `BuildingArt.covers()`/`.outline()`/
`.open_cells()` (collision, derived from one sprite's silhouette) and
`RegionTiles`' draw order. Real surface area for a feature whose own scope
is "a handful of buildings, walkable and visually distinct" — not arbitrary
storey counts forever.

**Call: pre-bake instead**, at import time, the same shape
`tools/import_limezu_buildings.py` already uses for the villa and the
storefront — `tools/import_limezu_downtown.py` stacks one ground cap
(`Ground_Floor_Condo_2` — measured against a column-ruled 3x render, door
centred on column 3 of 7, the same convention `police_1.png` already set for
a 7-wide building) with N repeats of a plain window-band middle floor
(`Middle_Floor_1`, correctly doorless — only the ground floor may have one)
and a flat roof cap (`Roof_1`, not the pitched `Roof_Modular` variant — a
flat teal-trimmed top reads as a tower's roof, not a house's), into three
fixed-height PNGs. Zero runtime changes to `BuildingArt`, `RegionTiles` or
`ArtShape` — each baked file becomes an ordinary `BUILDINGS` entry.

**Three heights, one door position reused across all of them:**
`downtown_2` (1 middle repeat, 2 walkable floors, 7×13), `downtown_4` (3
repeats, 4 floors, 7×21), `downtown_6` (5 repeats, 6 floors, 7×29 — the
skyline piece). `porch_rows: 0` for all three (flush to the sidewalk, like
`shop`/`bar`/`civic`/`work`, not the villa's porch). Using the same ground
cap for every height, rather than hunting for a distinct door position per
variant, is a deliberate simplification — the existing storefront art
already reuses one image four ways (recoloured, not redrawn), so this is the
established house style, not a shortcut.

`tests/test_building_art.gd`'s `KINDS_WITH_ART` const gains the three keys,
which extends every generic per-kind test (wrong-size refusal, footprint
math, door-column-inside-footprint, real-file-when-installed) to them for
free — no new test functions needed. 1152 tests still green (assertions rose
from 30948 to 30972: the same tests, now also checking three more kinds). No
map or region JSON references these keys yet — that is Session E's job.

Ends Session D. Session E (the plan's steps 5–7) authors the `downtown`
region itself: the map, the four buildings, and the interiors/stairs that
make the mechanic from D-091 real.

---

## D-093 — Downtown, the fourth region: geography before population

**Why (Session E step 5).** D-091/D-092 built the floor mechanic and the
tower art; nothing in the world used either yet. This step opens the fourth
region — `downtown`, neighbouring `old_town` and `harbourside`
(`harbourside↔downtown` 15 min, `old_town↔downtown` 11 min, both in the
existing 8–18 minute range) — and places the four towers on it, following
D-072's own precedent that a district's geography lands before anyone lives
there. **Deliberately not built this pass**: no shops, no jobs, no NPCs, no
interiors yet (that is step 6) — matching the user's own explicit scope for
this session, "Downtown + upper floors", not "+ new NPCs".

**Layout, one deliberate departure from the existing two-district
convention.** Harbourside/Old Town/Eastfield stagger buildings across two
rows at two different door heights (flats, then shops, each row's doors on
its own street). Downtown's four towers instead share **one street level**
— each building's rect is sized so its door lands on the same row (30)
regardless of height, tallest towers simply starting higher up (`rect.y`),
matching the varied-height skyline the plan actually asked for; a two-row
layout would have hidden that variety behind an arbitrary split. `BY_LOCATION`
(D-060's mechanism, its first user since the police post) gives each of the
four its own art: `loc_downtown_flats_a`→`downtown_2`,
`loc_downtown_flats_b`/`loc_downtown_tower_a`→`downtown_4` (the same art
file on two different buildings — no reference is unique to one location,
matching how `shop`/`bar`/`civic`/`work` already share one file four ways),
`loc_downtown_tower_b`→`downtown_6`. `kind` stays `home`/`work`, matching
what the buildings actually are — `BY_LOCATION` is only ever about *which
art*, never about what a building means to the rest of the game.

**The apartment blocks are `access: "private"` with no owner** — nobody
lives there yet, so "you can't get in" is the honest answer, the same
refusal a real private home gives; `Game._enter_building`'s own
`"no_interior"` guard (reached only past the lock/access/hours checks) means
a `"private"`/`"semi_public"` building missing an interior never gets that
far anyway, so the two towers don't strictly need to wait for step 6 to be
authored safely, they just are.

**Region/travel wiring is reciprocal by convention, not by a validator that
enforces it**: harbourside and old_town both gained a third exit (west and
north respectively — their only free edges once the existing ones to each
other and to eastfield/downtown occupied the rest) and a `downtown` entry in
their own `neighbours`/`travel_times`, checked only by
`test_region_neighbours_are_mutual` (generic, covers any region pair) and
the new `test_downtown_is_joined_to_its_neighbours` (walks all four new
exits both ways, mirroring `test_old_town_and_eastfield_are_joined`).
`test_every_place_in_both_districts_is_on_its_map` and
`test_the_new_buildings_are_the_size_the_drawn_art_needs` — whose names
predate a third district — extended to include `"downtown"`, noted in a
comment rather than renamed, to keep the diff to what this step needed.

**Benchmark re-run back to back against the pre-downtown commit** (be9e128,
via `git stash`/`stash pop`, same machine, same session) rather than against
`PROJECT_STATUS.md`'s own table, which this session's numbers already ran
well above at every population — matching the elevated-but-matched pattern
D-077 documented once before. Both runs landed within a few percent of each
other at every population, spread and concentrated: no regression from a
fourth region with five new locations and two new map exits per neighbour.

1153 tests green (was 1152): the one new test, plus the two extended loops
now also covering downtown's own content. Next: step 6 puts real interiors
— and a real `stairs` object — on these four buildings, the first time
D-091's mechanic runs on content instead of a test fixture.

---

## D-094 — Sixteen interiors, one template, the mechanic proven on real content

**Why (Session E step 6).** D-091 proved the floor/stairs mechanic against
a synthetic fixture; nothing real used it. This step authors an interior
for every floor of all four downtown towers — 2 + 4 + 4 + 6 = 16 entries in
`data/interiors.json` — closing the loop D-091 opened.

**One 6×6 template, reused on every floor of every building.** Each floor is
`{width:6, height:6, fill:"floor", door:[3,5]}`; every floor but the top
also gets a `table` solid at `[1,2,1,1]` (the stairwell's structure — there
is no dedicated "stairs" `SOLID_NAMES` entry, and inventing one for a single
placeholder cell would be authoring effort this pass does not need) and a
`stairs` object at cell `[1,2]`, generated programmatically rather than
hand-typed to rule out a copy-paste mismatch across sixteen near-identical
entries. The top floor of each building has neither — no object at all,
just the required door, which `Game.interaction_at` already reads as
`"stairs_down"` once `storey > 1` (D-091). Every floor of a building
reusing the same local layout is a deliberate simplification, the same
"the stairwell core sits in about the same place on every floor" model
D-091's own design section already named — not a shortcut invented here.

**Two of the four are climbable this pass, not four.** `loc_downtown_tower_
a`/`_b` are `semi_public` (matching `loc_worksite`/`loc_garage`'s own
walk-in-lobby precedent) and are climbed end to end, floor by floor, in
`test_every_downtown_tower_can_be_climbed_to_the_top_and_back`
(`tests/test_stairs.gd`). `loc_downtown_flats_a`/`_b` are `private` — D-093's
own call, nobody lives there yet — and `Game._enter_building`'s access
check refuses them before it ever reaches the (now real) interior lookup,
proven by `test_downtowns_apartment_blocks_stay_private_with_nobody_living_
there`. Their sixteen-entry share of this step's interiors is authored and
validated (`DataRegistry._interior_floor_problems` checks all sixteen for
contiguous floors, same as the two towers') even though nothing can reach
them yet — schema-complete, structurally real, simply locked, exactly
D-072's own "geography before population" shape one level deeper.

**This is the first real proof that D-091's "no v14 migration" call holds**
on content, not just a hand-built fixture: climbing every floor of both
towers and descending back through every one leaves
`SaveMigrations.CURRENT_VERSION` untouched, and the composite keys
(`"loc_downtown_tower_b#6"` at the top) round-trip through `PlayerState.
to_dict()`/`from_dict()` exactly as D-091 predicted.

2 new tests, 1155 green (was 1153). No benchmark — sixteen more interiors
carry zero per-minute simulation cost (nothing in `src/npc/`, `src/time/`
or `src/world/`'s hot path changed; interiors are looked up, never ticked).

**This closes the downtown plan's steps 5–7** (`Downtown & Walkable Upper
Floors`, `C:\Users\miika\.claude\plans\parallel-swimming-hummingbird.md`).
**Worth trying in play**: walk from Harbourside's west edge (or Old Town's
north edge) into Downtown, climb either office tower to its top floor and
back down, and confirm the two apartment blocks correctly refuse a
stranger at the door. **Deliberately left for a later pass, named so it is
found by reading**: no shops, jobs, NPCs, or residents anywhere in
Downtown — the district is real and walkable, not yet lived in. The five
call sites named in D-091 that assume `player.interior` is a bare location
id (`Game._findable`, the stash gate, `Game.buy`/`sell`, the phone's "you
are here" pin, `dialogue_director.gd`'s "is this NPC in the room") remain
unfixed and, since nothing this pass ever puts a home, shop, stash or
NPC above floor 1, still unreached.

---

## D-095 — Two people move into Downtown

**Why.** After D-094 closed the downtown plan, the user said "continue" once
more with no further scope given. Populating Downtown was the call I made
rather than asked about: it uses no new system (the same `nature`/`deals`
NPC schema, job/occupation/schedule shapes M8 already froze), follows the
exact historical sequencing D-072 and D-088 already established (geography
lands, then people), and is a direct continuation of the district just
opened rather than a jump to an unrelated one (romance, sex work, civic art
— all still just named, still all the user's call). Modest on purpose: two
people, not thirty, since the point is proving the pattern still holds on a
building with floors, not filling the district.

**One new occupation, `occ_clerk`** (`daily_wage: 105`, `workplace_kind:
"work"`, skills `observation`/`persuasion` — the same pair `occ_librarian`
already uses, an office job being closer to a librarian's than a
dockhand's). Two jobs, `job_downtown_tower_a`/`_b`, weekday 08:00–17:00,
wages 100/115 (the taller tower pays more — a judgement call, not derived
from anything). One new schedule, `sched_downtown_office`, built by copying
`sched_clinic_day`'s exact shape (same shift timing, lunch kept `@work`
rather than sent to a location) and swapping its one non-`@home`/`@work`
stop for `loc_downtown_street` — Downtown has no shop or bar yet for a
lunch or evening stop to name, so the copied schedule's own choice to keep
lunch `@work` when nothing external exists was already the right answer,
not something this step had to invent.

**Saana Virtanen (29) lives in `loc_downtown_flats_a`, works
`loc_downtown_tower_a`. Iiro Mäkelä (34) lives in `loc_downtown_flats_b`,
works `loc_downtown_tower_b`.** Each is their own job's `employer` — the
same shape `npc_veikko`'s own dockhand entry already uses (a senior person
who does the job and is also who the player would ask about it), chosen
over inventing an unseen owner NPC neither job needs. Both homes gain an
`owner` field, matching every other resident's home in the game
(`loc_ida_flat`→`npc_ida` and so on) — `Game._default_home()`'s own
"first home with no owner" scan for a background-less start still finds
`loc_player_flat` unchanged, since JSON load order is insertion order and
Downtown's entries land last in the file.

**A naming collision caught by the suite, not by inspection**: the first
choice of name for the second new person, "Eero", already belonged to
`npc_eero` (Eero Nurmi, Harbourside, age 51) — `new_game()` failed
outright (`"npcs: duplicate id 'npc_eero'"`), cascading into roughly ninety
unrelated-looking failures across `test_shops`/`test_theft`/`test_work`/
`test_time_skip`/`test_weapons`, every one of them a downstream symptom of
`Game.world` never finishing setup. Renamed to Iiro Mäkelä. Worth recording
as a reminder that a large, flat, hand-authored id/name space like
`npcs.json` has no compiler to catch a repeat — only the suite, and only
because `new_game()` fails loudly rather than silently overwriting.

**`test_every_new_person_lives_and_works_in_their_own_district`
(`tests/test_regions.gd`) gains both ids**, walking each through a full
week exactly as it already does for every Old Town/Eastfield resident —
proving the district discipline D-072 established extends to Downtown too,
not asserted, checked. `test_downtowns_apartment_blocks_stay_private_to_a_
stranger` (renamed from D-094's own "...with nobody living there", since
that is no longer true) still passes unchanged: a private home refuses a
stranger at the door whether or not anyone lives there, and now someone
does.

No new tests (the existing loop-based checks absorbed both people and both
jobs for free); assertions rose from 31116 to 32323, almost all of it the
per-NPC weekly walk. 1155 tests still green. Downtown's shops, and its
other two buildings' own residents, remain unbuilt and unnamed — still the
user's call, same as before this step.

---

## D-096 — A fifth building: the kiosk

**Why.** The user said "jatka" (continue) once more, no further detail.
Downtown could walk and now had two residents, but nowhere to buy anything
— every other region has at least one shop; Downtown had none. Adding one
follows directly from D-095's own reasoning (no new system, direct
continuation of the district just opened) and closes the single most
obviously missing piece, so it needed no separate check-in.

**A fifth building, not a shop bolted onto an existing one.** The four
towers already have their own roles (two homes, two workplaces); rather
than repurpose one, `loc_downtown_kiosk` is new ground, using the shared
`shop`/`bar`/`civic`/`work` storefront art (`BuildingArt.BUILDINGS["shop"]`,
the same Post Office image `loc_corner_shop`/`loc_bakery`/`loc_pharmacy`
already wear) rather than a fourth downtown-specific tower variant — a
kiosk is not a tower, and the shared storefront is exactly the "ordinary,
plainer" building D-024's own design intended for anything that doesn't
need a dedicated sprite. Placed at `rect: [55, 18, 8, 13]`, door row 30 —
the same street level every other downtown building's door already shares,
so the skyline stays coherent without any new geometry decision.

**`shop_downtown_kiosk`** (`data/shops.json`): coffee, a sandwich,
cigarettes, water, juice, a lighter, a bandage — the same "small convenience
stock" shape `shop_corner`/`shop_fuel` already use, markup 1.25 (between
`shop_bakery`'s 1.1 and `shop_lantern`'s 1.6), no buyback. **No new
occupation** — `occ_shopkeeper` already existed and fit exactly.
**`sched_downtown_shop`** is `sched_shop_day` with `loc_cafe_kaisla` swapped
for `loc_downtown_street` throughout, the same substitution D-095 already
made once for `sched_downtown_office`; Downtown still has nothing else to
send anyone to.

**Taina Lehto (41) runs it, and shares a home with Saana** rather than
getting a third apartment building authored just for one person —
`Location.owner_id` names one NPC, but nothing enforces that only its owner
may set `home` to it, and D-088 already established two NPCs sharing one
home as the ordinary shape, not a special case (`npc_rami`/`npc_marko`'s
own flat). Employer is Taina herself, matching `npc_veikko`'s dockhand
precedent D-095 already used.

**The id collision from D-095 did not repeat**: five candidate names were
grepped against `npcs.json` before picking one (`npc_riina` was already
taken; `npc_taina` was not) — the cheap five-second check the previous
step's failure should have prompted from the start.

`test_every_new_person_lives_and_works_in_their_own_district` gains
`npc_taina`; `test_every_shop_in_the_new_districts_has_someone_behind_the_
counter_when_open` gains `shop_downtown_kiosk`, proving the schedule
actually staffs it for at least 80% of its open hours, not just that the
data loads. No new test file — both extensions land in the same generic
loop-based checks D-093 through D-095 already extended. 1155 tests still
green; assertions rose from 32323 to 33020.

Downtown now has geography, walkable upper floors, three residents and one
shop. Still open, and still the user's call: more households in the two
apartment blocks (each plausibly holds more than the one or two people
living there now, the way a couple of Harbourside/Old Town homes already
share an occupant), a second shop or a bar, and the rest of the Sessions
D+ list (civic art, home variants, romance, sex work).

## D-097 — A floor key is never a place: `interior_base()`, and D-091's named follow-up closed

**Why now.** D-091 named five call sites that compared `player.interior` to
a real location id by exact equality, and deferred them because nothing
then reached an upper floor with anyone in it. That stopped being true in
D-095: Saana works at `loc_downtown_tower_a`, and the tower is climbable.
On floor 2 her body is drawn in the room (`NpcBodies` compares against
`map.interior_of`, the building), but talking to her refused
`nobody_there`, because `DialogueDirector._where_problem()` compared her
location with `"loc_downtown_tower_a#2"`. Worse, and a site D-091 did not
list: `Game.follow_location()` returned `player.interior` as it was, so
anyone asked to "follow me" up the stairs was moved to
`"loc_downtown_tower_a#2"` — a string that is not a `Location`, which
`WorldState.get_location()` answers with `null`. And the phone's map lost
its "you are here" pin on any upper floor.

**The fix is the helper D-091 proposed, and nothing more.**
`DistrictMap.building_of(key)` is `floor_key()`'s inverse (the text before
`#`, the key itself on a ground floor, `""` for `""`);
`PlayerState.interior_base()` applies it to `interior`. Every comparison of
the player's interior with a location id now reads the base: the follower's
destination, who is in the room for conversation, the phone pin,
`open_shop()` and the counter-opens-shop check in `WorldView`, the stash
gate in `_move_between()` and `_findable()`'s "at home". The last four
never see a floor key today (no home or shop has an upper floor), and are
changed anyway so that the rule is simple: `interior` is a key for
`WorldState.interior_for()` and nothing else; anything asking *where* uses
`interior_base()`. `PlayerState.interior` keeps its shape — no migration,
D-091's conclusion unchanged.

**Consequence, deliberate:** everyone at a building is in the room on
whichever floor the player stands on. That matches what `NpcBodies` already
drew; floors are not places, so a person at work in a tower has no floor of
their own to be on. If one day they need one, that is the "structured
per-floor state" D-091 said would need its own schema change.

3 new tests in `tests/test_stairs.gd` (the inverse, a follower upstairs,
talking to someone in the building upstairs plus the `nobody_there` refusal
for someone elsewhere); the follower and conversation tests fail on the old
comparisons, checked by reverting them. 1158 tests green (was 1155).

## D-098 — Downtown gets a bar: the Late Desk

The user said "continue" again with no direction; D-096 had named "a second
shop or a bar" as the next in-scope step. A bar gives Downtown what the
kiosk does not: somewhere to be in the evening, and a `meeting_place`.
`MeetingDirector.suggest()` only looks in the person's own home region, so
until now it found nowhere for any Downtown resident and none of them could
ever suggest meeting (D-047). Now they can, on days their start hour
(12–19) falls late enough for the bar to be open from gathering to the end
— 17:00 or later.

**Everything follows an existing shape; nothing new was invented.**
`loc_downtown_bar` copies the Lantern's location entry (kind `bar`, public,
16:00–02:00, `meeting_place`), stands on Downtown's one street level east of
the kiosk at `[67, 18, 8, 13]` with its door at column 4 — the `bar_` art's
own footprint, which `test_the_new_buildings_are_the_size_the_drawn_art_needs`
checks — and its interior is `int_lantern_bar`'s layout under new ids.
`sched_downtown_bar` is `sched_night_bar_old` with its one Old Town place
(`loc_market`, the afternoon shop) swapped for `loc_downtown_kiosk`, the same
substitution D-095 and D-096 made. `occ_barkeep` already existed.

**One keeper, not two.** The Lantern has Oskar and Pekka on the same
schedule; one person on an every-night schedule already staffs the counter
for every open hour, which the existing staffing test proves. A second
barkeep is more population, not more bar.

**No job for the player**, matching the Lantern, which has none: jobs are
authored where the player is meant to be able to work, and none of the
three bars offers shifts today.

Venla Kallio (28) shares `loc_downtown_flats_b` with Iiro (D-088's
shared-home precedent) and starts with two acquaintances, Taina and Iiro,
so Downtown's four residents are not four strangers. The id was checked
against `npcs.json` first (D-095's lesson). The two loop checks in
`tests/test_regions.gd` gained `npc_venla` and `shop_downtown_bar`; no new
test file. 1158 green, assertions 33047 → 33744.

## D-099 — Downtown's pocket park, a day for people at home, and four more residents

The user said "continue autonomously". The step D-098 named next was more
households; doing it well needed two things Downtown lacked, so all three
land together.

**A park first, because a person at home needs somewhere to be.** Every
region's idle schedule sends people to an open-air place in the afternoon
(`sched_local_idle` → `loc_harbour`, `sched_oldtown_day` → `loc_old_garden`);
Downtown had only its street. `loc_downtown_green` is a `park`, public,
`meeting_place`, at `[50, 39, 20, 12]` across the street from the kiosk and
bar, east of the south road — grass already, since Downtown's map fills
with grass. `PlaceArt.DECORATIONS` gives it Harbour Park's trees and two
benches, laid out for a rect one row shorter;
`test_no_decoration_hangs_outside_its_own_place` checks the offsets, a
screenshot checked the look. It also gives Downtown a second meeting place,
this one open all day, so meetings starting at noon now have somewhere to go.

**`sched_downtown_idle`** is `sched_local_idle`'s shape with Downtown's own
places — street walk, a morning at the kiosk, the afternoon in the park —
plus an early-evening stop at the Late Desk (18:00–20:00), so the bar has
customers other than its keeper, and sleep at 22:00 rather than 21:30.

**Four residents**, ids and every name part checked against `npcs.json`
first (D-095). Raili Heikkinen (68, `occ_unemployed` as every retiree is)
and Lauri Järvinen (51, clerk, tower A, beside Saana) join
`loc_downtown_flats_a`; Marja Honkanen (44, clerk, tower B, Iiro's
colleague) and her nephew Tomi Laaksonen (23, between things) join
`loc_downtown_flats_b`. The low block now holds four, the tall one four.
Relationships tie them to each other and to the four already there, so
Downtown is a small web rather than eight strangers. Nobody new needed a
job (the tower jobs exist and have employers), an occupation or a home.

`test_every_new_person_lives_and_works_in_their_own_district` gained the
four; it walks each through every hour of a week, so the new schedule is
proven never to leave Downtown. 1158 green, assertions 33744 → 36092.
Benchmark back to back with HEAD: within ±2% at every population.

## D-100 — Downtown in the dialogue prompt, and a test that covers every region

Found while checking Downtown for hand-written per-region tables (the only
one in `src/` is this). `DialoguePrompt.REGION_PHRASE` (D-088) listed the
three regions that existed then; everyone living in Downtown was introduced
to the model as a clerk "in a small Finnish port town", the bare fallback,
with no district at all. Not wrong, but the exact loss of place D-088 set
out to fix, and it would have repeated for every region added after.

`"downtown"` gains its phrase in the same apposition shape ("the newer
centre of the same small Finnish port town, office towers and blocks of
flats"). `test_every_region_has_its_own_phrase` (in
`tests/test_dialogue_model.gd`, beside D-088's own test) walks
`Game.data.ids("regions")`, so the next region fails the suite until it has
one, and checks Saana's prompt names Downtown. Fails on the old table,
passes on the new. 1159 green.

## D-101 — Downtown's signs, an errand, and its names in Finnish

The rest of the per-region check that found D-100. Three pieces of
hand-authored, per-region content every other district has and Downtown
did not:

- **Signs.** Each district has a notice and a road sign (`obj_old_town_notice`
  / `obj_eastfield_road`, …). `obj_downtown_notice` stands on the south
  pavement at `[24, 38]` (first placed at `[30, 38]`, beside a hydrant, and
  moved after a screenshot), `obj_downtown_road` by the south exit at
  `[47, 66]` naming both roads out with D-093's travel times. Neither sets a
  flag — every road is already open (D-077).
- **An errand.** Only three people in the town ask for help with shopping,
  all in Harbourside. Raili (D-099), a retiree like Pirjo, asks for two
  juices every three days, 12 euros — the kiosk sells juice, so it can be
  done without leaving Downtown. One is enough to prove Downtown takes part;
  errands for Old Town and Eastfield are the same one-line job, left for
  whoever next wants more of them.
- **Finnish names.** Nothing Downtown had a Finnish string: the region, its
  description and all eight location names fell back to English in a
  Finnish game. Added (Keskusta, Taskupuisto, …), with the two sign texts
  and the errand name. Translation stays deliberately partial elsewhere
  (known issue 3); this closes only the gap this session's own content
  opened. The suite's assertion count fell by exactly the 13 keys added —
  a test asserts once per missing Finnish key — not a lost check.

1159 green.

## D-102 — The first Finnish strings get their ä and ö back; Eastfield is Itäpelto

Seen while adding Downtown's Finnish names (D-101). `locale/fi.json`'s
first commit (c5d9290, 99 keys) was written without a single ä or ö, and
some of it still showed that in a Finnish game: the HUD's "Kateinen" and
"Tehtavat", "Voileipa" in the bag, people "toissa", "kavelee" and "syo" in
the developer overlay and conversation header, and two of the region
descriptions. Every one of those 99 keys was checked by hand (the next
commit already used umlauts, so the gap is exactly that set); 11 were
wrong, the other 81 are Finnish that simply has none (Tavarat, Satama,
Asetukset…). A vocabulary scan of the whole file — any word that appears
elsewhere with an ä/ö but here without — found nothing outside that set.

**Eastfield had two Finnish names**: "Itapelto" (the region, its yard)
and "Itäkenttä" (its street, the fuel station, the road sign). The region's
own name wins, since it is the one the travel prompt and the phone show:
**Itäpelto** everywhere, five strings changed. No test asserted any of the
old spellings. 1159 green.

## D-103 — Eight people stop commuting to Harbourside every day

Found auditing per-region content after D-100/D-101. D-088 gave its thirty
new people "existing schedules", reasoning that `@home`/`@work` (D-011)
makes a schedule cost nothing to reuse in another region. That holds for
the tokens, not for a schedule that names places: `sched_local_idle` and
`sched_student_day` name `loc_dock_street`, `loc_cafe_kaisla`,
`loc_harbour` and `loc_anchor_bar`. Six Old Town and two Eastfield people
on them — Otto, Eero, Anna-Liisa, Jussi, Mari, Riina, Paula, Elli — left
home at eight every morning for Harbourside, against their own bios
("at the Lantern most evenings", "most of her days at the library",
"keeps half an eye on the street from her window"), and their districts
were emptier by day than authored. `test_every_new_person_lives_and_works_
in_their_own_district` could not see it: it walks a hand-written list, and
none of the eight were on it.

**Four regional schedules, each the Harbourside original's shape with its
own district's places** (D-099's method for Downtown):
`sched_oldtown_idle` (street, square, garden, the Lantern at 19:00),
`sched_oldtown_student` (the library from 10:00 when it opens, not 08:00
when it would be shut), `sched_eastfield_idle` (street, the fuel station,
the pitch, home by the window) and `sched_eastfield_student` (the fuel
station, the Furnace in the evening). A student's `work` block at a shop is
safe: `staff_serving()` requires the shop to be their workplace.

**The test that would have caught it now covers everyone.**
`test_nobody_spends_their_ordinary_week_outside_their_own_district` walks
every NPC in `data`, every hour of a week, and allows only the home region
or the workplace's (nobody commutes today, but a job in another district
would be legitimate). One assertion per person, naming the first three
stray hours. It fails on the old data for exactly these eight. 1160 green.
No simulation code changed; the eight now count toward their own
district's local population instead of Harbourside's.

## D-104 — Closed days: a shop is shut on the days nobody works it

**Found by auditing every shop on every day** (the staffing test checked
eight shops on a Wednesday). Five were open, by their hours, with nobody
behind the counter for a whole day: the corner shop, Kaisla and the kiosk
on Sundays, the pawn shop and the pharmacy all weekend. The player walked
through an open door to "nobody is serving". No exploit — stealing already
needs someone serving — but a place that lies about being open.

**Two answers, chosen per place by who else goes there that day:**

- **Shut** where nobody goes on the day: the pharmacy and the pawn shop
  (weekends), the corner shop (Sundays; the Anchor's barkeep, whose
  `sched_bar_night` shopped there daily, now spends Sunday afternoon at
  Kaisla instead). This needed a small mechanism:
  `Location.closed_days` (weekdays, 0 = Sunday as `GameClock.weekday()`),
  `is_closed_on(weekday, minute)` — a place open past midnight counts its
  small hours to the evening they started — and an optional weekday on
  `is_open_at()`. Callers that know the day pass it: the door
  (`closed_today`, "{place} is closed today", rather than quoting hours it
  keeps every other day), `ask_go`'s check now and at the return time, and
  meetings and summons, which are always for tomorrow
  (`MeetingDirector._open_tomorrow()`). `DataRegistry` refuses a closed day
  outside 0–6. Not saved: it is authored data, like the hours.
- **Staffed** where people go anyway: Kaisla is where Harbourside spends
  Sunday (its own owner socialises there), so Emma now works Sunday to
  Friday and has Saturdays off (`sched_cafe_sunday`), and Leena keeps
  Monday to Saturday. The kiosk is on Downtown's idle round every day, so
  Tomi (D-099, "looking for work") minds it on Sundays
  (`sched_downtown_sunday_cover`, `occ_counter_hand`); his bio says so.
  Elias was the obvious corner-shop cover and deliberately not used: his
  being out of work is the debt quest's premise.

**Tests.** The staffing test now covers every shop with a counter, every
day, with closed days honoured (`test_every_shop_has_someone_behind_the_
counter_whenever_open`); `test_nobody_is_sent_to_a_place_on_its_closed_
day` walks every NPC's week; plus the Location rules (including past
midnight), the door's refusal and its text, the validator, and a meeting
never suggested at a place shut tomorrow. 1165 green (was 1160). Benchmark
back to back: this machine was heavily loaded (HEAD itself ~75% above the
morning's numbers) and the two runs differ in both directions; nothing
here is on the per-minute path — `is_open_at` has no caller in
`src/npc/` or `src/time/`.
