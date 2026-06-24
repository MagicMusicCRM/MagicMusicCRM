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
