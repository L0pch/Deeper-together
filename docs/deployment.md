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

Do not use --include-seed for production. supabase/seed.sql is development-only. The production prompt bank is populated by the private Google Sheet sync after the server-only credentials are configured.

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

## 4. Provision an administrator and private Google Sheet

1. Create a non-anonymous email/password user in Supabase Authentication.
2. From a trusted SQL session, add its Auth UUID to public.admin_users.
3. Create a Google Cloud project, enable the Google Sheets API, create a service account, and create a JSON key for that account.
4. Create a private Google Sheet with a tab named Prompts. Row 1 must contain prompt_text, level, category, and status.
5. Share the sheet with approved human collaborators as Editor.
6. Share the same sheet with the service account email as Viewer. Domain-wide delegation is not required.
7. Copy the spreadsheet ID from the Google Sheets URL.
8. After the application variables below are configured and deployed, sign in at /admin and choose Sync Google Sheet now.
9. Confirm active prompts exist at levels 1, 2, and 3 before opening the site to players.

## 5. Deploy Next.js to Vercel

Import the GitHub repository into Vercel and keep the detected Next.js build settings. Configure these browser-visible variables separately for Preview and Production:

- NEXT_PUBLIC_SUPABASE_URL
- NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY

Configure these server-only variables in Production:

- SUPABASE_SERVICE_ROLE_KEY
- GOOGLE_SERVICE_ACCOUNT_EMAIL
- GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY
- GOOGLE_SHEETS_SPREADSHEET_ID
- GOOGLE_SHEETS_RANGE (normally Prompts!A:D)
- CRON_SECRET (a random value of at least 16 characters)

Paste the Google private key exactly as supplied, including its BEGIN/END lines. Vercel stores multiline environment variables. Never prefix any of these server-only values with NEXT_PUBLIC_.

The service-role key is used only by the protected server synchronization route. Google access uses the read-only spreadsheets scope. CRON_SECRET authenticates Vercel's daily request to /api/cron/prompts/sync.

Point Preview deployments at staging rather than production. Redeploy after changing any environment variable.

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
6. Verify /admin rejects an anonymous player, accepts only the allowlisted administrator, and can synchronize the private sheet.
7. Verify unauthenticated requests to both synchronization endpoints return 401.
8. Check that security headers are present and no service-role or Google credential appears in downloaded JavaScript or browser network requests.

The automated browser suite can target a staging deployment with `PLAYWRIGHT_BASE_URL`, but it creates temporary rooms and should not be pointed at production casually:

```powershell
$env:PLAYWRIGHT_BASE_URL = 'https://staging.example.com'
pnpm test:e2e
```

## 8. Rollback and recovery

- Vercel application rollback: promote the last known-good deployment.
- Database rollback: use a reviewed forward migration. Do not edit migration history or reset production.
- Secret exposure: revoke and rotate the credential immediately, redeploy affected environments, and audit access logs.
- Faulty prompt content: change its status in the private sheet and synchronize; existing draw history retains its original snapshot.
