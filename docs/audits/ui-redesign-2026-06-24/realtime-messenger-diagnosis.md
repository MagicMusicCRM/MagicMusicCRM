# Realtime + Messenger Diagnosis (2026-06-24)

Scope: full-app realtime, with `Администрация` and `Объявления` as P0 blockers. This
report is evidence-based (file:line references). Companion coverage matrix:
[`full-app-realtime-coverage.md`](./full-app-realtime-coverage.md).

## TL;DR root causes

1. **Announcements (`Объявления`) realtime never reaches anyone.** Channel posts are
   published to a *chat* room that no one can join, and the realtime contract has no
   `channel` room type at all.
2. **No durable `Объявления` channel exists.** There is no seed/migration/bootstrap, so
   `GET /messenger/channels` returns nothing for `client`/`teacher` (they have no
   `channel_permissions` rows), i.e. the entry point is simply missing.
3. **Administration inbox has no realtime fan-out.** Staff see admin conversations via a
   REST `listChats` OR-clause, but nothing pushes *new conversations* or *new messages*
   to staff who have not manually opened that specific chat room; symmetrically the
   client's chat list does not update when staff reply unless the client is sitting
   inside the chat.
4. **Reconnect does not restore chat/channel subscriptions.** On socket reconnect the
   server re-joins only `user:` and `crm` rooms; every `room.join`-based subscription is
   lost and Flutter has no reconnect re-join hook.
5. **Full-app realtime coverage is narrow.** Only schedule, leads, and lessons-kanban
   subscribe to `crm.changed`. Tasks, payments/finance, reports, students board,
   users/roles, settings and notifications neither emit nor subscribe.

## Evidence

### Broken path: channel post → nobody

- `MessengerService.createChannelPost` publishes with
  `this.realtime.publishChatEvent(channelId, "channel.post_created", post)`
  — `server/src/messenger/messenger.service.ts:908`.
- `RealtimeGateway.publishChatEvent` emits only to `chat:${id}`
  — `server/src/messenger/realtime.gateway.ts:200,253`.
- There is **no channel room type**: `JoinRoomPayload.roomType` is `@IsIn(['chat','user'])`
  — `server/src/messenger/dto/realtime-events.dto.ts:4`; `joinRoom` builds only chat/user
  rooms — `realtime.gateway.ts:139`; `canJoinRealtimeRoom` throws for anything but
  `chat`/`user` — `messenger.policy.ts:104-106`.
- Flutter has no `joinChannel`; the messenger screen merges channels into the chat list
  and on select calls `joinChat(channelId)` →
  `room.join {roomType:'chat', roomId: channelId}`
  (`lib/core/services/magic_realtime_service.dart:106`; messenger_screen select path).
- That join is **rejected by the backend**: `canJoinRealtimeRoom('chat', channelId)` runs
  `getChatAccess(channelId)`, which finds no row in `app.chats` for a channel id →
  `NotFoundException` (`messenger.policy.ts:108-110,113-126`).

Net effect: the post is emitted to `chat:<channelId>`, which nobody can join, and even
the client's attempt to join that room is denied. **`channel.post_created` is delivered to
zero sockets.**

### Missing durable `Объявления` channel

- `app.channels` schema has no system/slug flag — only
  `id,title,description,avatar_file_id,created_by,created_at,updated_at,deleted_at`
  (`server/db/migrations/0003_messenger.up.sql:60-69`).
- No seed/bootstrap: `main.ts` has no `OnApplicationBootstrap`; the only `OnModuleInit`
  hooks are the notifications reminder scheduler and analytics worker — neither seeds data.
- `listChannels` returns a channel to non-staff only when a matching `channel_permissions`
  row exists (`messenger.service.ts:726-743`); with no seeded channel + perms, `client`
  and `teacher` see no announcements channel.

### Administration inbox semantics

- Staff DO see admin chats over REST: `listChats` OR-clause
  `($1 in ('manager','admin','system_admin') and c.type='administration')`
  — `messenger.service.ts:172-175`; policy allows staff read/write of administration chats
  — `messenger.policy.ts:29,35`.
- BUT realtime delivery is room-scoped: a new message emits `message.created` only to
  `chat:${chatId}` (`messenger.service.ts:318`). Staff join a chat room only when they open
  that chat. There is **no push** to make a *new* administration conversation appear, and no
  push to staff who have the inbox list open but not that specific chat.
- The client side has the mirror problem: when staff reply, `message.created` reaches only
  sockets joined to `chat:${chatId}`; the client's chat-list/badge does not update unless
  the client is inside the chat.

### Reconnect

- On (re)connect the gateway re-joins `user:${sub}` and (non-client) `crm`
  (`realtime.gateway.ts:114-118`) but **not** any `room.join` chat/channel rooms.
- Flutter relies on socket.io auto-reconnect and never re-issues `room.join` after a
  reconnect (no `connect`/reconnect listener in `magic_realtime_service.dart` or
  `messenger_screen`).

### Full-app realtime emission/subscription gaps

- `emitCrmChanged` is called only for lessons (created/updated/deleted) and lead/student
  mutations — `server/src/crm/crm.service.ts:3341,3428,3569,5529,5616,5646,5673`.
- No emission on: tasks, payments, comments, expenses, homework, student create/update,
  teachers/staff, rooms, lead statuses, user/role changes, settings, notifications.
- Flutter subscribers to `crm.changed`: only `schedule_widget.dart:865`,
  `leads_widget.dart:1131`, `lessons_kanban_widget.dart:98`. Students board, tasks,
  finance, reports, users/roles do not subscribe. The notification bell
  (`lib/core/widgets/notification_bell_widget.dart`) polls on tap; no push.

## Tests / smoke status

- Backend unit specs for messenger exist (`messenger.service.spec.ts`,
  `messenger.policy.spec.ts`) but **do not** cover: default channel idempotency, channels
  visibility per role, channel write RBAC, channel realtime room delivery, or staff
  administration-inbox realtime.
- `server/src/smoke/realtime-smoke.ts` covers only a single self-signup client joining its
  own administration chat and receiving `message.created`. It does not cover staff↔client
  administration realtime, announcements posts/`403`, or CRM invalidation.
- Flutter realtime/messenger tests do not cover `joinChannel`, default-channel mapping,
  composer gating, dedupe, or reconnect re-subscription.

## Fix strategy (summary; implemented in this change)

- **Data contract:** migration `0042_default_announcements_channel` adds `slug` + `is_system`
  to `app.channels`, seeds the `Объявления` system channel idempotently, and grants read to
  all roles + write to `admin`/`manager`/`system_admin`; mirrored by an idempotent
  `MessengerService.ensureDefaultChannels()` run from `OnModuleInit` (self-heal).
- **Realtime rooms:** add `channel` room type end-to-end (DTO + gateway + policy via
  `getChannelAccess`), publish `channel.post_created` to `channel:${id}`.
- **Administration inbox:** staff join an `admin-inbox` room on connect; administration
  message writes fan out `chat.updated` to that room and to each member's `user:` room so
  new conversations and replies surface without manual refresh.
- **Flutter:** add `joinChannel`, join the announcements channel + active chat rooms on
  connect, re-join everything on reconnect (`connect` listener), keep `Администрация` +
  `Объявления` always visible, keep the announcements composer staff-only, dedupe via the
  existing id-based upsert.
- **Full-app:** broaden `crm.changed` emission (tasks/payments/comments/students) and add
  `crm.changed`/scoped subscriptions to the remaining boards; surfaces that stay
  REST-refresh are documented with reasons in the coverage matrix.
