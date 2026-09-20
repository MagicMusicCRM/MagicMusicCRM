import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_decision/lesson_decision_models.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_decision/lesson_decision_sections.dart';

void main() {
  for (final subject in ['CLIENT', 'TEACHER']) {
    for (final duration in ['ZERO', 'FULL']) {
      testWidgets('$subject $duration warning is readable', (tester) async {
        final code =
            '${subject}_${duration}_DURATION_SETTLEMENT_TYPE_RECOMMENDED';
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: LessonDecisionPreviewCard(
                preview: LessonDecisionPreview({
                  'canConfirm': true,
                  'warnings': [code],
                }),
                participantNames: const {},
              ),
            ),
          ),
        );
        expect(find.text(code), findsNothing);
        expect(
          find.textContaining('Можно подтвердить изменение'),
          findsOneWidget,
        );
      });
    }
  }
}
