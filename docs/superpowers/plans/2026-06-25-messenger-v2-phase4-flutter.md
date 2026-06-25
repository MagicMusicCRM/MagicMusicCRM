# Messenger v2 — Phase 4: Flutter Client — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.
> The Flutter messenger is a single large screen `lib/features/messenger/presentation/screens/messenger_screen.dart` (~3300 lines, all state via `setState`, no typed models — chats/messages flow as `Map<String,dynamic>` through the `_legacyChat`/`_legacyMessage` mappers in `lib/core/services/magic_messenger_service.dart`). For tasks that edit the screen, READ the named method first and integrate at the indicated point. Logic that the spec wants tested (folder bucketing, unread badges, chat.created/removed/updated list mutations) is extracted into a **pure, widget-free helper** (`lib/features/messenger/inbox_logic.dart`) so it can be unit-tested; the screen delegates to it.

**Goal:** Consume the Phase 3 backend in the Flutter client — a staff "Администрация" inbox with **Лиды/Ученики/Архив** folders + live per-folder unread badges, assignment ("Взять в работу"/"Передать"), per-staff archive, realtime `chat.created`/`chat.removed`/`chat.updated` handling, a masked unified "Администрация" view for clients, group "Выйти из группы" + add-members, and no new-direct-chat entry for clients.

**Architecture:** Add 5 service methods + new `_legacyChat` fields (Task 1); add realtime connection hooks for `chat.created`/`chat.removed` (Task 2); extract a pure inbox-logic helper for folders/badges/list-reducers with full unit tests (Task 3); wire folder UI (Task 4), realtime handlers (Task 5), assignment UI (Task 6), archive action (Task 7), group leave/add (Task 8), and verify the client view (Task 9).

**Tech Stack:** Flutter, Riverpod, Dio (via `MagicApiClient`), Socket.IO (`MagicRealtimeService`). Tests: `flutter test` with the existing fake-Dio adapter (`test/core/services/magic_messenger_service_test.dart`) and fake-transport (`test/core/services/magic_realtime_service_test.dart`) patterns.

## Global Constraints

- **Locked design (do not re-litigate — from spec §2/§6):** staff "Администрация" inbox labeled by client name; assignment ("Взять в работу" / "Передать") visible to all staff, assignee replies, manager may reassign; client sees a single unified **"Администрация"**, staff identities masked; clients have **no 1-on-1 chats** and **no "new direct chat" entry**; groups staff-managed, **any member may leave**; folders organize the admin inbox: **Лиды / Ученики / Архив** (Архив per-staff), each with a **live unread badge**.
- **Server already masks staff identity** (Phase 3): masked sender arrives as `sender: { id: null, name: 'Администрация', firstName: null, lastName: null, email: null }`. The client must render whatever the server sends and must NOT add its own un-masking. No client-side identity logic.
- **Backend routes (Phase 3, exact):** `POST /messenger/chats/:id/assign` body `{ userId? }` · `POST /messenger/chats/:id/unassign` · `POST /messenger/chats/:id/archive` · `POST /messenger/chats/:id/unarchive` · `POST /messenger/groups/:id/leave`. Existing: `PATCH /messenger/groups/:id/members` body `{ addUserIds?, removeUserIds? }`.
- **Server chat-summary JSON fields (Phase 3 `toChatSummaryDto`, camelCase):** existing `id, type, title, unreadCount, isMuted, lastMessage…` PLUS new `ownerName` (string|null), `assignedTo` (`{ id, name }`|null), `folder` (`'leads'|'students'|'archive'`), `archived` (bool). `type` may be `'administration'` (the mapper preserves it in `raw_type`).
- **Realtime event contract (Phase 3 spec §5):** `chat.created` → full summary to `user:{id}` (insert) · `chat.removed` `{ id }` → `user:{id}` (drop) · `chat.updated` → `chat:{id}` + `user:{id}` + `admin-inbox`, **partial** payloads (patch only the fields present: `assignedTo`, `archived`, last-message preview). Rooms restored on reconnect.
- **Role helpers already in the screen:** `_isStaffRole` = admin/system_admin/manager/teacher; `_isManagerOrAdminRole` = admin/system_admin/manager. **Folder UI + assignment UI + archive action are gated on `_isManagerOrAdminRole`** (the admin-inbox owners); clients/teachers do not see them. Client = `widget.role == 'client'`.
- **No l10n system** — all strings are inline Russian literals. Add new labels inline: `'Лиды'`, `'Ученики'`, `'Архив'`, `'Взять в работу'`, `'Передать'`, `'Снять с работы'`, `'Архивировать'`, `'Вернуть из архива'`, `'Выйти из группы'`, `'Добавить участников'`.
- **No `git add -A`** — the working tree carries an intentionally-untracked `dist/`. Commit each task's specific files only. Commit after each task with a `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>` trailer.
- Run `flutter analyze` clean and the focused `flutter test <file>` green before each commit; run the full `flutter test` at the end of the last task.

