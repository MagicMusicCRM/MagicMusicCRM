# 🚦 MagicMusicCRM v3 — S5 Cutover Readiness Report

> Date: 2026-06-12
> Scope: Supabase Cloud export → v3 PostgreSQL/private storage dry-run verification
> Status: **S5 dry-run verification passed with non-blocking follow-ups**

---

## ✅ Executive Summary

S5 migration tooling is ready for the next phase.

Two full dry-runs were completed against the Selectel staging v3 backend:

1. Export Supabase data and Storage manifest.
2. Download Supabase Storage objects into private local storage.
3. Dry-run insert `app.file_objects`.
4. Dry-run transform/import Supabase data into v3 PostgreSQL.
5. Verify transaction rollback kept staging data unchanged.

The second dry-run reproduced the first run’s counts and passed without database constraint failures.

---

## 📦 Source Export Evidence

| Run | Export package | Tables | Source rows | Storage objects | Warnings |
|---|---:|---:|---:|---:|---:|
| Dry-run 1 | `exports/supabase/20260612-000929` | 69 | 23,188 | 36 | 0 |
| Dry-run 2 | `exports/supabase/20260612-003310` | 69 | 23,188 | 36 | 0 |

Working Supabase pooler:

```text
aws-1-eu-central-2.pooler.supabase.com:6543
```

The direct Supabase DB host is not suitable from the current environment because it resolves IPv6-only.

Secret handling checks:

- Export metadata did not contain the DB password.
- File import reports did not contain the service role key.
- Runtime secrets were passed only through environment variables.

---

## 🗂️ Storage Migration Evidence

| Run | Source objects | Downloaded | Skipped | Bytes written | DB dry-run warnings |
|---|---:|---:|---:|---:|---:|
| Dry-run 1 | 36 | 36 | 0 | 8,081,527 | 0 |
| Dry-run 2 | 36 | 36 | 0 | 8,081,527 | 0 |

Bucket split:

| Bucket | Objects |
|---|---:|
| `avatars` | 13 |
| `chat-attachments` | 23 |

Purpose split:

| Purpose | Objects |
|---|---:|
| `profile_avatar` | 13 |
| `chat_attachment` | 17 |
| `chat_voice` | 6 |

Signed download smoke:

- Created a temporary staging file fixture.
- Issued token via `POST /api/files/:id/download-token`.
- Downloaded through `GET /api/files/download/:token`.
- Verified `Content-Type`, `Content-Disposition`, byte count and SHA-256.
- Removed fixture row, token and file.

Cleanup evidence:

```text
files=2
smoke_files=0
```

---

## 🧬 Data Import Evidence

| Run | Source rows | Planned rows | Inserted/skipped in transaction | Skipped rows | Warnings |
|---|---:|---:|---:|---:|---:|
| Dry-run 1 | 22,709 | 25,002 | 25,002 | 38 | 8 |
| Dry-run 2 | 22,709 | 25,002 | 25,002 | 38 | 8 |

High-risk coverage:

| Target | Planned rows |
|---|---:|
| `app.users` | 32 |
| `app.profiles` | 32 |
| `app.students` | 921 |
| `app.teachers` | 21 |
| `app.groups` | 2,032 |
| `app.lessons` | 12,254 |
| `app.payments` | 2,706 |
| `app.messages` | 1,105 |
| `app.message_reactions` | 4 |
| `app.notifications` | 195 |
| `app.notification_recipients` | 412 |
| `app.notification_devices` | 25 |

Messenger mapping was corrected during dry-run:

- Single-sided legacy administration messages are assigned to deterministic administration chats.
- Orphan reactions are skipped unless the referenced message maps into v3.
- Final coverage: `1,105/1,105` messages and `4/4` reactions planned.

Rollback evidence after dry-runs:

```text
users=18
files=2
messages=2
```

---

## ⚠️ Non-Blocking Follow-Ups

These did not block the S5 dry-run gate:

1. `public.student_balances` is not exported as a base table.
   - Recommended action: recalculate balances from imported lessons/payments, or add a dedicated materialization step if product requires exact legacy snapshot values.

2. Legacy legal documents contain inline content.
   - v3 legal model expects URL/file-backed documents.
   - Recommended action: convert legacy legal content to files/URLs or keep v3 seeded current legal URLs and preserve legacy records as historical non-current versions.

3. Supabase security advisor warning: `pg_net` extension is installed in `public`.
   - Recommended action: track under S7 security cleanup. This does not affect v3 runtime after cutover.

---

## 🟡 Readiness Decision

S5 is **ready to close**.

Production cutover is not yet approved by this report alone. Before DNS cutover, S7 must still complete:

- full security checklist;
- dependency/container/secrets scans;
- backup restore drill on the production server;
- production cutover runbook rehearsal;
- final smoke with Flutter client against v3 API.

---

## ✅ S5 Exit Criteria

| Criterion | Status |
|---|---|
| Supabase export produces counts/checksums | ✅ Passed |
| Storage objects download into private storage | ✅ Passed |
| File map rewrites references for data import | ✅ Passed |
| v3 data import dry-run passes DB constraints | ✅ Passed |
| Two dry-run reports are reproducible | ✅ Passed |
| Dry-runs roll back staging DB changes | ✅ Passed |
| Signed download API smoke passes | ✅ Passed |
| Blocking migration gaps remain | ✅ None |
