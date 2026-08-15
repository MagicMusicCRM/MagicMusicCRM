import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_day_canvas.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_teacher_timeline.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_widget.dart';

/// KVA-195 redesign coverage: Месяц/Неделя/День navigation, the day-grid canvas,
/// the interaction legend (no per-cell instructions), and the quick-create
/// popover wired to the existing `POST /crm/lessons` contract.

const _branchId = '11111111-1111-1111-1111-111111111111';
const _roomId = '22222222-2222-2222-2222-222222222222';

DateTime _today() {
  final now = DateTime.now();
  return DateTime.utc(now.year, now.month, now.day, 10);
}

class _FakeClient extends MagicApiClient {
  _FakeClient({this.reviewRequired = false})
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  final bool reviewRequired;
  final previews = <Map<String, dynamic>>[];

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    final iso = _today().toIso8601String();
    if (path == '/crm/branches') {
      return <String, dynamic>{
            'items': [
              {'id': _branchId, 'name': 'Сокол', 'utcOffsetMinutes': 0},
            ],
          }
          as T;
    }
    if (path == '/crm/rooms') {
      return <String, dynamic>{
            'items': [
              {'id': _roomId, 'branchId': _branchId, 'name': 'Аудитория 1'},
            ],
          }
          as T;
    }
    if (path == '/crm/rooms/availability') {
      return <String, dynamic>{
            'items': [
              {
                'roomId': _roomId,
                'branchId': _branchId,
                'roomName': 'Аудитория 1',
                'isAvailable': false,
                'lessons': const [],
                'conflictTypes': const [],
              },
              {
                'roomId': 'room-without-lessons',
                'branchId': _branchId,
                'roomName': 'Аудитория 2',
                'isAvailable': true,
                'lessons': const [],
                'conflictTypes': const [],
              },
            ],
          }
          as T;
    }
    if (path == '/crm/schedule/matrix') {
      return <String, dynamic>{
            'items': [
              {
                'id': 'lesson-1',
                'version': reviewRequired ? 2 : 1,
                'studentId': 'student-a',
                'studentName': 'Ольга Ученик',
                'teacherId': 'teacher-a',
                'teacherName': 'Анна Сусарина',
                'branchId': _branchId,
                'roomId': _roomId,
                'roomName': 'Аудитория 1',
                'scheduledAt': iso,
                'durationMinutes': 120,
                'status': 'scheduled',
                'lifecycleState': reviewRequired
                    ? 'settlement_pending'
                    : 'scheduled',
                if (reviewRequired)
                  'settlementFailureCode': 'ConflictException',
              },
            ],
            'groups': const [],
            'conflicts': const [],
          }
          as T;
    }
    if (reviewRequired && path == '/crm/configuration/lesson-decisions') {
      return <String, dynamic>{
            'settlementTypes': const [
              {
                'stableKey': 'lesson',
                'label': 'Занятие',
                'colorToken': 'success',
                'allowedContexts': ['settle'],
                'active': true,
                'order': 0,
              },
            ],
            'teacherCompensationRules': const [
              {
                'stableKey': 'standard',
                'label': 'Полная стандартная ставка',
                'mode': 'standard',
                'value': '0',
                'active': true,
                'order': 0,
              },
            ],
          }
          as T;
    }
    return <String, dynamic>{'items': const []} as T;
  }

  @override
  Future<T> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/crm/lessons/lesson-1/settle/preview') {
      previews.add(Map<String, dynamic>.from(data as Map));
      return <String, dynamic>{
            'operation': 'settle',
            'source': const {
              'id': 'lesson-1',
              'version': 2,
              'state': 'settlement_pending',
            },
            'successor': null,
            'financialDecision': previews.last['financialDecision'],
            'financialPreview': const {
              'clientFacts': [],
              'teacherFact': {
                'compensationRuleKey': 'standard',
                'compensationRuleLabel': 'Полная стандартная ставка',
                'amountMinor': '0',
              },
            },
            'violations': const [],
            'warnings': const [],
            'canConfirm': true,
            'confirmRequired': true,
            'previewToken': 'signed-review-preview',
          }
          as T;
    }
    throw StateError('Unexpected POST $path');
  }
}

Widget _host(Widget child, {MagicApiClient? client}) {
  return ProviderScope(
    overrides: [
      magicApiClientProvider.overrideWithValue(client ?? _FakeClient()),
      capabilitySnapshotProvider.overrideWith(
        (ref) async => const CapabilitySnapshot(
          accountId: 'manager-1',
          role: 'manager',
          accessVersion: 1,
          capabilities: {'schedule.lesson.read.branch'},
          scopes: {'schedule': 'assigned'},
        ),
      ),
    ],
    child: MaterialApp(home: child),
  );
}

