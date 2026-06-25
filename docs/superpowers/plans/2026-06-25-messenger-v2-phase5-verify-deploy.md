# Messenger v2 — Phase 5: Tests / Smoke / Builds / Deploy — Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development for the code task (Task 1). Tasks 2–4 are controller-run verification/build operations. Task 5 is a DESTRUCTIVE, USER-GATED deploy runbook — DO NOT execute any part of Task 5 without explicit per-step user approval.

**Goal:** Verify Messenger v2 (Phase 1 onboarding + Phase 3 backend + Phase 4 Flutter) end-to-end, build refreshed client artifacts, and deploy the backend together with the Phase 2 data wipe.

**Architecture:** Extend the live realtime smoke for the v2 scenarios (assign → masked client reply; group create/leave live); run the full backend + Flutter suites; rebuild Windows/APK/AAB at `1.1.22+128`; then (gated) backup → wipe → deploy → live-smoke verify.

**Tech Stack:** NestJS/jest, Flutter, socket.io-client smoke, Docker Compose deploy on the Selectel VPS.

## Global Constraints

- **Deploy + Phase 2 wipe + any prod-DB write are USER-GATED** — explicit approval each time; backup (`pg_dump|gzip`) before destructive DB work; dry-run migrations in `BEGIN…ROLLBACK` first. SSH/DB via the Bash tool with `dangerouslyDisableSandbox: true`.
- Build: `flutter build {windows|apk|appbundle} --release --dart-define=MAGIC_API_BASE_URL=https://api.phantom-net.ru/api`. Version `1.1.22+128` (confirm `pubspec.yaml`). A running `magic_music_crm.exe` LOCKS `dist/` — `Stop-Process magic_music_crm` first.
- `dist/` is git-ignored (193MB binaries) — NEVER `git add -f dist`. Artifacts are refreshed in place + SHA-256 recorded; not committed.
- Live smoke needs verified creds; prod enforces email verification (do NOT email-verify a prod user — gated). Use magic3 (admin) / a client account via the smoke env vars. Synthetic smoke accounts (`realtime-smoke%`) are cleaned by the Phase 2 wipe.
- Commit code changes (Task 1) with the `Co-Authored-By: Claude Opus 4.8 (1M context)` trailer; `git add` only the smoke file (never `-A`).
- Realtime contract (Phase 3 spec §5) and masking (server-side) are the source of truth the smoke asserts.

---

### Task 1: Extend `realtime-smoke.ts` with v2 scenarios (CODE — subagent + review)

**Files:** Modify `server/src/smoke/realtime-smoke.ts`.

**Interfaces (Consumes):** existing helpers `request`, `connectRealtime`, `emitWithAck`, `waitForEvent`, `expectForbidden`. Existing optional staff session via `REALTIME_SMOKE_STAFF_EMAIL`/`REALTIME_SMOKE_STAFF_PASSWORD`.

Add INSIDE the `if (staffSocket && staffToken)` block (these scenarios require staff), after the existing staff↔client scenarios:

- [ ] **Step 1: Assign → masked staff reply.**
  - Staff claims the administration chat: `await request("POST", \`/messenger/chats/${chat.id}/assign\`, {}, staffToken);` → record `steps.assigned = true`.
  - Staff sends a reply; the CLIENT's realtime `message.created` for that content MUST have a **masked** sender. Capture the full payload and assert the sender is "Администрация" and carries no staff id/name:
```ts
const masked = `masked-reply-${Date.now()}`;
const clientMaskedRecv = waitForEvent<MessageResponse & { sender?: { id: string | null; name?: string }; senderId?: string | null }>(
  socket, "message.created",
  (p) => p.chatId === chat.id && p.content === masked,
);
await request("POST", `/messenger/chats/${chat.id}/messages`, { content: masked, messageType: "text" }, staffToken);
const maskedEvent = await clientMaskedRecv;
const senderName = maskedEvent.sender?.name;
const senderId = maskedEvent.sender?.id ?? maskedEvent.senderId ?? null;
if (senderName !== "Администрация" || senderId !== null) {
  throw new Error(`Staff identity leaked to client: sender=${JSON.stringify(maskedEvent.sender)} senderId=${senderId}`);
}
steps.maskedStaffReply = { ok: true };
```
  (Adjust the field path to the actual realtime message payload shape — read how `message.created` serializes `sender`/`senderId` in the gateway/DTO; the masked object is `{ id: null, name: "Администрация", ... }` with `senderId: null`. The assertion MUST fail if a real staff name or id appears.)

- [ ] **Step 2: Group create → client receives `chat.created`; leave → `chat.removed`.**
  - Staff creates a group including the client: client's `user:` room is already joined? The client socket joined its own `chat`/`channel` rooms but the smoke must ensure the client joined its USER room to receive `chat.created`. Add (near the client's other joins): `await emitWithAck(socket, "room.join", { roomType: "user", roomId: login.user.id });`.
  - Then:
