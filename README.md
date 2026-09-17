# Humptown

A 2D JRPG-style life simulation with a persistent social world, built in Godot.

You start with a background, not a destiny. The town keeps its own hours
whether or not you are watching: people go to work, drink in the evening, fall
out with each other, and learn things about you only if somebody actually saw
or was told. What they know is what your reputation is made of.

## Status

Milestone 1 is complete: the simulation spine runs and is fully tested. There
is no rendering yet — the current entry point is a developer screen that shows
the world running. See `PROJECT_STATUS.md`.

## Running it

Requires **Godot 4.5.x**.

```bash
# play (currently the debug simulation viewer)
godot --path .

# tests
godot --headless --path . res://tests/test_runner.tscn

# performance benchmark
godot --headless --path . res://tests/benchmark.tscn
```

In the viewer: change the clock speed, jump an hour, sleep eight hours, save
and reload, or press **Gossip** to drop a fact into the world and watch it
spread from one witness through the town over the following day.

## AI dialogue

Conversation will use a language model you supply a key for — OpenAI,
Anthropic, Google or OpenRouter. The provider layer is built and tested, but
nothing calls it yet (Milestone 3).

The game is designed to be fully playable without it. With no key, no network
or a dead provider, the world, movement, menus and systems all continue; only
free-form conversation falls back to authored lines. Keys are stored encrypted
under Godot's user directory and never touch settings, saves, logs or this
repository.

## Documentation

- `CLAUDE.md` — working rules for development sessions
- `ARCHITECTURE.md` — how the systems fit together and why
- `DECISIONS.md` — decisions worth defending later, with their costs
- `ROADMAP.md` — what comes next, and what is deliberately out of scope
- `PROJECT_STATUS.md` — current state, next task, known issues
- `CHANGELOG.md` — what changed when
