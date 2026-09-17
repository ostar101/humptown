# Humptown architecture

## The layering rule

Four layers, and the arrows only point one way.

```
  Presentation     scenes, UI, the debug viewer
       |  reads state, emits input intent, never mutates
       v
  Execution        Game, NpcDirector, validators
       |  the only code that changes the world
       v
  Simulation       WorldState, NpcRegistry, RelationshipGraph,
                   KnowledgeNetwork, PlayerState, GameClock
       ^
       |  proposes; every proposal is validated before it lands
  Interpretation   LlmClient, LlmRouter, providers
```

The reason this is stated first, and enforced by code review, is that an LLM in a game engine will become a god-object if you let it. A model that can write to world state can invent a building, a debt, a relationship or a memory, and every later system will believe it. Keeping the model on the interpretation side means the worst a bad response can do is get rejected.

## Directory map

```
src/core/      Log, Events, Settings, Game (composition root), Result, SafeJson, RngStreams
src/data/      DataRegistry — loads and validates res://data/*.json
src/time/      GameClock, WorldEventQueue
src/world/     WorldState, Region, Location
src/npc/       Npc, NpcRegistry, NpcSchedule, NpcNeeds, SimLod, NpcDirector
src/social/    Relationship, RelationshipGraph, KnowledgeNetwork, Reputation
src/player/    PlayerState
src/economy/   Wallet, Inventory
src/progression/ Stats, Skills
src/llm/       LlmClient, LlmRouter, LlmBudget, LlmRequest/Response, SecretStore, providers/
src/save/      SaveManager, SaveMigrations
src/loc/       Localization
src/debug/     SimViewer
data/          authored content (JSON)
locale/        en.json, fi.json
tests/         test framework, suites, benchmark
```

Four autoloads and no more: `Log`, `Events`, `Settings`, `Game`. Systems receive their dependencies at setup and communicate afterwards through `Events`, so the dependency graph stays shallow and testable.

## Time

Time is one integer: minutes since the world's epoch. Calendar fields come from a real Gregorian calendar through Godot's `Time` singleton, so month lengths, leap years and weekdays are correct with no bespoke calendar code.

There are two advancement modes, because an eight-hour sleep must not cost eight hours of ticks.

`tick(delta)` is continuous play: it emits `minute_passed` for each minute and drains due world events.

`advance(n)` is a batched jump for sleep, travel and scene transitions. It walks to each queued event in turn so that event's handler observes the correct clock, emits hour and day boundaries but never per-minute signals, and finishes with one `time_skipped`. Jumps longer than three days stop emitting hour boundaries as well. NPC state is then brought forward in a single `catch_up` step rather than replayed.

## The world outside the player's view

`WorldEventQueue` is a binary min-heap of scheduled events, ordered by time and then by insertion sequence so resolution is deterministic and therefore save-safe. This is how distant things happen without being simulated: instead of an off-screen manager thinking every frame, the world records that a response is due in 45 minutes and resolves it then.

Regions are the unit of streaming and of unlocking. Unlock requirements are a list — story flag, money, reputation, contact, item, knowledge, skill — and each region may use a different one, so the world does not read as a single corridor with a key at each door.

## NPC simulation, and why a large population is affordable

The central trick: **a schedule is a pure function of time.** `NpcSchedule.resolve(weekday, minute_of_day)` reads no state and writes none. So a dormant NPC does not need ticking — their position is *computed on demand*. Two thousand people cost nothing until someone looks at them.

Four tiers, assigned by `NpcDirector`:

| Tier | Who | Cost |
|---|---|---|
| `DORMANT` | everyone far away | nothing; position computed on demand |
| `BACKGROUND` | neighbouring regions, plus all named and story NPCs | one tick per 15 game minutes |
| `ACTIVE` | in the player's region, capped at 60 | one tick per game minute |
| `FOCUS` | in conversation or combat, capped at 8 | full detail, may use the LLM |

Three things keep the per-minute cost flat as the population grows:

