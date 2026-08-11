# Deeper Together

Deeper Together is a mobile-friendly, real-time conversation card game for Christian friends, cell groups, churches, and small communities. It combines light general questions with respectful faith-based prompts across three levels of depth.

The application is being built with Next.js, React, TypeScript, Tailwind CSS, Supabase, and Vercel. The server and database will remain authoritative for room membership, queue order, host permissions, turns, and prompt selection.

## Current status

The application foundation and secured database schema are implemented. Anonymous guest authentication, create/join flows, realtime synchronization, the normal turn loop, host/lifecycle controls, and the protected prompt-management foundation are connected. Players can draw, redraw without limits, change level for the next draw, finish or skip, and review immutable prompt history. Hosts can kick players, transfer host status, move a player into the current turn, lock the room, or close it. Authorized administrators can manage prompt wording, levels, categories, tags, activation, and archiving from `/admin` without changing previously drawn history.

Expired rooms are deleted in bounded batches by a private hourly PostgreSQL job. Room membership, turns, draw history, and deck state are removed through database cascades only after the room's 24-hour expiry has passed.

Orphaned anonymous Auth identities are also cleaned up in bounded batches after 30 days. The cleanup preserves any identity that still has room membership or an administrator allowlist entry, so it cannot invalidate an active or not-yet-cleaned game.

The Playwright multiplayer suite uses isolated browser contexts to exercise late joining, realtime recovery after a temporary offline period, refresh persistence, redraw history, turn advancement, room locking, play-now reordering, host transfer, and kicking. With local Supabase running, build the production app with `pnpm build`, run `pnpm test:e2e:server` in one terminal, and run `pnpm test:e2e` in another. Linux CI starts the isolated test server automatically. `PLAYWRIGHT_BASE_URL` can target an already-running deployment instead.

The same E2E command runs automated WCAG 2.0/2.1/2.2 A/AA checks on the public routes, lobby, pre-draw game, visible-prompt game, and mobile game. It also verifies keyboard entry order and guards against horizontal mobile overflow. Automated checks complement rather than replace manual assistive-technology testing.

Successful state-changing RPCs are protected by private atomic per-user database limits. Authoritative snapshot reads are intentionally not throttled so realtime recovery remains reliable. Production must also configure Supabase Auth/API or edge-level limits for failed authentication and incorrect room-code attempts; failed PostgreSQL statements roll back database counter updates and cannot provide that protection alone.

The local security review verifies the effective RLS/grant surface, fixed search paths on privileged functions, ignored secret files, security response headers, and the production dependency advisory state. A Content Security Policy derives its network allowlist from the configured Supabase project URL, including its matching WebSocket origin. HSTS is emitted only by Vercel production builds so local HTTP development remains safe. Hosted rate limits, CAPTCHA, and redirect allowlists remain deployment controls. See `docs/security.md` for the release checklist.

GitHub Actions now reproduces the complete local verification stack without hosted secrets: it starts disposable Supabase, runs database tests and lint, builds the application, and runs all Playwright suites. The production deployment sequence is documented in `docs/deployment.md`.

## Local development

1. Install dependencies with `pnpm install`.
2. Copy `.env.example` to `.env.local` and fill in the local or hosted Supabase URL and publishable key.
3. Start the local database as described below.
4. Run `pnpm dev`.
5. Open the local URL shown in the terminal.

## Local database

The local Supabase stack requires Docker Desktop or another Docker-compatible runtime.

1. Run `pnpm dlx supabase@latest start`.
2. Run `pnpm dlx supabase@latest db reset` to rebuild from migrations and load development seed prompts.
3. Run `pnpm dlx supabase@latest test db` to execute the pgTAP security and queue tests.

Anonymous sign-ins are enabled in the committed local Supabase configuration. Production anonymous sign-ins must also be enabled in the hosted Supabase project's authentication settings.

The official `@supabase/supabase-js` client is the only additional runtime dependency for this phase. It persists the anonymous browser session and calls the narrowly granted database functions; no service-role key is used by the frontend.

## Administrator provisioning

The application does not expose administrator sign-up. Create an email/password user through Supabase Auth, copy that user's UUID, and add it to the allowlist using a trusted SQL session:

```sql
insert into public.admin_users (user_id)
values ('ADMIN_AUTH_USER_UUID')
on conflict (user_id) do nothing;
```

The administrator can then sign in at `/admin`. Every prompt-management RPC requires both a non-anonymous Supabase session and a current `admin_users` entry. Remove the allowlist row to revoke access immediately. Never put administrator credentials or a service-role key in browser environment variables.

### Prompt CSV format

The admin interface can download a ready-to-edit template and export the complete prompt library. CSV files use these columns:

```text
prompt_text,level,category,tags,status
```

- `level` must be `1`, `2`, or `3`.
- `category` uses a category ID such as `secular`, `christian`, or `hybrid`.
- `tags` contains tag slugs separated by `|`, for example `faith|growth`.
- `status` must be `active`, `inactive`, or `archived`.
- Each import is limited to 500 rows. A malformed row rejects the whole transaction, while prompt text already present in the library is safely skipped.

Exports contain prompt content and management metadata only. They never contain room codes, players, room history, or conversation data.

See `docs/architecture.md` for the accepted architecture and implementation sequence, `docs/security.md` for the security boundary, and `docs/deployment.md` for the hosted release runbook. Repository-wide engineering and product rules are in `AGENTS.md`.
