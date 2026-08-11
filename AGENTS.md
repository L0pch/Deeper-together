# AGENTS.md

## Project Overview

This repository contains a real-time multiplayer Christian conversation card game inspired by the general concept of conversation games such as "We're Not Really Strangers".

The game is intended for Christian friends, cell groups, church communities, and other small groups.

The game contains both:
- PG secular/general conversation questions
- Christian/faith-related questions

Questions are organised into three levels of increasing depth and vulnerability.

The goal is to create a welcoming, simple, mobile-friendly game that encourages meaningful conversation without forcing players to answer questions they are uncomfortable with.

---

## Core Product Principles

When implementing features, prioritise:

1. Simplicity
2. Mobile usability
3. Real-time multiplayer reliability
4. Privacy
5. Security
6. Maintainable code
7. Easy prompt/content management

Do not introduce unnecessary complexity or infrastructure unless there is a clear benefit.

If a simpler implementation adequately solves the problem, prefer it.

---

# Technology Stack

Unless the existing repository says otherwise, use:

- Next.js
- React
- TypeScript
- Tailwind CSS
- Supabase PostgreSQL
- Supabase Auth
- Supabase Realtime
- Vercel for deployment

Prefer modern Next.js App Router patterns.

Use React with TypeScript. React components should use `.tsx`; non-React TypeScript modules should use `.ts`. Do not introduce JavaScript/JSX files when TypeScript/TSX is suitable.

Avoid adding major libraries unless they provide a meaningful advantage.

Before installing a new dependency:
1. Check whether the existing stack already provides the functionality.
2. Prefer small, maintained dependencies.
3. Explain significant dependency additions in the relevant commit/task summary.

---

# Game Model

The application is a room-based real-time multiplayer game.

Players should be able to:

- Create a room
- Join a room using a room code
- Choose a display name
- Choose an avatar colour/icon if implemented
- Join an existing game even after it has started
- See the current player
- See the player queue
- See the current prompt
- See the prompt level
- See how many redraws occurred
- Select their preferred prompt level
- Draw a card on their turn
- Redraw a card
- Mark themselves as done sharing
- View prompt history
- See the room code throughout the game

Players must always be allowed to skip/redraw a question without providing a reason.

Do not build mechanics that pressure users into answering vulnerable questions.

---

# Prompt Levels

The game has three prompt levels.

## Level 1

Light, easy, fun, and low vulnerability.

Examples:
- preferences
- hobbies
- first impressions
- everyday life
- light Christian questions

## Level 2

More reflective and personal.

Examples:
- experiences
- relationships
- values
- personal growth
- faith journey
- what God has been teaching someone

## Level 3

Deep and vulnerable.

Examples:
- fears
- struggles
- difficult experiences
- hopes
- identity
- spiritual vulnerability
- meaningful prayer/reflection

Level 3 questions should remain respectful and appropriate for a PG/church setting.

Do not assume that deeper means more provocative.

---

# Prompt Categories

Prompts should support categories such as:

- secular
- christian
- hybrid

The database structure should allow additional categories or tags in the future.

Do NOT hard-code the main prompt bank into frontend source files.

Prompts should ultimately be stored in the database so that they can be edited without redeploying the application.

---

# Prompt Management

The application should eventually include a protected admin interface for prompt management.

Administrators should be able to:

- Add prompts
- Edit prompts
- Archive prompts
- Activate/deactivate prompts
- Assign a level
- Assign a category
- Add tags
- Search/filter prompts
- Import prompts in bulk
- Export prompts

Changing an active prompt should affect future draws without requiring a new deployment.

Previously drawn cards/history should preserve the wording that existed when the card was drawn.

Therefore, history records should store a snapshot of the prompt text and metadata rather than only referencing the current prompt record.

---

# Multiplayer Architecture

The server/database is authoritative.

Never trust the client to determine:

- whose turn it is
- whether someone is host
- queue ordering
- whether a player can draw
- whether a player can redraw
- whether a player can advance the turn
- whether a player can kick another player
- which prompt was selected

Client-side UI may optimistically display safe visual changes where appropriate, but authoritative game state must be validated server-side.

Do not implement critical game state purely using React client state.

---

# Player Identity

Players should not need to create an email/password account to play.

