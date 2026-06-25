# Messenger v2 — Design Spec (2026-06-25)

Status: approved (design). Next: implementation plan (writing-plans).
Branch: `kvazar2727/leads-to-students-dnd`. Backend: NestJS (`server/`). Client: Flutter (`lib/`).

## 1. Problem & Goals

The current messenger is operationally broken and conceptually unclear:

- **Администрация** is modelled as one chat per user, all hard-titled "Администрация".
  Staff see a pile of identical, "anonymized" entries; no notion of *who is handling
  which conversation*. (Especially when clients have no profile name → everything shows
  "Администрация".)
- **Clients can DM teachers directly** (teaching-relationship rule), but the school wants
  client↔teacher communication to happen **only inside staff-supervised groups**.
- **Groups**: new groups don't appear in realtime for members; added/removed members
  aren't notified; **no "leave group"** for a regular member.
- **Realtime** list/badge updates are partial (only the open chat room is joined; group
  create/membership changes aren't fanned out). Transport itself is fine (prod WS verified).
- Staff have **no organization** of incoming client conversations.
- **Onboarding/phone**: signup has no phone field; the profile phone field can't delete
  characters and accepts non-`+7` formats; a stray glowing ellipse sits behind the signup
  screen. Phone is also the key the new folders rely on.

Goal: a clear, supervised, realtime messenger — **Variant A** (targeted evolution of the
existing `chats`/`chat_members` schema, not a rewrite).

## 2. Decisions (locked with owner)

1. **Администрация** = shared staff inbox; each conversation labeled with the **client's
   name**; **"взять в работу"/assign** — others see "ведёт: Имя", the assignee replies,
   a manager (Управляющий) can intervene/reassign. Others still *see* the conversation.
2. **Client side**: always the unified brand **"Администрация"**; staff identities are
   **hidden** from the client (admin switches are invisible).
3. **Clients have no 1-on-1 chats at all** — only "Администрация" + groups they were added
   to by staff. Client↔teacher only inside a group that includes an admin/manager.
4. **Groups**: created/managed by **staff only** (admin/manager/system_admin), as today;
   **any member can leave themselves**; create/add/remove/leave are **realtime** for all
   affected users.
5. **Folders** (admin/manager) organize the **Администрация inbox**: by normalized phone of
   the conversation owner → linked to a **student → "Ученики"**; else linked to a
   **lead → "Лиды"**; **no link → "Лиды"** (auto-create lead, as today). **"Архив" is
   per-staff** (personal). Groups/staff chats live in a separate section. Each folder shows
   a **live unread badge**.
6. **Data wipe**: delete all chats/messages/groups/attachments (keep the system
   **"Объявления"** channel) + delete **synthetic smoke accounts** (`%@example.com`,
   `realtime-smoke%`). Real users/leads/students and the magic1–4 test accounts are kept.
   Backup first; show account-deletion candidates for confirmation.

## 3. Roles recap

`client` < `teacher` < `admin` < `manager` < `system_admin`. Staff = admin/manager/
system_admin (`isStaffRole`). Manager-tier = manager/system_admin.

## 4. Data Model Changes (migration)

`app.chats` add:
- `owner_user_id uuid null references app.users(id)` — the single non-staff participant of
  an `administration` chat (the client/teacher who opened it). Set on administration-chat
  creation. Used for the staff label and phone→folder linking. (Null for direct/group.)
- `assigned_to_user_id uuid null references app.users(id)` — current assignee (staff).
- `assigned_at timestamptz null`.

New `app.chat_inbox_state`:
```
chat_id uuid not null references app.chats(id) on delete cascade,
staff_user_id uuid not null references app.users(id) on delete cascade,
archived_at timestamptz null,
primary key (chat_id, staff_user_id)
```
Per-staff archive (and room for future per-staff inbox flags).

Folders are **derived at query time**, not stored:
- `archived_at` set for this staff → **Архив**.
- else owner's normalized phone matches a non-deleted `students` row → **Ученики**.
- else matches a `leads` row → **Лиды**.
- else → **Лиды**.

Phone match uses the existing normalized-phone columns/trigger (migrations 0025/0035/0036).

## 5. Backend API & Service

### Administration inbox
- `listChats` (staff): for `administration` chats, resolve label from `owner_user_id`'s
  profile (name/phone/avatar), include `assignedTo` (id+name), `folder` bucket, and
  `archivedAt` for the requesting staff. Order/group by folder on the client.
- `POST /messenger/chats/:id/assign` — body optional `{ userId }`. Self-claim if empty;
  manager/system_admin may pass another staff `userId`. Sets `assigned_to_user_id`/
  `assigned_at`. Emits `chat.updated` to admin-inbox + owner is unaffected.
- `POST /messenger/chats/:id/unassign` — clear assignment (assignee or manager).
- `POST /messenger/chats/:id/archive` / `.../unarchive` — upsert `chat_inbox_state`
  (per requesting staff). Emits `chat.updated` to that staff's user room. A **new client
  message resurfaces** the conversation: it clears `archived_at` for all staff (the thread
  re-enters its Лиды/Ученики folder), so an archived-then-reopened conversation isn't lost.
- Write policy: any staff may reply (collaborative). Assignment is advisory + visible;
  reassign restricted to the assignee or manager-tier.

### Client-side identity masking
- `getMessages`/realtime payloads: when the **viewer is the administration chat owner**
  (client/teacher) and the message sender is staff, the `sender` is masked to a generic
  `{ name: "Администрация" }` (no staff id/name/email). Staff viewers see real identities.

### RBAC: no client DMs
- `canCreateDirectChat`: throw if `actor.role === 'client'` OR `targetUser.role ===
  'client'`. Remove the teaching-relationship allowance. Direct chats only between
  non-client roles.

### Groups
- `createGroup`: after insert, emit `chat.created` (summary payload) to **each member's
  user room** so it appears live.
- `updateGroupMembers`: emit `chat.created` to **added** members' user rooms, `chat.removed`
  `{ id }` to **removed** members' user rooms, `chat.updated` to the chat room.
- `POST /messenger/groups/:id/leave`: any current member sets own `left_at`; emit
  `chat.removed` to the leaver's user room and `chat.updated` to the room. (No
  `assertCanManageGroup` for self-leave.)