---

### Task 1: Service methods + chat-summary fields

**Files:**
- Modify: `lib/core/services/magic_messenger_service.dart` (add 5 methods; extend `_legacyChat`)
- Test: `test/core/services/magic_messenger_service_test.dart`

**Interfaces (Produces):**
- `Future<Map<String,dynamic>> assignChat(String chatId, {String? userId})` → `POST /messenger/chats/:id/assign`
- `Future<Map<String,dynamic>> unassignChat(String chatId)` → `POST /messenger/chats/:id/unassign`
- `Future<Map<String,dynamic>> archiveChat(String chatId)` → `POST /messenger/chats/:id/archive`
- `Future<Map<String,dynamic>> unarchiveChat(String chatId)` → `POST /messenger/chats/:id/unarchive`
- `Future<void> leaveGroup(String chatId)` → `POST /messenger/groups/:id/leave`
- `_legacyChat` output gains: `folder` (String?), `assigned_to` (Map? `{id,name}`), `archived` (bool), `owner_name` (String?).

- [ ] **Step 1: Failing tests** — append to the existing test file, reusing `_FakeAdapter`/`_FakeResponse`/`_client`:

```dart
test('assignChat self-claim posts to assign with empty body', () async {
  final adapter = _FakeAdapter([
    _FakeResponse('/messenger/chats/c1/assign', 200, {'id': 'c1', 'type': 'administration'}),
  ]);
  final svc = MagicMessengerService(_client(adapter));
  await svc.assignChat('c1');
  final req = adapter.captured.single;
  expect(req.method, 'POST');
  expect(req.path, '/messenger/chats/c1/assign');
  expect(req.body['userId'], isNull);
});

test('assignChat with userId posts the target', () async {
  final adapter = _FakeAdapter([
    _FakeResponse('/messenger/chats/c1/assign', 200, {'id': 'c1'}),
  ]);
  final svc = MagicMessengerService(_client(adapter));
  await svc.assignChat('c1', userId: 'staff-9');
  expect(adapter.captured.single.body['userId'], 'staff-9');
});

test('archiveChat / unarchiveChat / unassignChat hit the right routes', () async {
  final adapter = _FakeAdapter([
    _FakeResponse('/messenger/chats/c1/archive', 200, {'id': 'c1'}),
    _FakeResponse('/messenger/chats/c1/unarchive', 200, {'id': 'c1'}),
    _FakeResponse('/messenger/chats/c1/unassign', 200, {'id': 'c1'}),
  ]);
  final svc = MagicMessengerService(_client(adapter));
  await svc.archiveChat('c1');
  await svc.unarchiveChat('c1');
  await svc.unassignChat('c1');
  expect(adapter.captured.map((r) => r.path).toList(), [
    '/messenger/chats/c1/archive',
    '/messenger/chats/c1/unarchive',
    '/messenger/chats/c1/unassign',
  ]);
  expect(adapter.captured.every((r) => r.method == 'POST'), isTrue);
});

test('leaveGroup posts to groups/:id/leave', () async {
  final adapter = _FakeAdapter([
    _FakeResponse('/messenger/groups/g1/leave', 200, {'success': true}),
  ]);
  final svc = MagicMessengerService(_client(adapter));
  await svc.leaveGroup('g1');
  expect(adapter.captured.single.path, '/messenger/groups/g1/leave');
});

test('_legacyChat surfaces folder, assignedTo, archived, ownerName', () async {
  final adapter = _FakeAdapter([
    _FakeResponse('/messenger/chats', 200, {
      'items': [
        {
          'id': 'c1', 'type': 'administration', 'title': 'Администрация',
          'unreadCount': 2, 'isMuted': false,
          'ownerName': 'Иван Петров', 'folder': 'students', 'archived': false,
          'assignedTo': {'id': 'staff-9', 'name': 'Анна'},
        }
      ]
    }),
  ]);
  final svc = MagicMessengerService(_client(adapter));
  final chats = await svc.listChats();
  final c = chats.single;
  expect(c['folder'], 'students');
  expect(c['archived'], false);
  expect(c['owner_name'], 'Иван Петров');
  expect((c['assigned_to'] as Map)['name'], 'Анна');
});
```

(If `_FakeAdapter` exposes captured requests under a different name than `captured`/`.path`/`.method`/`.body`, READ the harness and adjust these assertions to its actual API — keep the same intent.)

