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

  test('restores and builds the complete frozen recurring decision', () {
    final controller = _controller(
      series: const {
        'id': 'series-a',
        'branch_id': 'branch-a',
        'weekday': 1,
        'begin_time': '15:00',
        'duration_minutes': 60,
        'valid_from': '2026-08-28',
        'valid_until': '2026-11-26',
        'teacher_id': 'teacher-a',
        'room_id': 'room-a',
        'financial_decision': {
          'settlementTypeKey': 'partial',
          'teacherCompensationRuleKey': 'percent',
          'teacherCreditedDurationMinutes': 45,
          'teacherCompensationSource': 'manual',
          'clientDecisions': [
            {'clientId': 'student-a', 'chargeDurationMinutes': 30},
          ],
        },
      },
      decisionCatalogs: _durationCatalogs,
      canManageTeacherCompensation: true,
    )..initialize(now: DateTime(2026, 8, 27));

    expect(controller.state.teacherCreditedDurationInput, '45');
    expect(controller.state.teacherCompensationSource, 'manual');
    expect(controller.state.compensationTouched, isTrue);
    final draft = controller.buildDraft(title: 'План', notes: '');
    expect(draft.teacherCreditedDurationMinutes, 45);
    expect(draft.teacherCompensationSource, 'manual');
    expect(draft.clientDecisions, [
      {'clientId': 'student-a', 'chargeDurationMinutes': 30},
    ]);
  });

  test(
    'settlement changes recompute inherited client and untouched teacher minutes',
    () {
      final controller = _controller(
        initialDraft: _draft(
          settlementTypeKey: 'partial',
          teacherCompensationRuleKey: 'percent',
          teacherCreditedDurationMinutes: 30,
          teacherCompensationSource: 'automatic',
          clientDecisions: const [
            {'clientId': 'student-a', 'chargeDurationMinutes': 20},
            {
              'clientId': 'student-b',
              'settlementTypeKey': 'partial',
              'chargeDurationMinutes': 15,
            },
          ],
        ),
        decisionCatalogs: _durationCatalogs,
      )..initialize(now: DateTime(2026, 8, 27));

      controller.selectSettlementType('full');

      expect(controller.state.teacherCompensationRuleKey, 'standard');
      expect(controller.state.teacherCreditedDurationInput, '60');
      expect(controller.state.teacherCompensationSource, 'automatic');
      expect(controller.state.clientDecisions, [
        {'clientId': 'student-a', 'chargeDurationMinutes': 60},
        {
          'clientId': 'student-b',
          'settlementTypeKey': 'partial',
          'chargeDurationMinutes': 15,
        },
      ]);
    },
  );

  test('manual teacher minutes stay exact until recommendation is applied', () {
    final controller = _controller(
      initialDraft: _draft(
        settlementTypeKey: 'partial',
        teacherCompensationRuleKey: 'percent',
        teacherCreditedDurationMinutes: 45,
        teacherCompensationSource: 'manual',
      ),
      decisionCatalogs: _durationCatalogs,
    )..initialize(now: DateTime(2026, 8, 27));

    controller.selectSettlementType('full');
    expect(controller.state.teacherCompensationRuleKey, 'percent');
    expect(controller.state.teacherCreditedDurationInput, '45');
    expect(controller.state.compensationTouched, isTrue);

    controller.applyRecommendedTeacherCompensation();
    expect(controller.state.teacherCompensationRuleKey, 'standard');
    expect(controller.state.teacherCreditedDurationInput, '60');
    expect(controller.state.teacherCompensationSource, 'automatic');
    expect(controller.state.compensationTouched, isFalse);
  });

  test(
    'duration changes report out-of-range manual minutes without clamping',
    () {
      final controller = _controller(
        planMode: true,
        requireFinancialDecision: true,
        initialDraft: _draft(
          teacherId: 'teacher-a',
          roomId: 'room-a',
          settlementTypeKey: 'partial',
          teacherCompensationRuleKey: 'percent',
          teacherCreditedDurationMinutes: 45,
          teacherCompensationSource: 'manual',
          clientDecisions: const [
            {'clientId': 'student-a', 'chargeDurationMinutes': 40},
          ],
        ),
        decisionCatalogs: _durationCatalogs,
      )..initialize(now: DateTime(2026, 8, 27));

      controller.selectDurationMinutes(30);

      expect(controller.state.teacherCreditedDurationInput, '45');
      expect(
        controller.state.clientDecisions.single['chargeDurationMinutes'],
        40,
      );
      expect(controller.validate(title: 'План'), isFalse);
      expect(controller.state.validationError, 'Не больше 30 мин');
    },
  );

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
  int? teacherCreditedDurationMinutes,
  String? teacherCompensationSource,
  List<Map<String, dynamic>> clientDecisions = const [],
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
  teacherCreditedDurationMinutes: teacherCreditedDurationMinutes,
  teacherCompensationSource: teacherCompensationSource,
  clientDecisions: clientDecisions,
);

const _durationCatalogs = {
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
      LessonDecisionCatalogItem(
        key: 'full',
        label: 'Полностью',
        order: 1,
        clientDurationMode: 'full',
        teacherDurationMode: 'full',
        defaultTeacherCompensationRuleKey: 'standard',
      ),
      LessonDecisionCatalogItem(
        key: 'zero',
        label: 'Без оплаты',
        order: 2,
        clientDurationMode: 'zero',
        teacherDurationMode: 'zero',
        defaultTeacherCompensationRuleKey: 'none',
      ),
    ],
    compensationRules: [
      LessonDecisionCatalogItem(key: 'none', label: 'Нет', order: 0),
      LessonDecisionCatalogItem(key: 'standard', label: 'Ставка', order: 1),
      LessonDecisionCatalogItem(key: 'percent', label: 'Процент', order: 2),
    ],
  ),
};
