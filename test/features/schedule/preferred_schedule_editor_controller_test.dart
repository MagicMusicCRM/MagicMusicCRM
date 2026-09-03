import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_decision/lesson_decision_models.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/preferred_schedule_draft.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/preferred_schedule_editor_controller.dart';

const _branches = [
  {'id': 'branch-a', 'name': 'Сокол'},
  {'id': 'branch-b', 'name': 'Центр'},
];
const _teachers = [
  {
    'id': 'teacher-a',
    'status': 'active',
    'assigned_branches': [
      {'id': 'branch-a'},
    ],
  },
  {
    'id': 'teacher-inactive',
    'status': 'inactive',
    'assigned_branches': [
      {'id': 'branch-a'},
    ],
  },
  {
    'id': 'teacher-b',
    'status': 'active',
    'assigned_branches': [
      {'id': 'branch-b'},
    ],
  },
];
const _rooms = [
  {'id': 'room-a', 'branch_id': 'branch-a', 'name': 'Класс 1'},
  {'id': 'room-b', 'branch_id': 'branch-b', 'name': 'Класс 2'},
];
const _catalogs = {
  'branch-a': LessonDecisionCatalog(
    settlementTypes: [
      LessonDecisionCatalogItem(key: 'visit', label: 'Визит', order: 0),
    ],
    compensationRules: [
      LessonDecisionCatalogItem(key: 'hourly', label: 'Почасовая', order: 0),
    ],
  ),
  'branch-b': LessonDecisionCatalog(
    settlementTypes: [
      LessonDecisionCatalogItem(key: 'package', label: 'Пакет', order: 0),
    ],
    compensationRules: [
      LessonDecisionCatalogItem(key: 'fixed', label: 'Фиксированная', order: 0),
    ],
  ),
};

void main() {
  test('filters branch resources and clears incompatible selections', () {
    final controller = _controller(
      initialDraft: _draft(
        branchId: 'branch-a',
        teacherId: 'teacher-a',
        roomId: 'room-a',
      ),
    )..initialize(now: DateTime(2026, 8, 27));

    expect(controller.state.teacherId, 'teacher-a');
    expect(controller.state.roomId, 'room-a');
    expect(controller.teachersForBranch.map((item) => item['id']), [
      'teacher-a',
    ]);
    expect(controller.roomsForBranch.map((item) => item['id']), ['room-a']);

    controller.selectBranch('branch-b');

    expect(controller.state.branchId, 'branch-b');
    expect(controller.state.teacherId, isNull);
    expect(controller.state.roomId, isNull);
    expect(controller.teachersForBranch.map((item) => item['id']), [
      'teacher-b',
    ]);
    expect(controller.roomsForBranch.map((item) => item['id']), ['room-b']);
  });

  test(
    'keeps a plan period past start editable and applies subscription fallback',
    () {
      final controller = _controller(
        allowOpenEnded: true,
        initialSubscriptionId: 'missing',
        subscriptionOptions: const [
          {'id': 'subscription-a', 'label': 'Абонемент'},
        ],
        planMode: true,
        series: const {
          'id': 'series-a',
          'branch_id': 'branch-a',
          'weekday': 2,
          'begin_time': '16:30',
          'duration_minutes': 45,
          'valid_from': '2025-01-01',
          'valid_until': null,
          'teacher_id': 'teacher-a',
          'room_id': 'room-a',
        },
      )..initialize(now: DateTime(2026, 8, 27, 18));

      expect(controller.state.validFrom, DateTime(2025, 1, 1));
      expect(controller.state.validUntil, DateTime(2025, 4, 1));
      expect(controller.state.openEnded, isTrue);
      expect(controller.state.subscriptionId, 'subscription-a');
    },
  );

  test('synchronizes financial decisions with the selected branch', () {
    final controller = _controller(
      initialDraft: _draft(
        settlementTypeKey: 'obsolete',
        teacherCompensationRuleKey: 'obsolete',
      ),
    )..initialize(now: DateTime(2026, 8, 27));

    expect(controller.state.settlementTypeKey, 'visit');
    expect(controller.state.teacherCompensationRuleKey, 'hourly');

    controller.selectBranch('branch-b');

    expect(controller.state.settlementTypeKey, 'package');
    expect(controller.state.teacherCompensationRuleKey, 'fixed');
  });

  test('reports the exact validation errors in form priority order', () {
    final empty = PreferredScheduleEditorController(
      branches: const [],
      teachers: const [],
      rooms: const [],
      defaultBranchId: null,
    )..initialize(now: DateTime(2026, 8, 27));
    expect(empty.validate(title: ''), isFalse);
    expect(empty.state.validationError, 'Выберите филиал.');

    final controller = _controller(
      planMode: true,
      requireSubscription: true,
      requireFinancialDecision: true,
      subscriptionOptions: const [],
      decisionCatalogs: const {},
    )..initialize(now: DateTime(2026, 8, 27));

    expect(controller.validate(title: ''), isFalse);
    expect(controller.state.validationError, 'Укажите название расписания.');
    expect(controller.validate(title: 'План'), isFalse);
    expect(controller.state.validationError, 'Выберите абонемент.');

    controller.selectSubscription('subscription-a');
    final initialDay = controller.state.weekdays.single;
    controller.toggleWeekday(initialDay, false);
    expect(controller.validate(title: 'План'), isFalse);
    expect(
      controller.state.validationError,
      'Выберите хотя бы один день недели.',
    );

    controller.toggleWeekday(initialDay, true);
    expect(controller.validate(title: 'План'), isFalse);
    expect(controller.state.validationError, 'Выберите педагога.');
    controller.selectTeacher('teacher-a');
    expect(controller.validate(title: 'План'), isFalse);
    expect(controller.state.validationError, 'Выберите аудиторию.');
    controller.selectRoom('room-a');
    expect(controller.validate(title: 'План'), isFalse);
    expect(controller.state.validationError, 'Выберите тип списания.');
    controller.selectSettlementType('visit');
    expect(controller.validate(title: 'План'), isFalse);
    expect(controller.state.validationError, 'Выберите оплату преподавателю.');
    controller.selectTeacherCompensationRule('hourly');
    controller.setOpenEnded(false);
    controller.setValidUntil(DateTime(2026, 8, 26));
    expect(controller.validate(title: 'План'), isFalse);
    expect(
      controller.state.validationError,
      'Дата окончания не может быть раньше даты начала.',
    );
    controller.setValidUntil(DateTime(2026, 8, 30));
    controller.setBeginTime('23:30');
    expect(controller.validate(title: 'План'), isFalse);
    expect(
      controller.state.validationError,
      'Последнее занятие выходит за границы выбранного дня.',
    );
    controller.setBeginTime('20:00');
    expect(controller.validate(title: 'План'), isTrue);
    expect(controller.state.validationError, isNull);
  });

  test('builds an immutable trimmed draft', () {
    final controller = _controller(
      planMode: true,
      initialDraft: _draft(
        teacherId: 'teacher-a',
        roomId: 'room-a',
        settlementTypeKey: 'visit',
        teacherCompensationRuleKey: 'hourly',
      ),
    )..initialize(now: DateTime(2026, 8, 27));

    final draft = controller.buildDraft(
      title: '  Постоянное расписание  ',
      notes: '  Только после школы  ',
    );

    expect(draft.title, 'Постоянное расписание');
    expect(draft.notes, 'Только после школы');
    expect(draft.branchId, 'branch-a');
    expect(() => draft.weekdays.add(7), throwsUnsupportedError);
  });

  test('operational editor does not require teacher compensation input', () {
    final controller = _controller(
      planMode: true,
      requireFinancialDecision: true,
      canManageTeacherCompensation: false,
      initialDraft: _draft(
        teacherId: 'teacher-a',
        roomId: 'room-a',
        settlementTypeKey: 'visit',
      ),
    )..initialize(now: DateTime(2026, 8, 27));

    expect(controller.validate(title: 'План'), isTrue);
  });

  test('keeps services out of the view and validation out of the shell', () {
    final view = File(
      'lib/features/crm/presentation/client_card/'
      'preferred_schedule_editor_view.dart',
    ).readAsStringSync();
    final shell = File(
      'lib/features/crm/presentation/client_card/preferred_schedule_editor.dart',
    ).readAsStringSync();

    expect(view, isNot(contains('/services/')));
    expect(view, isNot(contains('MagicCrmService')));
    expect(view, isNot(contains('WidgetRef')));
    expect(view, isNot(contains('preferred_schedule_editor_controller.dart')));
    expect(view, contains('preferred_schedule_editor_state.dart'));
    expect(shell, contains('DirtyFormExitController'));
    expect(shell, contains('showMagicDatePicker'));
    expect(shell, contains('showMagicTimePicker'));
    expect(shell, isNot(contains('Выберите педагога.')));
    expect(shell, isNot(contains('Последнее занятие выходит')));
  });
}