- [ ] **Step 2: Run → fail.** `flutter test test/core/services/magic_messenger_service_test.dart`
- [ ] **Step 3: Add the 5 methods** (place near `sendMessage`/`updateGroupMembers`, matching the existing POST/PATCH/DELETE style):

```dart
Future<Map<String, dynamic>> assignChat(String chatId, {String? userId}) async {
  final data = <String, dynamic>{};
  if (userId != null) data['userId'] = userId;
  final response = await _api.post<Map<String, dynamic>>(
    '/messenger/chats/$chatId/assign', data: data);
  return _legacyChat(response);
}

Future<Map<String, dynamic>> unassignChat(String chatId) async {
  final response = await _api.post<Map<String, dynamic>>(
    '/messenger/chats/$chatId/unassign', data: <String, dynamic>{});
  return _legacyChat(response);
}

Future<Map<String, dynamic>> archiveChat(String chatId) async {
  final response = await _api.post<Map<String, dynamic>>(
    '/messenger/chats/$chatId/archive', data: <String, dynamic>{});
  return _legacyChat(response);
}

Future<Map<String, dynamic>> unarchiveChat(String chatId) async {
  final response = await _api.post<Map<String, dynamic>>(
    '/messenger/chats/$chatId/unarchive', data: <String, dynamic>{});
  return _legacyChat(response);
}

Future<void> leaveGroup(String chatId) async {
  await _api.post<Map<String, dynamic>>(
    '/messenger/groups/$chatId/leave', data: <String, dynamic>{});
}
```

(If `_legacyChat` requires a non-null shape and an endpoint may return `{id}` only, ensure `_legacyChat` tolerates missing fields — it already defaults most. Verify by reading it.)

- [ ] **Step 4: Extend `_legacyChat`** — in its returned map add:

```dart
'folder': item['folder'],
'assigned_to': item['assignedTo'],     // {id, name} or null
'archived': item['archived'] == true,
'owner_name': item['ownerName'],
```

- [ ] **Step 5: Run → pass; analyze.** `flutter test test/core/services/magic_messenger_service_test.dart && flutter analyze lib/core/services/magic_messenger_service.dart`
- [ ] **Step 6: Commit** (`feat(messenger): client service methods for assign/archive/leave + summary v2 fields`).

---

### Task 2: Realtime connection hooks for chat.created / chat.removed

**Files:**
- Modify: `lib/core/services/magic_realtime_service.dart` (`MagicRealtimeConnection`)
- Test: `test/core/services/magic_realtime_service_test.dart`

**Interfaces (Produces):** on `MagicRealtimeConnection`: `void onChatCreated(void Function(Map<String,dynamic>) handler)` and `void onChatRemoved(void Function(Map<String,dynamic>) handler)`, registered the same way `onMessageCreated`/`onChatUpdated` are (an `_onMap('chat.created', …)` / `_onMap('chat.removed', …)` subscription). `chat.updated` already has `onChatUpdated`.

- [ ] **Step 1: Failing tests** — append, reusing `_FakeTransport`/`_FakeTransportFactory` and the existing "maps socket payloads" style:

```dart
test('onChatCreated receives chat.created payloads', () async {
  final transport = _FakeTransport();
  final svc = _serviceWith(transport);            // mirror the existing helper that builds the service+connection
  final conn = await svc.connect();
  Map<String, dynamic>? got;
  conn.onChatCreated((p) => got = p);
  transport.fire('chat.created', {'id': 'c9', 'type': 'group', 'title': 'Группа'});
  expect(got!['id'], 'c9');
  expect(got!['type'], 'group');
});

test('onChatRemoved receives chat.removed payloads', () async {
  final transport = _FakeTransport();
  final svc = _serviceWith(transport);
  final conn = await svc.connect();
  String? removedId;
  conn.onChatRemoved((p) => removedId = p['id'] as String?);
  transport.fire('chat.removed', {'id': 'c9'});
  expect(removedId, 'c9');
});
```

(READ the existing test to reuse its exact service-construction helper and the `onMessageCreated` test shape; adapt `_serviceWith` to whatever the file already uses.)

- [ ] **Step 2: Run → fail.** `flutter test test/core/services/magic_realtime_service_test.dart`
- [ ] **Step 3: Implement** — in `MagicRealtimeConnection`, mirror the existing `onChatUpdated` registration:

```dart
void onChatCreated(void Function(Map<String, dynamic>) handler) =>
    _onMap('chat.created', handler);
void onChatRemoved(void Function(Map<String, dynamic>) handler) =>
    _onMap('chat.removed', handler);
```

(Use the real private subscription helper name found in the file — likely `_onMap`/`_on`. Match `onChatUpdated` exactly.)

