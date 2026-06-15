# 07_CHALLENGE_REPORT - MagicMusicCRM v3

**Date**: 2026-06-10
**Mode**: DESIGN + TASKS
**Verdict**: Yellow light - proceed only with gated execution.

## 1. Overview

| Severity | Finding | Required action |
|---|---|---|
| Critical | Big-bang cutover can cause extended outage if migration rehearsal is skipped. | Two full dry runs and rollback window are mandatory. |
| Critical | One-server production can lose data if backups are local-only or untested. | External encrypted backup and restore drill block launch. |
| High | Direct Supabase calls are spread across Flutter UI/providers, making cutover broad. | Create `MagicApiClient` and feature services before removing Supabase flows. |
| High | Replacing RLS with API guards can introduce IDOR if repositories trust request IDs. | Actor matrix tests and scoped repositories are mandatory. |
| High | File storage on local NVMe is durable only with verified external snapshots. | File backup/restore evidence required before production files move. |
| Medium | Google/Resend/Firebase remain external dependencies. | Keep fallback paths and graceful degradation. |

## 2. Pre-Mortem

Six months after v3 starts, the most likely failure is not NestJS itself. The likely failure is incomplete operational discipline: a migration edge case, broken backup restore, or endpoint that trusts a client-supplied ID.

Evidence:

- Current codebase contains many direct Supabase calls across UI/providers/screens.
- v2 used Supabase RLS as the main data boundary; v3 moves that responsibility into custom backend code.
- First production topology intentionally starts without automatic HA.

## 3. Design Review Findings

### Critical - Migration rehearsal is non-negotiable

Big-bang cutover with full data migration cannot be safe without rehearsal. The design now requires two dry runs, count/checksum reports and a rollback decision window.

### Critical - Backups must be restored, not only created

The primary Moscow server is a single point of failure. Backup jobs that never restore do not prove recoverability. The launch gate requires restore to a clean target and smoke verification.

### High - Authorization must be repository-scoped

The backend must not expose generic `findById(id)` methods to controllers for private data. Repositories should accept authenticated actor context and enforce scope at query construction.

### High - File paths must never be public contracts

Files must be referenced by file IDs and served through backend authorization. Raw local paths and stable public URLs are forbidden.

### Medium - Provider fallback should be tested

Resend/Firebase/Google can fail. Login must work without Google, email must have fallback SMTP, and push must be optional.

## 4. Required Actions

P0:

- Complete S0/S1 before backend feature work.
- Add actor matrix tests before feature API expansion.
- Add backup restore drill before storing production files.
- Add migration dry-run reports before Flutter cutover.

P1:

- Add admin audit dashboard after core audit events exist.
- Add second standby server after first stable v3 launch.

## 5. Final Verdict

Proceed with v3 implementation, but do not cut over production until Critical/High items are closed with evidence.
