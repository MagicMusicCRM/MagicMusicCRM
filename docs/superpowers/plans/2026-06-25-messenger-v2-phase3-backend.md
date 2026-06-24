# Messenger v2 — Phase 3: Backend — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.
> Implementers: each task names exact files; the code blocks are the source of truth for NEW logic. For edits to large existing files (`messenger.service.ts` ~1300 lines, `messenger.policy.ts`, `messenger.controller.ts`, `realtime.gateway.ts`), READ the current file and integrate the shown code at the indicated place. Reuse the existing jest unit-test harness in `messenger.service.spec.ts` / `messenger.policy.spec.ts` (mocked `DatabaseService`/`MessengerPolicy`/`RealtimeGateway`/`CrmService`).

**Goal:** Turn the messenger backend into the v2 model — a staff "Администрация" inbox labeled by client name with assignment ("взять в работу"), per-staff folders (Лиды/Ученики/Архив) derived by normalized phone, client-side staff-identity masking, no client DMs, and group leave + realtime create/remove fan-out.

**Architecture:** Targeted evolution of the existing `app.chats`/`app.chat_members` schema (Variant A). Add `owner_user_id`/`assigned_to_user_id`/`assigned_at` to `chats` and a per-staff `chat_inbox_state` table; resolve labels/folders at query time.

**Tech Stack:** NestJS + Postgres; jest unit tests.

## Global Constraints

- Roles: `client` < `teacher` < `admin` < `manager` < `system_admin`. Staff = admin/manager/system_admin (`isStaffRole`). Manager-tier = manager/system_admin (`isManagerRole`).
- Administration **owner** = the single non-staff member of the chat (`chats.owner_user_id`).
- Client sees the unified brand **"Администрация"**; staff sender identity is masked from the client (id/email/name stripped → `{ name: "Администрация" }`).
- Clients have **no direct chats** at all. Direct chats only between non-client roles.
- Groups: created/managed by staff only; **any member may leave**.
- Folder of an administration chat (per staff): `archived_at` set → **archive**; else owner's normalized phone matches a non-deleted student → **students**; else → **leads** (includes no-match).
- Normalized phone = digits only; 11 digits starting `8` → `7`+last10 (reuse the existing `profile.service` SQL `case` form). Same rule everywhere so matching is consistent.
- Realtime events: `message.created`/`message.updated` → `chat:{id}`; `chat.created` → new member `user:{id}`; `chat.removed {id}` → removed/left member `user:{id}`; `chat.updated` (preview/assignment/archive) → `chat:{id}` + member `user:{id}` + `admin-inbox` (administration). No unauthenticated broadcast.
- Migration files: `NNNN_snake_case.{up,down}.sql`; current head is `0042`. This is `0043`.
- Commit after each task (Co-Authored-By trailer). Branch `kvazar2727/leads-to-students-dnd`.

---

### Task 1: Migration 0043 — inbox columns + per-staff state

**Files:** Create `server/db/migrations/0043_messenger_v2_inbox.up.sql` and `.down.sql`.

- [ ] **Step 1: Write the up migration**

```sql
-- chats: administration owner + assignment
alter table app.chats add column if not exists owner_user_id uuid references app.users(id) on delete set null;
alter table app.chats add column if not exists assigned_to_user_id uuid references app.users(id) on delete set null;
alter table app.chats add column if not exists assigned_at timestamptz;

create index if not exists chats_owner_user_idx on app.chats (owner_user_id) where deleted_at is null;

-- per-staff inbox state (personal archive)
create table if not exists app.chat_inbox_state (
  chat_id uuid not null references app.chats(id) on delete cascade,
  staff_user_id uuid not null references app.users(id) on delete cascade,
  archived_at timestamptz,
  primary key (chat_id, staff_user_id)
);

-- backfill existing administration chats' owner (single non-staff member); after the
-- Phase 2 wipe there are none, but keep idempotent.
update app.chats c
set owner_user_id = (
  select cm.user_id from app.chat_members cm
  where cm.chat_id = c.id and cm.left_at is null
  order by cm.joined_at asc limit 1
)
where c.type = 'administration' and c.owner_user_id is null and c.deleted_at is null;
```

