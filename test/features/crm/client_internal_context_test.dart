import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/services/crm_realtime_provider.dart';
import 'package:magic_music_crm/shared/widgets/audit_event_card.dart';

import '../crm/client_card/card_fake_api.dart';

const _student = <String, dynamic>{
  'id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'firstName': 'Анна',
  'lastName': 'Соколова',
  'status': 'active',
  'branchId': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  'branchName': 'Сокол',
};

Map<String, dynamic> _auditEvent({
  required String id,
  required String actionKey,
  required String title,
  required String reason,
  required String summary,
  required String occurredAt,
  String before = 'Старое значение',
  String after = 'Новое значение',
}) => <String, dynamic>{
  'id': id,
  'actionKey': actionKey,
  'title': title,
  'summary': summary,
  'reason': reason,
  'actor': <String, dynamic>{
    'id': 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
    'name': 'Анна Администратор',
    'role': 'admin',
  },
  'target': <String, dynamic>{
    'type': 'student',
    'id': _student['id'],
    'label': 'Ученик',
    'displayName': 'Анна Соколова',
    'routeType': 'student',
  },
  'changes': <Map<String, dynamic>>[
    <String, dynamic>{
      'key': 'status',
      'label': 'Статус',
      'before': before,
      'after': after,
    },
  ],
  'occurredAt': occurredAt,
};

List<Map<String, dynamic>> _operationalHistoryFixture() =>
    List.generate(12, (index) {
      final number = index + 1;
      return _auditEvent(
        id: '00000000-0000-4000-8000-${number.toString().padLeft(12, '0')}',
        actionKey: 'crm.test_$number',
        title: 'Понятное действие $number',
        reason: 'Причина $number',
        summary: 'Результат $number',
        before: 'До $number',
        after: 'После $number',
        occurredAt: DateTime.utc(2026, 8, 30 - index, 12).toIso8601String(),
      );
    });

