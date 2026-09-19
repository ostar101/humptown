# Roadmap

Milestones are sequenced so each one is testable on its own and so the systems
that define the game's identity exist before content is built on top of them.
Scope control is the largest risk on this project; anything not listed here is
deliberately later.

## M1 — Foundation and simulation spine ✅ complete

Project setup, core services, time, world and NPC model, schedules and
simulation tiers, relationships, knowledge propagation, reputation, player
state, economy, progression, the LLM provider layer, saving with migrations,
localisation, a debug viewer, the test suite and the benchmark.

No rendering. The world runs and is observable, and every claim about it is
covered by a test.

## M2 — The world you can see and walk

- Tilemap-based district rendering for Harbourside, chunk-loaded by region
- Player controller and the angled top-down camera with contextual framing
- NPC bodies attached to `ACTIVE` tier NPCs and released on demotion
- Interaction system: doors, shops, objects worth touching
- Day/night lighting
- Title screen, background selection, character customisation, the opening
- Replaces `SimViewer` as the main scene; the viewer moves behind developer mode

Done when: you can start a character, walk Harbourside, watch inhabitants keep
their routines around you, and sleep to the next morning.

## M3 — Conversation

- Dialogue UI: portrait upper left, name, typewriter reveal, free text entry
  at the bottom, optional quick replies that never replace typing
- Prompt assembly: identity, present circumstance, selected memories, the
  relationship, and only what this person actually knows
- Intent interpretation on the cheap model; **validation in Godot**
- The proposal/validation pipeline with `Events.action_rejected`
- Hierarchical NPC memory with summarisation
- Authored fallback lines for offline play
- Developer overlay: tokens, latency, cost, cache hits, selected memories,
  rejected proposals

Done when: you can talk to Ida in your own words, she answers in character
knowing only what she should, and unplugging the network degrades the
conversation without breaking the game.

## M4 — Making a living

- Jobs, shifts and wages; gig work
- Shops, buying and selling, haggling against the skill
- The player's home as a functioning base
- Sleep, meals, the condition loop closing properly
- Basic quest system: authored threads plus NPC-need-driven jobs
- Quest UI that states the goal without drawing the route

## M5 — The phone ✅ complete (0.5.0)

Messages, calls, contacts, map, photos, calendar, email, and the criminal
contacts view. NPCs reach out on their own when it makes sense, rate-limited so
it never becomes spam. Its own UI window, not a reskinned pause menu.

Built: messages both ways, contacts, calls, calendar with meeting requests,
bank and cash machine, map of what the player has learned (D-045 to D-050).
**Deliberately not built, with reasons (D-050):** email (nothing yet writes to
it), photos (nothing to photograph), the criminal-contacts view (waits for
crime, M6).

## M6 — Consequences ✅ complete (0.6.0)

- Turn-based JRPG combat: attack, defend, skills, items, flee, context actions
- Conflict resolution that is not only fighting — partial successes, costs,
  debts, delayed consequences
- Crime, witnesses, investigation, police response proportionate to what is
  actually known
- Injuries that persist and a clinic that treats them
- Dynamic events generated from world state

## M7 — Opening out

Old Town and Eastfield. Travel. Progressive map revelation. Factions with their
own goals. The main story threads. More inhabitants. Audio.

## Explicitly out of scope for v1

Weather. Seasons. Voice acting or TTS. Property management. Vehicles.
Minigames. Deep career simulation. Difficulty settings — the world's own
conditions are the difficulty.
