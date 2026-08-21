import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/widgets/telegram/message_input.dart';
import 'package:magic_music_crm/features/messenger/presentation/screens/messenger_screen.dart';

import 'messenger_test_api.dart';

class _ClientMessengerHarness extends StatelessWidget {
  const _ClientMessengerHarness();

  @override
  Widget build(BuildContext context) {
    return MessengerScreen(
      role: 'client',
      onOpenSchool: () {
        Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) =>
                Scaffold(appBar: AppBar(title: const Text('Учебный портал'))),
          ),
        );
      },
    );
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('ru', null));

  testWidgets(
    'client messenger delegates school navigation and keeps chat after Back',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final api = RecordingFakeApiClient(
        profileRole: 'client',
        chats: const [
          {'id': 'admin-1', 'type': 'administration', 'unreadCount': 0},
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [magicApiClientProvider.overrideWithValue(api)],
          child: const MaterialApp(home: _ClientMessengerHarness()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Администрация'));
      await tester.pump();
      expect(find.byType(MessageInput), findsOneWidget);

      await tester.tap(find.byTooltip('Моя школа'));
      await tester.pumpAndSettle();
      expect(find.text('Учебный портал'), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(MessageInput), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('school action is hidden without an owner callback', (
    tester,
  ) async {
    final api = RecordingFakeApiClient(profileRole: 'client');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [magicApiClientProvider.overrideWithValue(api)],
        child: const MaterialApp(home: MessengerScreen(role: 'client')),
      ),
    );
    await tester.pump();

    expect(find.byTooltip('Моя школа'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