- [ ] **Step 2: Write the down migration**

```sql
drop table if exists app.chat_inbox_state;
drop index if exists app.chats_owner_user_idx;
alter table app.chats drop column if exists assigned_at;
alter table app.chats drop column if exists assigned_to_user_id;
alter table app.chats drop column if exists owner_user_id;
```

- [ ] **Step 3: Dry-run on the live DB inside a transaction (rolled back)** — like the 0042 dry-run: `BEGIN; <up.sql>; \d app.chat_inbox_state; ROLLBACK;` via `docker exec psql`. Confirm columns/table create cleanly.
- [ ] **Step 4: Commit** (`feat(messenger): migration 0043 — inbox owner/assignment + chat_inbox_state`).

---

### Task 2: RBAC — clients have no direct chats

**Files:** Modify `server/src/messenger/messenger.policy.ts` (`canCreateDirectChat`); Test: `messenger.policy.spec.ts`.

**Interfaces:** `canCreateDirectChat(actor, targetUserId)` keeps signature; now rejects any chat where either party is a `client`, and no longer consults the teaching relationship.

- [ ] **Step 1: Failing tests**

```ts
it('forbids a client from creating any direct chat', async () => {
  await expect(policy.canCreateDirectChat({ userId: 'c', role: 'client' }, 'x'))
    .rejects.toThrow(ForbiddenException);
});
it('forbids a direct chat whose target is a client', async () => {
  query.mockResolvedValueOnce({ rows: [{ role: 'client' }] }); // target lookup
  await expect(policy.canCreateDirectChat({ userId: 't', role: 'teacher' }, 'client-x'))
    .rejects.toThrow(ForbiddenException);
});
it('allows a direct chat between two non-client staff/teachers', async () => {
  query.mockResolvedValueOnce({ rows: [{ role: 'admin' }] }); // target lookup
  await expect(policy.canCreateDirectChat({ userId: 't', role: 'teacher' }, 'admin-x'))
    .resolves.toBeUndefined();
});
```

- [ ] **Step 2: Run → fail.** `cd server && npx jest --runInBand messenger.policy`

- [ ] **Step 3: Replace `canCreateDirectChat` body**

```ts
async canCreateDirectChat(actor: ActorContext, targetUserId: string): Promise<void> {
  if (actor.userId === targetUserId) {
    throw new ForbiddenException('Нельзя создать чат с самим собой.');
  }
  if (actor.role === 'client') {
    throw new ForbiddenException('Клиенты не могут создавать личные чаты.');
  }
  const target = await this.database.query<{ role: string }>(
    'select role from app.users where id = $1 and deleted_at is null limit 1',
    [targetUserId],
  );
  if (!target.rows[0]) throw new NotFoundException('Пользователь не найден.');
  if (target.rows[0].role === 'client') {
    throw new ForbiddenException('С клиентом можно общаться только через Администрацию или группу.');
  }
  // both non-client → allowed (teaching-relationship rule removed).
}
```

- [ ] **Step 4: Run → pass; typecheck.** `npx jest --runInBand messenger.policy && npm run typecheck`
- [ ] **Step 5: Commit** (`feat(messenger): clients cannot create direct chats (supervised comms only)`).

---

### Task 3: Set `owner_user_id` on administration chat creation

**Files:** Modify `server/src/messenger/messenger.service.ts` (`createAdministrationChat`); Test: `messenger.service.spec.ts`.

- [ ] **Step 1: Failing test** — assert the administration insert sets `owner_user_id = actor.userId`.

