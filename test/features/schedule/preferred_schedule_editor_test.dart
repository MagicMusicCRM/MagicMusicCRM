import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/widgets/magic_sheet.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/preferred_schedule_editor.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_decision/lesson_decision_models.dart';

const _branches = [
  {'id': 'branch-a', 'name': 'Сокол'},
  {'id': 'branch-b', 'name': 'Центр'},
];
const _teachers = [
  {
    'id': 'teacher-a',
    'first_name': 'Мария',
    'last_name': 'Иванова',
    'status': 'active',
    'assigned_branches': [
      {'id': 'branch-a', 'name': 'Сокол'},
    ],
  },
];
const _rooms = [
  {'id': 'room-a', 'branch_id': 'branch-a', 'name': 'Класс 1'},
  {'id': 'room-b', 'branch_id': 'branch-b', 'name': 'Класс 2'},
];

void main() {
  for (final width in const [360.0, 840.0]) {
    testWidgets('editor uses client branch and fits ${width.toInt()}', (
      tester,
    ) async {
      await _openEditor(tester, width: width);

      expect(find.text('Сокол'), findsOneWidget);
      expect(find.text('Вся школа'), findsNothing);
      expect(find.text('Дни недели'), findsOneWidget);
      expect(find.text('Занятий в день'), findsOneWidget);
      expect(find.text('Дата начала'), findsOneWidget);
      expect(find.text('Дата окончания'), findsOneWidget);
      expect(find.text('Описание'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('validation keeps an incomplete preference open', (tester) async {
    await _openEditor(tester, width: 840);

    await tester.ensureVisible(
      find.byKey(const ValueKey('preferred-schedule-save')),
    );
    await tester.tap(find.byKey(const ValueKey('preferred-schedule-save')));
    await tester.pumpAndSettle();

    expect(find.text('Выберите педагога.'), findsOneWidget);
    expect(find.byKey(const ValueKey('magic-sheet-frame')), findsOneWidget);
  });

  testWidgets('system Back protects dirty preference input', (tester) async {
    await _openEditor(tester, width: 360);
    await tester.tap(find.byKey(const ValueKey('magic-sheet-toggle')));
    await tester.pumpAndSettle();
    final notes = find.byKey(const ValueKey('preferred-schedule-notes'));
    await tester.ensureVisible(notes);
    await tester.enterText(notes, 'Только после школы');
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Сохранить изменения?'), findsOneWidget);
    await tester.tap(find.text('Остаться'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('magic-sheet-frame')), findsOneWidget);
    expect(find.text('Только после школы'), findsOneWidget);
  });

  testWidgets('editor returns weekdays and consecutive lessons per day', (
    tester,
  ) async {
    PreferredScheduleDraft? result;
    await _openEditor(tester, width: 840, onResult: (value) => result = value);

    final monday = find.byKey(const ValueKey('preferred-schedule-weekday-1'));
    if (!tester.widget<FilterChip>(monday).selected) {
      await tester.tap(monday);
    }
    await _choose(
      tester,
      const ValueKey('preferred-schedule-teacher'),
      'Мария Иванова',
    );
    await _choose(tester, const ValueKey('preferred-schedule-room'), 'Класс 1');

    await tester.tap(
      find.byKey(const ValueKey('preferred-schedule-lessons-per-day')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('2').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('preferred-schedule-save')),
    );
    await tester.tap(find.byKey(const ValueKey('preferred-schedule-save')));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.branchId, 'branch-a');
    expect(result!.teacherId, 'teacher-a');
    expect(result!.roomId, 'room-a');
    expect(result!.weekdays, contains(DateTime.monday));
    expect(result!.lessonsPerDay, 2);
  });

  testWidgets('plan editor opens the date picker for a historical start', (
    tester,
  ) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final historicalStart = today.subtract(const Duration(days: 30));
    await _openEditor(
      tester,
      width: 840,
      editor: PreferredScheduleEditor(
        branches: _branches,
        teachers: _teachers,
        rooms: _rooms,
        defaultBranchId: 'branch-a',
        planMode: true,
        initialTitle: 'Исторический период',
        initialDraft: PreferredScheduleDraft(
          branchId: 'branch-a',
          weekdays: const {DateTime.monday},
          beginTime: '10:00',
          durationMinutes: 60,
          lessonsPerDay: 1,
          validFrom: historicalStart,
          validUntil: today.add(const Duration(days: 30)),
          teacherId: 'teacher-a',
          roomId: 'room-a',
          notes: '',
        ),
      ),
    );

    final startField = find.byKey(const ValueKey('preferred-schedule-start'));
    await tester.ensureVisible(startField);
    await tester.tap(startField);
    await tester.pumpAndSettle();

    expect(find.byType(DatePickerDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('operational plan editor hides teacher compensation control', (
    tester,
  ) async {
    await _openEditor(
      tester,
      width: 840,
      editor: const PreferredScheduleEditor(
        branches: _branches,
        teachers: _teachers,
        rooms: _rooms,
        defaultBranchId: 'branch-a',
        planMode: true,
        initialTitle: 'План',
        canManageTeacherCompensation: false,
        decisionCatalogs: {
          'branch-a': LessonDecisionCatalog(
            settlementTypes: [
              LessonDecisionCatalogItem(key: 'visit', label: 'Визит', order: 0),
            ],
            compensationRules: [
              LessonDecisionCatalogItem(
                key: 'hourly',
                label: 'Почасовая',
                order: 0,
              ),
            ],
          ),
        },
      ),
    );

    expect(
      find.byKey(const ValueKey('schedule-plan-settlement-type')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('schedule-plan-compensation-rule')),
      findsNothing,
    );
  });

  for (final width in const [360.0, 840.0]) {
    testWidgets(
      'partial recurring controls fit ${width.toInt()} without overflow',
      (tester) async {
        await _openEditor(
          tester,
          width: width,
          editor: PreferredScheduleEditor(
            branches: _branches,
            teachers: _teachers,
            rooms: _rooms,
            defaultBranchId: 'branch-a',
            planMode: true,
            initialTitle: 'Частичное занятие',
            canManageTeacherCompensation: true,
            decisionCatalogs: _partialCatalogs,
            initialDraft: PreferredScheduleDraft(
              branchId: 'branch-a',
              weekdays: const {DateTime.monday},
              beginTime: '10:00',
              durationMinutes: 60,
              lessonsPerDay: 1,
              validFrom: DateTime(2026, 9, 1),
              validUntil: DateTime(2026, 12, 1),
              teacherId: 'teacher-a',
              roomId: 'room-a',
              notes: '',
              settlementTypeKey: 'partial',
              teacherCompensationRuleKey: 'percent',
              teacherCreditedDurationMinutes: 45,
              teacherCompensationSource: 'manual',
              clientDecisions: const [
                {'clientId': 'student-a', 'chargeDurationMinutes': 30},
              ],
            ),
          ),
        );

        expect(
          find.byKey(const ValueKey('schedule-plan-teacher-minutes')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('schedule-plan-client-minutes-student-a')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('schedule-plan-apply-recommendation')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('existing row displays frozen keys removed from the catalog', (
    tester,
  ) async {
    await _openEditor(
      tester,
      width: 840,
      editor: const PreferredScheduleEditor(
        branches: _branches,
        teachers: _teachers,
        rooms: _rooms,
        defaultBranchId: 'branch-a',
        planMode: true,
        initialTitle: 'Историческая строка',
        canManageTeacherCompensation: true,
        decisionCatalogs: _partialCatalogs,
        series: {
          'id': 'series-a',
          'branch_id': 'branch-a',
          'weekday': 1,
          'begin_time': '10:00',
          'duration_minutes': 60,
          'valid_from': '2026-09-01',
          'valid_until': '2026-12-01',
          'teacher_id': 'teacher-a',
          'room_id': 'room-a',
          'financial_decision': {
            'settlementTypeKey': 'archived-partial',
            'teacherCompensationRuleKey': 'archived-percent',
            'teacherCreditedDurationMinutes': 37,
            'teacherCompensationSource': 'manual',
            'clientDecisions': [
              {'clientId': 'student-a', 'chargeDurationMinutes': 19},
            ],
          },
        },
      ),
    );

    expect(find.text('Сохранено: archived-partial'), findsOneWidget);
    expect(find.text('Сохранено: archived-percent'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final width in const [360.0, 840.0]) {
    testWidgets(
      'four participant minute fields stay usable at ${width.toInt()}',
      (tester) async {
        const clientIds = ['student-a', 'student-b', 'student-c', 'student-d'];
        await _openEditor(
          tester,
          width: width,
          editor: PreferredScheduleEditor(
            branches: _branches,
            teachers: _teachers,
            rooms: _rooms,
            defaultBranchId: 'branch-a',
            planMode: true,
            initialTitle: 'Групповое частичное занятие',
            canManageTeacherCompensation: true,
            decisionCatalogs: _partialCatalogs,
            participantLabels: const {
              'student-a': 'Александра Смирнова',
              'student-b': 'Владислав Кузнецов',
              'student-c': 'Екатерина Морозова',
              'student-d': 'Константин Волков',
            },
            initialDraft: PreferredScheduleDraft(
              branchId: 'branch-a',
              weekdays: const {DateTime.monday},
              beginTime: '10:00',
              durationMinutes: 60,
              lessonsPerDay: 1,
              validFrom: DateTime(2026, 9, 1),
              validUntil: DateTime(2026, 12, 1),
              teacherId: 'teacher-a',
              roomId: 'room-a',
              notes: '',
              settlementTypeKey: 'partial',
              teacherCompensationRuleKey: 'percent',
              teacherCreditedDurationMinutes: 45,
              teacherCompensationSource: 'manual',
              clientDecisions: [
                for (final clientId in clientIds)
                  {'clientId': clientId, 'chargeDurationMinutes': 30},
              ],
            ),
          ),
        );

        for (final clientId in clientIds) {
          final field = find.byKey(
            ValueKey('schedule-plan-client-minutes-$clientId'),
          );
          expect(field, findsOneWidget);
          expect(tester.getSize(field).width, greaterThanOrEqualTo(220));
          final input = tester.widget<InputDecorator>(
            find.descendant(of: field, matching: find.byType(InputDecorator)),
          );
          expect(input.decoration.labelText, isNot(contains('\n')));
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}

const _partialCatalogs = {
  'branch-a': LessonDecisionCatalog(
    settlementTypes: [
      LessonDecisionCatalogItem(
        key: 'partial',
        label: 'Частично',
        order: 0,
        clientDurationMode: 'manual',
        teacherDurationMode: 'manual',
        defaultTeacherCompensationRuleKey: 'percent',
      ),
    ],
    compensationRules: [
      LessonDecisionCatalogItem(key: 'percent', label: 'Процент', order: 0),
    ],
  ),
};

Future<void> _choose(WidgetTester tester, Key field, String option) async {
  await tester.tap(find.byKey(field));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(MenuItemButton, option).hitTestable());
  await tester.pumpAndSettle();
}

Future<void> _openEditor(
  WidgetTester tester, {
  required double width,
  ValueChanged<PreferredScheduleDraft?>? onResult,
  PreferredScheduleEditor? editor,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        platform: width >= 840
            ? TargetPlatform.windows
            : TargetPlatform.android,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () async {
                final result = await showMagicSheet<PreferredScheduleDraft>(
                  context,
                  title: 'Добавить предпочтение',
                  builder: (_) =>
                      editor ??
                      const PreferredScheduleEditor(
                        branches: _branches,
                        teachers: _teachers,
                        rooms: _rooms,
                        defaultBranchId: 'branch-a',
                      ),
                );
                onResult?.call(result);
              },
              child: const Text('Открыть'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Открыть'));
  await tester.pumpAndSettle();
}
