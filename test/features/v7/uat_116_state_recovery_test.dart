import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/models/payment.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/admin_overview_widget.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/manage_entities_widget.dart';
import 'package:magic_music_crm/features/auth/presentation/screens/legal_consent_screen.dart';
import 'package:magic_music_crm/features/auth/providers/release_gate_provider.dart';
import 'package:magic_music_crm/features/client/presentation/screens/client_dashboard_screen.dart';
import 'package:magic_music_crm/features/client/presentation/widgets/subscription_status_card.dart';
import 'package:magic_music_crm/features/client/presentation/widgets/upcoming_lessons_list.dart';
import 'package:magic_music_crm/features/messenger/presentation/screens/messenger_screen.dart';
import 'package:magic_music_crm/features/profile/presentation/screens/profile_screen.dart';

import '../messenger/messenger_test_api.dart';

class _RecoveringMessengerApi extends RecordingFakeApiClient {
  _RecoveringMessengerApi({
    super.profileRole,
    this.chatFailures = 0,
    this.postFailures = 0,
    this.includeChannel = false,
  });

  int chatFailures;
  int postFailures;
  final bool includeChannel;
  int chatAttempts = 0;
  int postAttempts = 0;

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/messenger/chats') {
      chatAttempts++;
      if (chatFailures > 0) {
        chatFailures--;
        throw Exception('private transport details');
      }
    }
    if (path == '/messenger/channels' && includeChannel) {
      calls.add((method: 'GET', path: path, data: null));
      return {
            'items': [
              {
                'id': 'channel-a',
                'title': 'Методические новости',
                'description': 'Для преподавателей',
                'createdBy': 'manager-a',
                'createdAt': '2026-08-12T10:00:00Z',
                'updatedAt': '2026-08-12T10:00:00Z',
              },
            ],
          }
          as T;
    }
    if (path == '/messenger/channels/channel-a/access') {
      calls.add((method: 'GET', path: path, data: null));
      return {'channelId': 'channel-a', 'canRead': true, 'canWrite': false}
          as T;
    }
    if (path.endsWith('/posts')) {
      postAttempts++;
      if (postFailures > 0) {
        postFailures--;
        throw Exception('private message transport details');
      }
    }
    return super.get<T>(
      path,
      queryParameters: queryParameters,
      authenticated: authenticated,
    );
  }
}

class _RecoveringProfileApi extends RecordingFakeApiClient {
  int profileAttempts = 0;

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/profile/me') {
      profileAttempts++;
      if (profileAttempts == 1) throw Exception('private profile details');
    }
    return super.get<T>(
      path,
      queryParameters: queryParameters,
      authenticated: authenticated,
    );
  }
}

Future<void> _pumpMessenger(
  WidgetTester tester,
  RecordingFakeApiClient api,
  String role,
) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [magicApiClientProvider.overrideWithValue(api)],
      child: MaterialApp(home: MessengerScreen(role: role)),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 150));
}

