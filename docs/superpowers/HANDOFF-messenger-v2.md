# HANDOFF — Messenger v2 (fresh-session continuation prompt)

You are continuing a multi-phase rebuild of the **MagicMusicCRM** messenger. The previous
session designed it, executed Phase 1, and wrote plans for Phases 2–3. Read this file
fully, then read the linked spec/plans and the progress ledger before doing anything.

## Project & environment

- Repo: `C:\Projects\MagicMusicCRM` — Flutter client (`lib/`) + NestJS backend (`server/`) + Postgres.
- Branch: `kvazar2727/leads-to-students-dnd`. Windows host; use the Bash tool (Git Bash) or PowerShell.
- The CLI cwd is `C:\Users\potyl` — always use absolute paths into `C:\Projects\MagicMusicCRM`.
- Live API: `https://api.phantom-net.ru/api` (prod, Selectel VPS Moscow). Realtime WS path `/realtime` (verified reachable; Flutter forces websocket-only transport).

## Method (MANDATORY)

Execute via the **superpowers:subagent-driven-development** skill: one fresh implementer
subagent per task (cheap model when the plan gives complete code; sonnet for integration),
a task review after each, a whole-branch review at phase end. Helper scripts live in the
skill dir (`task-brief`, `review-package`). Track progress in the ledger:
`C:\Projects\MagicMusicCRM\.superpowers\sdd\progress.md` — **it is the source of truth**;
after any compaction trust it + `git log`, do NOT re-dispatch completed tasks.

## What's DONE

- **Design spec (approved):** `docs/superpowers/specs/2026-06-25-messenger-v2-design.md` — read it; all model decisions are locked there. Do not re-litigate them.
- **Phase 1 — phone & onboarding — EXECUTED & reviewed (READY TO MERGE).** Commits `48127dbc..417ff9ac` (6): fixed the RU phone formatter (can delete/edit), removed the signup glowing ellipse, added a `+7` phone field at signup, backend signup stores normalized phone, profile enforces canonical `+7` on save. NOT yet deployed/rebuilt.

## What's PLANNED (not executed)

- **Phase 2 — data wipe (runbook):** `docs/superpowers/plans/2026-06-25-messenger-v2-phase2-data-wipe.md`. DESTRUCTIVE on prod. Backup-first, dry-run-first, human-approves the candidate list. Soft-deletes synthetic accounts (`%@example.com`, `realtime-smoke%` only — NEVER magic1–4 or real users), wipes chat content, keeps the «Объявления» channel.
- **Phase 3 — backend v2:** `docs/superpowers/plans/2026-06-25-messenger-v2-phase3-backend.md` (8 TDD tasks): migration 0043 (chats.owner_user_id/assigned_to_user_id/assigned_at + `chat_inbox_state`), client-no-DM RBAC, owner on admin chat, inbox label+phone-folders+assignment+archive in `listChats`, assign/unassign endpoints, per-staff archive + resurface, client-side staff-identity masking, group leave + realtime create/remove fan-out.

## What's NOT planned yet (you must write these with superpowers:writing-plans)

- **Phase 4 — Flutter v2** (spec §6): inbox with folders **Лиды/Ученики/Архив** + live unread badges; assignment UI («Взять в работу»/«Передать»); per-staff archive action; realtime handlers for `chat.created`/`chat.removed`/`chat.updated`(assignment/archive); masked client view ("Администрация", staff names hidden — the realtime payload is already masked server-side for the chat room per Phase 3 Task 7); group «Выйти из группы» + add-members UI; client has no "new direct chat" entry.
- **Phase 5 — tests/smoke/builds/deploy** (spec §9–§11): extend `server/src/smoke/realtime-smoke.ts`; run full `npm test` + `flutter test`; rebuild Windows/APK/AAB; deploy.

## CRITICAL gotchas

