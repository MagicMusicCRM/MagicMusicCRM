import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/finance_widget_widgets.dart';

void main() {
  testWidgets(
    'an uncertain save keeps the form and retries the exact expense',
    (tester) async {
      final calls = <Map<String, dynamic>>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExpenseSheetForm(
              initialExpense: const {
                'amount': 100,
                'category': 'rent',
                'occurredAt': '2026-07-15T10:00:00Z',
              },
              onSubmit: (data) async {
                calls.add(Map.of(data));
                throw const MagicApiException(message: 'Нет соединения');
              },
            ),
          ),
        ),
      );
      expect(find.textContaining('15.07.2026'), findsOneWidget);
      await tester.tap(find.text('Сохранить изменения'));
      await tester.pumpAndSettle();
      expect(calls, hasLength(1));
      expect(find.byType(ExpenseSheetForm), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).enabled,
        isFalse,
      );
      await tester.tap(find.text('Сохранить изменения'));
      await tester.pumpAndSettle();
      expect(calls, hasLength(2));
      expect(calls.last, calls.first);
      expect(calls.last['occurredAt'], '2026-07-15T10:00:00.000Z');
    },
  );
}
