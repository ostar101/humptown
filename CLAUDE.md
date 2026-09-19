# Working rules for Claude sessions on Humptown

Read this and `PROJECT_STATUS.md` before touching anything.

## Start of every session

1. Read `CLAUDE.md` (this file) and `PROJECT_STATUS.md`.
2. `git log --oneline -15` to see where the last session stopped.
3. `git status` — the tree should be clean. If it is not, find out why before adding to it.
4. Run the tests: `godot --headless --path . res://tests/test_runner.tscn`. They must be green before you change anything, so that any failure you see later is yours.
5. If the `humptown-memory` MCP server is available, read `memory_context` (see below).
6. Continue from the "Next task" section of `PROJECT_STATUS.md`.

## End of every session, and whenever you are near a usage limit

Stop at a safe point rather than mid-refactor.

1. Finish the current subtask so the tree builds.
2. Run the tests. Green, or explicitly recorded as red in `PROJECT_STATUS.md` with the reason.
3. Update `PROJECT_STATUS.md`: what is done, what is next, anything a fresh session would not guess.
4. Add an entry to `CHANGELOG.md`.
   If `humptown-memory` is available, also call `memory_update_current` and
   `memory_append_history` with a short summary.
5. Commit with a conventional-commit message. Push if a remote is configured.
6. If the push fails, say so plainly and leave the commit local. Never report a push that did not happen.

## Persistent project memory

`Humptown-Claude-Memory/` holds a local MCP server, `humptown-memory`,
registered in `.mcp.json`. Both are git-ignored: they are machine-specific.

The repository stays the source of truth. `PROJECT_STATUS.md`, `DECISIONS.md`
and `CHANGELOG.md` are authoritative; the memory is a compact aid that points
into them. When the two disagree, the repository wins — fix the memory.

- At the start of substantial work: read `memory_context`, then use
  `memory_search` only for what the current task needs. Check the actual files
  before relying on anything the memory says.
- After a milestone, once tests have run: `memory_update_current`, record
  durable decisions with `memory_write` (short, linking to the `D-0xx` entry),
  and add a compact `memory_append_history` entry.
- Do not load the whole memory or history by default.
- Never store secrets, API keys, passwords or credentials in memory.

## The architectural rule that outranks convenience

**Godot owns the world. The LLM interprets and proposes. Godot validates and executes. The UI shows what happened.**

Concretely, and without exception:

- No LLM response ever writes to `WorldState`, `NpcRegistry`, `PlayerState`, `Wallet`, `Inventory`, `RelationshipGraph` or `KnowledgeNetwork` directly.
- A model's output is a *proposal*. It passes through a validator that returns a `Result`. A rejected proposal emits `Events.action_rejected` and the world is unchanged.
- If you find yourself writing "the model decides whether…", stop. The model decides what the player *meant*. Rules decide what *happens*.

## Decision authority

Make implementation decisions yourself and record the notable ones in `DECISIONS.md`. Ask the user only when a choice would change the game's vision, introduce a major new system, significantly expand scope, contradict an explicit requirement, or be expensive to reverse.

## Code conventions

- **Language:** English for code, comments, commits, docs, internal ids, debug output. Player-facing text goes through `tr()` with a key defined in `locale/en.json`.
- **Typing:** static types everywhere. GDScript's inference gives up on `Variant` returns — annotate explicitly (`var x: QueuedEvent = array.pop_back()`), because warnings are errors in this project.
- **Closures:** GDScript lambdas capture locals **by value**. A captured `int` counter will silently stay at zero. Use a one-element array, or an object.
- **Failure:** anything that can legitimately be refused returns `Result`, not `null` and not a crash. Reason codes are short snake_case strings.
- **JSON from outside:** parse with `SafeJson.parse()`, never `JSON.parse_string()`. The latter pushes an engine error, which is right for a bug and wrong for a model returning prose.
- **Serialisation:** every persistent class has `to_dict()` / `from_dict()`. Add the section to `SaveManager.SECTIONS` and a migration step in the same commit.
- **New `class_name`:** run `godot --headless --path . --import` once so the global class cache picks it up, or dependent scripts fail to compile in confusing ways.

## Performance rules

- No NPC runs expensive logic every frame. Tiering lives in `NpcDirector`; respect it.
- Never call an LLM in a loop over NPCs, and never to decide something deterministic logic can decide. Walking to work is a state machine's job.
- Long stretches of time advance in batches (`GameClock.advance`), never by replaying every minute.
- After changing anything in `src/npc/`, `src/time/` or `src/world/`, run the benchmark: `godot --headless --path . res://tests/benchmark.tscn`. Compare against the numbers in `PROJECT_STATUS.md`.

## Testing rules

- New system, new test file. Tests live in `tests/test_*.gd`, extend `TestCase`, and are discovered automatically.
- Every persistent class gets a save round-trip test.
- Every validator gets a test for the refusal path, not just the happy one.
- Do not mark a milestone complete without running the suite.

## Content rules

- Authored content is JSON in `data/`. Schedules use `@home` and `@work` tokens so one routine serves many people.
- Adding content means updating `locale/en.json` in the same commit. `test_content` and `test_localization` will catch you if you forget.
- Every simulated NPC must be an adult. This is enforced by a test, deliberately, so it cannot be lost later.

## Things that are deliberately not done yet

Do not "fix" these; they are sequenced, not forgotten. See `ROADMAP.md`.

- No live LLM call has ever been made — the provider layer and dialogue are built and tested offline; first contact needs the player's own key, entered by the player.
- No combat, crime or police. The phone has its core only (M5 step 1: contacts, texts, errands by text); replies, calendar, map and the rest are sequenced in `PROJECT_STATUS.md`. No weather or seasons ever in v1 (explicitly out of scope).
