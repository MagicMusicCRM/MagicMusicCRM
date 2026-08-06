import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/client_archive_button.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/comment_share_button.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/teacher_client_card.dart';

class _ClientCardRolesFakeApi extends MagicApiClient {
  _ClientCardRolesFakeApi()
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  final posts = <({String path, Map<String, dynamic> data})>[];
  final patches = <({String path, Map<String, dynamic> data})>[];

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/crm/clients/student/student-a/card') {
      return <String, dynamic>{
            'projection': 'teacher',
            'header': {
              'id': 'student-a',
              'type': 'student',
              'displayName': 'Анна Клиент',
              'status': 'active',
              'branchName': 'Центр',
              // A malicious/stale extra field must still not become UI.
              'phone': '+79990000000',
            },
            'lifecycle': {'state': 'active', 'tombstone': false, 'version': 3},
            'sections': {
              'lessons': {
                'count': 1,
                'items': [
                  {
                    'id': 'lesson-a',
                    'scheduledAt': '2026-08-01T10:00:00.000Z',
                    'lifecycleState': 'scheduled',
                  },
                ],
              },
              'homework': {
                'count': 1,
                'items': [
                  {
                    'id': 'homework-a',
                    'title': 'Распевка',
                    'status': 'assigned',
                  },
                ],
              },
              'comments': {
                'count': 1,
                'items': [
                  {
                    'id': 'comment-a',
                    'body': 'Педагогу',
                    'sharedWithTeacher': true,
                  },
                ],
              },
              'finance': {
                'balanceMinor': 999999,
                'secret': 'Финансовый секрет',
              },
            },
          }
          as T;
    }
    throw StateError('Unexpected GET $path');
  }

  @override
  Future<T> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    final body = Map<String, dynamic>.from(data! as Map);
    posts.add((path: path, data: body));
    if (path == '/crm/clients/archive/preview') {
      return <String, dynamic>{
            'ref': {'type': 'student', 'id': 'student-a'},
            'label': 'Анна Клиент',
            'version': 7,
            'tombstone': false,
            'warnings': [
              {
                'code': 'FINANCE_FACTS_PRESERVED',
                'count': 2,
                'message': 'Финансовые факты останутся неизменными.',
              },
            ],
            'links': [
              {
                'rel': 'sourceLead',
                'ref': {'type': 'lead', 'id': 'lead-a'},
              },
            ],
          }
          as T;
    }
    if (path == '/crm/clients/archive') {
      return <String, dynamic>{
            'tombstone': {
              'ref': {'type': 'student', 'id': 'student-a'},
              'version': 8,
              'tombstone': true,
            },
          }
          as T;
    }
    throw StateError('Unexpected POST $path');
  }

  @override
  Future<T> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    final body = Map<String, dynamic>.from(data! as Map);
    patches.add((path: path, data: body));
    return <String, dynamic>{
          'id': 'comment-a',
          'body': 'Педагогу',
          'sharedWithTeacher': true,
          'version': 5,
        }
        as T;
  }
}

Future<void> _pump(
  WidgetTester tester,
  Widget child,
  _ClientCardRolesFakeApi api, {
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [magicApiClientProvider.overrideWithValue(api)],
      child: MaterialApp(home: Scaffold(body: child)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('Teacher card renders only learning sections on narrow layout', (
    tester,
  ) async {
    final api = _ClientCardRolesFakeApi();
    await _pump(
      tester,
      const TeacherClientCard(entityType: 'student', entityId: 'student-a'),
      api,
      size: const Size(320, 700),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Анна Клиент'), findsOneWidget);
    expect(find.text('Активен · Центр'), findsOneWidget);
    expect(find.textContaining('01.08.2026'), findsOneWidget);
    expect(find.text('Запланировано'), findsOneWidget);
    expect(find.text('+79990000000'), findsNothing);
    expect(find.text('Финансовый секрет'), findsNothing);
    expect(find.text('Оплаты'), findsNothing);
    expect(find.text('Задачи'), findsNothing);
    expect(
      find.byKey(const ValueKey('teacher-client-card-tabs')),
      findsOneWidget,
    );

    await tester.drag(
      find.byKey(const ValueKey('teacher-client-card-tabs')),
      const Offset(-220, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Домашние задания'));
    await tester.pumpAndSettle();
    expect(find.text('Распевка'), findsOneWidget);
    await tester.drag(
      find.byKey(const ValueKey('teacher-client-card-tabs')),
      const Offset(-180, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Комментарии'));
    await tester.pumpAndSettle();
    expect(find.text('Педагогу'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'archive action is hidden without role and confirms exact impact',
    (tester) async {
      final api = _ClientCardRolesFakeApi();
      var archived = false;
      await _pump(
        tester,
        Column(
          children: [
            ClientArchiveButton(
              entityType: 'student',
              entityId: 'student-a',
              allowed: false,
              onArchived: () {},
            ),
            ClientArchiveButton(
              entityType: 'student',
              entityId: 'student-a',
              allowed: true,
              onArchived: () => archived = true,
            ),
          ],
        ),
        api,
      );

      expect(find.byKey(const ValueKey('client-archive-open')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('client-archive-open')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.text('Финансовые факты останутся неизменными.'),
        findsOneWidget,
      );
      expect(
        find.text('Связанные карточки: 1. Они не будут архивированы.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('client-archive-confirm')));
      await tester.pumpAndSettle();

      expect(archived, isTrue);
      expect(api.posts.last.path, '/crm/clients/archive');
      expect(api.posts.last.data, {
        'type': 'student',
        'id': 'student-a',
        'expectedVersion': 7,
        'confirm': true,
        'reason': 'crm.client.archive.inactive',
      });
    },
  );

  testWidgets('comment share uses explicit flag and expected version', (
    tester,
  ) async {
    final api = _ClientCardRolesFakeApi();
    var refreshed = false;
    await _pump(
      tester,
      CommentShareButton(
        commentId: 'comment-a',
        version: 4,
        sharedWithTeacher: false,
        allowed: true,
        onChanged: () => refreshed = true,
      ),
      api,
    );

    await tester.tap(find.byKey(const ValueKey('comment-share-comment-a')));
    await tester.pumpAndSettle();
    expect(refreshed, isTrue);
    expect(api.patches.single.path, '/crm/comments/comment-a/visibility');
    expect(api.patches.single.data, {
      'sharedWithTeacher': true,
      'expectedVersion': 4,
      'reasonCode': 'crm.comment.teacher-sharing',
    });
  });

  test('archive role matrix is fail-closed', () {
    expect(clientRoleCanArchive('teacher'), isFalse);
    expect(clientRoleCanArchive('admin'), isFalse);
    expect(clientRoleCanArchive('manager'), isFalse);
    expect(clientRoleCanArchive('director'), isTrue);
    expect(clientRoleCanArchive('system_admin'), isTrue);
    expect(clientRoleCanArchive('unknown'), isFalse);
  });
}