Use Supabase anonymous authentication or another secure guest identity mechanism.

A player's chosen display name is NOT their identity.

Permissions must be based on authenticated user IDs/session IDs.

Do not grant permissions based on:

- display names
- client-provided roles
- URL parameters
- localStorage values alone

---

# Room Codes

Rooms should have:

- An internal database UUID
- A human-readable room code

Use the internal UUID for database relations and real-time channels.

The room code is an invitation mechanism, not the sole security mechanism.

Prefer room codes made from unambiguous uppercase letters/numbers.

Avoid easily confused characters where practical.

The architecture should support:

- room locking
- room expiry
- room-code rotation
- maximum player count
- optional host approval in the future

Room-code rotation is deferred beyond the MVP. Room locking is the initial control for preventing additional joins. Do not design the schema in a way that prevents rotation from being added later.

---

# Accepted Product Decisions

These decisions are authoritative unless the product owner changes them later:

- Rooms expire and may be deleted 24 hours after the last meaningful game action. Meaningful actions include creating or joining a room, drawing or redrawing, completing a turn, and host actions. Realtime presence or an open browser connection must not extend expiry.
- Temporary disconnection must not remove a player, expire a room, or immediately transfer host status.
- Retain room history until room expiry, even if all players are temporarily disconnected.
- The initial room capacity is 20 players. The schema and UI must support a hard maximum of 30 players. Capacity selection is not required in the MVP.
- Redraws are unlimited. Every drawn prompt remains visible in history with its outcome, including prompts that were redrawn.
- A player's selected prompt level persists between turns. On their turn, they may change it before drawing; changing it also becomes their preference for future turns. If changed after a card is visible, the new level applies to the next redraw rather than changing the visible card.
- Prompt categories remain part of the data model, but player-facing category filters are not required in the MVP.
- When a host explicitly leaves or is removed, host status transfers transactionally to the next active player in queue order, wrapping to the first remaining player when necessary. Do not choose a random successor.
- Everyone can see the ordered player list and a visible `Host` label. Only the host can use player-management actions.
- Host player actions include `Kick player`, `Make host`, and `Play now`. These actions must be server-authoritative.
- `Play now` cancels or supersedes the current turn safely, moves the selected player into the current queue position, shifts the previous current player and intervening players back while preserving their relative order, and creates a new unique turn for the selected player. Stale actions for the replaced turn must fail safely.
- Room-code rotation is not part of the MVP.

---

# Queue Behaviour

The player queue is central to the game.

Example:

Current queue:

A -> B -> C -> D

If A is currently answering and E joins:

A -> E -> B -> C -> D

If F joins before A finishes:

A -> E -> F -> B -> C -> D

New players who join during an active turn must be placed immediately after the current player, while preserving the arrival order of multiple new players.

This prevents late joiners from waiting an entire round.

Queue changes should be transactional/atomic so simultaneous joins cannot corrupt ordering.

---

# Turn Behaviour

Each turn should have a unique identifier.

Typical turn flow:

1. Player becomes current player
2. Player selects/has selected prompt level
3. Player draws
4. Prompt appears for everyone
5. Player may redraw
6. Player shares
7. Player presses Done
8. Server advances to next player

Duplicate requests must not advance multiple turns.

For example, if Done is submitted twice for the same turn ID, only the first valid request should change state.

The host may override the normal flow using host controls.

---

# Joining During A Game

Players may join at any time unless the room is locked.

Joining flow:

1. Enter room code
2. Verify room exists
3. Enter display name
4. Optionally select avatar colour/icon
5. Join room
6. Insert into queue according to late-join rules

If the game is already running, the joining player should immediately receive the current room snapshot.

Refreshing the browser should not create a duplicate player if the same anonymous authentication session still exists.

---

# Host Permissions

The room creator initially becomes host.

Host-only functionality may include:

- Start game
- End game
- Kick player
- Lock/unlock room
- Advance turn
- Draw on behalf of current player
- Redraw on behalf of current player
- Select/change current player
- Change another player's selected level
- Transfer host
- Rotate room code
- Close room

All host permissions MUST be validated server-side.

Never trust a client field such as:

isHost: true

Host status must be determined from authoritative room data.

