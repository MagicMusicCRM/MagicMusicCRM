# Flutter Messenger — Production-Readiness Audit Inventory

## 1. Overview

The messenger is the central feature of MagicMusicCRM. It is a Telegram-style chat system built entirely in a single large screen (`MessengerScreen`) plus a supporting layer of widgets, services, and providers. The same screen adapts to every role: `client`, `teacher`, `manager`, `admin`, `system_admin`. Staff roles get a full CRM navigation rail/bottom-bar alongside the chat; clients only see the chat shell.

Realtime delivery is Socket.IO via `MagicRealtimeService`. File storage uses a private backend with token-based download URLs. The service layer is fully REST-based (`MagicMessengerService`, `ChatAttachmentService`, `MagicCrmService`).

There is a secondary, legacy `AdminChatDashboard` widget that pre-dates `MessengerScreen` and is still used in the old admin flow. It duplicates a significant portion of the messenger logic.

---

## 2. Features

### 2.1 Chat List
- Load up to 100 chats via `GET /messenger/chats` (RPC `get_recent_chats_v3`), channels, and (for clients) the administration chat in parallel on mount.
- Per-item: unread badge count, last message preview, timestamp, mute indicator, pinned-chat indicator, group status icon (answered/unanswered for admin/manager).
- Sort: pinned chats first, then by `_last_message_time` descending.
- Filter: text search by display name on the client side.
- Pull-to-refresh reloads the full chat list.
- 30-second timeout on the load; failure silently clears the loading spinner.
- Deep-link / notification navigation: `messengerNavigationProvider` stores a pending `{partnerId, groupChatId}`; resolved after chat list loads or retried if list is empty.
- Hamburger menu: Profile, toggle dark/light theme, Sign out.
- Client role: "My School" shortcut button opens `ClientPortalScreen`.
- Staff role (manager/admin): "New Group" button opens `CreateGroupChatDialog`.

### 2.2 Conversation / Chat View
- Header: avatar, name, online/offline subtitle (direct), "Group chat" (group), "Channel" (channel), back button (mobile), pinned-message icon, CRM actions popup (staff, direct only), search toggle.
- Presence banner: amber strip shows "Собеседник в сети" when partner's presence is online (direct chats only).
- Typing indicator: "Пользователь печатает..." displayed at bottom of message list when remote user is typing; clears on `typing.stop` event.
- Date separator widget inserted between messages on day boundaries.
- Message list: `ListView.builder` with `GlobalObjectKey` per message for jump-to support; `ScrollController` auto-scrolls to bottom when user is near bottom.
- Scroll-to-bottom FAB with unread-message badge shown when user scrolls up; badge increments per new real-time message received while scrolled away.
- Optimistic UI: text messages appear immediately with `_pending: true` marker ("отправка" shown in timestamp); replaced by server response on success or removed on failure.
- Pinned messages bar: top strip shows most-recent pin's content; tap jumps to that message; "X" hides bar per-chat (stored in `_hiddenPinnedBars` Set, ephemeral/in-memory only); button in header to restore hidden bar.
- Pinned messages dialog: shows all pinned messages; tap to jump; unpin from dialog.
- In-chat search: header toggles search bar; client-side filter over loaded messages by text content; next/prev navigation with count display; matched message highlighted 2 seconds after jump.
- `ChatInfoDialog` side panel (desktop) or pushed route (mobile) on title tap.

### 2.3 Message Types
- **text**: plain UTF-8 content; edit (own, text-only), copy, reply, forward, delete, pin, react.
- **voice**: recorded audio uploaded as `.m4a` (AAC-LC, 44100 Hz, 128 kbps); displayed as `VoicePlayerWidget` with static waveform bars, play/pause, seek bar, elapsed/total time; lazy URL resolution via download-token API.
- **image / photo / file (image mime)**: uploaded and displayed inline as `FileAttachmentWidget`; full-screen `InteractiveViewer` on tap; zoom 0.5x–4x; lazy URL resolution.
- **file (non-image)**: displayed as a downloadable card with type-specific icon (PDF, DOCX, XLSX, MP4, MP3, generic); tap downloads to device and opens with `open_filex`; deduplicates filename on disk.
- Channel posts: `text` or `file` only; no reactions, no edit, no pin.

