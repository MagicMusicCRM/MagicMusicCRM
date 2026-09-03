// #4: архив чатов — закреплённый контракт №3 (PATCH /api/chats/:id/archive
// {archived:boolean}) и его UI-обвязка: долгое нажатие/правый клик по строке,
// вкладка «Архив», возврат из архива и повторная загрузка после remount.
// Плюс #5: чат вообще не предлагает создать lead/student-дубль.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_api_tokens.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/services/magic_messenger_service.dart';
import 'package:magic_music_crm/core/services/magic_realtime_service.dart';
import 'package:magic_music_crm/core/widgets/telegram/chat_header.dart';
import 'package:magic_music_crm/core/widgets/telegram/chat_info_dialog.dart';
import 'package:magic_music_crm/features/messenger/data/chat_archive_api.dart';
import 'package:magic_music_crm/features/messenger/presentation/screens/messenger_screen.dart';

import 'messenger_test_api.dart';

Map<String, dynamic> _adminChatJson({bool archived = false}) => {
  'id': 'c1',
  'type': 'administration',
  'partnerId': 'client-user-1',
  'partner': {
    'id': 'client-user-1',
    'firstName': 'Иван',
    'lastName': 'Петров',
    'email': 'ivan@example.com',
  },
  'folder': 'leads',
  'archived': archived,
  'unreadCount': 0,
};