Do not transfer host status merely because the host temporarily loses their realtime connection. Host transfer occurs after an explicit leave/removal or a separately defined abandonment policy.

---

# History

Everyone in the room may view game history.

History should include:

- Player
- Prompt text
- Prompt level
- Prompt category where useful
- Draw/redraw order
- Whether the card was answered or redrawn
- Timestamp where useful

Do NOT store players' spoken/written answers unless a future feature explicitly requires this.

The default product should record cards, not private conversation content.

---

# Prompt Drawing

Prompt selection must happen on the server/database side.

Do not send the complete prompt database to every player's browser.

When drawing:

1. Determine requested level
2. Find eligible active prompts
3. Exclude prompts already used in the room/deck cycle
4. Randomly choose one
5. Record the draw
6. Return/broadcast the selected prompt

Avoid repeats until the available prompts for that level have been exhausted.

After exhaustion, the deck for that level may reset.

The design should handle prompt edits/deactivations safely.

---

# Real-Time Synchronisation

Use Supabase Realtime or the project's selected equivalent.

Players should receive live updates for:

- joins
- leaves
- queue changes
- turn changes
- draws
- redraws
- level changes
- history
- kicks
- room lock state

Do not assume WebSocket/realtime messages are guaranteed to arrive perfectly.

After reconnecting, request/read the authoritative current room state.

The application should be able to recover from:

- temporary disconnection
- refresh
- duplicate realtime events
- events received out of order where practical

---

# Security Requirements

Security should be treated as part of the architecture, not added at the end.

## Secrets

Never expose server secrets in frontend code.

Never place secrets in:

- committed files
- React components
- browser JavaScript
- NEXT_PUBLIC environment variables

Sensitive keys such as:

- Supabase service-role keys
- admin secrets
- future AI API keys

must remain server-side.

Commit an `.env.example` containing variable names but no real secrets.

Ensure `.env.local` and equivalent secret files are ignored by Git.

---

# Supabase Security

Enable Row Level Security on exposed tables.

Use least-privilege policies.

Players should only be able to access rooms they belong to where practical.

Users should not be able to directly mutate critical game-state tables from arbitrary client queries.

Critical operations should use controlled server endpoints, RPC/database functions, or similarly authoritative mechanisms.

Examples include:

- join room
- kick player
- draw prompt
- redraw prompt
- complete turn
- change current player
- modify queue

Do not use the Supabase service-role key in the browser.

---

# Input Validation

Validate all input server-side.

This includes:

- room codes
- display names
- prompt levels
- IDs
- admin prompt content
- host actions

Display names should:

- be plain text
- have a sensible maximum length
- not allow HTML injection
- be escaped when rendered

Do not rely solely on frontend form validation.

---

# Abuse Protection

Design endpoints so rate limiting can be applied to:

- room creation
- joining rooms
- incorrect room-code attempts
- draws
- redraws
- authentication attempts
- host actions
- admin actions

CAPTCHA may be introduced for suspicious or abusive behaviour.

Do not add intrusive anti-abuse steps to every normal player interaction unless necessary.

---

# Privacy

The game may involve personal and vulnerable conversation.

Therefore:

- collect minimal personal information
- do not store conversation answers by default
- do not record audio
- do not generate transcripts
- do not expose room histories publicly
- do not include room codes or personal conversation data in analytics
- expire/delete abandoned game sessions after a reasonable period

Avoid unnecessary tracking.

---

# Responsive UI

The interface must be designed for both mobile and desktop from the beginning.

Do not build a desktop-only UI and attempt to retrofit mobile later.

## Mobile

Prioritise:

- one-handed usage
- large tap targets
- readable prompt text
- current player visibility
- easy redraw/done controls
- minimal clutter

Suggested mobile layout:

- Top bar with game/room code
- Horizontal player queue
- Current-player indicator
- Large central prompt card
- Level indicator
- Sticky bottom turn controls
- History as bottom sheet/drawer
- Player/host controls as drawer

## Desktop

Desktop may use:

- Player queue sidebar
- Central prompt card
- History sidebar
- Host control panel

The core prompt should remain the visual focus.

---

# Accessibility

Do not rely on colour alone to identify players.

Pair colours with:

- initials
- icons
- names

Maintain suitable contrast.

