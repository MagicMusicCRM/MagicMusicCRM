import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/lead_lesson_date_tray.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('lead lesson tray opens a lesson when editing is allowed', (
    tester,
  ) async {
    Map<String, dynamic>? openedLesson;
    final scheduledAt = DateTime.now().add(const Duration(days: 1));
    final lesson = <String, dynamic>{
      'id': 'lead-lesson-1',
      'scheduled_at': scheduledAt.toIso8601String(),
      'lifecycle_state': 'scheduled',
    };

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LeadLessonDateTray(
            lessons: [lesson],
            canWrite: true,
            onOpenLesson: (value) => openedLesson = value,
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('client-lesson-date-tray')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('client-lesson-lead-lesson-1')));

    expect(openedLesson, same(lesson));
  });

  testWidgets('trial section exposes create edit and cancel actions', (
    tester,
  ) async {
    Map<String, dynamic>? editedLesson;
    Map<String, dynamic>? cancelledLesson;
    var createCount = 0;
    final lesson = <String, dynamic>{
      'id': 'trial-1',
      'scheduled_at': DateTime(2026, 9, 22, 18, 30).toIso8601String(),
      'lifecycle_state': 'scheduled',
      'teacher_name': 'Анна Петрова',
      'room_name': 'Класс 2',
    };

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LeadTrialLessonsSection(
            lessons: [lesson],
            canWrite: true,
            onCreate: () => createCount += 1,
            onEdit: (value) => editedLesson = value,
            onCancel: (value) => cancelledLesson = value,
          ),
        ),
      ),
    );

    expect(find.text('Пробные занятия'), findsOneWidget);
    expect(find.text('Анна Петрова · Класс 2'), findsOneWidget);
    await tester.tap(find.byKey(const Key('lead-trial-create')));
    await tester.tap(find.byKey(const Key('lead-trial-edit-trial-1')));
    await tester.tap(find.byKey(const Key('lead-trial-cancel-trial-1')));

    expect(createCount, 1);
    expect(editedLesson, same(lesson));
    expect(cancelledLesson, same(lesson));
  });

  testWidgets('trial section stays read only without schedule write access', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LeadTrialLessonsSection(
            lessons: [
              <String, dynamic>{
                'id': 'trial-readonly',
                'scheduled_at': DateTime(2026, 9, 22).toIso8601String(),
                'lifecycle_state': 'scheduled',
              },
            ],
            canWrite: false,
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('lead-trial-create')), findsNothing);
    expect(
      find.byKey(const Key('lead-trial-edit-trial-readonly')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('lead-trial-cancel-trial-readonly')),
      findsNothing,
    );
  });
}
