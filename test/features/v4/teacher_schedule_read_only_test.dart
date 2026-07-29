import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/features/messenger/presentation/screens/messenger_screen.dart';
import 'package:magic_music_crm/features/teacher/presentation/widgets/teacher_schedule_widget.dart';

class _TeacherCalendarApiClient extends MagicApiClient {
  _TeacherCalendarApiClient({
    this.lessons = const <Map<String, dynamic>>[],
    this.failFirstLessonRequest = false,
  }) : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  final List<Map<String, dynamic>> lessons;
  final bool failFirstLessonRequest;
  final List<Map<String, dynamic>> lessonQueries = [];
  final List<Map<String, dynamic>> homeworkQueries = [];
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
      case '/crm/lessons':
        lessonQueries.add(
          Map<String, dynamic>.from(
            queryParameters ?? const <String, dynamic>{},
          ),
        );
        if (failFirstLessonRequest && lessonQueries.length == 1) {
          throw StateError('network unavailable');
        }
        return <String, dynamic>{'items': lessons} as T;
      case '/crm/homeworks':
        homeworkQueries.add(
          Map<String, dynamic>.from(
            queryParameters ?? const <String, dynamic>{},
          ),
        );
        return <String, dynamic>{
              'items': <Map<String, dynamic>>[
                {'id': 'homework-1', 'title': 'Этюд № 3', 'status': 'assigned'},
              ],
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
  final scheduledAt = DateTime.utc(
    now.year,
    now.month,
    now.day,
    9,
  ).toIso8601String();
  return {
    'id': 'lesson-1',
    'version': 3,
    'studentId': 'student-1',
    'teacherId': 'teacher-1',
    'scheduledAt': scheduledAt,
    'durationMinutes': 60,
    'status': 'scheduled',
    'lifecycleState': 'scheduled',
    'reservationState': null,
    'isTrial': true,
    'studentName': 'Анна Ученица',
    'teacherName': 'Мария Педагог',
    'roomName': 'Класс 1',
    'branchName': 'Центр',
    'notes': 'Гаммы и этюд',
  };
}

Future<void> _pumpCalendar(
  WidgetTester tester,
  _TeacherCalendarApiClient api, {
  Size size = const Size(900, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [magicApiClientProvider.overrideWithValue(api)],
      child: const MaterialApp(home: Scaffold(body: TeacherScheduleWidget())),
    ),
  );
  for (
    var attempt = 0;
    attempt < 40 &&
        find.byKey(const ValueKey('teacher-calendar-grid')).evaluate().isEmpty;
    attempt++
  ) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets(
    'assigned Day/Week calendar exposes only safe read-only client links',
    (tester) async {
      final api = _TeacherCalendarApiClient(lessons: [_assignedLesson()]);
      await _pumpCalendar(tester, api);

      expect(
        find.byKey(const ValueKey('teacher-calendar-view-segments')),
        findsOneWidget,
      );
      expect(find.text('День'), findsOneWidget);
      expect(find.text('Неделя'), findsOneWidget);
      expect(find.text('Месяц'), findsNothing);
      expect(
        find.byKey(const ValueKey('teacher-lesson-lesson-1')),
        findsOneWidget,
      );
      expect(api.lessonQueries.single['teacherId'], 'teacher-1');

      await tester.tap(find.byKey(const ValueKey('teacher-lesson-lesson-1')));
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        find.byKey(const ValueKey('teacher-client-card-title')),
        findsOneWidget,
      );
      expect(find.text('История занятий'), findsOneWidget);
      expect(find.text('Домашние задания'), findsOneWidget);
      for (final mutationLabel in const [
        'Изменить план',
        'Создать занятие',
        'Перенести',
        'Отменить занятие',
        'Посещаемость',
        'Сохранить',
      ]) {
        expect(find.text(mutationLabel), findsNothing);
      }

      final historyLink = find.byKey(
        const ValueKey('teacher-history-lesson-1'),
      );
      await tester.ensureVisible(historyLink);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(historyLink);
      await tester.pump(const Duration(milliseconds: 700));

      expect(find.text('История занятий'), findsWidgets);
      expect(api.lessonQueries, hasLength(2));
      expect(api.lessonQueries.last['studentId'], 'student-1');
      expect(api.lessonQueries.last['teacherId'], 'teacher-1');
      expect(api.lessonQueries.last['order'], 'desc');
      expect(api.mutationPaths, isEmpty);
    },
  );

  testWidgets('narrow layout keeps only Day/Week and renders empty state', (
    tester,
  ) async {
    final api = _TeacherCalendarApiClient();
    await _pumpCalendar(tester, api, size: const Size(390, 844));

    expect(
      find.byKey(const ValueKey('teacher-calendar-view-dropdown')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('teacher-calendar-grid')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('teacher-calendar-empty')),
      findsOneWidget,
    );
    expect(find.text('Занятий пока нет'), findsOneWidget);
    expect(find.text('Месяц'), findsNothing);
    expect(find.text('Расписание'), findsNothing);
    expect(api.mutationPaths, isEmpty);
  });

  testWidgets('homework link stays actor-scoped and read-only', (tester) async {
    final api = _TeacherCalendarApiClient(lessons: [_assignedLesson()]);
    await _pumpCalendar(tester, api);

    await tester.tap(find.byKey(const ValueKey('teacher-lesson-lesson-1')));
    await tester.pump(const Duration(milliseconds: 500));
    final homeworkLink = find.byKey(
      const ValueKey('teacher-homeworks-lesson-1'),
    );
    await tester.ensureVisible(homeworkLink);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(homeworkLink);
    for (
      var attempt = 0;
      attempt < 30 && api.homeworkQueries.isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('Домашние задания'), findsWidgets);
    expect(api.homeworkQueries, hasLength(1));
    expect(find.text('Этюд № 3'), findsOneWidget);
    expect(api.homeworkQueries.single['studentId'], 'student-1');
    expect(api.homeworkQueries.single['limit'], 50);
    expect(api.mutationPaths, isEmpty);
  });

  testWidgets('error state retries the assigned read-only calendar', (
    tester,
  ) async {
    final api = _TeacherCalendarApiClient(failFirstLessonRequest: true);
    await _pumpCalendar(tester, api);

    expect(find.text('Не удалось загрузить расписание'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('teacher-calendar-retry')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('teacher-calendar-retry')));
    for (
      var attempt = 0;
      attempt < 40 && api.lessonQueries.length < 2;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 300));

    expect(api.lessonQueries, hasLength(2));
    expect(api.lessonQueries.last['teacherId'], 'teacher-1');
    expect(find.byKey(const ValueKey('teacher-calendar-grid')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('teacher-calendar-empty')),
      findsOneWidget,
    );
    expect(api.mutationPaths, isEmpty);
  });

  testWidgets('Teacher CRM route opens the same read-only calendar', (
    tester,
  ) async {
    final api = _TeacherCalendarApiClient();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [magicApiClientProvider.overrideWithValue(api)],
        child: const MaterialApp(home: MessengerScreen(role: 'teacher')),
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));

    await tester.tap(find.text('Расписание'));
    for (
      var attempt = 0;
      attempt < 40 &&
          find
              .byKey(const ValueKey('teacher-calendar-grid'))
              .evaluate()
              .isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.byKey(const ValueKey('teacher-calendar-grid')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('teacher-calendar-view-dropdown')),
      findsOneWidget,
    );
    expect(api.mutationPaths, isEmpty);
  });
}
