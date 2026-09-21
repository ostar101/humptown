# Changelog

All notable changes to Humptown. Format loosely follows Keep a Changelog;
versions are milestones rather than releases until there is something to release.

## [Unreleased]

### Added
- Asking someone to go to a place ("go to Ropewalk Park", "mene satamaan") sends
  them there for up to two hours, or until their shift or night; refused for a
  phone line, a grudge, a shut, private or distant place, or a day that is
  already spoken for (D-061).
- The police post is now LimeZu's police station, with the badge and POLICE sign (D-060). Re-run `python tools/import_limezu_buildings.py` to get it.
- An event feed at the top right (D-059): money paid and received and what for,
  things going in and out of your bag, skill levels, and the important messages
  (texts, meetings, quest steps, new places, arrests).

### Changed
- People remember what was actually said, in person, on calls and in texts, and
  the texts they wrote themselves (D-059); they greet you as someone they have
  met, spoken to today, or texted, instead of always as a stranger.
- The speech window sits lower so the time and place stay visible.

- Character animations beyond walking (D-058): people idle now and then, the
  player holds money out when handing it over and holds the phone to their ear
  on a call. The importer keeps more of LimeZu's rows and the sprite code reads
  an `actions` table; re-run `python tools/import_limezu.py` to get them.
- Walking with the player (D-057): "follow me" / "seuraa minua" makes someone
  actually come along, through doors and along the street, until their own shift
  or night is due, "wait here", trouble, sleep or leaving the region.
  Refused with a reason for a shift, a grudge or a phone line.
- Asking someone to fetch, bring, carry or go is refused honestly
  (`cannot_do`): they no longer say yes to something the game will not do.

### Fixed
- NPC replies cut off mid-sentence or very short on reasoning models
  (Gemini Flash via OpenRouter and similar): thinking shared the 160-token cap
  with the answer. All providers now reserve room for thinking (D-056), the
  dialogue budget is 200 tokens, and a reply that still hits the limit is
  trimmed to its last finished sentence.

## [0.6.0] — 2026-09-19 — Milestone 6: consequences

What you do stays done. Take something and someone who saw it may tell the
police, who answer in proportion to what they *believe*; talk your way out of
trouble, or into worse; start a fight with real people who keep their wounds
and their friends, and be met for one in turn. A serious offence costs a job;
someone you hurt warns you, then names a time and place; a debt let go is
collected, then someone is sent. The clinic treats what a fight leaves.
816 tests, 9873 assertions.

### Decided
- Dynamic events: once a day the world asks what it already knows — who
  believes what of the player, who is fond of whom, what is owed — with no
  dice and at most one new step a day: a dismissal (an employer who believes
  something serious), a grudge (a warning, then a named time and place that,
  if kept, they start), a collection (three reminders, then someone stronger).
  Being met for a fight you were told of is not a crime. The clinic treats
  injuries (D-055)
- Combat: a turn-based fight you start by saying so in person; Attack, Heavy
  blow, Defend, Intimidate, Bandage, Run, Back down; real people with builds
  from who they are, health of their own that mends by the hour, friends and
  officers who step in; wounds that last on the player, feelings and memories
  in the others, and assault as a crime by the same witnesses, reports and
  police response as theft (D-054)
- Talking someone round: `negotiate` (and `persuade`, `ask_favor`) put an
  authored ask when there is one to put — graded success, partial (with a
  cost), failure or backfire, from skill against difficulty on seeded dice; a
  model only reads what was meant; the two authored asks reach into two
  systems (a debt's time and price, an officer's leniency) (D-053)
- The police respond to what an officer *believes*, not to what happened: her
  case is built from her knowledge (how sure, how serious, whether there is a
  record) and the answer steps up from nothing to a warning, a fine or an
  arrest; she sends for the player by text; coming in gets the case weighed at
  the desk, not coming in gets it weighed worse without you and the player is
  taken in once time has stopped moving; a fine that cannot be paid is a night
  in the cells; an arrest is known and travels (D-052)
- Crime is only what someone saw: theft at a shop counter is judged against
  who is there and how closely they watch (post, character, the player's
  stealth), on seeded dice; someone on duty who notices stops it, a bystander
  lets it happen and remembers; nobody noticing leaves nothing behind. A
  witness is a firsthand fact, a change of heart and a memory, and tells the
  police only if it matters enough to them — by rule — a while later, and
  secondhand (D-051)

