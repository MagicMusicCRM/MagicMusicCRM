import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/features/client/presentation/widgets/subscription_status_card.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ru'));
  testWidgets('renders active subscription without expiration date', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          subscriptionProvider.overrideWith(
            (ref) async => {
              'type': 'Абонемент',
              'lessons_total': 4,
              'lessons_used': 0,
              'valid_until': null,
            },
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: SubscriptionStatusCard()),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Нет активного абонемента'), findsNothing);
    expect(find.text('Осталось: 4 ч'), findsOneWidget);
    expect(find.text('Действует: бессрочно'), findsOneWidget);
  });

  testWidgets(
    'renders the complete client financial status on a compact card',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            subscriptionProvider.overrideWith(
              (ref) async => {
                'package_name': '12 занятий по 60 минут',
                'lessons_total': 12,
                'lessons_used': 3,
                'valid_until': '2026-12-31T21:00:00.000Z',
                'actual_paid_minor': '1500000',
                'debt_minor': '1000000',
                'pending_minor': '500000',
                'overpayment_minor': '125050',
                'next_payment_at': '2026-09-15T09:00:00.000Z',
              },
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: SubscriptionStatusCard()),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('12 ЗАНЯТИЙ ПО 60 МИНУТ'), findsOneWidget);
      expect(find.byKey(const Key('subscription-hours')), findsOneWidget);
      expect(find.text('3 из 12'), findsOneWidget);
      expect(find.text('15\u00a0000 ₽'), findsOneWidget);
      expect(find.text('10\u00a0000 ₽'), findsOneWidget);
      expect(find.text('5\u00a0000 ₽'), findsOneWidget);
      expect(find.text('1\u00a0250,50 ₽'), findsOneWidget);
      expect(find.textContaining('15 сентября 2026'), findsOneWidget);
    },
  );
}
