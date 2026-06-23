# Backend Audit: Messenger + Notifications + Files

## 1. Overview

Three tightly-coupled NestJS modules (all PostgreSQL, schema `app`):

- **Messenger** (`server/src/messenger/`) — real-time chat and broadcast channels; chat types: `direct`, `group`, `administration`. Backed by Socket.IO WebSocket gateway (`/realtime`). Every send on an `administration` chat triggers automatic CRM lead creation for non-staff senders.
- **Notifications** (`server/src/notifications/`) — in-app, email, and Firebase push notification pipeline; includes a background scheduler for lesson reminders.
- **Files** (`server/src/files/`) — upload/download with purpose-scoped validation, local filesystem storage, and one-time signed download tokens.

---

## 2. Features (Exhaustive)

### Messenger — Chat HTTP Endpoints (`/messenger`)

- **GET /messenger/chats** — Paginated (cursor `before`, max 100) list of chats the actor is a member of; managers/admins/system_admins also see all `administration` chats. Returns last-message preview, unread count (computed per-query), mute state, partner profile for direct chats.
- **GET /messenger/chats/:chatId** — Single chat detail with partner info and mute state.
- **GET /messenger/chats/:chatId/messages** — Paginated message list (cursor `before`, max 100); includes sender profile, attachment metadata, `is_read` status (sender-relative: true once ALL other members have read past that message).
- **GET /messenger/chats/:chatId/members** — All current (non-left) chat members with profile/role/avatar; marks `isCurrentUser`.
- **POST /messenger/chats/:chatId/messages** — Send a message; supports `text`, `file`, `voice` message types; optional `replyToId`, `forwardedFromId`, `attachmentFileId`. Validates file is owned by the chat with correct purpose. Broadcasts `message.created` via WebSocket. **Triggers `autoCreateLeadFromChat` when sender is non-staff and chat type is `administration` (fire-and-forget, error suppressed).**
- **POST /messenger/chats/direct** — Create or retrieve a direct chat; `type: "administration"` creates/retrieves the user's administration chat (singleton per user). Enforces shared-lesson constraint for non-managers.
- **POST /messenger/groups** — Create a named group chat; restricted to managers/admins. Creator gets `admin` chat-member role.
- **PATCH /messenger/groups/:id/members** — Add or remove group members; restricted to managers/admins or group admin members. Emits `chat.updated`.
- **POST /messenger/chats/:chatId/read** — Mark chat read up to a given message (or latest); inserts/upserts chat_members row for administration chats. Emits `chat.updated` and `message.updated` for newly-read sender messages.
- **PUT /messenger/chats/:chatId/mute** — Per-user mute toggle (`muted_until = 'infinity'` or `null`). Emits `chat.updated`.
- **PUT /messenger/messages/:id/reactions/:emoji** — Add emoji reaction (upsert); emits `message.updated` with updated reaction counts.
- **DELETE /messenger/messages/:id/reactions/:emoji** — Remove emoji reaction; emits `message.updated`.
- **POST /messenger/messages/:id/pin** — Pin a message; requires `assertCanManageGroup` (manager/admin or group admin).
- **DELETE /messenger/messages/:id/pin** — Unpin a message; same permission requirement.
- **DELETE /messenger/messages/:id** — Soft-delete: nulls `content` and `attachment_file_id`, sets `deleted_at`, stores `delete_mode` (`own` if actor is sender; `moderated` otherwise). Emits `message.updated`. Only admins can delete others' messages.
- **PATCH /messenger/messages/:id** — Edit a message's text content; only sender may edit; only `text` type without attachment; message must not be deleted.

### Messenger — Channels HTTP Endpoints (`/messenger/channels`)

- **GET /messenger/channels** — List channels accessible to the actor (managers/admins see all; others see channels with matching `channel_permissions` row).
- **POST /messenger/channels** — Create channel with title, optional description, and permissions array. Restricted to managers/admins.
- **PATCH /messenger/channels/:id** — Update channel title/description and fully replace permissions. Restricted to channel write-access holders.
- **GET /messenger/channels/:id/access** — Returns `{canRead, canWrite}` for the actor on a channel.
- **GET /messenger/channels/:id/permissions** — List all permission rows (user- or role-scoped). Requires channel write access.
- **GET /messenger/channels/:id/posts** — Paginated channel posts (cursor `before`, max 100).
- **POST /messenger/channels/:id/posts** — Publish a channel post (content + optional attachment); emits `channel.post_created`.

