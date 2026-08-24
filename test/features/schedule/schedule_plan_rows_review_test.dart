import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/preferred_schedule_draft.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/schedule_plan_rows_review.dart';

void main() {
  testWidgets('rows review owns preview submission without a CRM service', (
    tester,
  ) async {
    var validationCalls = 0;
    final row = PreferredScheduleDraft(
      branchId: 'branch-a',
      weekdays: const {1},
      beginTime: '10:00',
      durationMinutes: 60,
      lessonsPerDay: 1,
      validFrom: DateTime(2026, 8, 25),
      validUntil: DateTime(2026, 9, 25),
      teacherId: 'teacher-a',
      roomId: 'room-a',
      notes: '',
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SchedulePlanRowsReview(
              initialRows: [row],
              rowSummary: (_) => 'Педагог · Аудитория · Филиал · 60 мин',
              onEditDraft: (_, _, _) async => null,
              onValidate: (rows) async {
                validationCalls += 1;
                expect(rows, hasLength(1));
                return {'valid': false, 'rows': const []};
              },
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('schedule-plan-row-group-0')), findsOne);
    expect(find.textContaining('10:00'), findsOne);

    await tester.tap(find.byKey(const Key('schedule-plan-preview-and-create')));
    await tester.pumpAndSettle();

    expect(validationCalls, 1);
    expect(find.byKey(const ValueKey('schedule-plan-row-group-0')), findsOne);
  });
}
