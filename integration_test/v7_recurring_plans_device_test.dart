import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/recurring_schedule_plan_section.dart';

import '../test/features/crm/client_card/card_fake_api.dart';

const _activePlan = {
  'id': 'plan-active',
  'kind': 'individual',
  'title': 'Индивидуальный вокал',
  'studentId': 'student-1',
  'subscriptionId': 'subscription-1',
  'activeFrom': '2026-08-01',
  'activeUntil': null,
  'status': 'active',
  'version': 1,
  'rows': [
    {
      'id': 'series-active',
      'teacherId': 'teacher-1',
      'teacherName': 'Мария Иванова',
      'roomId': 'room-1',
      'roomName': 'Класс 1',
      'branchId': 'branch-1',
      'branchName': 'Сокол',
      'weekday': 4,
      'beginTime': '16:00',
      'durationMinutes': 60,
      'validFrom': '2026-08-01',
      'validUntil': null,
      'financialDecision': {
        'settlementTypeKey': 'free_lesson',
        'teacherCompensationRuleKey': 'none',
      },
      'active': true,
    },
  ],
};

const _endedPlan = {
  'id': 'plan-ended',
  'kind': 'individual',
  'title': 'Завершённое фортепиано',
  'studentId': 'student-1',
  'subscriptionId': 'subscription-1',
  'activeFrom': '2026-01-01',
  'activeUntil': '2026-07-31',
  'status': 'ended',
  'version': 2,
  'rows': <Map<String, dynamic>>[],
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('recurring plan lifecycle keeps card state on device', (
    tester,
  ) async {
    await initializeDateFormatting('ru');
    final api = FakeCardApiClient(
      role: 'manager',
      branches: const [
        {'id': 'branch-1', 'name': 'Сокол'},
      ],
      teachers: const [
        {'id': 'teacher-1', 'firstName': 'Мария', 'lastName': 'Иванова'},
        {'id': 'teacher-2', 'firstName': 'Пётр', 'lastName': 'Сидоров'},
      ],
      rooms: const [
        {'id': 'room-1', 'branchId': 'branch-1', 'name': 'Класс 1'},
        {'id': 'room-2', 'branchId': 'branch-1', 'name': 'Класс 2'},
      ],
      schedulePlans: const [_activePlan, _endedPlan],
      schedulePlanTrays: const {
        'plan-active': {
          'planId': 'plan-active',
          'items': [
            {
              'id': 'lesson-active',
              'scheduledAt': '2026-08-07T13:00:00.000Z',
              'localDate': '2026-08-07',
              'localTime': '16:00',
              'state': 'scheduled',
              'settlementMarkers': [
                {
                  'key': 'paid_absence',
                  'label': 'Оплачиваемый пропуск',
                  'colorToken': 'blue',
                },
              ],
              'relationMarker': 'none',
              'teacher': {'id': 'teacher-1', 'name': 'Мария Иванова'},
              'room': {'id': 'room-1', 'name': 'Класс 1'},
            },
          ],
          'hasPrevious': false,
          'hasNext': false,
        },
      },
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [magicApiClientProvider.overrideWithValue(api)],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: RecurringSchedulePlanSection(
                  studentId: 'student-1',
                  fallbackLessons: const [],
                  branches: api.branches,
                  defaultBranchId: 'branch-1',
                  subscriptions: const [
                    {'id': 'subscription-1', 'label': '12 занятий'},
                  ],
                  canWrite: true,
                  onChanged: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Индивидуальный вокал'), findsOneWidget);
    expect(find.byKey(const Key('client-lesson-date-tray')), findsOneWidget);
    expect(find.text('Завершённое фортепиано'), findsNothing);
    await tester.ensureVisible(find.text('Завершённые (1)'));
    await tester.tap(find.text('Завершённые (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Завершённое фортепиано'), findsOneWidget);

    final edit = find.byKey(
      const ValueKey('schedule-plan-row-edit-series-active'),
    );
    await tester.ensureVisible(edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    expect(find.text('Изменить строку'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Индивидуальный вокал'), findsOneWidget);
    expect(find.text('Мария Иванова'), findsWidgets);

    await tester.ensureVisible(find.byKey(const Key('schedule-plan-add')));
    await tester.tap(find.byKey(const Key('schedule-plan-add')));
    await tester.pumpAndSettle();
    await _chooseReferences(tester);
    await _saveEditor(tester);
    expect(
      find.byKey(const ValueKey('schedule-plan-row-group-0')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('schedule-plan-add-row-group')));
    await tester.pumpAndSettle();
    final currentDay = DateTime.now().weekday;
    final otherDay = currentDay == 7 ? 1 : currentDay + 1;
    await tester.tap(
      find.byKey(ValueKey('preferred-schedule-weekday-$currentDay')),
    );
    await tester.tap(
      find.byKey(ValueKey('preferred-schedule-weekday-$otherDay')),
    );
    await tester.tap(find.text('Мария Иванова').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Пётр Сидоров').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Класс 1').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Класс 2').last);
    await tester.pumpAndSettle();
    await _saveEditor(tester);
    await tester.tap(find.byKey(const Key('schedule-plan-preview-and-create')));
    await tester.pumpAndSettle();
    expect(
      api.idempotentRequests.where(
        (request) => request.path == '/crm/schedule-plans',
      ),
      hasLength(1),
    );

    await tester.ensureVisible(edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    await _saveEditor(tester);
    expect(
      api.idempotentRequests.where(
        (request) => request.path == '/crm/schedule-plans/plan-active',
      ),
      hasLength(1),
    );

    final end = find.byKey(const ValueKey('schedule-plan-end-plan-active'));
    await tester.ensureVisible(end);
    await tester.tap(end);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('schedule-plan-end-reason')),
      'Клиент завершил занятия',
    );
    final submit = find.byKey(const Key('schedule-plan-end-submit'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('schedule-plan-end-impact')), findsOneWidget);
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(
      api.idempotentRequests.where(
        (request) => request.path == '/crm/schedule-plans/plan-active/end',
      ),
      hasLength(1),
    );
    expect(tester.takeException(), isNull);
    debugPrint('V7_RECURRING_PLANS_DEVICE_PASS');
  });
}

Future<void> _chooseReferences(WidgetTester tester) async {
  final teacher = find.text('Выберите педагога');
  await tester.ensureVisible(teacher);
  await tester.tap(teacher);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Мария Иванова').last);
  await tester.pumpAndSettle();
  final room = find.text('Выберите аудиторию');
  await tester.ensureVisible(room);
  await tester.tap(room);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Класс 1').last);
  await tester.pumpAndSettle();
  await tester.ensureVisible(
    find.byKey(const ValueKey('schedule-plan-settlement-type')),
  );
  await tester.tap(find.byKey(const ValueKey('schedule-plan-settlement-type')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Бесплатное занятие').last);
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(const ValueKey('schedule-plan-compensation-rule')),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Не оплачивать').last);
  await tester.pumpAndSettle();
}

Future<void> _saveEditor(WidgetTester tester) async {
  final save = find.byKey(const ValueKey('preferred-schedule-save'));
  await tester.ensureVisible(save);
  await tester.tap(save);
  await tester.pumpAndSettle();
}
