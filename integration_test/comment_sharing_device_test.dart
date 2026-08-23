import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/services/crm_realtime_provider.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/client_card.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/teacher_client_card.dart';

import '../test/features/crm/client_card/card_fake_api.dart';
import 'evidence_screenshot.dart';

const _studentId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _student = <String, dynamic>{
  'id': _studentId,
  'firstName': 'Анна',
  'lastName': 'Соколова',
  'status': 'active',
  'branchName': 'Сокол',
};

class _CommentProjectionApi extends FakeCardApiClient {
  _CommentProjectionApi({required super.role, required this.comments})
    : super(student: _student);

  final List<Map<String, dynamic>> comments;
  final List<Map<String, dynamic>> createdBodies = [];
  final List<Map<String, dynamic>> visibilityBodies = [];

  List<Map<String, dynamic>> get projectedComments => comments
      .where((comment) {
        if (role == 'teacher') return comment['sharedWithTeacher'] == true;
        if (role == 'client') return comment['kind'] == 'progress';
        return true;
      })
      .map(Map<String, dynamic>.from)
      .toList(growable: false);

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/crm/comments') {
      return <String, dynamic>{'items': projectedComments} as T;
    }
    if (path == '/crm/clients/student/$_studentId/card') {
      return <String, dynamic>{
            'projection': role,
            'header': {
              'id': _studentId,
              'type': 'student',
              'displayName': 'Анна Соколова',
              'status': 'active',
              'branchName': 'Сокол',
            },
            'lifecycle': {'state': 'active', 'tombstone': false, 'version': 1},
            'sections': {
              'lessons': {'count': 0, 'items': <dynamic>[]},
              'homework': {'count': 0, 'items': <dynamic>[]},
              'comments': {
                'count': projectedComments.length,
                'items': projectedComments,
              },
            },
          }
          as T;
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
    if (path == '/crm/comments') {
      final body = Map<String, dynamic>.from(data! as Map);
      createdBodies.add(body);
      final kind = body['kind']?.toString() ?? 'admin_comment';
      final created = <String, dynamic>{
        'id': 'comment-local',
        'entityType': body['entityType'],
        'entityId': body['entityId'],
        'authorId': 'manager-1',
        'authorName': 'Мария Управляющая',
        'body': body['body'],
        'kind': kind,
        'progress': kind == 'progress',
        'sharedWithTeacher': kind == 'teacher_note',
        'version': 1,
        'createdAt': '2026-08-12T10:00:00.000Z',
      };
      comments.add(created);
      return Map<String, dynamic>.from(created) as T;
    }
    return super.post<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      authenticated: authenticated,
    );
  }

  @override
  Future<T> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/crm/comments/comment-local/visibility') {
      final body = Map<String, dynamic>.from(data! as Map);
      visibilityBodies.add(body);
      final comment = comments.singleWhere(
        (item) => item['id'] == 'comment-local',
      );
      comment['kind'] = body['sharedWithTeacher'] == true
          ? 'teacher_note'
          : 'admin_comment';
      comment['sharedWithTeacher'] = body['sharedWithTeacher'];
      comment['version'] = 2;
      return Map<String, dynamic>.from(comment) as T;
    }
    return super.patch<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      authenticated: authenticated,
    );
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('staff publishes one comment and teacher receives only shared', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final comments = <Map<String, dynamic>>[
      {
        'id': 'comment-hidden',
        'entityType': 'student',
        'entityId': _studentId,
        'authorId': 'manager-1',
        'authorName': 'Мария Управляющая',
        'body': 'Скрытый служебный контекст',
        'kind': 'admin_comment',
        'progress': false,
        'sharedWithTeacher': false,
        'version': 1,
        'createdAt': '2026-08-12T09:00:00.000Z',
      },
      {
        'id': 'comment-shared',
        'entityType': 'student',
        'entityId': _studentId,
        'authorId': 'manager-1',
        'authorName': 'Мария Управляющая',
        'body': 'Опубликовано преподавателю',
        'kind': 'teacher_note',
        'progress': false,
        'sharedWithTeacher': true,
        'version': 1,
        'createdAt': '2026-08-12T09:30:00.000Z',
      },
    ];
    final staffApi = _CommentProjectionApi(role: 'manager', comments: comments);
    await _pumpStaffCard(tester, staffApi);

    final hiddenHint = find.text('Комментарий виден только админам');
    await tester.ensureVisible(hiddenHint);
    await tester.pumpAndSettle();
    expect(hiddenHint, findsOneWidget);
    expect(find.text('Скрытый служебный контекст'), findsOneWidget);
    expect(find.text('Опубликовано преподавателю'), findsOneWidget);
    await captureEvidence(tester, 'comment-hidden-staff');

    await tester.enterText(
      find.widgetWithText(TextField, 'Написать комментарий...'),
      'Новый закрытый комментарий',
    );
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();
    expect(
      staffApi.createdBodies.single,
      containsPair('kind', 'admin_comment'),
    );
    expect(find.text('Новый закрытый комментарий'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('comment-share-comment-local')));
    await tester.pumpAndSettle();
    expect(staffApi.visibilityBodies.single, {
      'sharedWithTeacher': true,
      'expectedVersion': 1,
      'reasonCode': 'crm.comment.teacher-sharing',
    });
    expect(find.text('Виден преподавателю'), findsWidgets);
    expect(find.textContaining('setState() callback argument'), findsNothing);
    expect(find.textContaining('Не удалось изменить видимость'), findsNothing);
    await captureEvidence(tester, 'comment-shared-staff');

    final teacherApi = _CommentProjectionApi(
      role: 'teacher',
      comments: comments,
    );
    await _pumpTeacherCard(tester, teacherApi);
    await tester.drag(
      find.byKey(const ValueKey('teacher-client-card-tabs')),
      const Offset(-360, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Комментарии'));
    await tester.pumpAndSettle();
    expect(find.text('Скрытый служебный контекст'), findsNothing);
    expect(find.text('Опубликовано преподавателю'), findsOneWidget);
    expect(find.text('Новый закрытый комментарий'), findsOneWidget);
    await captureEvidence(tester, 'comment-shared-teacher');
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpStaffCard(
  WidgetTester tester,
  _CommentProjectionApi api,
) async {
  await tester.pumpWidget(
    RepaintBoundary(
      key: const Key('evidence-screenshot-root'),
      child: ProviderScope(
        overrides: [
          magicApiClientProvider.overrideWithValue(api),
          crmRealtimeProvider.overrideWith(
            (ref) => const Stream<CrmChangedEvent>.empty(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(
            body: ClientCard(
              lead: _student,
              entityType: 'student',
              routed: true,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpTeacherCard(
  WidgetTester tester,
  _CommentProjectionApi api,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  await tester.pumpWidget(
    RepaintBoundary(
      key: const Key('evidence-screenshot-root'),
      child: ProviderScope(
        overrides: [magicApiClientProvider.overrideWithValue(api)],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(
            body: TeacherClientCard(
              entityType: 'student',
              entityId: _studentId,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