void main() {
  setUpAll(() => initializeDateFormatting('ru', null));

  group('KVA-195 schedule redesign', () {
    testWidgets('responsive toolbar has one labelled create action', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_host(const ScheduleWidget()));
      await tester.pumpAndSettle();

      expect(find.text('Расписание'), findsOneWidget);
      expect(find.text('Создать занятие'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('schedule-create-lesson')),
        findsOneWidget,
      );
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(
        find.byKey(const ValueKey('schedule-view-switcher')),
        findsOneWidget,
      );
      expect(find.text('Филиал'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Месяц / Неделя / День switcher changes the view', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const ScheduleWidget()));
      await tester.pumpAndSettle();

      // Default = month: weekday headers visible.
      expect(find.text('Пн'), findsOneWidget);
      expect(find.text('Год'), findsNothing);

      await tester.tap(find.text('Неделя'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('schedule-week-view')), findsOneWidget);
      expect(find.byType(ScheduleDayCanvas), findsOneWidget);
      expect(find.text('Ольга Ученик'), findsOneWidget);
      expect(find.textContaining('Перетащить'), findsNothing);

      // Switch to День → the time grid (wide «Время» gutter header) is shown.
      await tester.tap(find.text('День'));
      await tester.pumpAndSettle();
      expect(find.byType(ScheduleDayCanvas), findsOneWidget);
      expect(find.text('Время'), findsOneWidget);
    });

    testWidgets('day grid shows the interaction legend, not per-cell hints', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const ScheduleWidget()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('День'));
      await tester.pumpAndSettle();

      // The legend has exactly three color statuses and one independent type badge.
      expect(find.text('Забронировано'), findsOneWidget);
      expect(find.text('Завершено'), findsOneWidget);
      expect(find.text('Конфликт'), findsOneWidget);
      expect(find.text('Пробное'), findsOneWidget);
      expect(find.textContaining('Бесплат'), findsNothing);
      // …and the old per-cell instruction is gone (owner rule #10).
      expect(find.text('Нажмите,\nчтобы назначить'), findsNothing);
      expect(find.textContaining('Нажмите'), findsNothing);
    });

    testWidgets('day summary describes whole-day occupancy, not free slots', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const ScheduleWidget()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('День'));
      await tester.pumpAndSettle();

      expect(find.text('Без занятий: 1'), findsOneWidget);
      expect(find.text('С занятиями: 1'), findsOneWidget);
      expect(find.textContaining('Свободно:'), findsNothing);
      expect(find.textContaining('Занято:'), findsNothing);
    });

    testWidgets('teacher mode uses horizontal time bands and teacher rows', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_host(const ScheduleWidget()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('День'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('По преподавателям'));
      await tester.pumpAndSettle();

      expect(find.byType(ScheduleTeacherTimeline), findsOneWidget);
      expect(find.text('Преподаватель'), findsOneWidget);
      expect(find.text('08:00-10:00'), findsOneWidget);
      expect(find.text('Анна Сусарина'), findsOneWidget);
      expect(find.text('1 занятие · 2 ч'), findsOneWidget);
      expect(find.text('Ольга Ученик'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'review-required lesson exposes safe repair flow with current version',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final api = _FakeClient(reviewRequired: true);

        await tester.pumpWidget(_host(const ScheduleWidget(), client: api));
        await tester.pumpAndSettle();
        await tester.tap(find.text('День'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('По преподавателям'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('schedule-lesson-lesson-1')),
        );
        await tester.pumpAndSettle();

        // Keep this assertion close to the interaction so a regression cannot
        // accidentally tap the empty grid and open the create dialog instead.
        expect(find.text('Новое занятие'), findsNothing);
        expect(find.text('Ольга Ученик'), findsNWidgets(2));

        expect(find.text('Конфликт'), findsWidgets);
        expect(
          find.byKey(const ValueKey('lesson-repair-settlement')),
          findsOneWidget,
        );
        expect(find.textContaining('Причина конфликта'), findsOneWidget);
        expect(find.textContaining('ConflictException'), findsNothing);
        expect(find.textContaining('Провести занятие'), findsNothing);

        await tester.tap(
          find.byKey(const ValueKey('lesson-repair-settlement')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Исправление расчёта'), findsOneWidget);
        await tester.enterText(
          find.byKey(const Key('lesson-decision-reason')),
          'Проверка расчёта сотрудником',
        );
        await tester.tap(find.byKey(const Key('lesson-decision-settlement')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Занятие').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('lesson-decision-compensation')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Полная стандартная ставка').last);
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const Key('lesson-decision-submit')),
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('lesson-decision-submit')));
        await tester.pumpAndSettle();

        expect(api.previews, hasLength(1));
        expect(api.previews.single['expectedVersion'], 2);
        expect(api.previews.single['financialDecision'], {
          'settlementTypeKey': 'lesson',
          'teacherCompensationRuleKey': 'standard',
        });
        expect(find.text('Изменение готово к подтверждению'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('tapping an empty hour opens the (single) create dialog', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const ScheduleWidget()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('День'));
      await tester.pumpAndSettle();

      // Tap an empty slot near the top of the first room column (the lesson is
      // at 10:00, well below the 08:00 fold we tap into).
      final canvas = tester.getRect(find.byType(ScheduleDayCanvas));
      final tapAt = Offset(
        canvas.left + kTimeColWidth + 40, // inside room column 1
        canvas.top + kHeaderHeight + 14, // ≈ 08:10
      );
      await tester.tapAt(tapAt);
      await tester.pumpAndSettle();

      // Consolidated to the single full create window (no separate compact sheet).
      expect(find.text('Новое занятие'), findsOneWidget);
    });

    testWidgets('week canvas maps each column to its own calendar date', (
      tester,
    ) async {
      final monday = DateTime(2026, 8, 3);
      final tuesday = monday.add(const Duration(days: 1));
      DateTime? createdAt;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScheduleDayCanvas(
              date: monday,
              columns: [
                ScheduleColumn(
                  id: 'tuesday',
                  name: 'Вт',
                  color: Colors.blue,
                  date: tuesday,
                ),
              ],
              entries: const [],
              onCreateSlot: (_, start, _) => createdAt = start,
              onOpenLesson: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final canvas = tester.getRect(find.byType(ScheduleDayCanvas));
      await tester.tapAt(
        Offset(
          canvas.left + kTimeColWidth + 40,
          canvas.top + kHeaderHeight + 14,
        ),
      );
      await tester.pump();

      expect(createdAt, isNotNull);
      expect(DateUtils.isSameDay(createdAt, tuesday), isTrue);
    });
  });
}
