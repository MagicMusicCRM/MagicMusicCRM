import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/core/services/crm_realtime_provider.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_day_canvas.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_teacher_timeline.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_widget.dart';

import '../crm/client_card/card_fake_api.dart';

Map<String, dynamic> lesson(
  String id,
  int hour, {
  int minute = 0,
  int duration = 60,
  int room = 1,
}) => {
  'id': id,
  'studentId': 'student-$id',
  'studentName': 'Анна Смирнова $id',
  'teacherId': 'teacher-1',
  'teacherName': 'Мария Иванова',
  'branchId': 'branch-1',
  'roomId': 'room-$room',
  'roomName': 'Аудитория $room',
  'scheduledAt': DateTime.utc(2026, 9, 4, hour, minute).toIso8601String(),
  'durationMinutes': duration,
  'status': 'scheduled',
  'lifecycleState': 'scheduled',
};

Widget host({bool client = false, double scale = 1}) => ProviderScope(
  overrides: [
    magicApiClientProvider.overrideWithValue(
      FakeCardApiClient(
        branches: const [
          {'id': 'branch-1', 'name': 'Сокол', 'utcOffsetMinutes': 0},
        ],
        rooms: [
          for (var i = 1; i <= 6; i++)
            {'id': 'room-$i', 'name': 'Аудитория $i', 'branchId': 'branch-1'},
        ],
        scheduleMatrix: [
          lesson('утро', 8),
          lesson('вечер', 21),
          lesson('короткое', 12, duration: 15),
          lesson('следующее', 12, minute: 15, duration: 15),
          lesson('вокал', 14, room: 2),
          lesson('фортепиано', 16, duration: 90, room: 3),
          lesson('первое', 18, duration: 90, room: 4),
          lesson('второе', 18, minute: 30, room: 4),
        ],
      ),
    ),
    crmRealtimeProvider.overrideWith(
      (ref) => const Stream<CrmChangedEvent>.empty(),
    ),
  ],
  child: MaterialApp(
    theme: AppTheme.production.copyWith(platform: TargetPlatform.windows),
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: RepaintBoundary(
          key: const Key('capture'),
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.only(top: 48, left: 64),
              child: ScheduleWidget(
                clientId: client ? 'student-утро' : null,
                clientType: client ? 'student' : null,
                clientName: client ? 'Анна Смирнова' : null,
                initialViewState: ContextViewState(
                  date: DateTime(2026, 9, 4),
                  filters: const {
                    'clientCalendarMode': 'day',
                    'branchId': 'branch-1',
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
    final font = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/InterVariable.ttf'));
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  for (final size in [
    const Size(1280, 720),
    const Size(1024, 768),
    const Size(1920, 1080),
  ]) {
    for (final client in [false, true]) {
      testWidgets('08:00–22:00 fits $size client=$client', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(host(client: client));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final hour in ['08:00', '22:00']) {
          final rect = tester.getRect(find.text(hour));
          expect(rect.top, greaterThanOrEqualTo(48));
          expect(rect.bottom, lessThanOrEqualTo(size.height));
        }
        for (final state in tester.stateList<ScrollableState>(
          find.descendant(
            of: find.byType(ScheduleDayCanvas),
            matching: find.byType(Scrollable),
          ),
        )) {
          if (state.position.axis == Axis.vertical) {
            expect(state.position.maxScrollExtent, closeTo(0, 0.01));
          }
        }
        if (!client) {
          final short = tester.getRect(
            find.byKey(const ValueKey('schedule-lesson-короткое')),
          );
          final next = tester.getRect(
            find.byKey(const ValueKey('schedule-lesson-следующее')),
          );
          expect(short.overlaps(next), isFalse);
          final one = tester.getRect(
            find.byKey(const ValueKey('schedule-lesson-первое')),
          );
          final two = tester.getRect(
            find.byKey(const ValueKey('schedule-lesson-второе')),
          );
          expect(one.overlaps(two), isFalse);
        }
        if (size.width == 1280 && !client) {
          final top = tester.getTopLeft(find.byType(ScheduleDayCanvas));
          await tester.tap(
            find.byKey(const ValueKey('schedule-filter-toggle')),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(tester.getTopLeft(find.byType(ScheduleDayCanvas)), top);
          await tester.tap(find.byKey(const ValueKey('schedule-filter-apply')));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('schedule-filter-apply')),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
          if (Platform.environment['CALENDAR_CAPTURE'] == '1') {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const Key('capture')),
            );
            await tester.runAsync(() async {
              final picture = await boundary.toImage();
              final bytes = await picture.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File(
                'outputs/calendar-desktop-1280.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              picture.dispose();
            });
          }
          await tester.tap(find.byTooltip('Крупнее'));
          await tester.pumpAndSettle();
          expect(
            tester
                .stateList<ScrollableState>(find.byType(Scrollable))
                .any(
                  (state) =>
                      state.position.axis == Axis.vertical &&
                      state.position.maxScrollExtent > 0,
                ),
            isTrue,
          );
          await tester.tap(find.byTooltip('Весь день'));
          await tester.pumpAndSettle();
          expect(
            tester.getRect(find.text('22:00')).bottom,
            lessThanOrEqualTo(size.height),
          );
          expect(tester.takeException(), isNull);
        }
      });
    }
  }

  for (final scale in [1.0, 1.25, 1.5]) {
    testWidgets('week and toolbar fit with text scale $scale', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 720);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(scale: scale));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('schedule-search-field')))
            .width,
        greaterThanOrEqualTo(140),
      );
      await tester.tap(find.text('Неделя'));
      await tester.pumpAndSettle();
      for (final header
          in find
              .byWidgetPredicate(
                (widget) =>
                    widget is Text && widget.data?.contains('\n') == true,
              )
              .evaluate()) {
        final paragraph = header.renderObject! as RenderParagraph;
        final painter = TextPainter(
          text: paragraph.text,
          textDirection: TextDirection.ltr,
          textScaler: TextScaler.linear(scale),
          maxLines: 2,
        )..layout(maxWidth: paragraph.size.width);
        expect(
          paragraph.size.height,
          greaterThanOrEqualTo(painter.height),
          reason: 'Both lines of each week date must fit without clipping.',
        );
        painter.dispose();
      }
      final range = find.byKey(const ValueKey('schedule-date-label'));
      expect(range, findsOneWidget);
      expect(
        tester.renderObject<RenderParagraph>(range).didExceedMaxLines,
        isFalse,
        reason: 'The complete week range must be readable.',
      );
      expect(tester.getRect(find.text('22:00')).bottom, lessThanOrEqualTo(720));
      expect(tester.takeException(), isNull);
      if (Platform.environment['CALENDAR_CAPTURE'] == '1') {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('capture')),
        );
        await tester.runAsync(() async {
          final picture = await boundary.toImage();
          final bytes = await picture.toByteData(
            format: ui.ImageByteFormat.png,
          );
          await File(
            'outputs/calendar-211-week-$scale.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          picture.dispose();
        });
      }
    });
  }

  testWidgets('teacher timeline fits hours and keeps short lessons separate', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1024, 768);
    addTearDown(tester.view.reset);
    final entries = [
      for (final minute in [0, 15, 55])
        ScheduleEntry(
          lesson: {'id': '$minute'},
          id: '$minute',
          columnId: 'teacher',
          startLocal: DateTime(2026, 9, 4, minute == 55 ? 23 : 12, minute),
          durationMinutes: 15,
          title: 'Короткое занятие',
          subtitle: 'Аудитория 1',
          isTrial: false,
          conflicts: const [],
          highlighted: false,
        ),
    ];
    String? opened;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.production,
        home: Scaffold(
          body: ScheduleTeacherTimeline(
            date: DateTime(2026, 9, 4),
            rows: const [
              ScheduleTeacherRow(
                id: 'teacher',
                name: 'Мария Иванова',
                color: Colors.brown,
                lessonCount: 3,
                totalMinutes: 45,
              ),
            ],
            entries: entries,
            onCreateSlot: (_, at, duration) {},
            onOpenLesson: (lesson) => opened = lesson['id'] as String,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final first = tester.getRect(
      find.byKey(const ValueKey('schedule-lesson-0')),
    );
    final next = tester.getRect(
      find.byKey(const ValueKey('schedule-lesson-15')),
    );
    expect(first.overlaps(next), isFalse);
    expect(
      tester.getRect(find.text('22:00-00:00')).right,
      lessThanOrEqualTo(1024),
    );
    await tester.tap(find.byKey(const ValueKey('schedule-lesson-55')));
    expect(opened, '55');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    '15-minute slot uses adaptive geometry, late lessons remain accessible',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1100, 720);
      addTearDown(tester.view.reset);
      DateTime? created;
      String? opened;
      final date = DateTime(2026, 9, 4);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScheduleDayCanvas(
              date: date,
              columns: const [
                ScheduleColumn(
                  id: 'room',
                  name: 'Аудитория',
                  color: Colors.brown,
                ),
              ],
              entries: [
                ScheduleEntry(
                  lesson: const {'id': 'late'},
                  id: 'late',
                  columnId: 'room',
                  startLocal: DateTime(2026, 9, 4, 23, 55),
                  durationMinutes: 15,
                  title: 'Позднее занятие',
                  subtitle: '',
                  isTrial: false,
                  conflicts: const [],
                  highlighted: false,
                ),
              ],
              onCreateSlot: (_, at, duration) => created = at,
              onOpenLesson: (lesson) => opened = lesson['id'] as String,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('00:00')).bottom, lessThanOrEqualTo(720));
      final y8 = tester.getCenter(find.text('08:00')).dy;
      final y9 = tester.getCenter(find.text('09:00')).dy;
      await tester.tapAt(Offset(200, y8 + (y9 - y8) * 4.4));
      expect(created, DateTime(2026, 9, 4, 12, 15));
      await tester.tap(find.byKey(const ValueKey('schedule-lesson-late')));
      expect(opened, 'late');
      expect(tester.takeException(), isNull);
    },
  );
}