- [ ] **Step 4: Run → pass; analyze.** `flutter test test/core/services/magic_realtime_service_test.dart && flutter analyze lib/core/services/magic_realtime_service.dart`
- [ ] **Step 5: Commit** (`feat(realtime): chat.created/chat.removed connection hooks`).

---

### Task 3: Pure inbox-logic helper (folders, badges, list reducers)

**Files:**
- Create: `lib/features/messenger/inbox_logic.dart`
- Test: `test/features/messenger/inbox_logic_test.dart`

**Interfaces (Produces):** widget-free pure functions over the `Map<String,dynamic>` chat items the screen already holds (`_chatItems`) and the `_unreadCounts` map:

```dart
// lib/features/messenger/inbox_logic.dart
enum InboxFolder { leads, students, archive }

const inboxFolderApiValues = {
  InboxFolder.leads: 'leads',
  InboxFolder.students: 'students',
  InboxFolder.archive: 'archive',
};

/// An administration chat's folder. Non-administration chats (groups/channels/
/// direct) return null (they live in a separate section, not the folders).
InboxFolder? folderOf(Map<String, dynamic> chat) {
  final raw = (chat['raw_type'] ?? chat['type']) as String?;
  if (raw != 'administration') return null;
  switch (chat['folder']) {
    case 'archive': return InboxFolder.archive;
    case 'students': return InboxFolder.students;
    case 'leads': return InboxFolder.leads;
    default: return InboxFolder.leads;   // no-link / null → Лиды (spec §2.5)
  }
}

/// Administration chats in the given folder, preserving input order.
List<Map<String, dynamic>> chatsInFolder(
    List<Map<String, dynamic>> chats, InboxFolder folder) =>
  chats.where((c) => folderOf(c) == folder).toList();

/// Non-administration chats (groups/channels/direct) — the separate section.
List<Map<String, dynamic>> nonInboxChats(List<Map<String, dynamic>> chats) =>
  chats.where((c) => folderOf(c) == null).toList();

/// Sum of unread for the administration chats in a folder.
int unreadForFolder(List<Map<String, dynamic>> chats,
    Map<String, int> unreadCounts, InboxFolder folder) =>
  chatsInFolder(chats, folder)
      .fold(0, (sum, c) => sum + (unreadCounts[c['id']] ?? 0));

/// Insert or replace a chat by id (chat.created). New chats go to the front.
List<Map<String, dynamic>> upsertChat(
    List<Map<String, dynamic>> chats, Map<String, dynamic> incoming) {
  final id = incoming['id'];
  final idx = chats.indexWhere((c) => c['id'] == id);
  if (idx == -1) return [incoming, ...chats];
  final next = [...chats];
  next[idx] = {...chats[idx], ...incoming};
  return next;
}

/// Remove a chat by id (chat.removed).
List<Map<String, dynamic>> removeChat(
    List<Map<String, dynamic>> chats, String id) =>
  chats.where((c) => c['id'] != id).toList();

/// Apply a PARTIAL chat.updated payload: patch only the keys present
/// (assigned_to/archived/folder/last_message…), leave others intact. Maps the
/// server's camelCase realtime keys (assignedTo/archived/folder) onto the
/// _legacyChat snake keys the list holds. Returns the list unchanged if the
/// chat is not present (the screen will reload for unknown chats).
List<Map<String, dynamic>> patchChat(
    List<Map<String, dynamic>> chats, Map<String, dynamic> payload) {
  final id = payload['id'];
  final idx = chats.indexWhere((c) => c['id'] == id);
  if (idx == -1) return chats;
  final patch = <String, dynamic>{};
  if (payload.containsKey('assignedTo')) patch['assigned_to'] = payload['assignedTo'];
  if (payload.containsKey('archived')) patch['archived'] = payload['archived'] == true;
  if (payload.containsKey('folder')) patch['folder'] = payload['folder'];
  final next = [...chats];
  next[idx] = {...chats[idx], ...patch};
  return next;
}

/// Display name for an administration chat's assignee chip, or null.
String? assigneeName(Map<String, dynamic> chat) {
  final a = chat['assigned_to'];
  if (a is Map && (a['name'] as String?)?.trim().isNotEmpty == true) {
    return (a['name'] as String).trim();
  }
  return null;
}
```

