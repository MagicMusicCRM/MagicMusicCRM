import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/widgets/telegram/chat_info_member_dialogs.dart';

void main() {
  testWidgets('danger confirmations return the selected decision', (
    tester,
  ) async {
    bool? leaveDecision;
    await _pumpLauncher(
      tester,
      onPressed: (context) async {
        leaveDecision = await showChatInfoLeaveConfirmation(context);
      },
    );

    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
    expect(find.text('Выйти из группы'), findsOneWidget);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(leaveDecision, isFalse);

    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Выйти'));
    await tester.pumpAndSettle();
    expect(leaveDecision, isTrue);
  });

  testWidgets('remove confirmation preserves member name and returns removal', (
    tester,
  ) async {
    bool? removeDecision;
    await _pumpLauncher(
      tester,
      onPressed: (context) async {
        removeDecision = await showChatInfoRemoveConfirmation(
          context,
          'Анна Петрова',
        );
      },
    );

    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Удалить Анна Петрова из группы? История сообщений сохранится.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(TextButton, 'Удалить'));
    await tester.pumpAndSettle();
    expect(removeDecision, isTrue);
  });

  testWidgets('note editor trims the returned body', (tester) async {
    String? note;
    await _pumpLauncher(
      tester,
      onPressed: (context) async {
        note = await showChatInfoNoteEditor(context);
      },
    );

    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '  Заметка о встрече  ');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Добавить'));
    await tester.pumpAndSettle();
    expect(note, 'Заметка о встрече');
  });

  testWidgets('members dialog only returns removable group members', (
    tester,
  ) async {
    Map<String, dynamic>? removed;
    await _pumpLauncher(
      tester,
      onPressed: (context) async {
        removed = await showDialog<Map<String, dynamic>>(
          context: context,
          builder: (_) => ChatInfoMembersDialog(
            canManageGroup: true,
            members: const [
              {
                'user_id': 'admin-user',
                '_display_name': 'Владелец',
                'role': 'admin',
                'is_current_user': true,
              },
              {
                'user_id': 'student-user',
                '_display_name': 'Анна Петрова',
                'user_role': 'client',
                'is_current_user': false,
              },
            ],
          ),
        );
      },
    );

    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
    expect(find.text('Участники (2)'), findsOneWidget);
    expect(find.text('Администратор группы'), findsOneWidget);
    expect(find.byTooltip('Удалить из группы'), findsOneWidget);
    await tester.tap(find.byTooltip('Удалить из группы'));
    await tester.pumpAndSettle();
    expect(removed?['user_id'], 'student-user');
  });

  testWidgets('add-members dialog filters profiles and returns the selection', (
    tester,
  ) async {
    Set<String>? selected;
    await _pumpLauncher(
      tester,
      onPressed: (context) async {
        selected = await showDialog<Set<String>>(
          context: context,
          builder: (_) => ChatInfoAddMembersDialog(
            existingMemberUserIds: const {'existing-user'},
            loadProfiles: () async => const [
              {
                'user_id': 'existing-user',
                'first_name': 'Уже',
                'last_name': 'В группе',
              },
              {'first_name': 'Без', 'last_name': 'Идентификатора'},
              {
                'user_id': 'anna-user',
                'first_name': 'Анна',
                'last_name': 'Петрова',
                'email': 'anna@example.test',
                'role': 'client',
              },
            ],
          ),
        );
      },
    );

    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
    expect(find.text('Уже В группе'), findsNothing);
    expect(find.text('Без Идентификатора'), findsNothing);
    expect(find.text('Анна Петрова'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'anna@example.test');
    await tester.pump();
    await tester.tap(find.text('Анна Петрова'));
    await tester.pump();
    expect(find.widgetWithText(ElevatedButton, 'Добавить (1)'), findsOneWidget);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Добавить (1)'));
    await tester.pumpAndSettle();
    expect(selected, {'anna-user'});
  });
}

Future<void> _pumpLauncher(
  WidgetTester tester, {
  required Future<void> Function(BuildContext context) onPressed,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => onPressed(context),
            child: const Text('Открыть'),
          ),
        ),
      ),
    ),
  );
}
