import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/create_lesson_dialog.dart';

const _teacherId = '22222222-2222-2222-2222-222222222222';
const _studentId = '33333333-3333-3333-3333-333333333333';
const _leadId = '77777777-7777-7777-7777-777777777777';
const _branchId = '11111111-1111-1111-1111-111111111111';
const _roomId = '55555555-5555-5555-5555-555555555555';
const _conflictId = '44444444-4444-4444-4444-444444444444';

Map<String, dynamic> _freePreview() => {
  'teacherBusy': false,
  'roomBusy': false,
  'conflicts': const [],
};

Map<String, dynamic> _busyPreview() => {
  'teacherBusy': true,
  'roomBusy': false,
  'conflicts': [
    {
      'lessonId': _conflictId,
      'title': 'Мария Занятова',
      'startsAt': '2026-07-18T07:00:00.000Z',
      'endsAt': '2026-07-18T08:00:00.000Z',
      'roomName': 'Зал 1',
      'teacherName': 'Пётр Педагогов',
    },
  ],
};

class _FakeApiClient extends MagicApiClient {
  _FakeApiClient({this.preview, this.createError})
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  Map<String, dynamic>? preview;
  MagicApiException? createError;
  final lessonPosts = <Map<String, dynamic>>[];
  final lessonPatches = <Map<String, dynamic>>[];

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    switch (path) {
      case '/crm/teachers':
        return <String, dynamic>{
              'items': [
                {
                  'id': _teacherId,
                  'firstName': 'Пётр',
                  'lastName': 'Педагогов',
                  'status': 'active',
                },
              ],
            }
            as T;
      case '/crm/branches':
        return <String, dynamic>{
              'items': [
                {
                  'id': _branchId,
                  'name': 'Главный филиал',
                  'utcOffsetMinutes': 180,
                },
              ],
            }
            as T;
      case '/crm/rooms':
        return <String, dynamic>{
              'items': [
                {'id': _roomId, 'name': 'Зал 1', 'branchId': _branchId},
              ],
            }
            as T;
      case '/crm/clients/search':
        return <String, dynamic>{
              'items': [
                {
                  'ref': {'type': 'student', 'id': _studentId},
                  'label': 'Иван Прилежный',
                  'lifecycleState': 'active',
                  'tombstone': false,
                  'version': 1,
                  'links': const [],
                },
                {
                  'ref': {'type': 'lead', 'id': _leadId},
                  'label': 'Анна Лидова',
                  'lifecycleState': 'active',
                  'tombstone': false,
                  'version': 1,
                  'links': const [],
                },
              ],
            }
            as T;
      case '/crm/subscriptions':
        return <String, dynamic>{'items': const []} as T;
      case '/crm/schedule/conflicts':
        return (preview ?? _freePreview()) as T;
      default:
        return <String, dynamic>{'items': const []} as T;
    }
  }

  @override
  Future<T> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/crm/lessons') {
      lessonPosts.add(Map<String, dynamic>.from(data as Map));
      if (createError case final error?) throw error;
      return <String, dynamic>{'id': 'lesson-1', 'version': 1} as T;
    }
    throw UnimplementedError('POST $path');
  }

  @override
  Future<T> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path.startsWith('/crm/lessons/')) {
      lessonPatches.add(Map<String, dynamic>.from(data as Map));
      return <String, dynamic>{'id': 'lesson-1', 'version': 8} as T;
    }
    throw UnimplementedError('PATCH $path');
  }
}

Widget _host(_FakeApiClient client, {Map<String, dynamic>? lesson}) {
  return ProviderScope(
    overrides: [magicApiClientProvider.overrideWithValue(client)],
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () => CreateLessonDialog.show(context, lesson: lesson),
              child: const Text('открыть диалог'),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _pumpDialog(
  WidgetTester tester,
  _FakeApiClient client, {
  Map<String, dynamic>? lesson,
}) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_host(client, lesson: lesson));
  await tester.pumpAndSettle();
  await tester.tap(find.text('открыть диалог'));
  await tester.pumpAndSettle();
}

