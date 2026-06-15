# Supabase Availability in Russia — Research Note

**Date**: 2026-06-10
**Project**: MagicMusicCRM
**Scope**: Restore VPN-free access for Russian users while preserving Auth, RLS, Storage, Realtime, Edge Functions, Resend SMTP, and Google OAuth.

## Key Insights

1. MagicMusicCRM is deeply coupled to Supabase, not just PostgreSQL: Auth, RLS, Storage, Realtime, and Edge Functions are all product boundaries.
2. The current Aeza VPS size, 1 vCPU / 2 GB RAM, is below Supabase's published minimum for running all self-hosted components.
3. A direct move to plain PostgreSQL would require replacing Supabase Auth, PostgREST APIs, Storage, Realtime, Edge Functions, and security policy enforcement. It is a rewrite, not a database migration.
4. The safest near-term strategy is staged: first test an access gateway/proxy path, then prepare self-hosted Supabase on a larger VPS only if the gateway is not reliable.
5. If self-hosting is chosen, Resend and Google OAuth can remain, but they must be reconfigured in the self-hosted Auth service and Google Cloud callback URLs.

## Options

| Option | Description | Fit |
|---|---|---|
| Access gateway before current Supabase | Keep Supabase Cloud as system of record and route Russian app traffic through a controlled HTTPS endpoint. | Best first experiment; lowest migration risk. |
| Self-host full Supabase in Moscow/RU-friendly location | Move Postgres/Auth/Storage/Realtime/Functions to own VPS. | Good sovereignty option, but needs bigger server and ops discipline. |
| PostgreSQL-only backend | Keep database only, build custom API/auth/storage/realtime around it. | Not recommended short-term; too much rewrite and security surface. |
| Hybrid custom backend over managed Supabase | Flutter talks to own API; API talks to Supabase server-side. | Possible later, but large refactor because app uses Supabase client broadly. |

## Recommended Direction

P0: Run a 1-2 day gateway proof of concept.

- Deploy Caddy/Nginx on an endpoint reachable from Russian ISPs.
- Test REST, Auth OAuth redirect, Storage upload/download, Realtime WebSocket, and Edge Function calls.
- Do not log Authorization headers, cookies, query tokens, or signed URLs.
- If the Moscow VPS cannot reach Supabase reliably, test a nearby non-blocked region while keeping the user-facing endpoint under `magic-music.org`.

P1: If gateway is unstable, move to self-hosted Supabase on a larger VPS.

- Minimum practical production target: 2 vCPU / 4 GB RAM for very small load; preferred 4 vCPU / 8 GB RAM / 80+ GB SSD.
- Keep all Supabase components used by MagicMusicCRM: Postgres, Auth, REST, Realtime, Storage, Functions.
- Use S3-compatible storage or carefully managed persistent volumes, with backups.
- Reconfigure Google OAuth callback to the self-hosted domain.
- Reconfigure SMTP with Resend or a reachable fallback SMTP provider.
- Expect all users to re-authenticate after cutover because JWT secrets and API keys change.

P2: Consider custom PostgreSQL/API only after release stability.

- This should be treated as a separate v3 architecture, because it replaces the security boundary currently provided by Supabase RLS and services.

## Security Notes

- A proxy must be transparent and minimal: TLS, WebSocket support, upload limits, rate limits, no credential logging, strict upstream allowlist.
- Self-hosting shifts patching, backups, key rotation, SMTP deliverability, monitoring, and incident response to the project owner.
- Keep the existing actor-matrix tests as a release gate after any backend endpoint change.