void main() {
  setUpAll(() => initializeDateFormatting('ru_RU', null));

  testWidgets('занятия показывают безопасную ошибку и повторяют запрос', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          upcomingLessonsRichProvider.overrideWith((ref) async {
            attempts++;
            if (attempts == 1) throw Exception('private lesson details');
            return const <Map<String, dynamic>>[];
          }),
          pastLessonsRichProvider.overrideWith((ref) async => const []),
        ],
        child: const MaterialApp(home: Scaffold(body: UpcomingLessonsList())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Не удалось загрузить занятия'), findsOneWidget);
    expect(find.textContaining('private lesson details'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Повторить'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.text('Нет предстоящих занятий'), findsOneWidget);
  });

  testWidgets('абонемент показывает безопасную ошибку и повторяет запрос', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          subscriptionProvider.overrideWith((ref) async {
            attempts++;
            if (attempts == 1) {
              throw Exception('private subscription details');
            }
            return null;
          }),
        ],
        child: const MaterialApp(
          home: Scaffold(body: SubscriptionStatusCard()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Не удалось загрузить абонемент'), findsOneWidget);
    expect(find.textContaining('private subscription details'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Повторить'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.text('Нет активного абонемента'), findsOneWidget);
  });

  testWidgets('оплаты клиента не раскрывают ошибку и восстанавливаются', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var attempts = 0;
    final api = RecordingFakeApiClient();
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          magicApiClientProvider.overrideWithValue(api),
          subscriptionProvider.overrideWith((ref) async => null),
          clientPaymentsProvider.overrideWith((ref) async {
            attempts++;
            if (attempts == 1) throw Exception('private payment details');
            return const <Payment>[];
          }),
        ],
        child: const MaterialApp(home: ClientDashboardScreen()),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Абонемент'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Оплаты'));
    await tester.pumpAndSettle();

    expect(find.text('Не удалось загрузить оплаты'), findsOneWidget);
    expect(find.textContaining('private payment details'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Повторить'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.text('Оплат пока нет'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('обзор директора сохраняет понятное действие повтора', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          statsProvider.overrideWith((ref) async {
            attempts++;
            if (attempts == 1) throw Exception('private dashboard details');
            return const <String, dynamic>{};
          }),
          upcomingTasksProvider.overrideWith((ref) async => const []),
        ],
        child: const MaterialApp(home: Scaffold(body: AdminOverviewWidget())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Не удалось загрузить обзор'), findsOneWidget);
    expect(find.textContaining('private dashboard details'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Повторить'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.text('Обзор системы'), findsOneWidget);
  });

  testWidgets('настройки различают ошибку доступа и реальный запрет', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          capabilitySnapshotProvider.overrideWith((ref) async {
            attempts++;
            if (attempts == 1) throw Exception('private access details');
            return const CapabilitySnapshot(
              accountId: '10000000-0000-4000-8000-000000000001',
              role: 'admin',
              accessVersion: 1,
              capabilities: {},
              scopes: {},
            );
          }),
        ],
        child: const MaterialApp(home: SystemSettingsRouteScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Не удалось проверить доступ'), findsOneWidget);
    expect(find.textContaining('private access details'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Повторить'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.text('Нет доступа к настройкам'), findsOneWidget);
  });

  testWidgets('профиль сохраняет ошибку до успешного ручного повтора', (
    tester,
  ) async {
    final api = _RecoveringProfileApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [magicApiClientProvider.overrideWithValue(api)],
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Не удалось загрузить профиль'), findsOneWidget);
    expect(find.textContaining('private profile details'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Повторить'));
    await tester.pumpAndSettle();

    expect(api.profileAttempts, 2);
    expect(find.text('Не удалось загрузить профиль'), findsNothing);
    expect(find.text('Изменить профиль'), findsOneWidget);
  });

  testWidgets('юридические документы можно повторно загрузить без выхода', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          currentLegalDocumentsProvider.overrideWith((ref) async {
            attempts++;
            if (attempts == 1) throw Exception('private legal details');
            return const [];
          }),
        ],
        child: const MaterialApp(
          home: LegalConsentScreen(requireAcceptance: false),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Не удалось загрузить документы.'),
      findsOneWidget,
    );
    expect(find.textContaining('private legal details'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Повторить'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.text('Актуальные документы MagicMusicCRM.'), findsOneWidget);
  });

  testWidgets('список чатов отличает сетевую ошибку от пустого результата', (
    tester,
  ) async {
    final api = _RecoveringMessengerApi(chatFailures: 1);
    await _pumpMessenger(tester, api, 'client');

    expect(find.text('Не удалось загрузить чаты'), findsOneWidget);
    expect(find.textContaining('private transport details'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Повторить'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(api.chatAttempts, 2);
    expect(find.text('Не удалось загрузить чаты'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('сообщения сохраняют ошибку до успешного повтора', (
    tester,
  ) async {
    final api = _RecoveringMessengerApi(
      profileRole: 'teacher',
      includeChannel: true,
      postFailures: 1,
    );
    await _pumpMessenger(tester, api, 'teacher');

    await tester.tap(find.text('Методические новости'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.text('Не удалось загрузить сообщения'), findsOneWidget);
    expect(
      find.textContaining('private message transport details'),
      findsNothing,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Повторить'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(api.postAttempts, 2);
    expect(find.text('Пока нет публикаций'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
