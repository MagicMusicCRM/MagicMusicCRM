import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../crm/client_card/card_fake_api.dart';

const _student = <String, dynamic>{
  'id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'firstName': 'Анна',
  'lastName': 'Соколова',
  'status': 'active',
  'branchId': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  'branchName': 'Сокол',
};

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
      operationalHistory: const [
        {
          'id': 'history-1',
          'actionKey': 'crm.payment_reversed',
          'action': 'Оплата удалена из статистики',
          'reason': 'Дубль банковской операции',
          'summary': 'Сумма: 3 000 ₽',
          'actorName': 'Анна Администратор',
          'occurredAt': '2026-08-07T11:00:00.000Z',
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

    expect(find.byKey(const Key('client-operational-history')), findsOneWidget);
    expect(find.text('Оплата удалена из статистики'), findsOneWidget);
    expect(find.text('Причина: Дубль банковской операции'), findsOneWidget);
    expect(find.textContaining('Анна Администратор'), findsOneWidget);
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
    expect(
      api.getRequests.where(
        (path) =>
            path.endsWith('/internal-note') ||
            path.endsWith('/operational-history'),
      ),
      isEmpty,
    );
  });

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
