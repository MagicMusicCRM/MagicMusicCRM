import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/widgets/telegram/channel_editor_dialog.dart';
import 'package:magic_music_crm/core/widgets/telegram/chat_info_dialog.dart';

import 'evidence_screenshot.dart';

typedef _Call = ({String method, String path, Object? data});

class _MessengerLifecycleApi extends MagicApiClient {
  _MessengerLifecycleApi()
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  final calls = <_Call>[];

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    calls.add((method: 'GET', path: path, data: null));
    if (path == '/admin/profiles') {
      return {
            'items': [
              {
                'id': 'profile-teacher',
                'userId': '11111111-1111-4111-8111-111111111111',
                'email': 'teacher@example.com',
                'role': 'teacher',
                'firstName': 'Анна',
                'lastName': 'Иванова',
              },
              {
                'id': 'profile-client',
                'userId': '22222222-2222-4222-8222-222222222222',
                'email': 'client@example.com',
                'role': 'client',
                'firstName': 'Илья',
                'lastName': 'Смирнов',
              },
            ],
          }
          as T;
    }
    if (path == '/messenger/chats/group-a') {
      return {
            'id': 'group-a',
            'type': 'group',
            'title': 'Вокальный ансамбль',
            'createdBy': 'manager-a',
            'isSystem': false,
            'unreadCount': 0,
            'createdAt': '2026-08-12T10:00:00Z',
            'updatedAt': '2026-08-12T10:00:00Z',
          }
          as T;
    }
    if (path == '/messenger/chats/group-a/members') {
      return {
            'items': [
              {
                'profileId': 'profile-manager',
                'userId': 'manager-a',
                'email': 'manager@example.com',
                'role': 'admin',
                'userRole': 'manager',
                'firstName': 'Мария',
                'lastName': 'Орлова',
                'isCurrentUser': true,
                'joinedAt': '2026-08-12T10:00:00Z',
              },
              {
                'profileId': 'profile-teacher',
                'userId': '11111111-1111-4111-8111-111111111111',
                'email': 'teacher@example.com',
                'role': 'member',
                'userRole': 'teacher',
                'firstName': 'Анна',
                'lastName': 'Иванова',
                'isCurrentUser': false,
                'joinedAt': '2026-08-12T10:00:00Z',
              },
              {
                'profileId': 'profile-client',
                'userId': '22222222-2222-4222-8222-222222222222',
                'email': 'client@example.com',
                'role': 'member',
                'userRole': 'client',
                'firstName': 'Илья',
                'lastName': 'Смирнов',
                'isCurrentUser': false,
                'joinedAt': '2026-08-12T10:00:00Z',
              },
            ],
          }
          as T;
    }
    if (path.endsWith('/messages')) return {'items': <dynamic>[]} as T;
    return {'items': <dynamic>[]} as T;
  }

  @override
  Future<T> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    calls.add((method: 'POST', path: path, data: data));
    final body = data as Map;
    return {
          'id': 'channel-a',
          'title': body['title'],
          'description': body['description'],
          'createdBy': 'manager-a',
          'createdAt': '2026-08-12T10:00:00Z',
          'updatedAt': '2026-08-12T10:00:00Z',
        }
        as T;
  }

  @override
  Future<T> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    calls.add((method: 'PATCH', path: path, data: data));
    return {
          'id': 'group-a',
          'type': 'group',
          'title': 'Вокальный ансамбль',
          'unreadCount': 0,
        }
        as T;
  }
}

Widget _app(Widget child, MagicApiClient api) => RepaintBoundary(
  key: evidenceRootKey,
  child: ProviderScope(
    overrides: [magicApiClientProvider.overrideWithValue(api)],
    child: MaterialApp(theme: AppTheme.dark, home: child),
  ),
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('channel permissions are editable on Windows', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _MessengerLifecycleApi();
    await tester.pumpWidget(_app(const ChannelEditorDialog(), api));
    await tester.pump(const Duration(seconds: 1));

    await tester.enterText(
      find.byKey(const ValueKey('channel-title')),
      'Методические новости',
    );
    final access = find.byKey(const ValueKey('channel-access-role:teacher'));
    await tester.ensureVisible(access);
    await tester.tap(access);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Чтение и публикация').last);
    await tester.pumpAndSettle();

    expect(find.text('Методические новости'), findsOneWidget);
    expect(find.text('Чтение и публикация'), findsWidgets);
    await captureEvidence(tester, 'channel-permissions');

    await tester.tap(find.byKey(const ValueKey('save-channel')));
    await tester.pumpAndSettle();
    final request = api.calls.singleWhere(
      (call) => call.method == 'POST' && call.path == '/messenger/channels',
    );
    expect(
      (request.data as Map)['permissions'],
      contains(predicate<Map>((rule) => rule['role'] == 'teacher')),
    );
    debugPrint('V7_CHANNEL_PERMISSIONS_DEVICE_PASS');
  });

  testWidgets('group participants expose add, remove and leave actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _MessengerLifecycleApi();
    await tester.pumpWidget(
      _app(
        const ChatInfoDialog(
          chatType: 'group',
          chatId: 'group-a',
          userRole: 'manager',
        ),
        api,
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Вокальный ансамбль'), findsWidgets);
    expect(find.text('Добавить'), findsOneWidget);
    expect(find.byTooltip('Удалить из группы'), findsNWidgets(2));
    expect(find.text('Выйти'), findsOneWidget);
    await captureEvidence(tester, 'group-member-management');
    debugPrint('V7_GROUP_MEMBERS_DEVICE_PASS');
  });
}
