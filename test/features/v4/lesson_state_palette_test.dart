import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/theme/lesson_state_palette.dart';
import 'package:magic_music_crm/core/widgets/lesson_state_badges.dart';

void main() {
  group('Lesson operational visual projection', () {
    test('scheduled lesson is booked', () {
      final projection = lessonStateProjection(lifecycleState: 'scheduled');

      expect(projection.token, LessonStateToken.booked);
      expect(projection.token.accent, AppColor.actionBlue);
      expect(projection.label, 'Забронировано');
    });

    test('reservation metadata does not change the booked color', () {
      final projection = LessonStateProjection.fromMap(const {
        'lifecycle_state': 'scheduled',
        'reservation_state': 'reserved',
      });

      expect(projection.token, LessonStateToken.booked);
      expect(projection.token.accent, AppColor.actionBlue);
      expect(projection.label, 'Забронировано');
    });

    test('successful completion is green without reservation', () {
      final projection = lessonStateProjection(
        lifecycleState: 'successfully_completed',
      );

      expect(projection.token, LessonStateToken.completed);
      expect(projection.token.accent, AppColor.success);
      expect(projection.label, 'Завершено');
    });

    test('automatic settlement exception uses the conflict color', () {
      final projection = lessonStateProjection(
        lifecycleState: 'settlement_pending',
      );

      expect(projection.token, LessonStateToken.conflict);
      expect(projection.label, 'Конфликт');
    });

    test('schedule conflict overrides completed state', () {
      final projection = lessonStateProjection(
        lifecycleState: 'successfully_completed',
        hasConflict: true,
      );

      expect(projection.token, LessonStateToken.conflict);
      expect(projection.token.accent, AppColor.danger);
      expect(projection.label, 'Конфликт');
    });

    test('legacy state is only a compatibility fallback', () {
      expect(
        LessonStateProjection.fromMap(const {'status': 'completed'}).state,
        'successfully_completed',
      );
      expect(
        LessonStateProjection.fromMap(const {
          'lifecycle_state': 'scheduled',
          'status': 'completed',
        }).token,
        LessonStateToken.booked,
      );
      expect(
        LessonStateProjection.fromMap(const {
          'status': 'scheduled',
          'conflict_types': ['room_overlap'],
        }).token,
        LessonStateToken.conflict,
      );
    });
  });

  testWidgets('trial marker is rendered separately from state', (tester) async {
    final projection = lessonStateProjection(lifecycleState: 'scheduled');

    await tester.pumpWidget(
      MaterialApp(
        home: Row(
          children: [
            const LessonTrialBadge(),
            LessonStateBadge(projection: projection),
          ],
        ),
      ),
    );

    expect(find.text('Пробное'), findsOneWidget);
    expect(find.text('Забронировано'), findsOneWidget);
  });
}
