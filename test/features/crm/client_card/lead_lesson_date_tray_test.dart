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
}
