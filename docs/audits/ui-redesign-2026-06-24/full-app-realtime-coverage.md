# Full-App Realtime Coverage Matrix (2026-06-24)

Companion to [`realtime-messenger-diagnosis.md`](./realtime-messenger-diagnosis.md).
Roles: `client`, `teacher`, `admin`, `manager`, `system_admin`.

Legend for **Fix implemented**: ✅ fixed in this change · ➖ already working · 📄 intentionally
REST-refresh (documented, has a visible refresh path) · ⏳ partial / follow-up.

| Role | Section | Scenario | Expected realtime behavior | Current (pre-fix) behavior | Backend event/room | Flutter subscriber | Fix implemented | Evidence |
|---|---|---|---|---|---|---|---|---|
| all | Messenger direct/group | peer sends a message | message appears live in open chat + list badge updates | live only inside open chat room; list badge needs refetch | `message.created` → `chat:${id}`; new `chat.updated` → member `user:` rooms | `onMessageCreated`, `onChatUpdated` | ✅ | service.ts sendMessage; messenger_screen `_handleRealtimeMessageCreated` |
| client/teacher | Администрация | user opens app | always sees `Администрация` entry | clients/teachers ensure their admin chat | `POST /chats/direct {administration}` | `ensureAdministrationChat()` | ➖/✅ verified | messenger_screen `_loadChatListInternal` |
| client/teacher | Администрация | user → staff message | staff see it live (new convo + message) | staff only via manual refetch | `chat.updated` → `admin-inbox` room + member `user:` rooms | staff `onChatUpdated` → refetch list | ✅ | gateway `admin-inbox`; service fan-out |
| admin/manager/system_admin | Администрация | staff reply | reaches user live | only if user inside chat | `message.created` → `chat:${id}` + `chat.updated` → user room | client `onMessageCreated`/`onChatUpdated` | ✅ | service sendMessage fan-out |
| all | Объявления | entry visibility | every role always sees `Объявления` | missing (no seed/perms) | seeded system channel via `GET /channels` | channels merged into list | ✅ | migration 0042 + `ensureDefaultChannels` |
| all | Объявления | new post published | appears live for every reader | delivered to zero sockets | `channel.post_created` → `channel:${id}` | `joinChannel` + `onChannelPostCreated` | ✅ | gateway channel room; service `publishChannelEvent` |
| client/teacher | Объявления | attempt to post | composer hidden + backend `403` | composer already hidden; backend blocks | `POST /channels/:id/posts` → `ForbiddenException` | `_canPostToChannel` (staff only) | ➖/✅ verified | policy `assertCanWriteChannel`; messenger_screen:1358 |
| all | Messenger | typing/presence | live indicators | working | `typing.*`, `presence.updated` | `onTypingStart/Stop`, `onPresenceUpdated` | ➖ | gateway typing/presence |
| all | Messenger | read receipts | live tick updates | working | `message.updated`/`chat.updated` | `onMessageUpdated` | ➖ | service markRead |
| any | Reconnect | network drop & recover | re-subscribe all needed rooms | only user+crm rooms restored | server re-join user/crm; client re-join on `connect` | `onConnect` re-join hook | ✅ | magic_realtime_service `onConnect`; messenger_screen rejoin |
| any | Optimistic UI | own send + echo | no duplicate row | id-based upsert dedupes | n/a | `_upsertMessage` by id | ➖ verified | messenger_screen:922 |
| admin/manager/system_admin | Schedule | lesson create/update/delete/reschedule | other staff session refetches affected day/month | working | `crm.changed{lesson}` → `crm` room | `schedule_widget`/`lessons_kanban` | ➖ | crm.service:3341/3428/3569; schedule_widget:865 |
| admin/manager/system_admin | Schedule | attendance change | refetch attendance/day | emits lesson updated | `crm.changed{lesson,updated}` | schedule_widget | ➖/✅ | crm.service attendance path |
| admin/manager/system_admin | Leads board | lead create/update/delete/status move | live kanban update | working | `crm.changed{lead}` → `crm` room | `leads_widget:1131` | ➖ | crm.service:5529/5616/5673 |
| admin/manager/system_admin | Students board | student create/update/branch/status | live board update | only delete emitted; board not subscribed | `crm.changed{student}` on create/update/delete | `students_board_widget` subscribe | ✅ | crm.service student writes; students_board listen |
| admin/manager/system_admin | Tasks | task create/update/status | live task list update | no emit, no subscribe | `crm.changed{task}` → `crm` room | `tasks_widget` subscribe | ✅ | crm.service task writes; tasks_widget listen |
| manager/system_admin | Finance | payment/expense affecting totals | refetch visible balances | no emit, no subscribe | `crm.changed{payment}` → `crm` room | `finance_widget` subscribe | ✅ | crm.service payment/expense; finance_widget listen |
| manager/system_admin | Reports | data affecting report totals | refetch report on demand | no emit, no subscribe | `crm.changed{payment,lesson}` | `reports_widget` subscribe (debounced) | ✅ | reports_widget listen |
| manager/system_admin | Users/roles | role/profile change | nav/access refetch | no emit, no subscribe | `crm.changed{user}` → `crm` room | `user_roles_widget` subscribe | ✅ | users service emit; user_roles_widget listen |
| all | Settings (admin chat avatar etc.) | shared setting change | shared UI refetch | no emit | `crm.changed{setting}` | targeted refetch | 📄 | low write frequency; manual refresh path exists |
| all | Notifications bell | new in-app notification | badge/list updates live | poll-on-tap only | `crm.changed{notification}` to recipient `user:` room | bell subscribe | ⏳/✅ | notifications emit; bell listen |
| all | Chat attachments | attachment lifecycle in open chat | appears with message | delivered with `message.created` | `message.created` payload carries attachment | `onMessageCreated` | ➖ | service toMessageDto attachment fields |

## Surfaces classified as REST-refresh acceptable (with reasons)

- **Profile/avatar self-view, static settings pages** — single-user surfaces; a second
  session is unlikely to be editing them concurrently. Manual pull-to-refresh available.
- **Reports heavy aggregates** — recomputed server-side; we emit a scoped invalidation but
  debounce refetch (expensive query); live patching the chart is out of scope and risky.
- **Audit log / history timelines** — append-only, low urgency; refreshed on screen entry.
- **Subscription packages / dictionaries** — config data edited rarely by a single admin;
  refreshed on screen entry.

## Required event contract (after fix)

Messenger (direct payloads):
- `message.created`, `message.updated` → `chat:${chatId}`
- `chat.updated` → `chat:${chatId}`, member `user:${userId}` rooms, and `admin-inbox`
  (administration only)
- `channel.post_created` → `channel:${channelId}`
- `typing.start`/`typing.stop`/`presence.updated` → `chat:${chatId}` / `user:${userId}`

CRM (scoped invalidation hint, no PII — clients refetch via REST):
```ts
crm.changed → room 'crm' (staff) : {
  entity: 'lesson'|'lead'|'student'|'task'|'payment'|'comment'|'user'|'setting'|'notification',
  action: 'created'|'updated'|'deleted'|'moved',
  id?, branchId?, affectedUserIds?, changedAt?
}
```
Recipient-scoped: `crm.changed{entity:'notification'}` is also emitted to the recipient's
`user:${userId}` room so non-staff get their bell badge live.

Rooms: `user:${userId}` (self), `chat:${chatId}` (members), `channel:${channelId}`
(readers), `crm` (staff CRM), `admin-inbox` (staff administration). No unauthenticated
global broadcast. Every subscription is restored on reconnect.
