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