### Messenger — WebSocket Gateway (`/realtime`)

- **Connection** — JWT in `handshake.auth.token` or `Authorization: Bearer` header; validates with `JWT_ACCESS_SECRET`. Disconnects immediately on invalid/missing token. On connect, auto-joins `user:<userId>` room.
- **room.join** — Join a `chat` or `user` room; rate-limited 20 joins/min; enforces chat-read access policy.
- **room.leave** — Leave any previously joined room.
- **typing.start / typing.stop** — Broadcast typing indicator to all other chat room members; rate-limited 60/min; validates chat access.
- **presence.update** — Broadcast presence status (`online`/`away`/`busy`); rate-limited 30/min. On disconnect, publishes `offline` to all joined chat rooms.
- **Server-push events**: `message.created`, `message.updated`, `chat.updated`, `channel.post_created`, `presence.updated`, `rate_limited`.
- **Rate limiting** — Per-socket, per-event-key, sliding window; excess emits `rate_limited` event then throws (disconnects safe handling at call site).

---

### Notifications

- **GET /notifications** — Actor's own notification list; cursor-paginated (`cursor`, `limit`); optional `unread=true` filter. Returns `total` via window function.
- **POST /notifications/:id/read** — Mark single notification read (sets `is_read = true`, `read_at`).
- **POST /notifications/read-all** — Mark all unread notifications read for the actor.
- **POST /notifications/devices** — Register a push device token (platform + FCM token). Token hashed with SHA-256 for dedup key; encrypted with AES-256-GCM for storage. Upserts on `(user_id, token_hash)`.
- **DELETE /notifications/devices/:id** — Soft-disable a push device (`enabled = false`).
- **POST /admin/notifications** (manager+) — Admin broadcast notification; targets: `users` (UUID list, max 200), `role`, or `all` (up to 10 000 users). Channels: `in_app`, `email`, `push`. Audited.
- **notifyUser()** (internal) — Single-user system notification; callable from other services.
- **sendEmail()** (internal) — Queue a transactional email directly (bypasses notification record).
- **Lesson reminder scheduler** — Polls every 5 minutes (only when `LESSON_REMINDERS_ENABLED=true`). Issues `day` reminder (12–24 h before) and `hour` reminder (0–1 h before). Idempotent: inserts claim row in `app.lesson_reminders(lesson_id, kind)` before sending — exactly-once guarantee even across overlapping ticks. Targets active students from individual and group lessons.

**Delivery pipeline:**
- **Email**: Primary provider — Resend API (`RESEND_API_KEY`, `RESEND_FROM_EMAIL`); fallback — hand-rolled SMTP over TLS (`SMTP_FALLBACK_*`). Exponential retry up to 5 attempts (1, 2, 4, 8, 16 min). Background drain timer every 30 s.
- **Push**: Firebase Cloud Messaging v1 API (`FIREBASE_PROJECT_ID`, `FIREBASE_CLIENT_EMAIL`, `FIREBASE_PRIVATE_KEY`). Per-delivery row claimed atomically (`dispatch_claimed_at`) to prevent double-send across drain cycles. Sends to up to 10 devices per user (most recently seen first). Fallback: skips if no devices registered. Background drain timer every 30 s.
- **In-app**: Written directly to `notification_recipients` (no async pipeline).
- **Email HTML rendering**: Branded Magic Music CRM template with optional 6-digit code block; templates: `auth_password_reset`, `student_invite`, generic.
- **Data sanitization**: Notification `data` field allows only keys `route`, `entityType`, `entityId`, `chatId`, `lessonId` with scalar values.

---

### Files

- **POST /files** — Upload a file (multipart `file` field); hard limit 26 MB at interceptor. Purpose validated against MIME allowlist and per-purpose size limit. Storage key: `private/YYYY/MM/<uuid>/<random32hex>.<ext>`. SHA-256 digest stored. On DB insert failure, storage file is cleaned up. Audited.
- **GET /files/:id** — File metadata (no file bytes). Requires auth + read permission check.
- **POST /files/:id/download-token** — Issue a single-use signed download token (32 random bytes, base64url). TTL: 60 s for `crm_document`, 5 min for all others. Token hash stored in `app.file_download_tokens`.
- **GET /files/download/:token** — Unauthenticated download endpoint. Validates token (not expired, not used), marks `used_at = now()` in same transaction (one-time use), streams file from local storage. `Cache-Control: private, no-store`.
- **DELETE /files/:id** — Soft-delete (`deleted_at = now()`). Does NOT delete from disk. Audited.