### 2.4 Sending Messages
- Text via `MessageInput` text field; desktop: Enter sends, Shift+Enter newlines; mobile: send button or `TextInputAction.send`.
- Emoji picker: in-app panel with 4 categories (Смайлы, Жесты, Сердца, Объекты), inserted at cursor position; dismisses keyboard when opened (KVA-172).
- Reply mode: shows quoted strip in input bar with cancel; `replyToId` sent to API.
- Edit mode: pre-fills input bar with current content; sends `PATCH /messenger/messages/:id`; edit indicator "изменено" shown on bubble.
- File attach: `FilePicker` (any type, single file, max 25 MB); shows `SendFileDialog` for optional caption before sending.
- Drag-and-drop: desktop drop target on the chat view; rejected for channels; enforces 25 MB limit.
- Voice record: replaces input bar with `VoiceRecorderWidget`; cancel deletes temp file; stop-and-send uploads bytes then sends `sendMessage` with `messageType: voice`.
- Forward: picker dialog lists all visible chats; confirm dialog before sending via `sendMessage` with `forwardedFromId`.
- Channel posts: staff (manager/admin) only; text only via the same `MessageInput` (no voice, no file upload currently wired).

### 2.5 Voice Recording
- Package: `record` (AudioRecorder); codec AAC-LC; saved to `getTemporaryDirectory()` as `.m4a`.
- Permission requested at start; failure shows snack and cancels.
- Animated pulsing red dot and MM:SS timer while recording.
- Temp file deleted after bytes are read (send path) or immediately (cancel path).

### 2.6 Voice Playback
- Package: `just_audio` (AudioPlayer).
- URL resolved lazily on first play via `POST /files/:id/download-token`.
- Static 24-bar waveform with progress highlight (bars left of cursor coloured, right dimmed).
- Shows MM:SS elapsed while playing, total duration at rest; resets on completion.
- Error snack on playback failure.

### 2.7 Attachments / Media
- Upload endpoint: `POST /files` (multipart); response is file object `id` (opaque string).
- Download URL: `POST /files/:id/download-token` returns short-lived token; URL assembled as `{baseUrl}/files/download/{token}`; in-flight deduplication via `_inFlightResolveUrls` map.
- Max size: 25 MB enforced client-side before upload.
- MIME detected via `lookupMimeType` (magic bytes + extension); determines `message_type` (image vs file).
- Image: inline preview max 250 × 280 dp with load progress; full-screen viewer on tap.
- Non-image: downloadable card; saves to Downloads or external storage; unique filename collision avoidance.
- Avatar uploads reuse same service (`uploadAvatar`), stored under `purpose: profile_avatar`.

### 2.8 Read State
- Unread count per chat loaded from `unread_count` field in chat list response.
- Optimistic clear: opening a chat sets `_unreadCounts[chatId] = 0` immediately; restored on server error.
- `POST /messenger/chats/:id/read` sends `lastReadMessageId` to server.
- Realtime `chat.updated` event with `readerId == _userId` also clears the badge.
- Outgoing message bubble shows single tick (sent) vs double tick (read) via `is_read` field; pending shows "отправка".

### 2.9 Reactions
- Eight quick-reactions in context menu: 👍 ❤️ 🔥 😂 😮 😢 🙏 💯
- Toggle: if user already reacted with that emoji, removes it; otherwise adds.
- Optimistic update applied immediately; reverted on server error.
- Server response is authoritative reactions list; UI reconciled from it.
- Displayed as grouped `{emoji} {count}` pills beneath message; tapping a pill toggles own reaction.

### 2.10 Pinning
- `POST /messenger/messages/:id/pin` / `DELETE /messenger/messages/:id/pin`
- Any participant can pin (no role gate in the UI).
- Pinned bar shows most-recent pin; multiple pins show count badge and open dialog.
- Jumping: `Scrollable.ensureVisible` with heuristic fallback (`index * 120 dp`).

### 2.11 Groups
- Create: `CreateGroupChatDialog` — staff only (manager/admin/system_admin); name field + searchable user list loaded from admin profiles API (all roles); multiselect with chip strip; `POST /messenger/groups`.
- Members managed via `PATCH /messenger/groups/:id/members` (`addUserIds`, `removeUserIds`).
- `ChatInfoDialog` members tab shows up to 6 with role labels; "+N more" text if overflow.
- Group status icon in chat list: amber `?` if `responded_at` is null (no staff response); green checkmark if responded. Tap shows responder name and timestamp.

