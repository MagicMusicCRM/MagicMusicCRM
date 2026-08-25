import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/models/lesson_schedule_analysis.dart';
import 'package:magic_music_crm/core/widgets/searchable_picker_field.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_decision/lesson_decision_models.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_editor/lesson_editor_feedback.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_editor/lesson_financial_section.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_editor/lesson_editor_models.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_editor/lesson_participant_section.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_editor/lesson_schedule_section.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_editor/lesson_editor_view.dart';

Widget _host(Widget child) => MaterialApp(home: Material(child: child));

const _suggestion = ScheduleSuggestion(
  kind: 'SAME_TIME_ROOM',
  rank: 1,
  score: 100,
  roomId: 'room-b',
  roomName: 'Класс B',
);

const _violation = LessonConstraintViolation(
  code: 'ROOM_OVERLAP',
  resourceType: 'room',
  resourceId: 'room-a',
  conflictingLessonIds: ['lesson-a'],
  ruleIds: ['room-overlap'],
);

LessonEditorDraft _draft({DateTime? localStart}) => LessonEditorDraft(
  localStart: localStart ?? DateTime(2026, 8, 26, 13),
  durationMinutes: 60,
  isTrial: false,
  completionType: 'standard.success',
  clientChargeType: 'personal_account',
  client: const LessonClientRef(
    type: 'student',
    id: 'student-a',
    label: 'Анна',
  ),
  teacherId: 'teacher-a',
  branchId: 'branch-a',
  roomId: 'room-a',
  settlementTypeKey: 'paid',
  compensationRuleKey: 'standard',
);

LessonEditorSession _session({bool isEdit = false, LessonEditorDraft? draft}) {
  final value = draft ?? _draft();
  return LessonEditorSession(
    draft: value,
    snapshot: isEdit
        ? LessonEditorSnapshot(
            lessonId: 'lesson-a',
            expectedVersion: 4,
            rawLesson: const {'id': 'lesson-a'},
            clientLocked: true,
            initialSchedulePayload: const {},
            initialCompensationRuleKey: 'standard',
            initialCompensationValueMinor: null,
          )
        : null,
    seededClient: value.client,
  );
}

LessonEditorReferenceState _references() => LessonEditorReferenceState(
  teachers: const [
    LessonEditorReferenceItem(
      id: 'teacher-a',
      label: 'Иван Петров',
      raw: {},
      status: 'active',
      assignedBranchIds: {'branch-a'},
    ),
  ],
  clients: const [
    LessonEditorReferenceItem(
      id: 'student:student-a',
      label: 'Анна',
      raw: {
        'ref': {'type': 'student', 'id': 'student-a'},
      },
    ),
    LessonEditorReferenceItem(
      id: 'lead:lead-a',
      label: 'Олег',
      raw: {
        'ref': {'type': 'lead', 'id': 'lead-a'},
      },
    ),
  ],
  branches: const [
    LessonEditorReferenceItem(id: 'branch-a', label: 'Центр', raw: {}),
  ],
  rooms: const [
    LessonEditorReferenceItem(
      id: 'room-a',
      label: 'Класс A',
      raw: {},
      branchId: 'branch-a',
      status: 'active',
    ),
  ],
  subscriptions: const [
    LessonEditorReferenceItem(
      id: 'subscription-a',
      label: 'Абонемент · остаток 4',
      raw: {},
    ),
  ],
  catalog: const LessonDecisionCatalog(
    settlementTypes: [
      LessonDecisionCatalogItem(key: 'paid', label: 'Обычное', order: 1),
    ],
    compensationRules: [
      LessonDecisionCatalogItem(
        key: 'standard',
        label: 'Стандартная ставка',
        order: 1,
        mode: 'standard',
      ),
    ],
  ),
);

LessonScheduleSectionModel _scheduleModel({
  List<ScheduleSuggestion> suggestions = const [],
  List<LessonConstraintViolation> violations = const [],
  bool isAnalyzing = false,
}) => LessonScheduleSectionModel(
  draft: _draft(),
  analysis: LessonScheduleAnalysis(
    valid: suggestions.isEmpty && violations.isEmpty,
    violations: violations,
    suggestions: suggestions,
  ),
  isAnalyzing: isAnalyzing,
  minimumDate: DateTime(2026, 7, 27),
  maximumDate: DateTime(2027, 8, 26),
);