- [ ] **Step 1: Failing tests** — create `test/features/messenger/inbox_logic_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/features/messenger/inbox_logic.dart';

Map<String, dynamic> admin(String id, {String? folder, int? unused, Map? assignedTo, bool archived = false}) =>
  {'id': id, 'type': 'administration', 'raw_type': 'administration',
   'folder': folder, 'archived': archived, 'assigned_to': assignedTo};

void main() {
  test('folderOf buckets administration chats; null folder → leads', () {
    expect(folderOf(admin('a', folder: 'students')), InboxFolder.students);
    expect(folderOf(admin('a', folder: 'leads')), InboxFolder.leads);
    expect(folderOf(admin('a', folder: null)), InboxFolder.leads);
    expect(folderOf(admin('a', folder: 'archive')), InboxFolder.archive);
  });

  test('folderOf returns null for non-administration chats', () {
    expect(folderOf({'id': 'g', 'type': 'group', 'raw_type': 'group'}), isNull);
  });

  test('unreadForFolder sums only that folder', () {
    final chats = [admin('a', folder: 'leads'), admin('b', folder: 'students'), admin('c', folder: 'leads')];
    final unread = {'a': 2, 'b': 5, 'c': 1};
    expect(unreadForFolder(chats, unread, InboxFolder.leads), 3);
    expect(unreadForFolder(chats, unread, InboxFolder.students), 5);
    expect(unreadForFolder(chats, unread, InboxFolder.archive), 0);
  });

  test('upsertChat inserts new at front and merges existing', () {
    final chats = [admin('a', folder: 'leads')];
    final inserted = upsertChat(chats, admin('b', folder: 'students'));
    expect(inserted.first['id'], 'b');
    final merged = upsertChat(inserted, {'id': 'a', 'folder': 'students'});
    expect(merged.firstWhere((c) => c['id'] == 'a')['folder'], 'students');
    expect(merged.length, 2);
  });

  test('removeChat drops by id', () {
    expect(removeChat([admin('a'), admin('b')], 'a').map((c) => c['id']), ['b']);
  });

  test('patchChat applies only present keys and maps camelCase', () {
    final chats = [admin('a', folder: 'leads', archived: false)];
    final p1 = patchChat(chats, {'id': 'a', 'archived': true});
    expect(p1.single['archived'], true);
    expect(p1.single['folder'], 'leads'); // untouched
    final p2 = patchChat(chats, {'id': 'a', 'assignedTo': {'id': 's', 'name': 'Анна'}});
    expect((p2.single['assigned_to'] as Map)['name'], 'Анна');
    expect(patchChat(chats, {'id': 'zzz', 'archived': true}), same(chats));
  });

  test('assigneeName returns trimmed name or null', () {
    expect(assigneeName(admin('a', assignedTo: {'id': 's', 'name': 'Анна'})), 'Анна');
    expect(assigneeName(admin('a', assignedTo: null)), isNull);
    expect(assigneeName(admin('a', assignedTo: {'id': 's', 'name': '  '})), isNull);
  });
}
```

- [ ] **Step 2: Run → fail.** `flutter test test/features/messenger/inbox_logic_test.dart`
- [ ] **Step 3: Create `lib/features/messenger/inbox_logic.dart`** with the code in the Interfaces block above.
- [ ] **Step 4: Run → pass; analyze.** `flutter test test/features/messenger/inbox_logic_test.dart && flutter analyze lib/features/messenger/inbox_logic.dart`
- [ ] **Step 5: Commit** (`feat(messenger): pure inbox-logic helper (folders, badges, list reducers)`).

---

### Task 4: Folder UI in the chat list (staff)

**Files:**
- Modify: `lib/features/messenger/presentation/screens/messenger_screen.dart` (`_buildChatList`, ~line 2006; add folder state field)
- Test: `test/features/messenger/inbox_folder_widget_test.dart` (widget test of the folder bar)

**Interfaces (Consumes):** `inbox_logic.dart` (`InboxFolder`, `chatsInFolder`, `nonInboxChats`, `unreadForFolder`).

- [ ] **Step 1: Failing widget test** — render a minimal harness that shows the folder bar over a small chat list and asserts segmentation + badge. Because the full screen is heavy, extract the folder bar into a small widget `InboxFolderBar` inside `inbox_logic.dart`'s sibling file `lib/features/messenger/widgets/inbox_folder_bar.dart` so it is testable in isolation:

```dart
// test/features/messenger/inbox_folder_widget_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/features/messenger/inbox_logic.dart';
import 'package:magic_music_crm/features/messenger/widgets/inbox_folder_bar.dart';

void main() {
  testWidgets('folder bar shows three folders with unread badges', (tester) async {
    InboxFolder? picked;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: InboxFolderBar(
      selected: InboxFolder.leads,
      unread: const {InboxFolder.leads: 3, InboxFolder.students: 0, InboxFolder.archive: 1},
      onSelected: (f) => picked = f,
    ))));
    expect(find.text('Лиды'), findsOneWidget);
    expect(find.text('Ученики'), findsOneWidget);
    expect(find.text('Архив'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);   // leads badge
    await tester.tap(find.text('Ученики'));
    expect(picked, InboxFolder.students);
  });
}
```

