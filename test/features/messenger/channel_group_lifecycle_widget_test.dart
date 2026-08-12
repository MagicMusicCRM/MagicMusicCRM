import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/widgets/telegram/channel_editor_dialog.dart';
import 'package:magic_music_crm/core/widgets/telegram/chat_info_dialog.dart';
import 'package:magic_music_crm/core/widgets/telegram/message_input.dart';
import 'package:magic_music_crm/features/messenger/presentation/screens/messenger_screen.dart';

import 'messenger_test_api.dart';

class _LifecycleApi extends RecordingFakeApiClient {
  _LifecycleApi({this.permissions = const [], this.groupMembers = const []})
    : super(profileRole: 'manager');

  final List<Map<String, dynamic>> permissions;
  final List<Map<String, dynamic>> groupMembers;

  static const profiles = <Map<String, dynamic>>[
    {
      'id': 'profile-teacher',
      'userId': '11111111-1111-4111-8111-111111111111',
      'email': 'teacher@example.com',
      'role': 'teacher',
      'firstName': 'Анна',
      'lastName': 'Иванова',
    },
  ];

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/admin/profiles') {
      calls.add((method: 'GET', path: path, data: null));
      return {'items': profiles} as T;
    }
    if (path == '/messenger/channels/channel-a/permissions') {
      calls.add((method: 'GET', path: path, data: null));
      return {'items': permissions} as T;
    }
    if (path == '/messenger/chats/group-a') {
      calls.add((method: 'GET', path: path, data: null));
      return {
            'id': 'group-a',
            'type': 'group',
            'title': 'Ансамбль',
            'createdBy': 'manager-a',
            'isSystem': false,
            'unreadCount': 0,
            'createdAt': '2026-08-12T10:00:00Z',
            'updatedAt': '2026-08-12T10:00:00Z',
          }
          as T;
    }
    if (path == '/messenger/chats/group-a/members') {
      calls.add((method: 'GET', path: path, data: null));
      return {'items': groupMembers} as T;
    }
    return super.get<T>(
      path,
      queryParameters: queryParameters,
      authenticated: authenticated,
    );
  }

  @override
  Future<T> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    calls.add((method: 'POST', path: path, data: data));
    if (path == '/messenger/channels') {
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
    return {'ok': true} as T;
  }

  @override
  Future<T> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    calls.add((method: 'PATCH', path: path, data: data));
    if (path == '/messenger/channels/channel-a') {
      final body = data as Map;
      return {
            'id': 'channel-a',
            'title': body['title'],
            'description': body['description'],
            'createdBy': 'manager-a',
            'createdAt': '2026-08-12T10:00:00Z',
            'updatedAt': '2026-08-12T10:01:00Z',
          }
          as T;
    }
    if (path == '/messenger/groups/group-a/members') {
      return {
            'id': 'group-a',
            'type': 'group',
            'title': 'Ансамбль',
            'unreadCount': 0,
          }
          as T;
    }
    return {'ok': true} as T;
  }
}

class _ChannelAccessApi extends RecordingFakeApiClient {
  _ChannelAccessApi({required this.canWrite}) : super(profileRole: 'teacher');

  final bool canWrite;

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/messenger/channels') {
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
      return {'channelId': 'channel-a', 'canRead': true, 'canWrite': canWrite}
          as T;
    }
    return super.get<T>(
      path,
      queryParameters: queryParameters,
      authenticated: authenticated,
    );
  }
}

Future<void> _pump(
  WidgetTester tester,
  Widget child,
  RecordingFakeApiClient api,
) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [magicApiClientProvider.overrideWithValue(api)],
      child: MaterialApp(home: Scaffold(body: child)),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('manager creates a channel with role and user ACL', (
    tester,
  ) async {
    final api = _LifecycleApi();
    await _pump(tester, const ChannelEditorDialog(), api);

    await tester.enterText(
      find.byKey(const ValueKey('channel-title')),
      'Новости',
    );
    final roleAccess = find.byKey(
      const ValueKey('channel-access-role:teacher'),
    );
    await tester.ensureVisible(roleAccess);
    await tester.tap(roleAccess);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Чтение и публикация').last);
    await tester.pumpAndSettle();

    final userAccess = find.byKey(
      const ValueKey(
        'channel-access-user:11111111-1111-4111-8111-111111111111',
      ),
    );
    await tester.ensureVisible(userAccess);
    await tester.tap(userAccess);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Чтение').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-channel')));
    await tester.pumpAndSettle();

    final request = api.callsWhere('POST', '/messenger/channels').single;
    final body = request.data as Map;
    expect(body['title'], 'Новости');
    final permissions = body['permissions'] as List;
    expect(
      permissions.any(
        (item) =>
            item['role'] == 'teacher' &&
            item['canRead'] == true &&
            item['canWrite'] == true,
      ),
      isTrue,
    );
    expect(
      permissions.any(
        (item) =>
            item['userId'] == '11111111-1111-4111-8111-111111111111' &&
            item['canRead'] == true &&
            item['canWrite'] == false,
      ),
      isTrue,
    );
  });

  testWidgets('channel edit preserves the loaded ACL', (tester) async {
    final api = _LifecycleApi(
      permissions: const [
        {
          'id': 'permission-a',
          'role': 'teacher',
          'canRead': true,
          'canWrite': true,
          'user': null,
        },
      ],
    );
    await _pump(
      tester,
      const ChannelEditorDialog(
        channelId: 'channel-a',
        initialTitle: 'Старое название',
      ),
      api,
    );

    await tester.enterText(
      find.byKey(const ValueKey('channel-title')),
      'Новое название',
    );
    await tester.tap(find.byKey(const ValueKey('save-channel')));
    await tester.pumpAndSettle();

    final request = api
        .callsWhere('PATCH', '/messenger/channels/channel-a')
        .single;
    final body = request.data as Map;
    expect(body['permissions'], [
      {'role': 'teacher', 'canRead': true, 'canWrite': true},
    ]);
  });

  testWidgets('manager removes another participant from a group', (
    tester,
  ) async {
    final api = _LifecycleApi(
      groupMembers: const [
        {
          'profileId': 'profile-manager',
          'userId': 'manager-a',
          'email': 'manager@example.com',
          'role': 'admin',
          'userRole': 'manager',
          'firstName': 'Мария',
          'lastName': 'Директор',
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
      ],
    );
    await _pump(
      tester,
      const ChatInfoDialog(
        chatType: 'group',
        chatId: 'group-a',
        userRole: 'manager',
      ),
      api,
    );

    await tester.ensureVisible(find.byTooltip('Удалить из группы').last);
    await tester.tap(find.byTooltip('Удалить из группы').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Удалить'));
    await tester.pumpAndSettle();

    final request = api
        .callsWhere('PATCH', '/messenger/groups/group-a/members')
        .single;
    expect(request.data, {
      'removeUserIds': ['11111111-1111-4111-8111-111111111111'],
    });
    expect(find.text('Анна Иванова'), findsNothing);
  });

  for (final canWrite in [true, false]) {
    testWidgets(
      'teacher channel composer follows explicit canWrite=$canWrite ACL',
      (tester) async {
        final api = _ChannelAccessApi(canWrite: canWrite);
        await _pump(tester, const MessengerScreen(role: 'teacher'), api);

        await tester.tap(find.text('Методические новости'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(
          find.byType(MessageInput),
          canWrite ? findsOneWidget : findsNothing,
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
