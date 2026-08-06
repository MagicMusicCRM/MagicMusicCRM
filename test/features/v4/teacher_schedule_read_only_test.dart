import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_day_canvas.dart';
import 'package:magic_music_crm/features/teacher/presentation/widgets/teacher_schedule_widget.dart';

class _TeacherCalendarApiClient extends MagicApiClient {
  _TeacherCalendarApiClient({
    this.lessons = const <Map<String, dynamic>>[],
    this.failFirstMatrixRequest = false,
  }) : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  final List<Map<String, dynamic>> lessons;
  final bool failFirstMatrixRequest;
  final List<Map<String, dynamic>> matrixQueries = [];
  final List<String> mutationPaths = [];

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    switch (path) {
      case '/profile/me':
        return <String, dynamic>{
              'userId': 'teacher-user',
              'email': 'teacher@example.test',
              'role': 'teacher',
              'emailOtp2faEnabled': false,
            }
            as T;
      case '/crm/teachers':
        return <String, dynamic>{
              'items': <Map<String, dynamic>>[
                {
                  'id': 'teacher-1',
                  'profileUserId': 'teacher-user',
                  'firstName': 'Мария',
                  'lastName': 'Педагог',
                },
              ],
            }
            as T;
      case '/crm/branches':
        return <String, dynamic>{
              'items': const [
                {'id': 'branch-1', 'name': 'Центр', 'utcOffsetMinutes': 0},
              ],
            }
            as T;
      case '/crm/rooms':
        return <String, dynamic>{
              'items': const [
                {'id': 'room-1', 'branchId': 'branch-1', 'name': 'Класс 1'},
              ],
            }
            as T;
      case '/crm/schedule/matrix':
        matrixQueries.add({...?queryParameters});
        if (failFirstMatrixRequest && matrixQueries.length == 1) {
          throw StateError('network unavailable');
        }
        return <String, dynamic>{
              'items': lessons,
              'groups': const <dynamic>[],
              'conflicts': const <dynamic>[],
            }
            as T;
      default:
        return <String, dynamic>{'items': <dynamic>[]} as T;
    }
  }

  @override
  Future<T> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    mutationPaths.add('POST $path');
    return <String, dynamic>{} as T;
  }

  @override
  Future<T> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    mutationPaths.add('PATCH $path');
    return <String, dynamic>{} as T;
  }
}

Map<String, dynamic> _assignedLesson() {
  final now = DateTime.now();
  return {
    'id': 'lesson-1',
    'version': 3,
    'studentId': 'student-1',
    'teacherId': 'teacher-1',
    'branchId': 'branch-1',
    'roomId': 'room-1',
    'scheduledAt': DateTime.utc(
      now.year,
      now.month,
      now.day,
      10,
    ).toIso8601String(),
    'durationMinutes': 60,
    'status': 'scheduled',
    'lifecycleState': 'scheduled',
    'isTrial': true,
    'studentName': 'Анна Ученица',
    'teacherName': 'Мария Педагог',
    'roomName': 'Класс 1',
    'branchName': 'Центр',
  };
}

Future<void> _pumpCalendar(
  WidgetTester tester,
  _TeacherCalendarApiClient api,
) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        magicApiClientProvider.overrideWithValue(api),
        capabilitySnapshotProvider.overrideWith(
          (ref) async => const CapabilitySnapshot(
            accountId: 'teacher-user',
            role: 'teacher',
            accessVersion: 1,
            capabilities: {
              'crm.client.read.basic',
              'schedule.lesson.read.assigned',
            },
            scopes: {'client': 'assigned', 'schedule': 'assigned'},
          ),
        ),
      ],
      child: MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        home: const Scaffold(body: TeacherScheduleWidget()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets(
    'teacher uses canonical assigned-only Day/Week read-only surface',
    (tester) async {
      final api = _TeacherCalendarApiClient(lessons: [_assignedLesson()]);
      await _pumpCalendar(tester, api);

      expect(
        find.byKey(const ValueKey('teacher-calendar-grid')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('schedule-view-switcher')),
        findsOneWidget,
      );
      expect(find.text('День'), findsOneWidget);
      expect(find.text('Неделя'), findsOneWidget);
      expect(find.text('Месяц'), findsNothing);
      expect(find.text('Создать занятие'), findsNothing);
      expect(find.byType(ScheduleDayCanvas), findsOneWidget);
      expect(
        find.byKey(const ValueKey('schedule-lesson-lesson-1')),
        findsOneWidget,
      );
      expect(api.matrixQueries, isNotEmpty);
      expect(
        api.matrixQueries.every((query) => query['teacherId'] == 'teacher-1'),
        isTrue,
      );

      await tester.tap(find.byKey(const ValueKey('schedule-lesson-lesson-1')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Ученик:'), findsOneWidget);
      expect(find.textContaining('Педагог:'), findsOneWidget);
      expect(find.textContaining('Филиал:'), findsOneWidget);
      expect(find.textContaining('Аудитория:'), findsOneWidget);
      expect(find.text('Изменить занятие'), findsNothing);
      expect(find.text('Удалить занятие'), findsNothing);
      expect(api.mutationPaths, isEmpty);
    },
  );

  testWidgets('teacher schedule exposes the same retryable error state', (
    tester,
  ) async {
    final api = _TeacherCalendarApiClient(failFirstMatrixRequest: true);
    await _pumpCalendar(tester, api);

    expect(find.text('Не удалось загрузить расписание'), findsOneWidget);
    await tester.tap(find.text('Повторить'));
    await tester.pumpAndSettle();

    expect(api.matrixQueries, hasLength(2));
    expect(find.byKey(const ValueKey('teacher-calendar-grid')), findsOneWidget);
    expect(api.mutationPaths, isEmpty);
  });
}