### Added
- `ConsequenceRules`, `ConsequenceDirector` (`Game.consequences`);
  `MeetingDirector.arrange_confrontation()`, hostile meetings on the calendar;
  `FightDirector`'s aggressor; `CrimeDirector.known_offences()`;
  `PhoneDirector.notice()`; `ClinicRules` and treatment at the clinic desk;
  `Events.ambush`; `collection` on a quest; save schema v10
  (`consequences`); `test_consequences` (22 tests)
- `CombatRules`, `Combat`, `FightDirector` (`Game.fights`), `CombatWindow`,
  `CombatText`; `Game.start_fight()`, `fight_act()`; the intent `attack`;
  `CrimeDirector.record_crime()` (theft uses it), the predicate `assaulted`;
  `Events.fight_requested`, `fight_started`, `fight_ended`; the deed `fought`;
  `ui_preview --fight=npc_id`; `test_combat` (19 tests), `test_fights` (18)
- `AskRules`, `AskDirector` (`Game.asks`), `data/asks.json` (two asks),
  data validation for asks; `QuestLog.extend_deadline()`,
  `raise_requirement()` and a quest's `extra_need`; `CrimeDirector.leniency`;
  the intent kind `negotiate`, offline phrases in English and Finnish;
  `Events.ask_resolved`; save schema v9 (`asks`); `test_asks` (19 tests)
- `PoliceRules`; `CrimeDirector.case_for()`, `assess()`, `resolve()`, the
  record and summons; `PhoneDirector.summons()`; the police desk
  (`Game._at_the_desk`); `Game._arrest()` and its deferral;
  `Events.summons_issued`, `police_action`, `player_arrested`; the world
  events `police_assess`, `police_summons_due`; save schema v8 (`crime`);
  `test_police` (19 tests)
- `TheftRules`, `CrimeDirector` (`Game.crime`); `Game.steal()`; "Pocket it" on
  the shop window; `Events.crime_committed`, `crime_reported`; the deed
  `stole`; the world event `crime_report`; `test_theft` (14 tests)

### Changed
- A message held back only because someone had just written now waits (up to a
  day) instead of being dropped
