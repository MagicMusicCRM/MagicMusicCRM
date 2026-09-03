import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';

import 'card_fake_api.dart';

const _lead = {
  'id': 'lead-1',
  'firstName': 'Анна',
  'lastName': 'Смирнова',
  'customData': <String, dynamic>{},
};
const _student = {
  'id': 'student-1',
  'version': 1,
  'leadId': 'lead-1',
  'firstName': 'Анна',
  'lastName': 'Смирнова',
  'status': 'active',
  'customData': <String, dynamic>{},
};

void main() {
  setUpAll(() => initializeDateFormatting('ru', null));

  for (final entityType in ['lead', 'student']) {
    testWidgets('converted origin is shown when opened as $entityType', (
      tester,
    ) async {
      final api = FakeCardApiClient(
        lead: _lead,
        student: _student,
        linkedStudents: const [_student],
      );
      await pumpClientCard(
        tester,
        api: api,
        seed: {'id': '$entityType-1'},
        entityType: entityType,
        settle: false,
      );

      expect(find.text('Лид → Ученик'), findsOneWidget);
      expect(
        api.getRequests.where((path) => path == '/crm/leads/lead-1/card'),
        hasLength(1),
      );
      expect(api.studentCardLoadCount, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('retry resolves the originating lead after a failed load', (
    tester,
  ) async {
    final gate = Completer<void>();
    final api = FakeCardApiClient(lead: _lead, student: _student)
      ..nextStudentCardGate = gate;
    await pumpClientCard(
      tester,
      api: api,
      seed: const {'id': 'student-1'},
      entityType: 'student',
      settle: false,
    );
    gate.completeError(const MagicApiException(message: 'Нет соединения'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Повторить').first);
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(api.getRequests, contains('/crm/leads/lead-1/card'));
    expect(find.text('Лид → Ученик'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a student created directly keeps the student badge', (
    tester,
  ) async {
    final api = FakeCardApiClient(student: {..._student, 'leadId': null});
    await pumpClientCard(
      tester,
      api: api,
      seed: const {'id': 'student-1'},
      entityType: 'student',
    );

    expect(find.text('Ученик'), findsOneWidget);
    expect(find.text('Лид → Ученик'), findsNothing);
    expect(
      api.getRequests.where((path) => path.startsWith('/crm/leads/')),
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });
}