```ts
it('creates an administration chat with the actor as owner', async () => {
  type MockClient = { query: jest.Mock };
  const client = { query: jest.fn()
    .mockResolvedValueOnce({ rows: [] }) // existing lookup
    .mockResolvedValueOnce({ rows: [{ id: 'chat-admin', type: 'administration', title: 'Администрация',
      created_by: 'user-a', last_message_id: null, last_message_content: null,
      last_message_created_at: null, unread_count: '0',
      created_at: new Date(), updated_at: new Date() }] }) // insert
    .mockResolvedValueOnce({ rows: [] }) }; // insertMembers
  const { service } = createService({ database: { transaction: jest.fn(
    async (w: (c: MockClient) => Promise<unknown>) => w(client)) as never } });
  await service.createDirectChat({ userId: 'user-a', role: 'client' }, { type: 'administration' });
  const insert = client.query.mock.calls.find(c => String(c[0]).includes("values ('administration'"));
  expect(insert![0]).toContain('owner_user_id');
  expect(insert![1]).toContain('user-a');
});
```

- [ ] **Step 2: Run → fail.**
- [ ] **Step 3: Update the administration INSERT** to include `owner_user_id`:

```sql
insert into app.chats (type, title, created_by, owner_user_id)
values ('administration', 'Администрация', $1, $1)
returning id, type, title, created_by, last_message_id, ...
```
(params already pass `actor.userId` once; `$1` reused for both `created_by` and `owner_user_id`.)

- [ ] **Step 4: Run → pass; typecheck.**
- [ ] **Step 5: Commit** (`feat(messenger): record administration chat owner`).

---

### Task 4: Inbox — label by owner, folder by phone, assignment + archive in `listChats`

**Files:** Modify `messenger.service.ts` (`listChats` SQL + `toChatSummaryDto`); Test: `messenger.service.spec.ts`.

**Interfaces (Produces):** chat summary DTO for staff administration chats gains: `ownerName` (string|null), `assignedTo` ({id,name}|null), `folder` ('leads'|'students'|'archive'), `archived` (bool).

- [ ] **Step 1: Failing test** — staff `listChats` returns, for an administration row, `ownerName` from the owner profile, `folder='students'` when the owner phone matches a student, `assignedTo` populated, `archived` from `chat_inbox_state`. (Mock `database.query` to return one administration row with the joined columns `owner_first_name`, `owner_last_name`, `assigned_to_user_id`, `assigned_first_name`, `assigned_last_name`, `folder`, `archived_at`; assert the DTO mapping.)

- [ ] **Step 2: Run → fail.**

- [ ] **Step 3: Extend the `listChats` SQL** (staff branch). Add to the SELECT for administration rows:
  - owner profile join: `left join app.users ow on ow.id = c.owner_user_id and ow.deleted_at is null  left join app.profiles owp on owp.user_id = ow.id and owp.deleted_at is null` → select `owp.first_name as owner_first_name, owp.last_name as owner_last_name, owp.phone as owner_phone`.
  - assignee join: `left join app.users asg on asg.id = c.assigned_to_user_id  left join app.profiles asgp on asgp.user_id = asg.id` → `c.assigned_to_user_id, asgp.first_name as assigned_first_name, asgp.last_name as assigned_last_name`.
  - per-staff archive: `left join app.chat_inbox_state ist on ist.chat_id = c.id and ist.staff_user_id = $2` → `ist.archived_at`.
  - folder (use the normalized-phone match; `norm(x)` = the existing `case when length(digits)=11 and left(digits,1)='8' then '7'||substr(digits,2) else digits end` over `regexp_replace(coalesce(x,''),'[^0-9]','','g')`):
```sql
case
  when ist.archived_at is not null then 'archive'
  when exists (
    select 1 from app.students s
    join app.profiles sp on sp.id = s.profile_id and sp.deleted_at is null
    where s.deleted_at is null
      and norm(sp.phone) <> '' and norm(sp.phone) = norm(owp.phone)
  ) then 'students'
  else 'leads'
end as folder
```
  Keep the existing OR-clause that lets staff see administration chats. (The folder/owner columns are null for non-administration chats — fine.)

- [ ] **Step 4: Map the new columns in `toChatSummaryDto`** → `ownerName` (joined first+last, trimmed, null if empty), `assignedTo` ({id, name} or null), `folder` (row.folder ?? null), `archived` (row.archived_at != null).