void main() {
  testWidgets('staff edits the versioned note and sees exact audit context', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = FakeCardApiClient(
      role: 'admin',
      student: _student,
      internalNote: const {
        'id': 'note-1',
        'body': 'Важен звонок перед занятием',
        'version': 4,
        'updatedByName': 'Мария Управляющая',
        'updatedAt': '2026-08-07T10:00:00.000Z',
      },
      operationalHistory: [
        _auditEvent(
          id: 'history-1',
          actionKey: 'crm.payment_reversed',
          title: 'Оплата удалена из статистики',
          reason: 'Дубль банковской операции',
          summary: 'Сумма: 3 000 ₽',
          before: 'Оплачено',
          after: 'Сторнировано',
          occurredAt: '2026-08-07T11:00:00.000Z',
        ),
      ],
    );
    final events = StreamController<CrmChangedEvent>();
    addTearDown(events.close);
    final container = ProviderContainer(
      overrides: [
        magicApiClientProvider.overrideWithValue(api),
        crmRealtimeProvider.overrideWith((ref) => events.stream),
      ],
    );
    addTearDown(container.dispose);

    await pumpClientCard(
      tester,
      api: api,
      seed: _student,
      entityType: 'student',
      routed: true,
      container: container,
    );

    expect(find.byKey(const Key('client-internal-note')), findsOneWidget);
    expect(find.text('Важен звонок перед занятием'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('client-internal-note-input')),
      'Позвонить за час',
    );
    await tester.pump(const Duration(milliseconds: 799));
    expect(api.updateInternalNoteBody, isNull);
    expect(find.byKey(const Key('client-internal-note-save')), findsNothing);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();
    expect(api.updateInternalNoteBody, {
      'body': 'Позвонить за час',
      'expectedVersion': 4,
    });
    expect(find.text('Сохранено'), findsWidgets);

    final noteEditor = find.descendant(
      of: find.byKey(const Key('client-internal-note-input')),
      matching: find.byType(EditableText),
    );
    final stateBeforeEcho = tester.state<EditableTextState>(noteEditor);
    final echoLoad = Completer<void>();
    addTearDown(() {
      if (!echoLoad.isCompleted) echoLoad.complete();
    });
    api.nextStudentCardGate = echoLoad;
    events.add(
      const CrmChangedEvent(
        entity: 'student',
        action: 'updated',
        id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(api.studentCardLoadCount, 2);
    expect(tester.state<EditableTextState>(noteEditor), same(stateBeforeEcho));

    echoLoad.complete();
    await tester.pumpAndSettle();
    expect(tester.state<EditableTextState>(noteEditor), same(stateBeforeEcho));
    expect(
      tester.widget<EditableText>(noteEditor).controller.text,
      'Позвонить за час',
    );

    expect(find.byKey(const Key('client-operational-history')), findsOneWidget);
    expect(find.text('Оплата удалена из статистики'), findsOneWidget);
    expect(find.textContaining('Анна Администратор'), findsOneWidget);
    expect(find.text('Причина: Дубль банковской операции'), findsNothing);
    final historyLoadsBeforeExpansion = api.getCalls
        .where((call) => call.path.endsWith('/operational-history'))
        .length;

    final expand = find.byKey(const Key('audit-event-expand'));
    await tester.ensureVisible(expand);
    await tester.tap(expand);
    await tester.pumpAndSettle();

    expect(find.text('Было: Оплачено'), findsOneWidget);
    expect(find.text('Стало: Сторнировано'), findsOneWidget);
    expect(find.text('Причина: Дубль банковской операции'), findsOneWidget);
    expect(find.textContaining('Версия'), findsNothing);
    expect(
      api.getCalls
          .where((call) => call.path.endsWith('/operational-history'))
          .length,
      historyLoadsBeforeExpansion,
    );
  });

  testWidgets('teacher neither requests nor sees staff-only client context', (
    tester,
  ) async {
    final api = FakeCardApiClient(role: 'teacher', student: _student);
    await pumpClientCard(
      tester,
      api: api,
      seed: _student,
      entityType: 'student',
    );

    expect(find.byKey(const Key('client-internal-note')), findsNothing);
    expect(find.text('История'), findsNothing);
    expect(
      api.getRequests.where(
        (path) =>
            path.endsWith('/internal-note') ||
            path.endsWith('/operational-history'),
      ),
      isEmpty,
    );
  });

  testWidgets(
    'staff history renders one readable page and reveals the next page without legacy duplicates',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = FakeCardApiClient(
        role: 'system_admin',
        student: _student,
        operationalHistory: _operationalHistoryFixture(),
        studentTimeline: const [
          {
            'id': 'legacy-lesson',
            'type': 'lesson',
            'title': 'Занятие из legacy-ленты',
            'body': '',
            'occurred_at': '2026-08-30T10:00:00.000Z',
          },
        ],
      );

      await pumpClientCard(
        tester,
        api: api,
        seed: _student,
        entityType: 'student',
        routed: true,
      );

      expect(
        find.byKey(const Key('client-operational-history')),
        findsOneWidget,
      );
      expect(find.byType(AuditEventCard), findsNWidgets(10));
      expect(find.text('Понятное действие 10'), findsOneWidget);
      expect(find.text('Понятное действие 11'), findsNothing);
      expect(find.text('Занятие из legacy-ленты'), findsNothing);
      expect(find.textContaining('Версия'), findsNothing);
      final more = find.byKey(const Key('client-operational-history-more'));
      expect(more, findsOneWidget);
      final firstHistoryRequest = api.getCalls.firstWhere(
        (call) => call.path.endsWith('/operational-history'),
      );
      expect(firstHistoryRequest.query['limit'], 10);
      expect(firstHistoryRequest.query['cursor'], isNull);

      final firstExpand = find.byKey(const Key('audit-event-expand')).first;
      await tester.ensureVisible(firstExpand);
      await tester.tap(firstExpand);
      await tester.pumpAndSettle();
      expect(find.text('Было: До 1'), findsOneWidget);

      await tester.ensureVisible(more);
      await tester.tap(more);
      await tester.pumpAndSettle();

      expect(find.byType(AuditEventCard), findsNWidgets(12));
      expect(find.text('Понятное действие 11'), findsOneWidget);
      expect(find.text('Понятное действие 12'), findsOneWidget);
      expect(find.text('Было: До 1'), findsOneWidget);
      expect(more, findsNothing);
      final historyRequests = api.getCalls
          .where((call) => call.path.endsWith('/operational-history'))
          .toList(growable: false);
      expect(historyRequests, hasLength(2));
      expect(historyRequests.last.query, {
        'limit': 10,
        'cursor': '00000000-0000-4000-8000-000000000010',
      });
    },
  );

  testWidgets('closing the card flushes a pending internal note', (
    tester,
  ) async {
    var closed = false;
    final api = FakeCardApiClient(
      role: 'admin',
      student: _student,
      internalNote: const {
        'id': 'note-1',
        'body': 'Старый текст',
        'version': 2,
        'updatedByName': 'Администратор',
        'updatedAt': '2026-08-07T10:00:00.000Z',
      },
    );
    await pumpClientCard(
      tester,
      api: api,
      seed: _student,
      entityType: 'student',
      routed: true,
      onClosed: (_) => closed = true,
    );

    await tester.enterText(
      find.byKey(const Key('client-internal-note-input')),
      'Свежий текст',
    );
    await tester.tap(find.text('Назад').last);
    await tester.pumpAndSettle();

    expect(api.updateInternalNoteBody, {
      'body': 'Свежий текст',
      'expectedVersion': 2,
    });
    expect(closed, isTrue);
  });

  testWidgets('note conflict keeps local text and retries on latest version', (
    tester,
  ) async {
    final api = FakeCardApiClient(
      role: 'admin',
      student: _student,
      internalNote: const {
        'id': 'note-1',
        'body': 'Старый текст',
        'version': 2,
        'updatedByName': 'Администратор',
        'updatedAt': '2026-08-07T10:00:00.000Z',
      },
    )..internalNotePutConflicts = 1;
    await pumpClientCard(
      tester,
      api: api,
      seed: _student,
      entityType: 'student',
      routed: true,
    );

    api.internalNote = const {
      'id': 'note-1',
      'body': 'Удалённое изменение',
      'version': 3,
      'updatedByName': 'Другой сотрудник',
      'updatedAt': '2026-08-07T11:00:00.000Z',
    };
    await tester.enterText(
      find.byKey(const Key('client-internal-note-input')),
      'Мой локальный текст',
    );
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();

    expect(find.text('Мой локальный текст'), findsOneWidget);
    expect(find.byKey(const Key('client-internal-note-retry')), findsOneWidget);
    expect(api.updateInternalNoteBodies.single['expectedVersion'], 2);

    await tester.tap(find.byKey(const Key('client-internal-note-retry')));
    await tester.pumpAndSettle();

    expect(api.updateInternalNoteBodies, hasLength(2));
    expect(api.updateInternalNoteBodies.last, {
      'body': 'Мой локальный текст',
      'expectedVersion': 3,
    });
    expect(find.text('Сохранено'), findsWidgets);
  });
}