- Create/manage members stays staff-only (`assertCanCreateGroup`/`assertCanManageGroup`).

### Realtime event contract (v2)
- `message.created`, `message.updated` → `chat:{id}` (+ user-room `chat.updated` fan-out).
- `chat.created` → added/new member `user:{id}` rooms (insert into list).
- `chat.removed` `{ id }` → removed/left member `user:{id}` room (drop from list).
- `chat.updated` → `chat:{id}`, member `user:{id}` rooms, `admin-inbox` (administration);
  carries last-message preview, `assignedTo`, archive state.
- Rooms unchanged: `user:`, `chat:`, `channel:`, `crm`, `admin-inbox`. Restored on reconnect.

## 6. Flutter Client

- **Inbox with folders** (admin/manager): segmented **Лиды · Ученики · Архив** over the
  administration inbox; group/staff chats in a separate section. Per-folder **unread badge**
  (sum of unread for chats in that folder), updated live on `chat.updated`/`message.created`.
- **Assignment UI**: "Взять в работу" / "Передать" (manager); show "ведёт: Имя" chip.
- **Archive action** per conversation (per-staff).
- **Realtime handlers**: `chat.created` (insert), `chat.removed` (remove), `chat.updated`
  (patch preview/assignment/archive + recompute folder badges). Client view shows
  "Администрация" and masked staff identity.
- **Groups**: "Выйти из группы" for any member; "Добавить участников" for staff/group-admin
  (existing `updateGroupMembers`); members appear/disappear live.
- **Client**: no "new direct chat" entry; only Администрация + groups.

## 7. Phone & Onboarding Fixes

- **Signup**: add a phone field using the existing `RuPhoneField` (canonical `+7…`); pass
  `phone` to `POST /auth/signup`; backend stores normalized phone on the user/profile.
- **Profile phone edit**: replace the buggy field with `RuPhoneField` so deletion works and
  only `+7…` is accepted (reject other formats with a clear message).
- **Signup screen**: remove the stray glowing background ellipse.

## 8. Data Wipe (one-off, after backup)

1. `pg_dump` backup to `/opt/magicmusiccrm/backups/` (manual, per ops notes).
2. Delete chat data: `message_reactions`, `messages`, `chat_members`, chat-owned
   `file_objects` (purpose `chat_attachment`/`chat_voice`), `channel_posts` for non-system
   channels, then `chats`. **Keep** the system "Объявления" channel + its permissions.
3. Delete synthetic accounts: users with email `ILIKE '%@example.com'` OR `ILIKE
   'realtime-smoke%'` (and their profiles/links) — **show the candidate list first**;
   never delete magic1–4 or real users.
4. Re-run `ensureDefaultChannels` (idempotent) to guarantee "Объявления" survives.

## 9. Testing

- Backend unit specs: assignment (claim/reassign/permissions), client-DM rejection,
  group leave + member-change realtime emissions, administration owner-label resolution,
  client-side identity masking, folder bucketing by phone.
- Flutter tests: inbox folder bucketing + unread badges, `chat.created`/`chat.removed`
  handlers, assignment chip, masked client view, `RuPhoneField` validation (delete works,
  `+7` enforced).
- Smoke: extend realtime smoke for assign → client reply masked, group create/leave live.

## 10. Non-goals (YAGNI)

- Conversation statuses (new/closed/reopened), SLA, tags (Variant B) — later if needed.
- Phone-based folder linking for groups/staff chats — folders apply to the Администрация
  inbox only.

## 11. Phasing (for the implementation plan)

1. Phone capture + validation (signup field, profile fix, `+7`, ellipse) — prerequisite for
   linking.
2. Data wipe (backup → delete chats + synthetic accounts → ensure default channel).
3. Backend messenger v2 (migration, owner/assignment, RBAC no-client-DM, group leave +
   realtime fan-out, identity masking, folder resolution).
4. Flutter (inbox folders + badges, assignment, archive, group leave/add, realtime handlers,
   masked client view).
5. Tests + smoke + Windows/Android/AAB rebuilds + deploy.
