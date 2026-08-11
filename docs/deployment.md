# Deployment runbook

This runbook keeps production changes deliberate and repeatable. The application uses Vercel for Next.js and a hosted Supabase project for Auth, PostgreSQL, Realtime, and scheduled cleanup.

## 1. Verify the release candidate

Every pull request and push to `main` runs `.github/workflows/ci.yml`. CI creates a disposable local Supabase stack and derives its local project URL and publishable key at runtime, so the verification job needs no hosted credentials.

The job must pass:

- dependency installation from the locked pnpm graph;
- ESLint and the production Next.js build;
- all pgTAP database tests and database lint;
- the Playwright multiplayer, recovery, accessibility, mobile-overflow, and security suites.

Do not add production deployment credentials to this test workflow.

## 2. Create hosted environments

Use separate Supabase projects for staging/preview and production when possible. Never expose the local Supabase stack to public traffic: it uses development defaults and has no TLS or production gateway protection.

For each hosted project:

1. Record the project reference and database password in a password manager.
2. Enable anonymous sign-ins under Authentication settings.
3. Set the exact Site URL and allowed redirect URLs. Do not leave localhost URLs in production.
4. Review Auth rate limits and enable Turnstile or another supported CAPTCHA for anonymous sign-in abuse protection before a broad public launch.
5. Confirm Realtime and the Cron integration are available. The migrations create the required publication entries, `pg_cron` extension, and cleanup jobs.

## 3. Apply the database

Authenticate and link the CLI to the intended hosted project:

```powershell
supabase login
supabase link --project-ref YOUR_PROJECT_REFERENCE
supabase migration list
supabase db push --dry-run
supabase db push
```

Read the dry-run output before applying it. Never use `db reset --linked` against production.

Do not use `--include-seed` for production. `supabase/seed.sql` is development-only. Provision the initial production prompt bank through the protected `/admin` CSV import after creating an administrator.

After migration, verify both scheduled jobs:

```sql
select jobname, schedule, command, active
from cron.job
where jobname in (
  'cleanup-expired-rooms-hourly',
  'cleanup-stale-anonymous-users-hourly'
)
order by jobname;
```

## 4. Provision an administrator and prompts

1. Create a non-anonymous email/password user in Supabase Authentication.
2. From a trusted SQL session, add its Auth UUID to the allowlist:

```sql
insert into public.admin_users (user_id)
values ('ADMIN_AUTH_USER_UUID')
on conflict (user_id) do nothing;
```

3. Deploy the web application, sign in at `/admin`, and import the reviewed production prompt CSV.
4. Confirm active prompts exist at levels 1, 2, and 3 before opening the site to players.

## 5. Deploy Next.js to Vercel

Import the GitHub repository into Vercel and keep the detected Next.js build settings. Configure these variables separately for Preview and Production:

```text
NEXT_PUBLIC_SUPABASE_URL
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY
```

These two values are intended for the browser; database security must continue to rely on Auth, grants, RLS, and authoritative functions. Do not add a service-role key, database password, administrator credentials, or Supabase access token to a `NEXT_PUBLIC_` variable.

Point Preview deployments at staging rather than production. Redeploy after changing a browser-visible environment variable because Next.js embeds it during the build.

## 6. Production-only security controls

After the final application and Supabase domains are known:

1. Verify the generated Content Security Policy permits only the required app and configured Supabase HTTPS/WebSocket origins. It is derived from `NEXT_PUBLIC_SUPABASE_URL` at build time.
2. Verify Vercel production responses include `Strict-Transport-Security: max-age=31536000`. The application deliberately does not commit unverified subdomains to HSTS.
3. Add IP-aware edge protection for room creation, room joining, and invalid room-code attempts. Failed PostgreSQL statements cannot retain database rate-limit increments.
4. Review Supabase Auth logs and Cron run history without logging room codes, prompt histories, passwords, tokens, or conversation content.

## 7. Release smoke test

Against the release candidate:

1. Create a room in one browser context and join it from another.
2. Start the game, draw, redraw, complete a turn, and verify immutable history.
3. Refresh and briefly disconnect one player; confirm authoritative recovery.
4. Exercise lock, Play now, host transfer, kick, leave, and close controls.
5. Test a 390-pixel mobile viewport, keyboard navigation, and a screen reader.
6. Verify `/admin` rejects an anonymous player and accepts only the allowlisted administrator.
7. Check that security headers are present and no service-role credential appears in downloaded JavaScript or browser network requests.

The automated browser suite can target a staging deployment with `PLAYWRIGHT_BASE_URL`, but it creates temporary rooms and should not be pointed at production casually:

```powershell
$env:PLAYWRIGHT_BASE_URL = 'https://staging.example.com'
pnpm test:e2e
```

## 8. Rollback and recovery

- Vercel application rollback: promote the last known-good deployment.
- Database rollback: use a reviewed forward migration. Do not edit migration history or reset production.
- Secret exposure: revoke and rotate the credential immediately, redeploy affected environments, and audit access logs.
- Faulty prompt content: deactivate or archive it in `/admin`; existing draw history retains its original snapshot.