PreferredScheduleEditorController _controller({
  PreferredScheduleDraft? initialDraft,
  Map<String, dynamic>? series,
  bool planMode = false,
  bool requireSubscription = false,
  bool allowOpenEnded = false,
  bool requireFinancialDecision = false,
  bool canManageTeacherCompensation = true,
  List<Map<String, dynamic>> subscriptionOptions = const [],
  String? initialSubscriptionId,
  Map<String, LessonDecisionCatalog> decisionCatalogs = _catalogs,
}) => PreferredScheduleEditorController(
  branches: _branches,
  teachers: _teachers,
  rooms: _rooms,
  defaultBranchId: 'branch-a',
  series: series,
  planMode: planMode,
  initialDraft: initialDraft,
  subscriptionOptions: subscriptionOptions,
  initialSubscriptionId: initialSubscriptionId,
  requireSubscription: requireSubscription,
  allowOpenEnded: allowOpenEnded,
  decisionCatalogs: decisionCatalogs,
  requireFinancialDecision: requireFinancialDecision,
  canManageTeacherCompensation: canManageTeacherCompensation,
);

PreferredScheduleDraft _draft({
  String branchId = 'branch-a',
  String teacherId = '',
  String roomId = '',
  String settlementTypeKey = '',
  String teacherCompensationRuleKey = '',
}) => PreferredScheduleDraft(
  branchId: branchId,
  weekdays: const {1},
  beginTime: '15:00',
  durationMinutes: 60,
  lessonsPerDay: 1,
  validFrom: DateTime(2026, 8, 28),
  validUntil: DateTime(2026, 11, 26),
  teacherId: teacherId,
  roomId: roomId,
  notes: '',
  settlementTypeKey: settlementTypeKey,
  teacherCompensationRuleKey: teacherCompensationRuleKey,
);
