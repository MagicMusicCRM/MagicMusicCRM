import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/theme/lesson_state_palette.dart';
import 'package:magic_music_crm/core/widgets/lesson_state_badges.dart';

void main() {
  group('Lesson state + reservation projection', () {
    test('expected lesson without reservation is neutral', () {
      final projection = lessonStateProjection(lifecycleState: 'scheduled');

      expect(projection.token, LessonStateToken.neutral);
      expect(projection.token.accent, AppColor.text2);
      expect(projection.label, 'Запланировано');
    });

    test('reserved slot is green independently of lifecycle', () {
      final projection = lessonStateProjection(
        lifecycleState: 'scheduled',
        reservationState: 'reserved',
      );

      expect(projection.token, LessonStateToken.success);
      expect(projection.token.accent, AppColor.success);
      expect(projection.label, 'Забронировано');
    });

    test('successful completion is green without reservation', () {
      final projection = lessonStateProjection(
        lifecycleState: 'successfully_completed',
      );

      expect(projection.token, LessonStateToken.success);
      expect(projection.label, 'Завершено');
    });

    test('rescheduled source remains red even when reservation exists', () {
      final projection = lessonStateProjection(
        lifecycleState: 'rescheduled',
        reservationState: 'reserved',
      );

      expect(projection.token, LessonStateToken.rescheduled);
      expect(projection.token.accent, AppColor.danger);
      expect(projection.label, 'Перенесено');
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
        LessonStateToken.neutral,
      );
    });
  });

  testWidgets('trial marker is rendered separately from state', (tester) async {
    final projection = lessonStateProjection(
      lifecycleState: 'scheduled',
      reservationState: 'reserved',
    );

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

    expect(find.text('Пробный урок'), findsOneWidget);
    expect(find.text('Забронировано'), findsOneWidget);
  });
}