Future<RecordingFakeApiClient> _pumpAdminMessenger(
  WidgetTester tester, {
  List<Map<String, dynamic>>? chats,
  Map<String, dynamic> contactByUser = const {},
  RecordingFakeApiClient? api,
  _TestRealtimeTransport? realtimeTransport,
  EntityLink? initialLink,
  Size size = const Size(1400, 900),
  TargetPlatform platform = TargetPlatform.windows,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final resolvedApi =
      api ??
      RecordingFakeApiClient(
        profileRole: 'admin',
        chats: chats ?? [_adminChatJson()],
        contactByUser: contactByUser,
      );
  final overrides = [
    magicApiClientProvider.overrideWithValue(resolvedApi),
    if (realtimeTransport != null)
      magicRealtimeServiceProvider.overrideWithValue(
        MagicRealtimeService(
          api: MagicApiClient(
            baseUrl: 'http://localhost/api',
            tokenStore: MemoryMagicTokenStore(
              const MagicApiTokens(
                accessToken: 'test-access',
                refreshToken: 'test-refresh',
                tokenType: 'Bearer',
                expiresIn: 900,
              ),
            ),
          ),
          apiBaseUrl: 'http://localhost/api',
          transportFactory: (_, _) => realtimeTransport,
        ),
      ),
  ];
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: ThemeData(platform: platform),
        home: MessengerScreen(role: 'admin', initialLink: initialLink),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  return resolvedApi;
}

void main() {
  setUpAll(() => initializeDateFormatting('ru', null));

  for (final device in [
    (platform: TargetPlatform.android, size: const Size(390, 844)),
    (platform: TargetPlatform.android, size: const Size(900, 390)),
    (platform: TargetPlatform.windows, size: const Size(1400, 900)),
    (platform: TargetPlatform.windows, size: const Size(640, 900)),
  ]) {
    testWidgets('chat title uses an adaptive modal for $device', (
      tester,
    ) async {
      await _pumpAdminMessenger(
        tester,
        size: device.size,
        platform: device.platform,
        initialLink: EntityLink.typed(
          entityType: EntityLinkType.chat,
          entityId: 'c1',
        ),
      );
      await tester.pumpAndSettle();
      final header = find.byType(ChatHeader);
      expect(header, findsOneWidget);
      final headerTitle = find
          .descendant(of: header, matching: find.byType(Text))
          .first;
      final conversationWidth = tester.getSize(header).width;
      await tester.tap(headerTitle);
      await tester.pumpAndSettle();

      expect(find.byType(ChatInfoDialog), findsOneWidget);
      expect(
        find.byKey(const ValueKey('magic-sheet-mobile')),
        device.platform == TargetPlatform.android
            ? findsOneWidget
            : findsNothing,
      );
      final dialogRoute = ModalRoute.of(
        tester.element(find.byType(ChatInfoDialog)),
      );
      expect(dialogRoute, isNot(isA<MaterialPageRoute<void>>()));
      expect(tester.getSize(header).width, conversationWidth);
      expect(tester.takeException(), isNull);

      expect(find.byTooltip('Закрыть'), findsOneWidget);
      await tester.tap(find.byTooltip('Закрыть'));
      await tester.pumpAndSettle();
      expect(find.byType(ChatInfoDialog), findsNothing);
      expect(find.byType(ChatHeader), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  test(
    'setChatArchived бьёт ровно в контракт №3: PATCH /chats/:id/archive',
    () async {
      final api = RecordingFakeApiClient();
      await api.setChatArchived('chat-9', archived: true);
      await api.setChatArchived('chat-9', archived: false);

      expect(api.calls, hasLength(2));
      expect(api.calls[0].method, 'PATCH');
      expect(api.calls[0].path, '/chats/chat-9/archive');
      expect((api.calls[0].data as Map)['archived'], isTrue);
      expect(api.calls[1].path, '/chats/chat-9/archive');
      expect((api.calls[1].data as Map)['archived'], isFalse);
    },
  );

  testWidgets('typed chat link mounts the requested chat content', (
    tester,
  ) async {
    final api = await _pumpAdminMessenger(
      tester,
      initialLink: EntityLink.typed(
        entityType: EntityLinkType.chat,
        entityId: 'c1',
      ),
    );

    expect(
      api.calls.any(
        (call) => call.path.contains('c1') && call.path.endsWith('/messages'),
      ),
      isTrue,
    );
  });

  test('listChats(archived:true) sends the archive query and branch', () async {
    final api = RecordingFakeApiClient(chats: [_adminChatJson(archived: true)]);
    final service = MagicMessengerService(api);

    final rows = await service.listChats(archived: true, branchId: 'branch-1');

    expect(api.chatQueries, hasLength(1));
    expect(api.chatQueries.single['archived'], isTrue);
    expect(api.chatQueries.single['branchId'], 'branch-1');
    // Fake server applies strict branch filtering as production does.
    expect(rows, isEmpty);
  });

  testWidgets('staff chat screen follows every server cursor past 100 rows', (
    tester,
  ) async {
    final chats = List.generate(101, (index) {
      final number = index + 1;
      return <String, dynamic>{
        ..._adminChatJson(),
        'id': 'chat-$number',
        'partnerId': 'client-$number',
        'partner': {
          'id': 'client-$number',
          'firstName': 'Lead',
          'lastName': '$number',
          'email': 'lead$number@example.com',
        },
      };
    });
    final api = RecordingFakeApiClient(
      profileRole: 'admin',
      chats: chats,
      chatPageSize: 100,
    );

    await _pumpAdminMessenger(tester, api: api);
    await tester.pumpAndSettle();

    expect(
      api.chatQueries.any((query) => query['cursor'] == '100'),
      isTrue,
      reason: 'the list must request the second keyset page',
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'админ: долгое нажатие → «Архивировать» → PATCH, чат уходит в «Архив», '
    'оттуда возвращается',
    (tester) async {
      final api = await _pumpAdminMessenger(tester);

      // Чат классифицирован в «Лиды» (folder с сервера дошёл до списка).
      expect(find.text('Иван Петров'), findsOneWidget);

      await tester.longPress(find.text('Иван Петров'));
      await tester.pump();
      await tester.tap(find.text('Архивировать'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final patches = api.calls.where((c) => c.method == 'PATCH').toList();
      expect(patches, hasLength(1));
      expect(patches.single.path, '/chats/c1/archive');
      expect((patches.single.data as Map)['archived'], isTrue);

      // Оптимистично исчез из «Лиды».
      expect(find.text('Иван Петров'), findsNothing);

      // Вкладка «Архив» показывает его; возврат — PATCH {archived:false}.
      await tester.tap(find.text('Архив'));
      await tester.pump();
      expect(find.text('Иван Петров'), findsOneWidget);

      await tester.longPress(find.text('Иван Петров'));
      await tester.pump();
      await tester.tap(find.text('Вернуть из архива'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final patches2 = api.calls.where((c) => c.method == 'PATCH').toList();
      expect(patches2, hasLength(2));
      expect(patches2.last.path, '/chats/c1/archive');
      expect((patches2.last.data as Map)['archived'], isFalse);

      // В «Архиве» пусто, чат снова в «Лидах».
      expect(find.text('Иван Петров'), findsNothing);
      await tester.tap(find.text('Лиды'));
      await tester.pump();
      expect(find.text('Иван Петров'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('архив загружается заново после полного remount', (tester) async {
    final chats = [_adminChatJson()];
    final api = await _pumpAdminMessenger(tester, chats: chats);

    await tester.longPress(find.text('Иван Петров'));
    await tester.pump();
    await tester.tap(find.text('Архивировать'));
    await tester.pumpAndSettle();

    // Simulate leaving the app/screen: no optimistic widget state survives.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await _pumpAdminMessenger(tester, api: api);
    await tester.tap(find.text('Архив'));
    await tester.pump();

    expect(find.text('Иван Петров'), findsOneWidget);
    expect(
      api.chatQueries.where((query) => query['archived'] == true),
      isNotEmpty,
    );

    await tester.longPress(find.text('Иван Петров'));
    await tester.pump();
    await tester.tap(find.text('Вернуть из архива'));
    await tester.pumpAndSettle();
    expect(chats.single['archived'], isFalse);
  });

  testWidgets('админ: правый клик по строке тоже открывает меню архива', (
    tester,
  ) async {
    await _pumpAdminMessenger(tester);

    await tester.tap(find.text('Иван Петров'), buttons: kSecondaryButton);
    await tester.pump();

    expect(find.text('Архивировать'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    '#5: контакт уже связан с лидом — «Сохранить как лид/ученик» не предлагаем',
    (tester) async {
      final api = await _pumpAdminMessenger(
        tester,
        contactByUser: {'leadId': 'lead-77'},
      );

      // Открываем чат — по выбору чата подтягивается связь контакта.
      await tester.tap(find.text('Иван Петров'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        api.callsWhere('GET', '/crm/contacts/by-user/client-user-1'),
        isNotEmpty,
        reason: 'связь с CRM должна разрешаться при открытии чата',
      );

      // Only the existing-card shortcut remains.
      expect(find.text('Сохранить как лид'), findsNothing);
      expect(find.text('Сохранить как ученик'), findsNothing);
      expect(find.byIcon(Icons.badge_outlined), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    '#5: несвязанный/ещё не разрешённый контакт не предлагает создание дубля',
    (tester) async {
      await _pumpAdminMessenger(tester);

      await tester.tap(find.text('Иван Петров'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Сохранить как лид'), findsNothing);
      expect(find.text('Сохранить как ученик'), findsNothing);
      expect(find.byIcon(Icons.badge_outlined), findsNothing);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'chat.updated resurfaces archive even when it also repeats lastMessageId',
    (tester) async {
      final transport = _TestRealtimeTransport();
      final chat = <String, dynamic>{
        ..._adminChatJson(archived: true),
        'lastMessageId': 'message-1',
        'lastMessage': 'Старое сообщение',
        'lastMessageAt': '2026-07-18T10:00:00.000Z',
      };
      await _pumpAdminMessenger(
        tester,
        chats: [chat],
        realtimeTransport: transport,
      );
      expect(transport.handlers['chat.updated'], isNotEmpty);

      await tester.tap(find.text('Архив'));
      await tester.pump();
      expect(find.text('Иван Петров'), findsOneWidget);

      transport.fire('chat.updated', {
        'id': 'c1',
        'archived': false,
        'folder': 'leads',
        'lastMessageId': 'message-1',
        'lastMessage': 'Старое сообщение',
        'lastMessageAt': '2026-07-18T10:00:00.000Z',
        'senderId': 'client-user-1',
      });
      await tester.pump();

      expect(find.text('Иван Петров'), findsNothing);
      await tester.tap(find.text('Лиды'));
      await tester.pump();
      expect(find.text('Иван Петров'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

class _TestRealtimeTransport implements MagicRealtimeTransport {
  final handlers = <String, List<void Function(Object? payload)>>{};

  @override
  void connect() {}

  @override
  void disconnect() {}

  @override
  void dispose() => handlers.clear();

  @override
  void emit(String event, Object? payload) {}

  @override
  void on(String event, void Function(Object? payload) handler) {
    handlers.putIfAbsent(event, () => []).add(handler);
  }

  @override
  void off(String event, [void Function(Object? payload)? handler]) {
    if (handler == null) {
      handlers.remove(event);
    } else {
      handlers[event]?.remove(handler);
    }
  }

  void fire(String event, Object? payload) {
    for (final handler in List.of(handlers[event] ?? const [])) {
      handler(payload);
    }
  }
}