Future<void> _selectRequiredResources(
  WidgetTester tester, {
  required String clientName,
}) async {
  await tester.tap(find.byKey(const ValueKey('lesson-client-field')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(clientName).last);
  await tester.pumpAndSettle();

  await tester.ensureVisible(
    find.byKey(const ValueKey('lesson-teacher-field')),
  );
  await tester.tap(find.byKey(const ValueKey('lesson-teacher-field')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Пётр Педагогов').last);
  await tester.pumpAndSettle();

  await tester.ensureVisible(find.byKey(const ValueKey('lesson-room-field')));
  await tester.tap(find.byKey(const ValueKey('lesson-room-field')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Зал 1').last);
  await tester.pumpAndSettle();
}

Future<void> _tapCreate(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Создать'));
  await tester.tap(find.text('Создать'));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('единый Client selector отправляет Lead и trial независимо', (
    tester,
  ) async {
    final client = _FakeApiClient();
    await _pumpDialog(tester, client);
    await _selectRequiredResources(tester, clientName: 'Анна Лидова');

    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('lesson-trial-toggle')),
          )
          .value,
      isFalse,
    );
    await _tapCreate(tester);
    await tester.pumpAndSettle();

    expect(client.lessonPosts, hasLength(1));
    final body = client.lessonPosts.single;
    expect(body['clientRef'], {'type': 'lead', 'id': _leadId});
    expect(body['isTrial'], isFalse);
    expect(body['completionType'], 'standard.success');
    expect(body['clientChargeType'], 'none');
    expect(body['clientChargeValue'], 0);
    expect(body['teacherCompensationType'], 'none');
    expect(body['teacherCompensationValue'], 0);
    expect(body['roomId'], _roomId);
    expect(body, isNot(contains('studentId')));
    expect(body, isNot(contains('leadId')));
    expect(body, isNot(contains('status')));
    expect(body, isNot(contains('force')));
  });

  testWidgets('preview-конфликт блокирует create без force affordance', (
    tester,
  ) async {
    final client = _FakeApiClient(preview: _busyPreview());
    await _pumpDialog(tester, client);
    await _selectRequiredResources(tester, clientName: 'Иван Прилежный');
    await _tapCreate(tester);

    expect(find.text('Конфликт расписания'), findsOneWidget);
    expect(find.text('Преподаватель занят в это время'), findsOneWidget);
    expect(find.textContaining('Мария Занятова'), findsOneWidget);
    expect(find.text('Всё равно назначить'), findsNothing);
    expect(client.lessonPosts, isEmpty);
  });

  testWidgets(
    'authoritative 422 показывает structured violations и lesson link',
    (tester) async {
      final error = MagicApiException(
        statusCode: 422,
        message: 'Lesson draft violates schedule constraints.',
        details: {
          'code': 'LESSON_CONSTRAINT_VIOLATIONS',
          'violations': [
            {
              'code': 'ROOM_OVERLAP',
              'resource': {'type': 'room', 'id': _roomId},
              'conflictingLessonIds': [_conflictId],
              'ruleIds': const [],
            },
            {
              'code': 'OUTSIDE_BRANCH_HOURS',
              'resource': {'type': 'branch', 'id': _branchId},
              'conflictingLessonIds': const [],
              'ruleIds': ['branch-hours-1'],
            },
          ],
        },
      );
      final client = _FakeApiClient(createError: error);
      await _pumpDialog(tester, client);
      await _selectRequiredResources(tester, clientName: 'Иван Прилежный');
      await _tapCreate(tester);

      expect(client.lessonPosts, hasLength(1));
      expect(find.text('Занятие не сохранено'), findsOneWidget);
      expect(find.text('Аудитория уже занята'), findsOneWidget);
      expect(find.text('Филиал закрыт в это время'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('conflict-lesson-$_conflictId')),
        findsOneWidget,
      );
      expect(find.text('Всё равно назначить'), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('conflict-lesson-$_conflictId')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Занятие не сохранено'), findsNothing);
      expect(find.text('Новое занятие'), findsNothing);
    },
  );

  testWidgets('edit отправляет expectedVersion и не меняет snapshot', (
    tester,
  ) async {
    final client = _FakeApiClient();
    final lesson = <String, dynamic>{
      'id': '66666666-6666-6666-6666-666666666666',
      'version': 7,
      'student_id': _studentId,
      'student_name': 'Иван Прилежный',
      'teacher_id': _teacherId,
      'branch_id': _branchId,
      'room_id': _roomId,
      'scheduled_at': '2026-07-18T07:00:00.000Z',
      'duration_minutes': 60,
      'is_trial': true,
      'snapshot_trial': true,
      'completion_type': 'custom.success',
      'client_charge_type': 'none',
      'client_charge_value': 0,
      'teacher_compensation_type': 'none',
      'teacher_compensation_value': 0,
    };
    await _pumpDialog(tester, client, lesson: lesson);

    await tester.ensureVisible(find.text('Сохранить'));
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();

    expect(client.lessonPatches, hasLength(1));
    final body = client.lessonPatches.single;
    expect(body['expectedVersion'], 7);
    expect(body['teacherId'], _teacherId);
    expect(body['roomId'], _roomId);
    expect(body, isNot(contains('clientRef')));
    expect(body, isNot(contains('isTrial')));
    expect(body, isNot(contains('completionType')));
    expect(body, isNot(contains('force')));
  });
}