- [ ] **Step 5: Run → pass; typecheck; run full `npx jest --runInBand messenger`.**
- [ ] **Step 6: Commit** (`feat(messenger): inbox owner label, phone folders, assignment + archive in listChats`).

---

### Task 5: Assignment endpoints (взять в работу / переназначить / снять)

**Files:** `messenger.controller.ts` (+routes), `messenger.service.ts` (+methods), `messenger.policy.ts` (assignment policy); Tests in both specs.

**Interfaces:** `POST /messenger/chats/:id/assign` body `{ userId? }`; `POST /messenger/chats/:id/unassign`. Self-claim if no userId; manager-tier may pass another staff `userId`. Reassign restricted to the current assignee or manager-tier. Emits `chat.updated` to `admin-inbox`.

- [ ] **Step 1: Failing tests** — `assignChat` sets `assigned_to_user_id`/`assigned_at` and publishes `chat.updated` to admin inbox; a non-manager cannot reassign a chat already assigned to someone else; self-claim allowed for any staff.
- [ ] **Step 2: Run → fail.**
- [ ] **Step 3: Implement.** Policy `assertCanAssign(actor, chat)`: `isManagerRole` always; else allowed only when chat is unassigned or already assigned to `actor.userId`. Service `assignChat(actor, chatId, userId?)`: require administration chat + staff actor; resolve target = `userId ?? actor.userId` (must be staff); `update app.chats set assigned_to_user_id=$2, assigned_at=now() where id=$1`; emit `this.realtime.publishAdminInboxEvent('chat.updated', { id: chatId, assignedTo: target })`. `unassignChat`: clear; emit. Controller wires both routes (JwtAuthGuard).
- [ ] **Step 4: Run → pass; typecheck.**
- [ ] **Step 5: Commit** (`feat(messenger): administration assignment (claim/reassign/unassign)`).

---

### Task 6: Per-staff archive + resurface on new message

**Files:** `messenger.controller.ts`, `messenger.service.ts`; Test: `messenger.service.spec.ts`.

**Interfaces:** `POST /messenger/chats/:id/archive` / `.../unarchive` (per requesting staff). `sendMessage` for an administration chat clears `archived_at` for all staff (resurface).

- [ ] **Step 1: Failing tests** — `archiveChat` upserts `chat_inbox_state(chat_id, staff_user_id, archived_at=now())` and emits `chat.updated` to the staff `user:` room; sending a message in an administration chat issues `update app.chat_inbox_state set archived_at = null where chat_id = $1`.
- [ ] **Step 2: Run → fail.**
- [ ] **Step 3: Implement.** `archiveChat(actor, chatId)`: require staff + administration; `insert into app.chat_inbox_state (chat_id, staff_user_id, archived_at) values ($1,$2,now()) on conflict (chat_id, staff_user_id) do update set archived_at = now()`; emit `publishUserEvent(actor.userId, 'chat.updated', { id: chatId, archived: true })`. `unarchiveChat`: set `archived_at = null`. In `sendMessage`, after the existing fan-out, if `chat.type === 'administration'`: `await this.database.query('update app.chat_inbox_state set archived_at = null where chat_id = $1', [chatId])` (best-effort).
- [ ] **Step 4: Run → pass; typecheck.**
- [ ] **Step 5: Commit** (`feat(messenger): per-staff archive + resurface administration chats on new message`).

---

### Task 7: Client-side staff-identity masking

**Files:** `messenger.service.ts` (`getMessages` + the message DTO + realtime publish in `sendMessage`); Test: `messenger.service.spec.ts`.

**Interfaces:** When the **viewer is the administration chat owner** (a non-staff user) and the message **sender is staff**, the returned/published `sender` is `{ id: null, name: 'Администрация', firstName: null, lastName: null, email: null }` and `senderId` is hidden (null). Staff viewers and non-administration chats are unchanged.