- [ ] **Step 2: Run → fail.** `flutter test test/features/messenger/inbox_folder_widget_test.dart`
- [ ] **Step 3: Create `lib/features/messenger/widgets/inbox_folder_bar.dart`** — a `StatelessWidget` with three segmented buttons (`Лиды`/`Ученики`/`Архив`), each showing a small unread badge when `unread[folder] > 0`, calling `onSelected(folder)`. Use the app's existing gold accent for the badge (match `chat_list_tile.dart` badge styling). Signature:

```dart
class InboxFolderBar extends StatelessWidget {
  final InboxFolder selected;
  final Map<InboxFolder, int> unread;
  final ValueChanged<InboxFolder> onSelected;
  const InboxFolderBar({super.key, required this.selected, required this.unread, required this.onSelected});
  // ...
}
```

- [ ] **Step 4: Run → pass.** `flutter test test/features/messenger/inbox_folder_widget_test.dart`
- [ ] **Step 5: Wire into `_buildChatList`** — READ `_buildChatList` (line ~2006) first. Add a state field `InboxFolder _selectedFolder = InboxFolder.leads;`. When `_isManagerOrAdminRole` is true: render `InboxFolderBar` above the `ListView.builder`, with `unread:` computed via `unreadForFolder(_chatItems, _unreadCounts, f)` for each folder; render the administration chats via `chatsInFolder(_chatItems, _selectedFolder)` and the groups/channels via `nonInboxChats(_chatItems)` in their existing separate section. For non-manager/admin roles, render the list exactly as today (no folder bar). `onSelected:` does `setState(() => _selectedFolder = f)`.
- [ ] **Step 6: Analyze + run inbox tests.** `flutter analyze lib/features/messenger && flutter test test/features/messenger/`
- [ ] **Step 7: Commit** (`feat(messenger): Лиды/Ученики/Архив folder bar with live unread badges (staff)`).

---

### Task 5: Realtime chat.created / chat.removed / chat.updated handlers in the screen

**Files:**
- Modify: `lib/features/messenger/presentation/screens/messenger_screen.dart` (`_connectRealtime`/`_onRealtimeReconnected` ~line 618; `_handleRealtimeChatUpdated` ~line 716; add two handlers)

**Interfaces (Consumes):** `inbox_logic.dart` (`upsertChat`, `removeChat`, `patchChat`) and the Task 2 hooks (`onChatCreated`, `onChatRemoved`).

- [ ] **Step 1: Subscribe to the new events** — READ `_connectRealtime` (where `onMessageCreated`/`onChatUpdated` are wired). Add:

```dart
connection.onChatCreated(_handleRealtimeChatCreated);
connection.onChatRemoved(_handleRealtimeChatRemoved);
```

- [ ] **Step 2: Add the handlers** (mirror the setState style of `_handleRealtimeChatUpdated`):

```dart
void _handleRealtimeChatCreated(Map<String, dynamic> payload) {
  if (!mounted) return;
  final mapped = _legacyChatFromRealtime(payload); // see Step 3
  setState(() => _chatItems = upsertChat(_chatItems, mapped));
}

void _handleRealtimeChatRemoved(Map<String, dynamic> payload) {
  if (!mounted) return;
  final id = payload['id'] as String?;
  if (id == null) return;
  setState(() {
    _chatItems = removeChat(_chatItems, id);
    _unreadCounts.remove(id);
  });
}
```

- [ ] **Step 3: Normalize the chat.created summary** — the realtime `chat.created` payload is a server `toChatSummaryDto` (camelCase), not run through `_legacyChat`. Add a tiny adapter so it matches the `_chatItems` shape. Reuse the service mapper if exposed; otherwise add a private `_legacyChatFromRealtime(Map payload)` in the screen that maps the same keys `_legacyChat` produces (`id`, `type`, `raw_type` (=payload['type']), `title`, `unread_count`, `is_muted`, `folder`, `assigned_to` (=payload['assignedTo']), `archived`, `owner_name` (=payload['ownerName']), last-message fields). Keep it consistent with Task 1's `_legacyChat` additions. (Preferred: expose `MagicMessengerService.legacyChatFromSummary(Map)` and call it, to avoid drift — if you do, add a one-line service test.)
- [ ] **Step 4: Extend `_handleRealtimeChatUpdated`** — READ it (line 716). Its existing branches (reader-ack zero-unread; mute toggle; enriched fan-out preview+unread) stay. ADD: when the payload carries `assignedTo`, `archived`, or `folder`, apply `setState(() => _chatItems = patchChat(_chatItems, payload));` so the folder/assignment/archive state and badges update live. (A chat moving to/from `archive` naturally re-buckets because the folder bar reads `folderOf` live.)
- [ ] **Step 5: Re-subscribe on reconnect** — confirm `_onRealtimeReconnected` (line 618) re-registers the new handlers OR that the connection re-attaches them automatically (it re-joins rooms; the handler registrations persist on the same connection object). If a fresh connection is built on reconnect, ensure `onChatCreated`/`onChatRemoved` are re-wired there too.
- [ ] **Step 6: Analyze.** `flutter analyze lib/features/messenger`
- [ ] **Step 7: Commit** (`feat(messenger): live chat.created/removed/updated inbox handlers`).