1. **The director walks the awake set, not the population.** `_awake` holds only non-dormant ids.
2. **Candidates are looked up by region.** `NpcRegistry` indexes everyone by the regions they can actually appear in, derived once from home, workplace and the explicit locations in their routine. A retier pass considers local residents plus the handful of narratively important people, not the whole town.
3. **Resolved positions are cached until the routine block ends.** A block lasts hours, so the schedule maths runs once per block rather than once per pass.

Known scaling property: the retier pass is O(people who could be in the player's region), not O(world). If a single district ever holds thousands of residents, that pass grows. The structural fix is more, smaller regions — which the design wants anyway — not a cleverer director.

## Information, reputation and the difference between them

NPCs never read world state to find things out. They know only what reached them, and every belief carries its provenance: who told them, how many retellings ago, how confident they are, how garbled it has become.

`KnowledgeNetwork` holds facts and, separately, each person's *belief* about each fact. A fact spreads by scheduling future "telling" events along the relationship graph, so a rumour crossing town is a handful of queue entries rather than a simulation loop. Each retelling costs confidence and adds distortion. Visibility decides whether a fact spreads at all: `PRIVATE` never leaves its witnesses, `SOCIAL` travels through personal ties, `PUBLIC` travels faster and wider, `BROADCAST` reaches everyone through news. Severity sets the speed — serious news moves in half an hour, trivia takes most of a day.

`Reputation` is then *derived*, not stored. Standing in a scope is a function of what that scope's members believe, weighted by their confidence and diluted by how few of them have heard. There is no global notoriety number. A crime nobody witnessed and nobody heard about changes nothing, which is the entire point. Scopes also read the same act differently: a criminal crew does not care that you were arrested, it cares that you talked; the police see it the other way round.

## The LLM stack

`LlmProvider` subclasses are **pure**: they turn a request into an HTTP call and an HTTP reply into a normalised response, and perform no I/O. Transport lives in `LlmClient`. That split is why every wire format, every error path and every routing decision is unit-tested offline on each run, with no key and no network.

`LlmRouter` decides which model — or none. Classification, extraction, summarisation and small reactions go to the cheap model; conversation and narrative go to the main one; `cheap_first` and `quality` modes tilt that, but a scene marked `KEY_DIALOGUE` is never demoted. Cacheable purposes are cached with a TTL; conversation never is.

`LlmBudget` answers "should this call happen right now" from three angles: a daily request cap, a minimum interval between calls, and a circuit breaker that stops calling a dead endpoint after repeated failures and probes it again later. Our own refusals — no key configured, budget spent — deliberately do not trip the breaker.

`NullProvider` is a first-class provider, not an error path. With no key, no network or AI turned off, calls still return well-formed responses carrying `error_code == "disabled"`, and the dialogue layer falls back to authored lines. The integration suite asserts the whole game is playable in that state.

API keys live in `user://secrets.dat`, encrypted with a passphrase derived from the machine id, and never appear in settings, saves, logs or the repository. See `DECISIONS.md` D-006 for the threat model, stated honestly.

## Saving

Manual and slot-based. The save is a dictionary of independent sections, each system serialising itself, so adding a system means adding a section rather than touching the others.

Writes go to a temporary file which is read back and parsed before it replaces the previous save. A failed write can never take the player's only recovery point with it.

`SaveMigrations` exists from day one with an empty step table, because the alternative is discovering at version six that every early save is garbage. Loading applies the chain from the file's version to the current one; a save from a newer build is refused with a message naming the version rather than loading half of itself.

## Content

Authored content is JSON in `data/`, not Godot `.tres` resources: it diffs cleanly in git, can be generated by tools, and needs no editor import step, so headless tests load exactly what the game loads. Everything is validated on load, and a malformed entry is dropped with a logged error rather than making the game unbootable. `DataRegistry.validate_references()` then catches the cross-file breakage that data-driven games actually die of — an NPC pointing at a location that was renamed.

## Localisation

JSON locale files loaded into `TranslationServer` at startup. English is the base and the fallback. A missing key renders as the key itself, so gaps are loud in testing rather than blank on screen. Finnish ships deliberately incomplete to exercise that path, and a test measures the gap rather than pretending it is not there.