const _lessonEditorPresentationFiles = [
  'lib/features/admin/presentation/widgets/lesson_editor/lesson_editor_view.dart',
  'lib/features/admin/presentation/widgets/lesson_editor/lesson_participant_section.dart',
  'lib/features/admin/presentation/widgets/lesson_editor/lesson_schedule_section.dart',
  'lib/features/admin/presentation/widgets/lesson_editor/lesson_financial_section.dart',
  'lib/features/admin/presentation/widgets/lesson_editor/lesson_editor_feedback.dart',
];

void main() {
  testWidgets('schedule section emits analyzer and suggestion intents', (
    tester,
  ) async {
    var analyzed = false;
    ScheduleSuggestion? applied;
    await tester.pumpWidget(
      _host(
        LessonScheduleSection(
          model: _scheduleModel(suggestions: [_suggestion]),
          onAnalyze: () => analyzed = true,
          onApplySuggestion: (value) => applied = value,
          onOpenConstraint: (_) {},
          onDateChanged: (_) {},
          onTimeChanged: (_) {},
          onDurationChanged: (_) {},
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('lesson-run-schedule-analyzer')),
    );
    await tester.tap(find.textContaining('№1 · Свободная аудитория'));

    expect(analyzed, isTrue);
    expect(applied, same(_suggestion));
  });

  testWidgets('constraint links emit only the typed open intent', (
    tester,
  ) async {
    LessonConstraintViolation? opened;
    await tester.pumpWidget(
      _host(
        LessonScheduleSection(
          model: _scheduleModel(violations: [_violation]),
          onAnalyze: () {},
          onApplySuggestion: (_) {},
          onOpenConstraint: (value) => opened = value,
          onDateChanged: (_) {},
          onTimeChanged: (_) {},
          onDurationChanged: (_) {},
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('conflict-lesson-lesson-a')));

    expect(opened, same(_violation));
  });

  testWidgets('schedule section preserves keys, copy and loading state', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        LessonScheduleSection(
          model: _scheduleModel(isAnalyzing: true),
          onAnalyze: () {},
          onApplySuggestion: (_) {},
          onOpenConstraint: (_) {},
          onDateChanged: (_) {},
          onTimeChanged: (_) {},
          onDurationChanged: (_) {},
        ),
      ),
    );

    expect(find.byKey(const ValueKey('lesson-date-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('lesson-time-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('lesson-duration-field')), findsOneWidget);
    expect(find.text('Проверяем расписание…'), findsOneWidget);
    final analyzer = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('lesson-run-schedule-analyzer')),
    );
    expect(analyzer.onPressed, isNull);
  });

  testWidgets(
    'date picker uses rolling create minimum and keeps old edit date',
    (tester) async {
      final now = DateTime(2026, 8, 26, 18);
      final oldDraft = _draft(localStart: DateTime(2026, 5, 10, 13));
      final createModel = LessonScheduleSectionModel.fromEditor(
        draft: _draft(),
        analysis: null,
        isAnalyzing: false,
        isEdit: false,
        now: now,
      );
      final editModel = LessonScheduleSectionModel.fromEditor(
        draft: oldDraft,
        analysis: null,
        isAnalyzing: false,
        isEdit: true,
        now: now,
      );

      expect(createModel.minimumDate, DateTime(2026, 7, 27));
      expect(editModel.minimumDate, DateTime(2026, 5, 10));

      await tester.pumpWidget(
        _host(
          LessonScheduleSection(
            model: editModel,
            onAnalyze: () {},
            onApplySuggestion: (_) {},
            onOpenConstraint: (_) {},
            onDateChanged: (_) {},
            onTimeChanged: (_) {},
            onDurationChanged: (_) {},
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('lesson-date-field')));
      await tester.pumpAndSettle();

      final picker = tester.widget<CalendarDatePicker>(
        find.byType(CalendarDatePicker),
      );
      expect(picker.firstDate, DateTime(2026, 5, 10));
      expect(picker.initialDate, DateTime(2026, 5, 10));
    },
  );

  testWidgets('participant section preserves controls and emits selections', (
    tester,
  ) async {
    LessonClientRef? client;
    String? branch;
    String? room;
    String? teacher;
    await tester.pumpWidget(
      _host(
        LessonParticipantSection(
          model: LessonParticipantSectionModel(
            session: _session(),
            draft: _draft(),
            references: _references(),
            isDisabled: false,
          ),
          onClientChanged: (value) => client = value,
          onBranchChanged: (value) => branch = value,
          onRoomChanged: (value) => room = value,
          onTeacherChanged: (value) => teacher = value,
        ),
      ),
    );

    final pickers = tester.widgetList<SearchablePickerField>(
      find.byType(SearchablePickerField),
    );
    pickers.first.onSelected(pickers.first.items.last);
    pickers.elementAt(1).onSelected(pickers.elementAt(1).items.first);
    pickers.elementAt(2).onSelected(pickers.elementAt(2).items.first);
    final branchField = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(const ValueKey('lesson-branch-field:branch-a')),
    );
    branchField.onChanged?.call('branch-a');

    expect(
      client,
      const LessonClientRef(type: 'lead', id: 'lead-a', label: 'Олег'),
    );
    expect(branch, 'branch-a');
    expect(room, 'room-a');
    expect(teacher, 'teacher-a');
    expect(find.text('Занятость проверим перед сохранением.'), findsOneWidget);
  });

  testWidgets('group edit keeps frozen group copy and disables replacement', (
    tester,
  ) async {
    final groupDraft = _draft().copyWith(
      client: const LessonClientRef(
        type: 'group',
        id: 'group-a',
        label: 'Старшая группа',
      ),
    );
    await tester.pumpWidget(
      _host(
        LessonParticipantSection(
          model: LessonParticipantSectionModel(
            session: _session(isEdit: true, draft: groupDraft),
            draft: groupDraft,
            references: _references(),
            isDisabled: false,
          ),
          onClientChanged: (_) {},
          onBranchChanged: (_) {},
          onRoomChanged: (_) {},
          onTeacherChanged: (_) {},
        ),
      ),
    );

    expect(find.byKey(const ValueKey('lesson-group-field')), findsOneWidget);
    expect(find.text('Старшая группа'), findsOneWidget);
    expect(
      find.text('Группа и замороженный состав сохраняются при переносе'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('lesson-client-field')), findsNothing);
  });

  testWidgets('financial section emits every editable financial intent', (
    tester,
  ) async {
    final actions = _RecordingActions();
    await tester.pumpWidget(
      _host(
        SingleChildScrollView(
          child: LessonFinancialSection(
            model: LessonFinancialSectionModel(
              session: _session(),
              draft: _draft(),
              references: _references(),
              isSaving: false,
              requiresCompensationValue: false,
              compensationNeedsReason: true,
            ),
            actions: actions,
          ),
        ),
      ),
    );

    tester
        .widget<SwitchListTile>(
          find.byKey(const ValueKey('lesson-trial-toggle')),
        )
        .onChanged
        ?.call(true);
    tester
        .widget<DropdownButtonFormField<String>>(
          find.byKey(const ValueKey('lesson-completion-type-field')),
        )
        .onChanged
        ?.call('standard.success');
    tester
        .widget<DropdownButtonFormField<String>>(
          find.byKey(const ValueKey('lesson-settlement-type-field')),
        )
        .onChanged
        ?.call('paid');
    tester
        .widget<DropdownButtonFormField<String>>(
          find.byKey(const ValueKey('lesson-compensation-rule-field')),
        )
        .onChanged
        ?.call('standard');
    tester
        .widget<DropdownButtonFormField<String>>(
          find.byKey(const ValueKey('lesson-charge-type-field')),
        )
        .onChanged
        ?.call('personal_account');

    expect(actions.trial, isTrue);
    expect(actions.completion, 'standard.success');
    expect(actions.settlement, 'paid');
    expect(actions.compensationRule, 'standard');
    expect(actions.funding, 'personal_account');
    expect(find.text('Результат и расчёты'), findsOneWidget);
  });

  testWidgets('feedback preserves snapshot, validation and action behavior', (
    tester,
  ) async {
    final actions = _RecordingActions();
    await tester.pumpWidget(
      _host(
        Column(
          children: [
            LessonEditorFeedback(
              model: LessonEditorFeedbackModel(
                session: _session(),
                draft: _draft(),
                validationMessage: 'Проверьте поля',
                settlementLabel: 'Обычное',
                clientSnapshotValue: '1 500 ₽',
                compensationLabel: 'Стандартная ставка',
                teacherSnapshotValue: '1 000 ₽/ч',
              ),
            ),
            LessonEditorActionsRow(
              isEdit: false,
              isSaving: false,
              actions: actions,
            ),
          ],
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('lesson-snapshot-preview')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('lesson-form-validation-error')),
      findsOneWidget,
    );
    expect(find.text('Расчёты перед созданием'), findsOneWidget);
    await tester.tap(find.text('Отмена'));
    await tester.tap(find.text('Создать'));
    expect(actions.cancelCount, 1);
    expect(actions.saveCount, 1);

    await tester.pumpWidget(
      _host(
        LessonEditorActionsRow(isEdit: true, isSaving: true, actions: actions),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });

  testWidgets('editor view keeps loading and adaptive page surfaces', (
    tester,
  ) async {
    final session = _session();
    final loadingModel = LessonEditorViewModel(
      session: session,
      draft: session.draft,
      references: const LessonEditorReferenceState.empty(),
      analysis: null,
      isLoading: true,
      isSaving: false,
      isAnalyzing: false,
      validationMessage: null,
    );

    await tester.pumpWidget(
      _host(
        LessonEditorView(
          model: loadingModel,
          actions: _RecordingActions(),
          pageMode: true,
        ),
      ),
    );
    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.text('Загрузка данных...'), findsOneWidget);

    await tester.pumpWidget(
      _host(
        LessonEditorView(
          model: LessonEditorViewModel(
            session: session,
            draft: session.draft,
            references: _references(),
            analysis: null,
            isLoading: false,
            isSaving: false,
            isAnalyzing: false,
            validationMessage: null,
          ),
          actions: _RecordingActions(),
          pageMode: false,
        ),
      ),
    );
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Новое занятие'), findsOneWidget);
  });

  test(
    'presentation files do not import API, services, Riverpod or navigation providers',
    () {
      for (final path in _lessonEditorPresentationFiles) {
        final source = File(path).readAsStringSync();
        expect(source, isNot(contains('magic_api_client')), reason: path);
        expect(source, isNot(contains('magic_crm_service')), reason: path);
        expect(source, isNot(contains('flutter_riverpod')), reason: path);
        expect(
          source,
          isNot(contains('schedule_navigation_provider')),
          reason: path,
        );
        expect(source, isNot(contains('Navigator.')), reason: path);
      }
    },
  );
}

class _RecordingActions implements LessonEditorActions {
  bool? trial;
  String? completion;
  String? settlement;
  String? compensationRule;
  String? funding;
  int saveCount = 0;
  int cancelCount = 0;

  @override
  Future<void> analyzeSchedule() async {}

  @override
  Future<void> applySuggestion(ScheduleSuggestion value) async {}

  @override
  void cancel() => cancelCount++;

  @override
  void changeCompensationValue(String value) {}

  @override
  void changePlannedSettlementReason(String value) {}

  @override
  void openConstraint(LessonConstraintViolation value) {}

  @override
  Future<void> save() async => saveCount++;

  @override
  void selectBranch(String? value) {}

  @override
  void selectClient(LessonClientRef? value) {}

  @override
  void selectCompensationRule(String? value) => compensationRule = value;

  @override
  void selectCompletion(String value) => completion = value;

  @override
  void selectDate(DateTime value) {}

  @override
  void selectDuration(int value) {}

  @override
  void selectFunding(String value) => funding = value;

  @override
  void selectRoom(String? value) {}

  @override
  void selectSettlement(String? value) => settlement = value;

  @override
  void selectSubscription(String? value) {}

  @override
  void selectTeacher(String? value) {}

  @override
  void selectTime(TimeOfDay value) {}

  @override
  void selectTrial(bool value) => trial = value;
}