---

### Task 6: Assignment UI (Взять в работу / Передать / Снять)

**Files:**
- Modify: `messenger_screen.dart` (`_buildChatView` actions ~line 2303; `ChatListTile` assignee chip via existing `statusIcon`/status prop ~line 2206)
- Modify (if needed): `lib/core/widgets/telegram/chat_list_tile.dart` (render an "ведёт: Имя" chip)

**Interfaces (Consumes):** `assignChat`/`unassignChat` (Task 1), `assigneeName` (Task 3).

- [ ] **Step 1: Add assignment actions to the conversation overflow menu** — READ `_buildChatView` and its `PopupMenuButton` (where "Сохранить в CRM" lives, ~line 2300). When `_isManagerOrAdminRole` AND the open chat is an administration chat (`raw_type == 'administration'`):
  - if unassigned or assigned to someone else → show **«Взять в работу»** → `await svc.assignChat(chatId); ` then optimistically set the open chat's `assigned_to` and `setState`; on error show the existing snackbar pattern.
  - if assigned → show **«Снять с работы»** → `unassignChat(chatId)`.
  - manager-tier only (`_isManagerOrAdminRole`) → show **«Передать»** → open a staff-picker (reuse the profile-list pattern from `CreateGroupChatDialog`), then `assignChat(chatId, userId: picked)`.
- [ ] **Step 2: Show the assignee chip in the chat list** — pass `assigneeName(item)` into `ChatListTile` (use the existing status/subtitle slot at line ~2206; the map shows a `statusIcon` prop is already wired). Render a subtle "ведёт: Имя" chip when non-null. Update `chat_list_tile.dart` only if it has no slot for this text.
- [ ] **Step 3: Manual-logic test** — add a unit test asserting the menu-eligibility predicate if you extract it (e.g. a pure `bool canAssign(role, chat)` / `bool canReassign(role)` helper in `inbox_logic.dart`); TDD that helper (manager can reassign; non-manager staff can claim unassigned; client cannot). Wire the menu to the helper. (Extracting the predicate keeps this testable without the widget.)

```dart
// add to inbox_logic.dart + a test
bool isAdministration(Map<String, dynamic> chat) =>
  (chat['raw_type'] ?? chat['type']) == 'administration';
bool canShowAssignActions(bool isManagerOrAdmin, Map<String, dynamic> chat) =>
  isManagerOrAdmin && isAdministration(chat);
```

- [ ] **Step 4: Run inbox tests + analyze.** `flutter test test/features/messenger/ && flutter analyze lib/features/messenger lib/core/widgets/telegram/chat_list_tile.dart`
- [ ] **Step 5: Commit** (`feat(messenger): assignment UI — взять в работу / передать / снять + assignee chip`).

---

### Task 7: Per-staff archive action

**Files:**
- Modify: `messenger_screen.dart` (chat-list `onLongPress` context menu on a chat row; the open-chat overflow menu)

**Interfaces (Consumes):** `archiveChat`/`unarchiveChat` (Task 1), `patchChat` (Task 3).

- [ ] **Step 1: Add archive/unarchive to the chat-row context menu** — READ where `ChatListTile.onLongPress` is wired (the map notes it exists). When `_isManagerOrAdminRole` AND the row is an administration chat:
  - if not archived → **«Архивировать»** → `await svc.archiveChat(id);` then optimistically `setState(() => _chatItems = patchChat(_chatItems, {'id': id, 'archived': true}));` (it leaves the current folder and appears under Архив).
  - if archived → **«Вернуть из архива»** → `unarchiveChat(id)` then `patchChat(..., {'archived': false})`.
  On error, revert + show the existing error snackbar.
- [ ] **Step 2: Resurface is automatic** — note (no code): the backend clears archive for all staff when a new client message arrives and emits `chat.updated`; Task 5's `patchChat` already moves it back out of Архив. Add a code comment to that effect at the archive call site.
- [ ] **Step 3: Analyze.** `flutter analyze lib/features/messenger`
- [ ] **Step 4: Commit** (`feat(messenger): per-staff archive / unarchive action`).