Use semantic HTML where appropriate.

Interactive elements should support keyboard navigation where practical.

Buttons must have meaningful accessible labels.

---

# UI Design Principles

The game should feel:

- warm
- welcoming
- calm
- modern
- conversational

Avoid making the Christian theme feel overly corporate or visually cliché.

Do not overuse religious imagery.

The cards/questions should remain the focus.

Avoid excessive animations that distract from conversation.

Use animation primarily for:

- drawing cards
- turn transitions
- queue changes
- lightweight feedback

---

# Code Quality

Use TypeScript types rather than `any` wherever reasonably possible.

Keep components focused and reasonably small.

Separate:

- UI
- data access
- game logic
- validation
- authentication
- real-time handling

Avoid duplicating important game rules across multiple client components.

Shared game rules should live in dedicated server/domain logic where possible.

Use descriptive names.

Prefer readability over cleverness.

---

# Database Changes

Use migrations for schema changes.

Do not manually depend on undocumented production database modifications.

Database migrations should be stored in the repository.

When changing schema:

1. Update migration/schema
2. Update relevant TypeScript types
3. Update validation
4. Update tests
5. Consider security/RLS implications

---

# Testing Requirements

Important multiplayer/game-state behaviour should have automated tests.

Prioritise tests for:

- late joining
- multiple simultaneous joins
- turn advancement
- duplicate Done requests
- host permissions
- non-host permission rejection
- non-current-player draw rejection
- kicking current player
- refreshing/reconnecting
- prompt repetition
- inactive prompt exclusion
- room locking
- realtime state resynchronisation

When fixing a game-state bug, add a regression test where practical.

---

# Critical Queue Test

The following behaviour must remain correct:

Starting state:

A -> B -> C -> D

A is current.

E joins.

Expected:

A -> E -> B -> C -> D

F joins before A completes.

Expected:

A -> E -> F -> B -> C -> D

After A completes:

E becomes current.

This behaviour should have an automated test.

---

# Error Handling

User-facing errors should be understandable.

Prefer:

"That room could not be found."

instead of exposing raw database errors.

Log enough server-side information to debug failures without logging secrets or sensitive user conversation content.

The application should gracefully handle:

- invalid room codes
- expired rooms
- kicked users
- locked rooms
- network failures
- realtime reconnects
- stale turn actions
- duplicate actions

---

# Working With Existing Code

Before making substantial changes:

1. Inspect the existing repository.
2. Understand the current architecture.
3. Reuse existing patterns where sensible.
4. Avoid unnecessary rewrites.
5. Check relevant tests.
6. Consider security impact.

Do not replace working architecture solely because another pattern is preferred.

For larger changes, briefly describe the approach before implementing.

---

# Scope Discipline

Do not prematurely build:

- voice chat
- audio recording
- answer transcription
- AI-generated questions
- user accounts/social profiles
- achievements
- leaderboards
- complicated analytics
- native mobile applications

unless explicitly requested.

The first priority is a reliable multiplayer conversation-card experience.

---

# When Requirements Are Ambiguous

Prefer the simplest behaviour consistent with:

- the existing product design
- player privacy
- multiplayer reliability
- host control
- mobile usability

If a decision would significantly affect architecture, security, user data, or game rules, explain the trade-off before making a large irreversible change.

Otherwise, make a reasonable implementation choice and document it.

---

# Code Review Rules

When reviewing changes, prioritise finding:

1. Security vulnerabilities
2. Client-authoritative game state
3. Broken queue behaviour
4. Race conditions
5. Authentication/authorization mistakes
6. Secret exposure
7. Incorrect RLS policies
8. Realtime synchronisation problems
9. Mobile usability regressions
10. Missing regression tests

Do not focus primarily on stylistic preferences when more important correctness or security problems exist.

---

<!-- BEGIN:nextjs-agent-rules -->

# This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` (resolved from this file's directory; in monorepos the `next` package may not be visible from the repo root) before writing any code. Heed deprecation notices.

This block is written and re-added by `next dev` — verify at `node_modules/next/dist/server/lib/generate-agent-files.js`. Removing it from a diff only re-creates the uncommitted change; committing it with your work keeps the tree clean.

<!-- END:nextjs-agent-rules -->
