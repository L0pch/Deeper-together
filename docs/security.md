# Security and release checklist

This document records the current security boundary and the controls that must be completed in the hosted environment. `AGENTS.md` remains authoritative.

## Locally verified controls

- The browser receives only the Supabase project URL and publishable key. No service-role key is required by normal gameplay or prompt administration.
- `.env.local` and other `.env*` files are ignored, while `.env.example` contains names only.
- Supabase anonymous authentication supplies player identity; display names, room codes, URL values, and client-provided roles are never authorization credentials.
- Critical game and administration changes use narrowly granted, server-authoritative PostgreSQL functions.
- Every exposed application table has Row Level Security enabled. Authenticated clients have direct `SELECT` access only to the four tables needed for room-scoped realtime invalidation, with RLS still applied, and have no direct table mutation privileges.
- Anonymous clients have no direct table or application-function privileges. Public RPCs require an authenticated session and perform their own membership, current-player, host, or administrator checks.
- All `SECURITY DEFINER` functions use an empty fixed `search_path`. The private helper schema is not exposed through the Supabase Data API.
- Successful state-changing RPCs use atomic per-user limits. Snapshot recovery stays unthrottled.
- Room content is membership-scoped, answers are not recorded, prompt history stores card snapshots only, and expired rooms are deleted by the scheduled database cleanup.
- Orphaned anonymous Auth identities are deleted after 30 days by a separate private bounded job. Identities with any room membership or administrator allowlist entry are preserved.
- Next.js suppresses its identifying response header and sends clickjacking, MIME-sniffing, referrer, camera, microphone, geolocation, and browsing-topic protections on every application route.
- Content Security Policy blocks objects, media, frames, and cross-origin embedding. Network access is limited to the app and the HTTPS/WebSocket origins derived from `NEXT_PUBLIC_SUPABASE_URL`; production policies do not permit `unsafe-eval`.
- Vercel production builds emit one-year HSTS without applying it to local HTTP development or making an unverified subdomain commitment.
- The production dependency advisory audit reports no known vulnerabilities as of 2026-08-11.

## Required hosted configuration

Before public release:

1. Create separate Supabase projects for preview/staging and production. Apply migrations with the Supabase CLI; do not edit production schema manually.
2. Enable anonymous authentication and set conservative Supabase Auth rate limits. Protect anonymous sign-up and repeated failed authentication with Supabase CAPTCHA or an edge/gateway control if abuse appears.
3. Add an IP-aware edge limit for room creation, joining, and invalid room-code attempts. Database counters cannot retain increments from failed PostgreSQL statements because the transaction rolls back.
4. Configure exact production Site URL and redirect allowlist values in Supabase Auth. Remove localhost redirect entries from the hosted project.
5. Store only `NEXT_PUBLIC_SUPABASE_URL` and the publishable key in Vercel's browser-visible environment. Keep any future service-role or third-party secret server-only and scope it to the environments that need it.
6. Provision administrators through a trusted database session, require strong unique passwords, and review the `admin_users` allowlist before launch.
7. Verify both hourly `pg_cron` jobs—for room expiry and stale anonymous identities—exist and monitor their failures in the hosted database.
8. Verify HTTPS and the production-only HSTS header on the final domain before launch. The current policy deliberately omits `includeSubDomains` and `preload`.
9. Verify the generated Content Security Policy contains only the selected hosted Supabase HTTPS and WebSocket origins. A future strict nonce policy would force dynamic rendering in Next.js 16; choose that performance trade-off deliberately.
10. Run database tests, lint, production build, Playwright multiplayer/security/accessibility tests, and a manual keyboard/screen-reader pass against the release candidate.

## Incident boundaries

- Do not log room codes, prompt history, authentication tokens, passwords, or spoken conversation content.
- If a browser-visible publishable key is abused, tighten Auth/edge limits and rotate it through Supabase; it is not a substitute for RLS.
- If a server secret is exposed, revoke and rotate it immediately, then audit database and hosting logs using identifiers rather than conversation content.
- Removing a user from `admin_users` revokes prompt-management authorization on their next RPC even if their authentication session remains valid.