1. **Earlier work is deployed but UNCOMMITTED in git.** The working tree carries ~27 modified + several untracked files from earlier in the session (full-app realtime fixes, settings/avatar realtime, the student-card finance fix, the Windows secure-storage serialization fix, the `MAGIC_PROFILE` per-instance namespacing, migration `0042` default «Объявления» channel, `dist/` artifacts, runtime_env files, audit docs). **These are LIVE on prod** (deployed via tar-copy, NOT via git) but exist only as uncommitted changes. **Do NOT `git clean -fdx`** (it destroys the ledger and this work). Phase 1's 6 commits sit on top of this dirty tree. **First action: ask the user whether to commit this earlier work as its own commit(s)** so git matches prod. When committing Phase tasks, `git add` only that task's specific files — never `git add -A` (it would sweep up the earlier work).
2. **0042 is already applied on prod** (default «Объявления» channel, slug `announcements`, is_system, 5 role perms — it adopted a pre-existing channel). Migration 0043 is next.
3. **Deploy = tar-copy + rebuild** (migrations run on api boot): `tar -czf - -C server src db package.json package-lock.json tsconfig.json tsconfig.build.json nest-cli.json Dockerfile | ssh -i C:/Users/potyl/.ssh/mmcrm_proxy_ed25519 magicdeploy@161.104.50.105 'tar --no-same-owner -xzf - -C /opt/magicmusiccrm/server && cd /opt/magicmusiccrm/infra/staging && docker compose --env-file .env up -d --build api'`. NEVER overwrite host `server/.env`. Production deploys + any DB write are gated by the safety classifier and require explicit user approval each time; SSH/DB commands need the Bash tool with `dangerouslyDisableSandbox: true`. DB: container `magicmusiccrm-v3-postgres-1`, user `magiccrm_owner`, db `magiccrm`, schema `app`. Backups: `/opt/magicmusiccrm/backups/`. Always `pg_dump | gzip` backup before destructive DB work, and dry-run migrations inside `BEGIN…ROLLBACK` first (see how 0042 was validated).
4. **Run Phase 2 wipe together with the Phase 3 backend deploy** so users don't recreate old-style chats in the gap.
5. **Builds & dist:** version `1.1.22+128`. `flutter build {windows|apk|appbundle} --release --dart-define=MAGIC_API_BASE_URL=https://api.phantom-net.ru/api`. Refresh `dist/MagicMusicCRM-1.1.22-128.{apk,aab}`, the `…-windows-x64/` folder (Dart logic is in `data/app.so`; the `.exe` is the unchanged runner host) and re-zip. A running `magic_music_crm.exe` LOCKS the dist folder — stop it first (`Stop-Process magic_music_crm`). The `…-windows-x64/` folder ships `run-account-A.bat`/`run-account-B.bat` (set `MAGIC_PROFILE`) for multi-account testing.
6. **Test accounts:** magic1=client, magic2=teacher, magic3=admin, magic4=manager (`magicN@gmail.com`), OTP-bypassed via `AUTH_OTP_BYPASS_EMAILS` on the host `.env`. Live `realtime-smoke` needs verified creds; the prod API enforces email verification (don't email-verify a prod user — classifier blocks it).
7. **Test harnesses:** backend jest mocks `DatabaseService`/policy/realtime/crm (see `messenger.service.spec.ts`); Flutter uses a fake Dio adapter (`test/core/services/magic_messenger_service_test.dart`) and a fake transport (`magic_realtime_service_test.dart`). Reuse them.

## Locked design decisions (do NOT re-ask the user)

- Администрация = shared staff inbox, labeled by **client name**; **«взять в работу»** (assign): all staff see it, assignee replies, manager can reassign/intervene.
- Client sees unified **«Администрация»**; staff identities **masked** from the client.
- Client has **no 1-on-1 chats**; client↔teacher only inside a group with an admin/manager.
- Groups: staff-only create/manage; **any member may leave**; create/add/remove/leave are realtime.
- Folders organize the admin inbox: student→**Ученики**, lead/none→**Лиды**, **Архив** is per-staff; live unread badges. Linking by normalized phone (same rule as `profile.service`).
- Wipe scope: chats + synthetic smoke accounts (soft-delete); keep «Объявления»; keep magic1–4 + real data.

## Recommended next actions (in order)

1. Read: this file, the spec, Phase 2 & 3 plans, the ledger, and memory entries `magicmusic-access`, `magicmusic-realtime-channels`, `magicmusic-windows-token-store`, `magicmusic-student-card-rbac`, `magicmusic-otp-bypass-test`.
2. Ask the user about committing the earlier uncommitted work (gotcha #1).
3. Execute **Phase 3** subagent-driven (ledger-tracked). Dry-run migration 0043 against prod (rollback) before relying on it.
4. Write (writing-plans) and execute **Phase 4** (Flutter).
5. Deploy: backup → Phase 2 wipe (with approval) → deploy Phase 1+3 backend → rebuild + refresh dist artifacts (Windows/APK/AAB) with SHA-256.
6. Write/execute **Phase 5** verification; report artifact paths + hashes + what was checked per role.