### 2.12 Channels
- List: `GET /messenger/channels` merged into chat list with type `channel`.
- Create/edit: `POST /messenger/channels`, `PATCH /messenger/channels/:id` (staff only; title, description, permissions array).
- Posts: `GET /messenger/channels/:id/posts`, `POST /messenger/channels/:id/posts`.
- Channel post `is_read` always set `true` (no read tracking for channels).
- Access check: `GET /messenger/channels/:id/access` (`canRead`, `canWrite`).
- Permissions: `GET /messenger/channels/:id/permissions` (per-user `canRead`/`canWrite`/`role`).
- Only manager/admin can post; all users read-only by default; channel type shows different empty state icon and label.

### 2.13 Administration Chat (Client ↔ School)
- For clients: `ensureAdministrationChat()` creates/retrieves a `type: administration` chat with the school; displayed as "Администрация" with custom avatar from settings.
- For staff: the same chat appears in the regular chat list; `_adminIds` list populated from admin/manager/system_admin profiles to identify admin senders.
- Teacher role ignores messages to `receiver_id: null` (administration queue) when updating last message in chat list item.
- Legacy `AdminChatDashboard` widget: separate "В школу" tab (administration chat) and "Личные чаты" tab (per-student direct chats, list of client-role profiles); has its own `_ChatView` with text/voice/file send, read marking, realtime, lead-save action.

### 2.14 CRM Integration from Chat
- Staff (manager/admin) direct chat header has a `person_add` popup menu with:
  - "Открыть карточку клиента": `GET /crm/contacts/by-user/:userId` resolves studentId or leadId; navigates to `/student/:id` or opens `LeadDetailDialog`.
  - "Сохранить как лид": `POST /crm/contacts/save-from-chat` with `as: lead`; idempotent; success snack with "Открыть карточку" action.
  - "Сохранить как ученик": same endpoint with `as: student`.
- `AdminChatDashboard._ChatView` also has its own save-as-lead action (KVA-175).
- `GET /crm/leads/:id/chat-user` resolves messenger userId from a lead (used elsewhere in CRM to open chat from lead card).

### 2.15 Real-Time Subscriptions
- Socket.IO connection (`/realtime` path, WebSocket transport) authenticated with bearer access token.
- Events received: `message.created`, `message.updated`, `chat.updated`, `channel.post_created`, `typing.start`, `typing.stop`, `presence.updated`.
- Events emitted: `room.join` (chat room, user room), `room.leave`, `typing.start`, `typing.stop`, `presence.update`.
- Typing debounce: starts on first keystroke (≥2 s gap), auto-stops after 3 s of no input, stops on send.
- Presence: `updatePresence` called on chat join; `_PresenceBanner` watches `_onlineUsers` set.
- Reconnect: not handled explicitly; no reconnect logic in `MagicRealtimeService.connect()`.
- Local notifications: `NotificationService.showLocalNotification` shown for new messages in non-selected, non-muted chats.

### 2.16 ChatInfoDialog (Profile / Info Panel)
- Available for direct, group, and channel chat types.
- Header: collapsible `SliverAppBar` with large avatar (Hero animation), name, subtitle (email or member count), description/role.
- Action buttons: "Чат" (navigate back to conversation), "Заглушить/Включить" (mute toggle).
- Tabs: Media (3-column image grid, tap to full-screen view), Files (list with size and download), Links (extracted URLs from message content, tap to launch).
- Additional "Заметки" tab for direct chats when viewer is manager/admin: staff notes against the conversation partner's profile; CRUD via `MagicProfileAdminService.listProfileNotes` / `createProfileNote`.
- Channel editors (manager/admin): inline-editable name and description via text dialog.
- Group members preview (up to 6) with role labels.
- `_ResolvedNetworkImage`: lazy token-resolved image widget used in media grid.

### 2.17 Notifications
- `notification_service.dart` (local): shows local push notification on `message.created` for non-selected / non-muted chats.
- Notification payload: `{type: 'chat', id: chatId}`; navigated via `messengerNavigationProvider` on tap.
- Deep link deferred if chat list hasn't loaded yet; retried after list load.

### 2.18 Mute
- `PUT /messenger/chats/:id/mute` with `{isMuted: bool}`.
- Optimistic UI; reverted on error.
- Muted chats: no local notification shown; mute icon shown on chat list tile.
- Realtime `chat.updated` with `isMuted` field syncs mute state across sessions.

### 2.19 Profile Integration
- `ProfileScreen` embedded in chat list pane (desktop slide-in or `/profile` push on mobile).
- Current user profile loaded on bootstrap (`currentProfile()`); name shown in outgoing messages; userId used for self-identification.

