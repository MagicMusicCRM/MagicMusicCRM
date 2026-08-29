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

  testWidgets('historical occurrences require a visible second confirmation', (
    tester,
  ) async {
    var validationCalls = 0;
    Object? result;
    final row = PreferredScheduleDraft(
      branchId: 'branch-a',
      weekdays: const {1},
      beginTime: '10:00',
      durationMinutes: 60,
      lessonsPerDay: 1,
      validFrom: DateTime(2026, 7, 1),
      validUntil: DateTime(2026, 9, 1),
      teacherId: 'teacher-a',
      roomId: 'room-a',
      notes: '',
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () async {
                  result = await Navigator.of(context).push<Object?>(
                    MaterialPageRoute(
                      builder: (_) => Scaffold(
                        body: SchedulePlanRowsReview(
                          initialRows: [row],
                          rowSummary: (_) =>
                              'Педагог · Аудитория · Филиал · 60 мин',
                          onEditDraft: (_, _, _) async => null,
                          onValidate: (_) async {
                            validationCalls += 1;
                            return {
                              'valid': true,
                              'rows': const [],
                              'historical': {
                                'confirmRequired': true,
                                'count': 2,
                                'from': '2026-07-06',
                                'until': '2026-07-13',
                                'previewToken': 'signed-history-preview',
                                'previewExpiresAt': '2026-08-29T12:05:00.000Z',
                                'occurrences': const [
                                  {
                                    'rowIndex': 0,
                                    'localDate': '2026-07-06',
                                    'startAt': '2026-07-06T07:00:00.000Z',
                                    'endAt': '2026-07-06T08:00:00.000Z',
                                  },
                                  {
                                    'rowIndex': 0,
                                    'localDate': '2026-07-13',
                                    'startAt': '2026-07-13T07:00:00.000Z',
                                    'endAt': '2026-07-13T08:00:00.000Z',
                                  },
                                ],
                              },
                            };
                          },
                        ),
                      ),
                    ),
                  );
                },
                child: const Text('Открыть проверку'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Открыть проверку'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('schedule-plan-preview-and-create')));
    await tester.pumpAndSettle();

    expect(validationCalls, 1);
    expect(find.byKey(const Key('schedule-plan-history-review')), findsOne);
    expect(find.text('Исторические занятия: 2'), findsOne);
    expect(
      find.text(
        '2026-07-06 — 2026-07-13. '
        'Подтвердите изменение этого периода расписания.',
      ),
      findsOne,
    );
    expect(find.text('Подтвердить и создать'), findsOne);
    expect(result, isNull);

    await tester.tap(find.byKey(const Key('schedule-plan-preview-and-create')));
    await tester.pumpAndSettle();

    final confirmed =
        result
            as ({
              List<PreferredScheduleDraft> rows,
              String? historyPreviewToken,
            });
    expect(validationCalls, 1);
    expect(confirmed.rows, [row]);
    expect(confirmed.historyPreviewToken, 'signed-history-preview');
  });
}
