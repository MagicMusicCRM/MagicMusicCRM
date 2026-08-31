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
    expect(find.text('Ученик · Анна Иванова'), findsOneWidget);
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

  testWidgets('renders an unknown target without an open action', (
    tester,
  ) async {
    final fallbackEvent = AuditPresentationEvent.fromJson(<String, dynamic>{
      'id': 'audit-unknown-target',
      'actionKey': 'crm.unknown_updated',
      'title': 'Данные изменены',
      'actor': <String, dynamic>{'name': 'Мария Администратор'},
      'target': <String, dynamic>{
        'type': 'unknown',
        'label': 'Неизвестная запись',
        'displayName': null,
        'routeType': null,
      },
      'changes': <Map<String, dynamic>>[],
      'occurredAt': '2026-08-30T10:15:00.000Z',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AuditEventCard(event: fallbackEvent)),
      ),
    );

    expect(find.text('Неизвестная запись · Не указано'), findsOneWidget);
    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets('renders absent change values as Не указано', (tester) async {
    final absentValueEvent = AuditPresentationEvent.fromJson(<String, dynamic>{
      'id': 'audit-absent-value',
      'actionKey': 'crm.student_updated',
      'title': 'Электронная почта изменена',
      'summary': null,
      'reason': null,
      'actor': <String, dynamic>{'id': null, 'name': 'Система', 'role': null},
      'target': <String, dynamic>{
        'type': 'student',
        'id': null,
        'label': 'Ученик',
        'displayName': null,
        'routeType': null,
      },
      'changes': <Map<String, dynamic>>[
        <String, dynamic>{
          'key': 'email',
          'label': 'Электронная почта',
          'before': null,
          'after': 'new@example.com',
        },
      ],
      'occurredAt': '2026-08-30T10:15:00.000Z',
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AuditEventCard(event: absentValueEvent)),
      ),
    );

    await tester.tap(find.byKey(const Key('audit-event-expand')));
    await tester.pumpAndSettle();
    expect(find.text('Было: Не указано'), findsOneWidget);
  });

  testWidgets('renders a changed-only reference as a single fact', (
    tester,
  ) async {
    final changedOnlyEvent = AuditPresentationEvent.fromJson(<String, dynamic>{
      'id': 'audit-changed-only',
      'actionKey': 'crm.lead_owner_changed',
      'title': 'Ответственный по лиду изменён',
      'summary': null,
      'reason': null,
      'actor': <String, dynamic>{'id': null, 'name': 'Система', 'role': null},
      'target': <String, dynamic>{
        'type': 'lead',
        'id': 'lead-1',
        'label': 'Лид',
        'displayName': 'Анна Иванова',
        'routeType': 'lead',
      },
      'changes': <Map<String, dynamic>>[
        <String, dynamic>{
          'key': 'assigned_to',
          'label': 'Ответственный',
          'before': null,
          'after': null,
        },
      ],
      'occurredAt': '2026-08-30T10:15:00.000Z',
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AuditEventCard(event: changedOnlyEvent)),
      ),
    );

    await tester.tap(find.byKey(const Key('audit-event-expand')));
    await tester.pumpAndSettle();

    expect(find.text('Ответственный'), findsOneWidget);
    expect(find.text('Изменено'), findsOneWidget);
    expect(find.textContaining('Было:'), findsNothing);
    expect(find.textContaining('Стало:'), findsNothing);
  });

  testWidgets('never renders a raw comment body as the target name', (
    tester,
  ) async {
    const privateBody = 'PRIVATE-COMMENT-BODY-MUST-NOT-LEAK';
    final commentEvent = AuditPresentationEvent.fromJson(<String, dynamic>{
      'id': 'audit-comment',
      'actionKey': 'crm.comment_created',
      'title': 'Комментарий добавлен',
      'summary': null,
      'reason': null,
      'actor': <String, dynamic>{'id': null, 'name': 'Система', 'role': null},
      'target': <String, dynamic>{
        'type': 'comment',
        'id': 'comment-1',
        'label': 'Комментарий',
        'displayName': null,
        'routeType': 'comment',
        'body': privateBody,
      },
      'changes': <Map<String, dynamic>>[],
      'occurredAt': '2026-08-30T10:15:00.000Z',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AuditEventCard(event: commentEvent)),
      ),
    );

    expect(find.text('Комментарий · Не указано'), findsOneWidget);
    expect(find.text(privateBody), findsNothing);
  });
}
