import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/features/client/presentation/widgets/subscription_status_card.dart';

void main() {
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
}