- [ ] **Step 1: Failing tests** — `getMessages` as the owner client over an administration chat masks a staff-sent message's sender to "Администрация"; the same call as a staff viewer returns the real sender; a client's OWN message is unchanged.
- [ ] **Step 2: Run → fail.**
- [ ] **Step 3: Implement.** Add `toMessageDto(row, opts?: { maskStaffSender?: boolean })`. In `getMessages`, compute `maskStaffSender = chat.type === 'administration' && chat.memberUserId === actor.userId && !isStaffRole(actor.role)` (the owner). For each row, mask when `maskStaffSender && row.sender_role is staff` — fetch the sender role (extend the messages query to `left join app.users su on su.id = m.sender_id` → `su.role as sender_role`). When masking: sender → `{ id: null, name: 'Администрация', firstName: null, lastName: null, email: null }`, `senderId: null`. For realtime: a staff reply in an administration chat publishes `message.created` to the chat room, which the client is in — so to keep staff identity off the wire entirely, publish the **masked** payload to the chat room for administration staff-sent messages (`sendMessage`: if `chat.type === 'administration' && isStaffRole(actor.role)`, publish `toMessageDto(message, { maskStaffSender: true })` to `chat:{id}`). The replying staff already sees their own message via optimistic UI; other staff see the real sender on REST refetch (`getMessages` is unmasked for staff viewers). This fully hides staff identity from the client at the transport layer with one shared room.
- [ ] **Step 4: Run → pass; typecheck.**
- [ ] **Step 5: Commit** (`feat(messenger): mask staff identity from the client in administration chats`).

---

### Task 8: Groups — leave + realtime create/remove fan-out

**Files:** `messenger.controller.ts` (leave route), `messenger.service.ts` (`leaveGroup`, fan-out in `createGroup`/`updateGroupMembers`); Test: `messenger.service.spec.ts`.

**Interfaces:** `POST /messenger/groups/:id/leave` — any current member sets own `left_at`; emits `chat.removed { id }` to the leaver's `user:` room and `chat.updated` to the chat room. `createGroup` emits `chat.created` (summary) to every member's `user:` room. `updateGroupMembers` emits `chat.created` to added members' `user:` rooms and `chat.removed { id }` to removed members' `user:` rooms (plus the existing `chat.updated` to the room).

- [ ] **Step 1: Failing tests** — `leaveGroup` updates the member's `left_at` and emits `chat.removed`; `createGroup` emits `chat.created` to each member; `updateGroupMembers` emits `chat.created` to added and `chat.removed` to removed.
- [ ] **Step 2: Run → fail.**
- [ ] **Step 3: Implement.** `leaveGroup(actor, chatId)`: require membership (`requireChat`), `chat.type === 'group'`; `update app.chat_members set left_at = now() where chat_id=$1 and user_id=$2 and left_at is null`; `publishUserEvent(actor.userId, 'chat.removed', { id: chatId })`; `publishChatEvent(chatId, 'chat.updated', { id: chatId })`. In `createGroup`, after insert+members, for each member `publishUserEvent(userId, 'chat.created', summary)`. In `updateGroupMembers`, emit `chat.created` to `dto.addUserIds` and `chat.removed` to `dto.removeUserIds`. (No `assertCanManageGroup` for `leaveGroup`.)
- [ ] **Step 4: Run → pass; typecheck; full `npx jest --runInBand messenger` + `npm test`.**
- [ ] **Step 5: Commit** (`feat(messenger): group leave + realtime create/remove fan-out`).

---

## Self-Review (coverage vs spec §4-§5)

- Migration owner/assignment/inbox state → Task 1. Client no DM → Task 2. Owner set → Task 3. Inbox label/folder/assignment/archive surfaced → Task 4. Assign endpoints → Task 5. Archive + resurface → Task 6. Identity masking → Task 7. Group leave + realtime → Task 8. ✓
- Flutter consumption of these events/DTO fields (folders UI, masking on client, chat.created/removed handlers) is **Phase 4** — out of scope here.

## After Phase 3

Backend deploy happens with Phase 2 (wipe) per the Phase 2 timing note; Flutter (Phase 4) consumes the new fields/events. Run `npm run typecheck && npm test && npm run build` green before deploying.
