import 'package:flutter_test/flutter_test.dart';

import 'card_fake_api.dart';

void main() {
  testWidgets('student balance summary renders all cancellation counters', (
    tester,
  ) async {
    final api = FakeCardApiClient(
      student: {
        'id': 'student-a',
        'firstName': 'Анна',
        'lastName': 'Иванова',
        'status': 'active',
        'customData': <String, dynamic>{},
      },
      studentIndicators: const {
        'paidMisses': 2,
        'partiallyPaidMisses': 1,
        'unpaidMisses': 3,
      },
    );

    await pumpClientCard(
      tester,
      api: api,
      seed: const {'id': 'student-a', 'custom_data': <String, dynamic>{}},
      entityType: 'student',
      initialSection: 'lessons',
      statuses: const [],
    );

    expect(find.text('Оплачиваемые пропуски'), findsOneWidget);
    expect(find.text('Частично оплачиваемые пропуски'), findsOneWidget);
    expect(find.text('Неоплачиваемые пропуски'), findsOneWidget);
    expect(find.text('2'), findsWidgets);
    expect(find.text('1'), findsWidgets);
    expect(find.text('3'), findsWidgets);
  });
}