**File purposes and limits:**

| Purpose | Max size | Allowed MIME types |
|---|---|---|
| `profile_avatar` | 1 MB | image/png, image/jpeg, image/webp |
| `chat_attachment` | 25 MB | images, PDF, office docs, audio (mp3/m4a/ogg/webm/wav), video (mp4/webm), txt |
| `chat_voice` | 25 MB | audio only (mp3/m4a/ogg/webm/wav) |
| `legal_document` | 10 MB | application/pdf only |
| `crm_document` | 25 MB | same as chat_attachment |

**Storage**: Local filesystem only; path: `FILE_STORAGE_ROOT` env var (default `/opt/magicmusiccrm/storage/private`). No cloud/S3 driver.

---

## 3. Per-role Behavior / Permissions

| Role | Messenger Chats | Groups | Channels | Moderation | Notifications Admin |
|---|---|---|---|---|---|
| `client` / `teacher` (non-staff) | Own chats only | Cannot create | By permission row only | Own messages only | No |
| `manager` | Own + all `administration` | Create/manage | Full access (read+write) | Own messages only | Yes |
| `admin` | Own + all `administration` | Create/manage | Full access (read+write) | Any message | Yes |
| `system_admin` | Own + all `administration` | Create/manage | Full access (read+write) | Any message | Yes |

**Direct chat creation (non-manager):** Requires at least one shared lesson between the two users.  
**Pinning/unpinning:** Requires `assertCanManageGroup` — manager/admin or group chat-admin member.  
**File read:** Own files, or managers/admins, or chat participants (for chat_attachment/chat_voice), or anyone (for `legal_document`).  
**File delete:** Own files or admin role.  
**File upload `legal_document`/`crm_document`:** Manager or admin only.  
**Profile avatar upload for another user:** Admin role only.

---

## 4. Data / Schema Touched

### Tables (schema `app`)

- `app.chats` — id, type (direct/group/administration), title, created_by, last_message_id, deleted_at, updated_at
- `app.chat_members` — chat_id, user_id, role (admin/member), joined_at, left_at, last_read_message_id, muted_until
- `app.messages` — id, chat_id, sender_id, content, message_type (text/file/voice), attachment_file_id, reply_to_id, forwarded_from_id, pinned_by, pinned_at, deleted_at, delete_mode, created_at, updated_at
- `app.message_reactions` — message_id, user_id, emoji (unique constraint: one emoji per user per message)
- `app.channels` — id, title, description, created_by, deleted_at, created_at, updated_at
- `app.channel_permissions` — channel_id, user_id (nullable), role (nullable), can_read, can_write
- `app.channel_posts` — id, channel_id, author_id, content, attachment_file_id, published_at, deleted_at, updated_at
- `app.notifications` — id, type, title, body, data (jsonb), created_by, created_at
- `app.notification_recipients` — notification_id, user_id, is_read, read_at, delivered_at
- `app.notification_deliveries` — id, notification_id, user_id, channel, provider, status, attempt_count, last_error, dispatch_claimed_at, updated_at
- `app.notification_devices` — id, user_id, platform, token_hash (SHA-256, dedup key), encrypted_token (AES-256-GCM), enabled, last_seen_at, created_at, updated_at
- `app.email_outbox` — id, user_id, to_email_hash (SHA-256), template, payload (jsonb), status, attempt_count, last_error, next_attempt_at, created_at, updated_at
- `app.lesson_reminders` — lesson_id, kind (day/hour) — unique constraint; used as exactly-once claim
- `app.file_objects` — id, owner_user_id, owner_type, owner_id, purpose (enum), original_name, mime_type, size_bytes, storage_key, sha256, created_by, created_at, deleted_at
- `app.file_download_tokens` — token_hash, file_id, actor_user_id, expires_at, used_at
- `app.user_crm_links` — user_id, entity_type (lead/student), entity_id, matched_phone, link_source (auto_phone/manual_phone), created_by, confirmed_at, deleted_at (consulted on lead auto-creation)
- `app.leads` — id, first_name, last_name, phone, source, status_id, created_by, deleted_at (written by auto-lead flow)
- `app.lead_statuses` — name field; queried for `'новый'` during auto-lead creation
- `app.profiles` — consulted for sender name/phone during auto-lead creation
- `app.users` — role, email, deleted_at — read in most queries
- `app.lessons`, `app.students`, `app.teachers`, `app.group_students` — read by policy for direct-chat access check and reminder dispatch