- Offline reading: asking to bargain outranks saying goodbye ("can I pay
  later?" is no longer a farewell)

## [0.5.0] — 2026-09-19 — Milestone 5: the phone

Your own phone, in a window of its own: messages, contacts, a calendar, a bank
and a map, and calls. People text you when the simulation gives them a reason,
held to quiet hours and a daily cap; you can write back, or ring them, in your
own words, and it goes through the same rules as speech. A friend may suggest
meeting; whether you kept it is read from where you stood. Money moves through
your account; the map shows only what you have learned. Email and photos are
deliberately not there yet (D-050). 705 tests, 9147 assertions.

### Decided
- Calls: a call is a conversation down a phone — the same box, the same
  rules, the same road as speech; whether they pick up (awake, not at work, a
  civil hour) stands in for presence; a call is not standing in front of
  someone, so it is the deed `called`. Email, photos and the criminal-contacts
  view are deliberately deferred, with reasons (D-050)
- The map: the phone's Map tab draws the district as the player knows it —
  places been to solid, places heard of outlined, numbered with a legend, the
  player on it and nobody else; a place is learned by going there, by being
  told (a rules-judged effect), by an invitation, or by being hired there
  (D-049)
- Banking: the ledger says when; the phone's Bank tab shows the account's
  statement in words; money sent by text goes through the account (replacing
  "cash cannot be sent by text") and counts as the same `gave_money` deed;
  a cash machine in the corner shop moves cash in and out (D-048)
- Meetings: a fond friend may suggest meeting tomorrow at an open public
  place; accepting is judged (notice, clashes) and schedules a reminder, the
  person heading over, and the moment it is settled as world events; kept or
  missed is read from where people stand, never from anyone's word; missing
  one costs trust and earns a text, being stood up costs nothing (D-047)
- Texting: a text goes through the same intent, rules and effects as a spoken
  line (one `_respond` behind two doors); cash cannot be sent by text; a text
  is read when the person gets to it — awake, at a civil hour, sooner if idle
  — and answered as a text (D-046)
- The phone: its own window on P, only if you have one on you; numbers come
  from being known or hired; nobody writes without a cause the simulation
  produced, and the rules hold them to quiet hours, per-kind gaps and three
  people a day; a text can ask something and your answer is judged like any
  other proposal (D-045)

### Added
- `PhoneRules.judge_call()`, `PhoneDirector.can_call()`, `Game.can_call()`,
  `start_call()`, `DialogueDirector.start_call()`, `Conversation.channel`;
  a Call button on the thread; `DialogueBox.open(npc, by_phone)`;
  `test_calls` (12 tests)
- `PhoneState` (`Game.phone`), `PhoneRules`, `PhoneDirector`
  (`Game.phone_director`), `PhoneText`, `PhoneWindow` (new `phone` input
  action); `Game.has_phone()`, `answer_message()`, `read_thread()`;
  `Events.phone_message`, `phone_read`, `phone_contact_added`
- Texts: an errand someone needs done (answerable in the thread), a quest
  deadline coming up, a shift missed, a friend checking in; the HUD says
  when something is unread
- `PhoneDirector.send_text()`, `process_due()`; `PhoneState.outbox`;
  `PhoneRules.judge_send()`, `judge_reading()`; `DialogueDirector.
  text_exchange()`; `Game.send_text()`; the deed `texted`; a compose row in
  the phone; contacts open as threads; `test_phone_texts` (20 tests)
- `Calendar` (`Game.calendar`), `MeetingRules`, `MeetingDirector`
  (`Game.meetings`); the phone's Calendar tab; `NpcRegistry.
  scheduled_location_of()`; `Events.meeting_updated`; the deed `met`;
  `meeting_place` on four locations; `test_meetings` (25 tests)
- `BankText`, `AtmWindow`, `Wallet.transfer_out()` and `Wallet.stamp`,
  `Game.atm_here()`, `atm_deposit()`, `atm_withdraw()`; the `atm` object
  kind, one in the corner shop; the phone's Bank tab; the effect `transfer`;
  `test_banking` (14 tests)
- `MapView`, the phone's Map tab; `PlayerState.known_places`,
  `learn_place()`, `knows_place()`; `Events.place_learned`; the effect
  `tell_place`; `test_map` (15 tests)
- `ui_preview --phone=calendar|bank|map`, `--atm=1`
- `test_phone` (24 tests); `ui_preview -- --screen=world --phone=threads|thread|contacts`

### Changed
- The phone's frame is wider (520 px) for a fifth tab
- Cash by text is no longer refused (`not_in_person` is gone): by phone
  `give_money` is judged against the account; a text with no money in the
  account is refused `not_enough_bank`
- The phone's Close button moved to its header
- `DialogueDirector.say()` is now a thin door onto `_respond()`; the
  conversation is passed in rather than held, `interpret()`, `end()` and the
  prompt context unchanged for callers
- Save schema version 7: adds `calendar`; a version 6 save gets an empty one
- Save schema version 6: adds `phone`; a version 5 save gets an empty one

## [0.4.0] — 2026-09-19 — Milestone 4: making a living

You can earn a wage, buy and sell and haggle, eat, sleep and collapse, keep
things in your own cupboard, and take on the threads your past left you with
and the small jobs people need done. 595 tests, 8511 assertions.

### Decided
- Shops: shelves and tills in data and saved state; buying and selling at
  the counter judged by `ShopRules`; midnight restocks and squares the till;
  time stands still at the counter (D-039)
- Haggling against the skill: one try per item per shop per day, odds from
  skill against the shopkeeper's trade and character and how they feel
  about you, rolled on the seeded stream (D-040)
- Meals and the condition loop: use what you carry; starving and
  exhaustion cost health; health at zero is a collapse that wakes you in
  the clinic, billed; the HUD says when, where, your cash and how you are
  (D-041)
- Jobs, shifts and wages: jobs are data; a shift is one batched step paid by
  the part worked; reliability is kept and missed days cost the job; asking
  for work and quitting are conversation intents the rules judge (D-042)
- The home as a base: a cupboard in your flat keeps what you do not carry,
  saved with you (D-043)
- Quests: threads and errands as data; stages move on deeds Godot already
  carried out, never on what a model said; the log states the goal and never
  the route (D-044)

### Added
- `data/shops.json` (corner shop, Kaisla, the Anchor, the pawn shop),
  `ShopRegistry` (`Game.shops`), `ShopRules`; `Game.open_shop()`,
  `shop_view()`, `buy()`, `sell()`, `close_shop()`
- `ShopWindow` in the world: a counter with a shop behind it opens it
- A cinnamon bun, at Kaisla
- `HaggleRules`, `Game.haggle()`, a Haggle button on every item for sale
- `ItemRules`, `Game.use_item()`, `InventoryWindow` on I (new `inventory`
  input action), `StatusText` and the HUD's status corner,
  `Events.player_collapsed`
- `data/jobs.json` (harbour, worksite, Kaisla, clinic) and three
  occupations; `Employment` (`Game.work`), `WorkRules`; `Game.work_shift()`,
  `job_here()`, `hire_player()`, `quit_job()`; `Wallet.add_to_bank()`;
  `Events.job_changed`, `Events.job_lost`
- Conversation kinds `ask_for_work` and `quit_job`, with generic lines
- `PlayerState.stash`, the `stash` object kind, `Game.store()` and
  `Game.take()`, `StashWindow`; `test_home` (6 tests)
- `test_shops` (13 tests), `test_haggling` (8 tests), `test_condition`
  (11 tests), `test_work` (11 tests)
- `ui_preview -- --screen=world --shop=location_id [--selling=1]`
- `data/quests.json` (the debt, the old face, the warehouse, the cover
  shift), `data/errands.json`; `QuestLog` (`Game.quests`), `QuestRules`,
  `QuestText`, `QuestWindow` on J (new `quests` input action);
  `Events.player_deed`, `Events.quest_updated`
- Conversation kind `offer_help` asks for an errand; delivering it in
  conversation pays; `test_quests` (12 tests)
- `ui_preview -- --screen=world --quests=1`

### Changed
- Hunger fills over ten waking hours instead of six
- Haggling odds fall when the player is hungry, tired or drunk
- Save schema version 3: adds `shops`; version 2 saves open every shop
  with its usual stock
- Save schema version 4: the job moves from `player.job_id` to its own
  `work` section
- Save schema version 5: adds `quests`; a version 4 save gets an empty log

## [0.3.0] — 2026-09-19 — Milestone 3: conversation

You can walk up to anyone and talk to them in your own words. With no model
they answer from authored lines by topic, in English and Finnish; with the
player's own key and a provider chosen in Settings, they answer in their own
words, knowing only what they should. What you say can do things — give
money, introduce yourself, compliment, insult, threaten — but only what the
rules allow, and they remember it. 534 tests, 8124 assertions.
**No live provider has been contacted yet**: the key is the player's to
enter, so first contact happens on the player's machine.

### Decided
- M3 step 1: talking to people works offline first. Interact while facing
  someone opens a conversation the simulation has to allow; a dialogue box in
  the house style; typed lines recognised by topic in English and Finnish and
  answered from authored lines, a voice for every story NPC; people only know
  who they know; time stands still while talking (D-035)
- The model speaks behind the same `say()`: the prompt is a pure function of
  what this person is, sees, feels and believes; a reply changes nothing by
  itself; any failure falls back to the authored line; the Anthropic provider
  speaks to current models; a settings screen takes the player's own key; no
  test can reach a provider or the player's own settings and keys (D-036)
- What the player meant is a proposal: the cheap model (or words, offline)
  reads the intent, `ConversationRules` judges it, Godot carries it out, a
  refusal emits `action_rejected`, and the reply is told what actually
  happened (D-037)
- People remember the player: episodes written by rule from what the rules
  judged, folded into a bounded summary that the cheap model may rewrite,
  recalled into prompts with how long ago; a developer overlay on F3 (D-038)

### Added
- `DialogueDirector` (`Game.dialogue`), `Conversation`, `OfflineTopics`,
  `DialogueLines`; `Game.start_conversation()`, `say_to_npc()`,
  `end_conversation()`
- `DialogueBox` scene in the world; `NpcBodies.body_at()`, `NpcBody.hold()`
  and `resume()`; a "Talk to …" prompt
- Authored lines for all ten story NPCs and for everyone else, in English
  and Finnish
- `test_dialogue`: 26 tests
- `ui_preview.tscn -- --screen=world --talk=npc_id [--say=text]`
- `DialoguePrompt`, `DialogueModel`, `LlmDialogueModel`;
  `DialogueDirector.prompt_context()`; `bio` and `voice` for every story NPC
- Settings screen (`SettingsScreen`), reached from the title screen:
  language, provider, API key, models, routing, status and disclosure
- `Settings.persist`, `LlmClient.sandboxed`, `SecretStore.path`
- `test_dialogue_model` (14 tests), `test_settings_screen` (13 tests), five
  more provider tests in `test_llm`
- `ui_preview.tscn -- --screen=settings [--provider=id] [--locale=fi]`
- `ConversationRules`, `IntentPrompt`, `DialogueDirector.interpret()`,
  `OfflineTopics.resolve()`; new kinds introduce_self, compliment, flirt,
  apologize, insult, threaten and give_money, with generic authored lines in
  English and Finnish
- `test_conversation_rules` (13 tests), `test_intent` (15 tests); the
  scripted test model is shared (`tests/scripted_dialogue_model.gd`)
- `MemoryBook` (`Game.memories`), saved as the `memories` section;
  `ConversationRules.memory_of()`, `DialogueDirector.summarise()`,
  `DialoguePrompt.summary_request()`, `DialogueDirector.turn_log`
- `DevOverlay` in the world scene; `ui_preview -- --screen=world --overlay=1`
- `test_memory` (13 tests), `test_dev_overlay` (4 tests)

### Changed
- `say()` and `Game.say_to_npc()` are coroutines; the dialogue box waits with
  a "…" while a model answers
- Anthropic: suggests `claude-opus-5`, `claude-sonnet-5`, `claude-haiku-4-5`;
  sends `temperature` only to model families that accept it, `effort: low`
  where supported, thinking headroom on models that think by default; a
  `refusal` stop reason is the `refused` failure
- The test runner starts from default settings and never writes them
- Save schema version 2: adds `memories`; version 1 saves migrate to an
  empty book
- `LlmBudget` price estimates match current models before their families

### Fixed
- The ObjectDB leak reported at the end of every test run: lambdas in
  `test_game_clock` held the test that held the clock

## [0.2.0] — 2026-09-19 — Milestone 2: the world you can see and walk

You can start a character, walk Harbourside, watch its people keep their
routines around you, and sleep to the next morning. 432 tests, 7444
assertions.

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
- M2 step 5: the world is the main scene, `SimViewer` moves behind
  `developer_mode`, and region exits are walked rather than pressed; Old Town
  and Eastfield stay unmapped (that's M7), so travelling there refuses today (D-023)
- A `home`-kind building the right size (8x13 cells) gets one whole,
  hand-drawn LimeZu house image instead of generic per-cell tiles; six of the
  seven homes were resized in `data/maps.json` to fit (the seventh's plot is
  too narrow) (D-024, corrected in D-025 to keep the whole porch)
- `shop`/`bar`/`civic`/`work` share a second whole building (a flat-roofed
  storefront, sign recoloured per kind since its own said "POST OFFICE"); six
  more buildings resized to fit, sharing a street with the resized homes
  forced two of them further along it than originally authored (D-026)
- `RegionView` y-sorts itself in code instead of relying on the embedding
  scene to remember the override; without it, whole-building sprites lost
  the draw order against later-streamed tile chunks and showed the plain
  per-cell tiles behind them instead (D-027)
- A building drawn as one whole sprite draws no per-cell tiles at all, puts
  its door on the column the art draws one in, and keeps its porch as
  walkable ground outside the rect so the door can be reached (D-028)
- Street furniture is placed by what a cell is — lamps at a regular interval
  along the back edge of a pavement, bins beside doors — instead of by a hash
  over any cell near a road (D-029)
- Harbourside is relaid at 96x72 with a second street, so the shop row's
  doors open onto a pavement instead of the carriageway; a basketball court,
  a park and a worksite are placed on it, furnished by `PlaceArt` (D-030)
- Grass, sand and dock are real LimeZu tiles; terrain that meets a different
  terrain picks from a 4x4 edge set by a four-neighbour mask, in its own
  atlas source, which also carries the sea's eight animation frames (D-031)
- M2 step 6, day and night: the outdoor world is tinted by the time of day
  through a `CanvasModulate`, and street lamps are real lights that come on as
  it gets dark; indoors is never darkened (D-032)
- A character is a `CharacterDraft` that Game validates before building a
  world from it: background, name, pronouns, a look, and at most two
  attribute points moved. A new life starts at home, indoors. Sleeping in your
  own bed is the save point (D-033)
- The way in: title screen over Harbourside at dusk, then background,
  appearance and confirmation, then a short authored opening per background,
  then the world. A project-wide UI theme in LimeZu's UI colours (D-034)

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
- `Boot.destination_scene()`: `world.tscn` normally, `SimViewer` only under
  `developer_mode` (D-023, M2 step 5); `test_boot`: 2 tests
- Region exits are walked, not pressed: `Game.move_player()` checks
  `DistrictMap.exit_at()` and travels to an unlocked, mapped neighbouring
  region or refuses (`region_locked`/`region_unmapped`/`region_unknown`)
  exactly like a blocked cell; `WorldView` reacts to a `"travelled"` result
  the same way it already did to a building's `entered`/`exited` (D-023)
- `test_player_movement`: 4 new tests for region exits, including the full
  success path against a throwaway destination map
- `TitleScreen`, `CharacterCreation`, `Opening`, `TitleBackdrop` and their
  scenes; `scenes/ui/humptown_theme.tres`; `Boot` hands off to the title
- `CharacterDraft`, `Game.new_game_from()`, `Game.has_saved_game()`,
  `Game.continue_game()`, `Game.save_slot`; `PlayerLook` (appearance to
  palette and sprite layers, and what there is to choose from);
  `CharacterSprites.look_for()` takes chosen styles, `styles()`
- `scenes/debug/ui_preview.tscn`: any front-end screen at any step, for
  screenshots
- `test_character_draft` (20), `test_front_end` (9)
- Opening lines for every background, in English and Finnish; Finnish for
  every new screen
- `DayNight`: the tint and the lamp brightness for any minute of the day;
  `WorldView.refresh_daylight()`, `RegionView.set_lamp_energy()`;
  `test_day_night`: 12 tests
- `tools/import_limezu_terrain.py`: builds the local, git-ignored
  `art/vendor/limezu/terrain/` (grass, sand, dock, and the shoreline and kerb
  edge sets) from the purchased packs
- `RegionTiles.ground_tile()` / `edge_coords()` / `edge_set_for()`: which
  atlas source and tile a ground cell draws, by what its neighbours are
- `tools/import_limezu_places.py`: builds the local, git-ignored
  `art/vendor/limezu/places/` (a basketball court, trees, benches, a building
  frame, an excavator, cones) from the purchased packs
- `PlaceArt`: authored decoration for an open-air location, drawn by
  `RegionView._build_place_art()`; `test_place_art` covers it
- `tools/import_limezu_buildings.py`: builds the local, git-ignored
  `art/vendor/limezu/buildings/` (five house sprites, plus one storefront per
  kind with its sign repainted) from the purchased packs
- `BuildingArt`: whether a building's kind and size match a whole LimeZu
  sprite, and which one (varied per building, stable per building);
  `RegionView._build_building_art()` draws it, y-sorted to always win against
  its own covered wall/door tiles; `DistrictMap.kind_of()`
- `test_building_art`: 7 tests, including a `RegionView` integration check

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
- Seven Finnish strings had lost their ä and ö ("Ruumiillinen tyo",
  "Patevoitynyt"); restored
- A world-scene test only passed when the runner happened to resume it before
  a frame's `_process` calls; it now waits for a full pass (D-034)
- `SimViewer` failed to compile under the strict warning settings (untyped
  `slice()` element in the scheduled-events panel)
- Whole-building sprites (D-024 through D-026) drew behind their own
  building's later-streamed tile chunks in `region_preview.tscn` (not
  `world.tscn`, which happened to override the setting), reading as leftover
  plain construction behind the real house/storefront art (D-027)
- The generic red roof showed through a villa's pitched-roof corners as
  stray brickwork behind every finished house; the six villa-sized homes had
  their door a column off the drawn door, and their porch was solid, so the
  door could not be walked up to (D-028)
- `region_preview.tscn` takes `--at=x,y` and `--zoom=z`, so a whole district
  can be judged in one screenshot instead of a doorway at a time
- Every pavement in town had been drawn in road grey since D-021: the tile
  importer took piece 10 of each LimeZu Sidewalk set, which is the asphalt a
  pavement borders, where piece 9 is the pavement itself (D-031)
- The player's sprite stuttered slightly while moving: physics runs at a
  fixed 30 Hz but the display renders faster, so `physics/common/
  physics_interpolation` is now on project-wide, with
  `PlayerBody.place_at()` resetting it on teleport so spawning/loading/
  entering a building doesn't visibly glide from the old position

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