### 2.20 Broadcast
- `BroadcastDialog.show(context)` accessible from `AdminChatDashboard` header (campaign icon).
- Sends a mass message to all or filtered users (implementation in `broadcast_dialog.dart`, not fully read but wired here).

---

## 3. Per-Role Behavior / Permissions

| Capability | client | teacher | manager | admin | system_admin |
|---|---|---|---|---|---|
| See chat list (all types) | Direct + admin chat only | Direct + group + channel | All | All | All |
| Create group chat | No | No | Yes | Yes | Yes |
| Create / edit channel | No | No | Yes | Yes | Yes |
| Post to channel | No | No | Yes | Yes | Yes |
| CRM "Save as lead/student" in chat | No | No | Yes | Yes | Yes |
| Open contact card from chat | No | No | Yes | Yes | Yes |
| Delete others' messages | No | No | Yes | Yes | Yes |
| Notes tab in ChatInfoDialog | No | No | Yes | Yes | Yes |
| Group status icon (answered?) | No | No | Yes | Yes | Yes |
| Admin chat dashboard (legacy) | No | No (no route) | Possibly | Yes | Yes |
| CRM navigation rail tabs | No | Chat + Schedule + Students | Chat + 4 tabs | Chat + 7 tabs | Chat + 7 tabs |
| "My School" button | Yes | No | No | No | No |
| See broadcast button | No | No | No | Yes | Yes |
| Resolve admin IDs for message attribution | Staff only | Staff only | Yes | Yes | Yes |
| Typing indicator visibility | Yes | Yes | Yes | Yes | Yes |
| Mute/unmute | Yes (except admin chat) | Yes | Yes | Yes | Yes |

`_isAdminRole` = `admin || system_admin`
`_isManagerOrAdminRole` = `admin || manager || system_admin`
`_isStaffRole` = all of the above + `teacher`

---

## 4. Data / Schema Touched

### Chat entities (REST)
- **Chat** (`/messenger/chats`): `id`, `type` (direct/group/administration), `title`, `partnerId`, `partner {firstName, lastName, email, avatarFileId}`, `lastMessageId`, `lastMessageContent`, `lastMessageCreatedAt`, `unreadCount`, `isMuted`, `createdBy`, `createdAt`, `updatedAt`.
- **Message** (`/messenger/chats/:id/messages`): `id`, `chatId`, `senderId`, `content`, `messageType` (text/voice/image/file), `attachmentFileId`, `attachmentName`, `attachmentFileName`, `attachmentSize`, `attachmentMimeType`, `voiceDurationMs`, `replyToId`, `forwardedFromId`, `pinnedBy`, `pinnedAt`, `isRead`, `isEdited`, `deletedAt`, `createdAt`, `updatedAt`, `sender {id, firstName, lastName}`, `reactions [{user_id, emoji}]`.
- **Group** (`/messenger/groups`): `id`, `name`, `memberUserIds`, `responded_at`, `first_responder {first_name, last_name}`, `avatar_url`.
- **Channel** (`/messenger/channels`): `id`, `title`, `description`, `createdBy`, `createdAt`, `updatedAt`.
- **ChannelPermission** (`/messenger/channels/:id/permissions`): `id`, `channelId`, `userId`, `role`, `canRead`, `canWrite`, `user {id, firstName, lastName, email}`.
- **ChannelPost** (`/messenger/channels/:id/posts`): `id`, `channelId`, `authorId`, `content`, `attachmentFileId`, `publishedAt`, `updatedAt`.
- **ChatMember** (`/messenger/chats/:id/members`): `profileId`, `userId`, `email`, `role`, `firstName`, `lastName`, `phone`, `avatarFileId`, `joinedAt`, `isCurrentUser`.

### File storage
- **File** (`/files`): `id` (opaque), `purpose` (chat_attachment/chat_voice/profile_avatar), `ownerType` (chat), `ownerId` (chatId), `mimeType`, `sizeBytes`, `originalFileName`.
- Download token: `POST /files/:id/download-token` → `{token}`.

### CRM (chat-integrated)
- `/crm/contacts/by-user/:userId` → `{studentId, leadId}`.
- `/crm/contacts/save-from-chat` body: `{userId, as: lead|student}` → `{leadId|studentId, created}`.
- `/crm/leads/:id/chat-user` → `{userId, name}`.

### Settings
- `/settings` — `getAdminChatAvatar()` / `updateAdminChatAvatar()` for the administration chat custom avatar.

