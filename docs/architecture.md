# Initial Architecture

## Status

This document records the accepted starting architecture. It should be updated through migrations and architecture decisions as implementation proceeds. `AGENTS.md` remains authoritative for durable product and engineering rules.

## System boundary

- Next.js App Router renders the responsive React UI.
- TypeScript and TSX are used throughout application code.
- Supabase anonymous authentication establishes guest identity without collecting an email address and persists it across refreshes in the same browser.
- Next.js Route Handlers will provide validation, friendly error mapping, and a future rate-limiting seam.
- PostgreSQL functions will own critical room, queue, turn, host, and prompt-draw transactions.
- Supabase Realtime notifies clients that state changed; clients reconcile against an authoritative room snapshot. A settled-subscription refresh closes the initial snapshot/subscription race, browser online/focus/visibility events trigger recovery, and a visible-page 30-second safety reconciliation covers missed invalidations.
- Row Level Security will limit reads to current room members and prevent arbitrary direct mutation of critical game-state tables.
- Vercel will host the Next.js application.

Normal gameplay should use the authenticated player's session to call narrowly granted operations. It should not require exposing or routinely using the Supabase service-role key.

## Planned source layout

```text
src/
├── app/                    # Routes, layouts, and Route Handlers
├── components/             # Reusable presentation components
├── features/               # Feature-specific UI, hooks, and mapping
├── lib/
│   ├── supabase/           # Browser and server Supabase clients
│   ├── validation/         # Server input schemas and normalization
│   └── errors/             # Safe application error mapping
└── types/                  # Domain and generated database types
supabase/
├── migrations/             # Versioned schema, functions, grants, and RLS
├── tests/                  # Database behavior and security tests
└── seed.sql                # Development prompt data
tests/
├── integration/
└── e2e/
```

Folders will be added when their phase begins rather than created empty.

## Planned data model

- `rooms`: lifecycle, code, host identity, lock, capacity, expiry, current turn, and monotonic state version.
- `room_players`: authenticated membership, display details, persistent selected level, queue position, and leave/kick state.
- `turns`: unique and idempotent turn lifecycle for one player.
- `prompts`: active/archived prompt content with level, category, source metadata, and private-Google-Sheet sync identity.
- `prompt_draws`: immutable prompt-text and metadata snapshots with draw order and outcome.
- `room_deck_state`: per-room, per-level deck cycle used to avoid repeats until exhaustion.
- `admin_users`: protected prompt-management authorization, added with the admin phase.

## Queue concurrency

Queue-changing transactions will lock the room row. A player joining during an active turn is inserted after the last player who joined during that same turn, or directly after the current player when they are the first late joiner. Later queue positions shift within the same transaction. This preserves `A → E → F → B → C → D` and prevents concurrent joins from producing duplicate positions.

## Realtime recovery

Realtime messages are invalidation signals, not authoritative commands. Initial load, refresh, reconnect, and version gaps trigger `get_room_snapshot`. The returned state replaces local room state before subscriptions continue.

## Accepted defaults

- Expiry: 24 hours after the last meaningful game action.
- Capacity: 20 initially, with a supported hard maximum of 30.
- Redraws: unlimited; every draw remains in history with its outcome.
- Level preference: persists per player but can be changed on their turn.
- Categories: represented in data, with no MVP player filter.
- Host succession: next active player in queue order after explicit host departure/removal.
- Temporary disconnection: does not immediately remove a player or transfer host.
- History: visible to current room members until room expiry.
- Room-code rotation: deferred beyond MVP; room locking comes first.

## Implementation phases

1. **Foundation — implemented:** Next.js, TypeScript, Tailwind, route shells, documentation, and environment template.
2. **Database and security — implemented and locally verified:** local Supabase setup, schema migrations, RLS, grants, transactional create/join/snapshot operations, and queue tests.
3. **Lobby — implemented:** anonymous identity, create/join flows, level preference, visible ordered queue, host label, transactional host start/lock controls, and refresh recovery.
4. **Turn loop — implemented:** server-selected draw, unlimited redraw, persisted level changes, answered/skipped completion, immutable prompt snapshots, per-level deck cycles, idempotent Done, queue advancement, visible history, and stale-turn-safe host overrides.
5. **Realtime reliability — core room and turn flow implemented:** room-scoped Postgres Changes subscriptions act as invalidation signals, reconnects reconcile against an authoritative snapshot, and `stateVersion` prevents stale responses from replacing newer state. Broader automated disconnect/reconnect coverage remains pending.
6. **Host and lifecycle controls — implemented:** kick, make host, play now, explicit leave, deterministic succession, locking, closure, expiry refresh, and kicked-client access recovery. Rate limiting remains part of hardening.
7. **Prompt administration — implemented:** non-anonymous administrator authentication, database allowlisting, a private Google Sheet as the content source of truth, server-only service-account access, transactional replacement sync, a protected manual sync control, daily Vercel reconciliation, combined search filters, and immutable historical prompt snapshots.
8. **Hardening and release — in progress:** private batched room-expiry and orphaned-anonymous-user cleanup jobs are implemented. Playwright covers late joining, realtime recovery, refresh persistence, turn and host controls, locked-room behavior, automated WCAG checks, and security response headers. The build derives a Content Security Policy from the selected Supabase origin and enables HSTS only in Vercel production. Atomic per-user database limits protect successful gameplay and administration RPCs; snapshot reconciliation remains unthrottled. The local security review verifies dependency advisories, secret hygiene, effective RLS/grants, and privileged-function search paths. Credential-free CI reproduces the complete local database, build, and browser verification stack. Failed room-code and authentication attempts still require complementary Supabase gateway or edge limits because PostgreSQL rolls back counters when an RPC fails. Manual assistive-technology review and hosted edge, Auth, and origin verification remain release work; the checklists are in `docs/security.md` and `docs/deployment.md`.