---

### Task 8: Group "Выйти из группы" + "Добавить участников"

**Files:**
- Modify: `lib/core/widgets/telegram/chat_info_dialog.dart` (`_buildMembersPreview` ~line 881; add leave + add-members actions)
- Modify: `messenger_screen.dart` (handle list removal after leaving; pass the needed callbacks/role into `ChatInfoDialog` if not already)

**Interfaces (Consumes):** `leaveGroup` + existing `updateGroupMembers` (Task 1 / service), `removeChat` (Task 3).

- [ ] **Step 1: "Выйти из группы"** — in `ChatInfoDialog` for a `group` chat, add a **«Выйти из группы»** action (any member, including staff). On confirm: `await svc.leaveGroup(chatId);` close the dialog/conversation and remove the chat from the list (`setState(() => _chatItems = removeChat(_chatItems, chatId))` in the screen — surface via a callback the dialog already has, or add one). The realtime `chat.removed` from Task 5 will also fire for the leaver, so guard against double-removal (removeChat is idempotent).
- [ ] **Step 2: "Добавить участников"** (staff only — `_isManagerOrAdminRole`) — add an **«Добавить участников»** button near the member list that opens a user-picker (reuse `CreateGroupChatDialog`'s profile-list pattern) and calls `updateGroupMembers(chatId, addUserIds: [...])`. Added members appear live via their own `chat.created` (Task 5) and the chat-room `chat.updated`.
- [ ] **Step 3: Analyze.** `flutter analyze lib/core/widgets/telegram/chat_info_dialog.dart lib/features/messenger`
- [ ] **Step 4: Commit** (`feat(messenger): group leave + add-members UI`).

---

### Task 9: Client view verification + lockdown

**Files:**
- Modify (only if a gap is found): `messenger_screen.dart`
- Test: `test/features/messenger/inbox_logic_test.dart` (add a client-masking assertion is N/A server-side; instead assert the no-folder path)

- [ ] **Step 1: Verify the client experience by reading the relevant branches** (no behavior change expected, per the map):
  - Client (`widget.role == 'client'`) sees NO folder bar (Task 4 gated on `_isManagerOrAdminRole`) — confirm.
  - Client sees NO group-create / new-direct-chat entry (already gated) — confirm; if any new staff-only affordance from Tasks 6–8 is reachable by a client code path, wrap it in `_isManagerOrAdminRole`/`!isClient`.
  - Masked staff identity renders as "Администрация" with `isMe == false` (server-driven) — confirm `_getSenderName` (line ~3067) and the `isMe` computation rely only on server fields.
- [ ] **Step 2: Add a guard-rail test** — a pure test asserting that for a non-manager/non-admin caller the folder bar is not used: extract (if not already) a `bool showInboxFolders(String role)` into `inbox_logic.dart` and TDD it (`'manager'/'admin'/'system_admin'` → true; `'client'/'teacher'` → false). Wire Task 4's gate to this helper so the rule is unit-tested.

```dart
bool showInboxFolders(String role) =>
  role == 'manager' || role == 'admin' || role == 'system_admin';
```

- [ ] **Step 3: Full suite + analyze.** `flutter test && flutter analyze`
- [ ] **Step 4: Commit** (`feat(messenger): client lockdown — no folders/new-chat, masked view verified`).

---

## Self-Review (coverage vs spec §6)

- Inbox folders Лиды/Ученики/Архив + live badges → Tasks 3,4. Assignment UI (взять/передать/снять) + chip → Task 6. Per-staff archive → Task 7. Realtime chat.created/removed/updated → Tasks 2,5. Masked client view → server-side (Phase 3) + verified Task 9. Group leave + add-members → Task 8. Client has no new-direct-chat → Task 9 (already gated). ✓
- Service plumbing (assign/unassign/archive/unarchive/leave + summary fields) → Task 1. ✓
- Testability: pure `inbox_logic.dart` (folders/badges/reducers/predicates) is fully unit-tested; connection hooks tested via fake transport; service methods via fake Dio; folder bar via widget test. The heavy screen wiring is integration (verified by analyze + the extracted-logic tests + Phase 5 smoke/manual).

## After Phase 4

Phase 5: extend `server/src/smoke/realtime-smoke.ts` (assign → masked client reply, group create/leave live); run full `npm test` + `flutter test`; rebuild Windows/APK/AAB (`1.1.22+128`, `--dart-define=MAGIC_API_BASE_URL=https://api.phantom-net.ru/api`); deploy backend WITH the Phase 2 wipe (backup → wipe → tar-copy + `docker compose up -d --build api`); refresh `dist/` artifacts with SHA-256. Deploy + DB writes are user-gated.