---

## 5. Notable Business Rules / Edge Cases

1. **Auto-lead creation on first admin-chat message**: In `sendMessage`, when `chat.type === 'administration'` and `!isStaffRole(actor.role)`, `crm.autoCreateLeadFromChat(actor, actor.userId)` is called fire-and-forget (error swallowed with `.catch(() => undefined)`). The CRM method acquires a PostgreSQL advisory lock (`pg_advisory_xact_lock(hashtext('autolead:<userId>'))`) to serialize concurrent first messages, checks for an existing `user_crm_links` row (both `lead` and `student` entity types), then inserts a lead with `source = 'Через приложение'` and status `'Новый'` (null-fallback safe). The link row uses `link_source = 'auto_phone'`. If the user already has a student link, no lead is created (returns `created: false`).

2. **Administration chat access for staff**: All users with roles `manager`, `admin`, `system_admin` can list and read ANY `administration` chat without being a `chat_members` row. They can also join `administration` chats' WebSocket rooms without being members.

3. **markRead for administration chats**: If the `UPDATE` on `chat_members` affects 0 rows (staff not yet in the members table), an upsert is performed — this allows staff to track their read position without a prior `chat_members` insert.

4. **Direct chat creation between non-staff**: Policy enforces a shared lesson between the two users (`app.lessons` join via student/teacher profiles). Managers/admins bypass this check.

5. **Message soft-delete content erasure**: On delete, both `content` and `attachment_file_id` are NULLed in the DB (not just `deleted_at`). `toMessageDto` additionally zeroes out attachment fields for deleted messages at DTO level. File row in `file_objects` is NOT soft-deleted; only the reference is nulled.

6. **File download token is single-use**: The `download` endpoint selects with `FOR UPDATE` on the token row and immediately sets `used_at`. Re-use returns 404.

7. **Push token encryption fall-through**: If `NOTIFICATION_TOKEN_ENCRYPTION_KEY` is not set, `encrypt()` stores `sha256:<hash>` (unencryptable). During push dispatch, `decrypt()` returns `null` for non-`v1:` prefixed tokens, causing the device to be skipped with `missing_token_encryption_key` — push silently fails with no error surfaced to the user.

8. **Lesson reminder kill-switch**: The scheduler only starts when `LESSON_REMINDERS_ENABLED=true`. Without it, no lesson reminders are ever sent, but all other notification flows work normally.

9. **Email provider failover**: Resend is tried first; on failure/non-configured, SMTP fallback is tried. Both failing marks the outbox row `failed` and schedules exponential retry (up to 5 attempts: 1, 2, 4, 8, 16 min). After 5 failures an audit record is written.

10. **Channel permission replace-on-update**: `PATCH /channels/:id` does a full delete + re-insert of all `channel_permissions` rows — there is no partial update. Every permission entry must specify either `userId` or `role` (not neither).

11. **File storage path traversal guard**: `LocalStorageDriver.resolveStoragePath` checks the resolved path starts with the configured root. However, it checks both `\` and `/` separators — this is a Windows/POSIX dual-mode guard.

12. **Chat attachment validation**: The file must already be uploaded to `file_objects` with `owner_type = 'chat'`, `owner_id = <chatId>`, and `purpose` in `('chat_attachment', 'chat_voice')` before `sendMessage` can reference it. Cross-chat attachment reuse is prevented.

13. **Unread count computed inline**: The `listChats` query computes unread count as a subquery per chat row rather than a materialized counter — no denormalization, but potentially heavy on chats with large message history at scale.

14. **Message edit restricted**: Only `message_type = 'text'` messages without attachments can be edited. Voice and file messages are immutable after send.

15. **Reaction dedup**: `message_reactions` has a unique constraint `(message_id, user_id, emoji)`; the insert uses `ON CONFLICT DO NOTHING` — no error on double-tap.
