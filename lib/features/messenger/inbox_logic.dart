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

/// True when the chat is an administration (inbox) chat.
bool isAdministration(Map<String, dynamic> chat) =>
  (chat['raw_type'] ?? chat['type']) == 'administration';

/// True when the current user can see assignment actions for this chat.
/// Requires manager-or-admin role AND the chat must be an administration chat.
bool canShowAssignActions(bool isManagerOrAdmin, Map<String, dynamic> chat) =>
  isManagerOrAdmin && isAdministration(chat);

/// Display name for an administration chat's assignee chip, or null.
String? assigneeName(Map<String, dynamic> chat) {
  final a = chat['assigned_to'];
  if (a is Map && (a['name'] as String?)?.trim().isNotEmpty == true) {
    return (a['name'] as String).trim();
  }
  return null;
}