```ts
const groupName = `smoke-group-${Date.now()}`;
const groupCreated = waitForEvent<ChatResponse & { id: string }>(
  socket, "chat.created", (p) => !!p.id, 15_000,
);
const group = await request<ChatResponse>("POST", "/messenger/groups",
  { name: groupName, memberUserIds: [login.user.id] }, staffToken);
steps.groupCreatedEvent = await groupCreated;   // client saw the new group live
steps.groupId = group.id;

// Client leaves the group → client's user room gets chat.removed {id}.
const groupRemoved = waitForEvent<{ id: string }>(
  socket, "chat.removed", (p) => p.id === group.id, 15_000,
);
await request("POST", `/messenger/groups/${group.id}/leave`, {}, accessToken);
steps.groupRemovedEvent = await groupRemoved;
```
  (Read `createGroup`'s response shape to confirm the group id field; adjust if it differs.)

- [ ] **Step 3: Typecheck the smoke file** (it compiles with the server build): `cd server && npx tsc --noEmit -p tsconfig.json` (or the script's lint path the repo already uses). Do NOT run the smoke live here — that is Task 5 (gated).
- [ ] **Step 4: Commit** `git add server/src/smoke/realtime-smoke.ts` → `test(smoke): assert masked staff reply + live group create/leave (messenger v2)`.

---

### Task 2: Backend suite gate (CONTROLLER-run)

- [ ] `cd server && npm run typecheck` → clean.
- [ ] `cd server && npm test` → all green (record counts).
- [ ] `cd server && npm run build` → succeeds.
- [ ] If anything fails, STOP and triage (likely surfaces a real regression from Phase 3); do not proceed to deploy.

---

### Task 3: Flutter suite gate (CONTROLLER-run)

- [ ] `flutter analyze` (whole project) → no errors (pre-existing info-level lints acceptable, note them).
- [ ] `flutter test` (whole suite) → all green (record counts; Phase 4 last saw 232/232).

---

### Task 4: Build + refresh artifacts (CONTROLLER-run; environment-affecting)

- [ ] Confirm `pubspec.yaml` version is `1.1.22+128` (bump only if the user asks).
- [ ] `Stop-Process -Name magic_music_crm -Force` (ignore "not running"); the app LOCKS `dist/`.
- [ ] `flutter build windows --release --dart-define=MAGIC_API_BASE_URL=https://api.phantom-net.ru/api`
- [ ] `flutter build apk --release --dart-define=MAGIC_API_BASE_URL=https://api.phantom-net.ru/api`
- [ ] `flutter build appbundle --release --dart-define=MAGIC_API_BASE_URL=https://api.phantom-net.ru/api`
- [ ] Refresh `dist/`: copy the Windows release into `dist/MagicMusicCRM-1.1.22-128-windows-x64/` (Dart logic in `data/app.so`; keep the existing `run-account-A.bat`/`run-account-B.bat`), re-zip to `dist/MagicMusicCRM-1.1.22-128-windows-x64.zip`; copy the APK → `dist/MagicMusicCRM-1.1.22-128.apk` and the AAB → `dist/MagicMusicCRM-1.1.22-128.aab`.
- [ ] Compute SHA-256 of the three artifacts (`Get-FileHash`) and record them in the report (and in the ledger). These prove what was shipped.
- [ ] Do NOT git-add `dist/`.

**STOP HERE. Report build results + hashes + suite results. Get explicit user approval before Task 5.**

---

### Task 5: DEPLOY + Phase 2 WIPE (USER-GATED — do NOT auto-run)

Run only with explicit approval, step by step, each destructive step confirmed:

- [ ] **Backup:** `ssh … pg_dump | gzip > /opt/magicmusiccrm/backups/magiccrm-pre-chat-wipe-<UTC>.sql.gz`; confirm it exists + non-trivial.
- [ ] **Phase 2 dry-run candidate list** (read-only SELECTs from `docs/superpowers/plans/2026-06-25-messenger-v2-phase2-data-wipe.md` Step 1) → human approves the synthetic-account list + `must_be_zero = 0`.
- [ ] **Wipe** (single transaction, verify counts, then COMMIT) per the Phase 2 runbook Step 2.
- [ ] **Deploy backend** (Phase 1 + Phase 3): tar-copy `server/{src,db,package.json,package-lock.json,tsconfig*.json,nest-cli.json,Dockerfile}` → `docker compose --env-file .env up -d --build api` (migration 0043 runs on boot). NEVER overwrite host `server/.env`.
- [ ] **Post-deploy live smoke:** set `REALTIME_SMOKE_EMAIL`/client + `REALTIME_SMOKE_STAFF_EMAIL`/`REALTIME_SMOKE_STAFF_PASSWORD` (magic3 admin) and run `npx ts-node server/src/smoke/realtime-smoke.ts` → assert `maskedStaffReply.ok`, `groupCreatedEvent`, `groupRemovedEvent`, announcements visible, client 403.
- [ ] **Per-role manual/curl verification:** client (unified Администрация, masked), admin/manager (folders Лиды/Ученики/Архив, assignment, archive), teacher, group leave/add. Health `GET /api/health`.
- [ ] Distribute the refreshed `dist/` artifacts (hashes recorded in Task 4). Report what was checked per role.

## After Phase 5

Messenger v2 shipped. Address the carried Minor backlog (Phase 3 + Phase 4 ledger sections) as follow-ups. Merge the branch per superpowers:finishing-a-development-branch once the user confirms the deploy verified.