### Profile notes
- `listProfileNotes(profileId)`, `createProfileNote({profileId, body})` via `MagicProfileAdminService`.

### Realtime (Socket.IO events)
- Inbound: `message.created`, `message.updated`, `chat.updated`, `channel.post_created`, `typing.start`, `typing.stop`, `presence.updated`.
- Outbound: `room.join {roomType, roomId}`, `room.leave {roomId}`, `typing.start {chatId}`, `typing.stop {chatId}`, `presence.update {status}`.

---

## 5. Notable Business Rules / Edge Cases

1. **Administration chat auto-creation**: `ensureAdministrationChat()` is called for every non-staff user on chat list load; this creates the chat if it doesn't exist server-side. The client therefore always has exactly one "school" chat. Teachers do NOT call this — they are filtered out via `_isStaffRole`.

2. **Lead auto-creation is manual, not automatic**: There is NO automatic lead creation when a new user writes to the system. Staff must manually click "Сохранить как лид" from the chat header. The code comment history (KVA-175) confirms this is intentional.

3. **Administration chat `_item_type` mapping**: The backend returns `type: administration` but the client remaps it to `direct` for all display/routing logic. The raw type is preserved in `raw_type` for the avatar fallback.

4. **Teacher chat list filtering**: When `_updateChatItemLastMessage` runs for a non-group message with `receiver_id == null`, teacher role skips updating the chat item. This prevents the administration queue from appearing to update in the teacher's chat list.

5. **Channel post read state**: Always forced to `is_read: true` both in the legacy mapper and realtime normalizer. Channels have no per-user read tracking.

6. **Pinned messages are derived from loaded messages only**: `_fetchPinnedMessages()` filters `_messages` where `pinned_at != null`. If a message was pinned but isn't in the current 100-message window, it won't appear in the pinned bar. No separate fetch for pinned messages.

7. **Voice duration stored client-side only on send**: The `voice_duration_ms` value is injected into the local optimistic/sent message from `_durationSeconds * 1000` (integer seconds, not true milliseconds). On subsequent loads it comes from `voiceDurationMs` field in the API response or attachment metadata.

8. **File size limit is client-enforced only**: The 25 MB cap (`ChatAttachmentService.maxFileSizeBytes`) is checked before upload in both the picker and drag-drop paths. No server-side enforcement is visible in the Flutter layer.

9. **Reaction optimistic update + revert**: Reactions use a full optimistic replace, not a delta. If two users react simultaneously during a network failure, the revert might overwrite a concurrent reaction from another user (stale read scenario).

10. **Message delete is own-only for non-admin**: `_deleteMessage` checks `isMe` and returns an error snack if false. The API call uses `mode: 'own'`; admins/managers get `mode: 'moderated'` only if `canDeleteOthers` is true (`admin || manager || system_admin`) — but the current UI guard (`!isMe`) blocks even admins from the delete option on others' messages in `MessengerScreen`. The `canDeleteOthers` flag is correctly passed to `MessageBubble` and does enable the menu item there.

11. **Deep-link race condition**: If `_checkDeepLink` runs before `_chatItems` is populated, it stores the pending navigation and retries after load. However if `_loadChatList` fails with a timeout, the deep link is never cleared and the navigation state leaks.

12. **Realtime reconnect not implemented**: `MagicRealtimeService.connect()` creates one Socket.IO connection; there is no reconnect/backoff logic. A network interruption will silently drop realtime delivery until the screen is disposed and recreated.

13. **`_adminIds` built from cached profile list**: Staff load admin/manager/system_admin profiles once on bootstrap to tag senders as "Администрация". If a new admin is added server-side during the session, the client won't reflect it until restart.

14. **Duplicate `AdminChatDashboard`**: The legacy `AdminChatDashboard` (`lib/features/admin/presentation/widgets/admin_chat_dashboard.dart`) has its own independent chat view with send-text, send-voice, send-file, realtime, and read-marking — all implemented separately from `MessengerScreen`. Two code paths must be maintained in sync.

15. **In-chat search is client-side and window-limited**: Search operates only on the currently loaded 100-message window. Messages outside the window are not searched.

16. **Pinned bar hidden state is ephemeral**: `_hiddenPinnedBars` is a `Set<String>` in widget state; it resets on every hot restart / app reopen. The hidden state is not persisted.

17. **Group chat "responded" status visible only to manager/admin**: The `_buildStatusIcon` method returns null for non-`_isManagerOrAdminRole` roles; clients and teachers don't see the amber/green response indicator.
