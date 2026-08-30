import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/models/audit_presentation_event.dart';
import 'package:magic_music_crm/shared/widgets/audit_event_card.dart';

void main() {
  final event = AuditPresentationEvent.fromJson(<String, dynamic>{
    'id': 'audit-42',
    'actionKey': 'crm.student_updated',
    'title': 'Электронная почта изменена',
    'summary': 'Почта обновлена после обращения ученика',
    'reason': 'Уточнение контактных данных',
    'actor': <String, dynamic>{
      'id': 'user-7',
      'name': 'Мария Администратор',
      'role': 'admin',
    },
    'target': <String, dynamic>{
      'type': 'student',
      'id': 'student-3',
      'label': 'Ученик',
      'displayName': 'Анна Иванова',
      'routeType': 'student',
    },
    'changes': <Map<String, dynamic>>[
      <String, dynamic>{
        'key': 'email',
        'label': 'Электронная почта',
        'before': 'old@example.com',
        'after': 'new@example.com',
      },
      <String, dynamic>{
        'key': 'phone',
        'label': 'Телефон',
        'before': '+79990000000',
        'after': '+79991111111',
      },
    ],
    'occurredAt': '2026-08-30T10:15:00.000Z',
  });

  testWidgets('expands audit details without opening the target', (
    tester,
  ) async {
    var openCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AuditEventCard(event: event, onOpenTarget: () => openCount++),
        ),
      ),
    );

    expect(find.text('Электронная почта изменена'), findsOneWidget);
    expect(find.text('crm.student_updated'), findsNothing);
    expect(find.text('old@example.com'), findsNothing);
    expect(find.text('Анна Иванова'), findsOneWidget);
    expect(find.text('Мария Администратор'), findsOneWidget);
    expect(
      find.text('Почта обновлена после обращения ученика'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('audit-event-expand')));
    await tester.pumpAndSettle();

    expect(find.text('Было: old@example.com'), findsOneWidget);
    expect(find.text('Стало: new@example.com'), findsOneWidget);
    expect(find.text('Причина: Уточнение контактных данных'), findsOneWidget);
    expect(openCount, 0);

    await tester.tap(find.byKey(const Key('audit-event-expand')));
    await tester.pumpAndSettle();
    expect(find.text('old@example.com'), findsNothing);
    expect(openCount, 0);
  });

  testWidgets('opens the target only through its dedicated action', (
    tester,
  ) async {
    var openCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AuditEventCard(event: event, onOpenTarget: () => openCount++),
        ),
      ),
    );

    await tester.tap(find.text('Открыть ученика'));
    expect(openCount, 1);
  });
}
