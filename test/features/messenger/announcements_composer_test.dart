// #18: клиент в «Объявлениях» просто читает — композер (поле ввода, голосовое,
// скрепка) скрыт целиком, и подсказки «пишут только управляющий и директор»
// тоже нет. Обычный чат с администрацией при этом остаётся с композером.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/widgets/telegram/message_input.dart';
import 'package:magic_music_crm/features/messenger/presentation/screens/messenger_screen.dart';

import 'messenger_test_api.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ru', null));

  testWidgets(
    'клиент в «Объявлениях»: ни композера, ни подсказки — только чтение',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final api = RecordingFakeApiClient(
        profileRole: 'client',
        chats: [
          {
            'id': 'ann-1',
            'type': 'group',
            'title': 'Объявления',
            'slug': 'announcements',
            'unreadCount': 0,
          },
          {'id': 'admin-1', 'type': 'administration', 'unreadCount': 0},
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [magicApiClientProvider.overrideWithValue(api)],
          child: const MaterialApp(home: MessengerScreen(role: 'client')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Ленивый POST: чат с администрацией уже в списке — создавать не надо.
      expect(
        api.callsWhere('POST', '/messenger/chats/direct'),
        isEmpty,
        reason: 'ensureAdministrationChat обязан быть ленивым: '
            'чат уже пришёл в listChats',
      );

      // Открываем «Объявления».
      await tester.tap(find.text('Объявления'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.byType(MessageInput),
        findsNothing,
        reason: 'клиент не пишет в «Объявления» — композер скрыт целиком',
      );
      expect(
        find.textContaining('пишут только'),
        findsNothing,
        reason: 'подсказка «кто может писать» клиенту не показывается',
      );

      // Контроль: обычный чат с администрацией — композер на месте.
      await tester.tap(find.text('Администрация'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(MessageInput), findsOneWidget);

      // Демонтируем экран, чтобы погасить таймеры фонового опроса.
      await tester.pumpWidget(const SizedBox());
    },
  );
}
