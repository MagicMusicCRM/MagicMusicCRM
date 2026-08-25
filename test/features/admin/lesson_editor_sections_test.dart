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

LessonEditorSession _session({
  bool isEdit = false,
  LessonEditorDraft? draft,
  LessonClientRef? seededClient,
  String? leadNoteSource,
}) {
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
    seededClient: seededClient,
    leadNoteSource: leadNoteSource,
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

LessonEditorReferenceState _financialReferences() => LessonEditorReferenceState(
  teachers: _references().teachers,
  clients: _references().clients,
  branches: _references().branches,
  rooms: _references().rooms,
  subscriptions: _references().subscriptions,
  catalog: const LessonDecisionCatalog(
    settlementTypes: [
      LessonDecisionCatalogItem(key: 'paid', label: 'Обычное', order: 1),
    ],
    compensationRules: [
      LessonDecisionCatalogItem(
        key: 'percent',
        label: 'Процент',
        order: 1,
        mode: 'percent',
        value: '12000',
      ),
      LessonDecisionCatalogItem(
        key: 'fixed',
        label: 'Фиксированная',
        order: 2,
        mode: 'fixed',
        value: '250000',
      ),
      LessonDecisionCatalogItem(
        key: 'hourly',
        label: 'Почасовая',
        order: 3,
        mode: 'hourly',
        value: '100000',
      ),
    ],
  ),
);

LessonEditorDraft _financialDraft({
  String rule = 'percent',
  String? valueMinor = '12000',
  String reason = 'Индивидуальная договорённость',
}) => _draft().copyWith(
  clientChargeType: 'subscription',
  subscriptionId: 'subscription-a',
  compensationRuleKey: rule,
  compensationValueMinor: valueMinor,
  plannedSettlementReason: reason,
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

LessonEditorViewModel _viewModel({
  LessonEditorDraft? draft,
  bool isEdit = false,
  bool isLoading = false,
  bool isSaving = false,
  bool isAnalyzing = false,
  LessonEditorReferenceState? references,
  String? leadNoteSource,
}) {
  final value = draft ?? _draft();
  return LessonEditorViewModel(
    session: _session(
      isEdit: isEdit,
      draft: value,
      leadNoteSource: leadNoteSource,
    ),
    draft: value,
    references: references ?? _references(),
    analysis: null,
    isLoading: isLoading,
    isSaving: isSaving,
    isAnalyzing: isAnalyzing,
    validationMessage: null,
  );
}

const _lessonEditorPresentationFiles = [
  'lib/features/admin/presentation/widgets/lesson_editor/lesson_editor_view.dart',
  'lib/features/admin/presentation/widgets/lesson_editor/lesson_participant_section.dart',
  'lib/features/admin/presentation/widgets/lesson_editor/lesson_schedule_section.dart',
  'lib/features/admin/presentation/widgets/lesson_editor/lesson_financial_section.dart',
  'lib/features/admin/presentation/widgets/lesson_editor/lesson_editor_feedback.dart',
];

final _forbiddenPresentationUses = <String, RegExp>{
  'Navigator static API': RegExp(r'\bNavigator\s*\.'),
  'context navigation extension': RegExp(
    r'\bcontext\s*\.\s*(?:(?:router|navigation)\s*\.\s*)?'
    r'(?:push|pushNamed|pushReplacement|go|goNamed|pop)\s*\(',
  ),
  'router variable navigation': RegExp(
    r'\brouter\s*\.\s*(?:push|pushNamed|pushReplacement|go|goNamed|pop)\s*\(',
  ),
  'GoRouter ownership': RegExp(r'\bGoRouter\b'),
  'Router lookup': RegExp(r'\bRouter\s*\.\s*of\s*\('),
  'provider ref access': RegExp(
    r'\b(?:ref|widgetRef|providerRef)\s*\.\s*'
    r'(?:read|watch|listen|invalidate|refresh)\s*\(',
  ),
  'provider widget ownership': RegExp(
    r'\b(?:ProviderScope|ProviderContainer|ConsumerWidget|'
    r'ConsumerStatefulWidget|ConsumerState|WidgetRef)\b',
  ),
  'stateful widget ownership': RegExp(r'\bStatefulWidget\b'),
  'State ownership': RegExp(r'\bState\s*<'),
  'setState ownership': RegExp(r'\bsetState\s*\('),
  'notifier type ownership': RegExp(
    r'\b(?:ChangeNotifier|ValueNotifier|StateNotifier|AsyncNotifier|Notifier)\b',
  ),
  'controller or notifier construction': RegExp(
    r'\b_*[A-Z]\w*(?:Controller|Notifier)\s*'
    r'(?:<[^;(){}]+>\s*)?(?:\.[A-Za-z_]\w*)?\s*\(',
  ),
  'focus ownership construction': RegExp(
    r'\b(?:FocusNode|FocusScopeNode)\s*\(',
  ),
  'restorable state construction': RegExp(r'\bRestorable[A-Z]\w*\s*\('),
};

List<String> _forbiddenUsesIn(String source) => [
  for (final entry in _forbiddenPresentationUses.entries)
    if (entry.value.hasMatch(source)) entry.key,
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

  testWidgets('schedule controls emit date time and duration changes', (
    tester,
  ) async {
    DateTime? selectedDate;
    TimeOfDay? selectedTime;
    int? selectedDuration;
    await tester.pumpWidget(
      _host(
        LessonScheduleSection(
          model: _scheduleModel(),
          onAnalyze: () {},
          onApplySuggestion: (_) {},
          onOpenConstraint: (_) {},
          onDateChanged: (value) => selectedDate = value,
          onTimeChanged: (value) => selectedTime = value,
          onDurationChanged: (value) => selectedDuration = value,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('lesson-date-field')));
    await tester.pumpAndSettle();
    tester
        .widget<CalendarDatePicker>(find.byType(CalendarDatePicker))
        .onDateChanged(DateTime(2026, 8, 27));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('lesson-time-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    tester
        .widget<DropdownButtonFormField<int>>(
          find.byKey(const ValueKey('lesson-duration-field')),
        )
        .onChanged
        ?.call(90);

    expect(selectedDate, DateTime(2026, 8, 27));
    expect(selectedTime, const TimeOfDay(hour: 13, minute: 0));
    expect(selectedDuration, 90);
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
      expect(createModel.maximumDate, DateTime(2027, 8, 26));
      expect(editModel.minimumDate, DateTime(2026, 5, 10));
      expect(editModel.maximumDate, DateTime(2027, 8, 26));

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
      expect(picker.lastDate, DateTime(2027, 8, 26));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        _host(
          LessonScheduleSection(
            model: createModel,
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
      final createPicker = tester.widget<CalendarDatePicker>(
        find.byType(CalendarDatePicker),
      );
      expect(createPicker.firstDate, DateTime(2026, 7, 27));
      expect(createPicker.lastDate, DateTime(2027, 8, 26));
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
          ),
          onSearchClients: (_) async => const [],
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
          ),
          onSearchClients: (_) async => const [],
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

  testWidgets(
    'participant preserves canonical metadata for a preloaded client',
    (tester) async {
      final baseReferences = _references();
      final draft = _draft().copyWith(
        client: const LessonClientRef(
          type: 'lead',
          id: 'lead-a',
          label: 'Олег',
        ),
      );
      final references = LessonEditorReferenceState(
        teachers: baseReferences.teachers,
        clients: [
          const LessonEditorReferenceItem(
            id: 'student:student-preloaded',
            label: 'Мария Каноническая',
            raw: {
              'ref': {'type': 'lead', 'id': 'stale-client'},
            },
            branchId: 'branch-canonical',
          ),
          baseReferences.clients.last,
        ],
        branches: baseReferences.branches,
        rooms: baseReferences.rooms,
        subscriptions: baseReferences.subscriptions,
        catalog: baseReferences.catalog,
      );
      LessonClientRef? selected;
      await tester.pumpWidget(
        _host(
          LessonParticipantSection(
            model: LessonParticipantSectionModel(
              session: _session(draft: draft),
              draft: draft,
              references: references,
            ),
            onSearchClients: (_) async => const [],
            onClientChanged: (value) => selected = value,
            onBranchChanged: (_) {},
            onRoomChanged: (_) {},
            onTeacherChanged: (_) {},
          ),
        ),
      );

      final clientField = find.byKey(const ValueKey('lesson-client-field'));
      tester
          .widget<DropdownMenu<String>>(
            find.descendant(
              of: clientField,
              matching: find.byType(DropdownMenu<String>),
            ),
          )
          .onSelected!('student:student-preloaded');
      await tester.pumpAndSettle();

      expect(selected?.type, 'student');
      expect(selected?.id, 'student-preloaded');
      expect(selected?.label, 'Мария Каноническая');
      expect(selected?.branchId, 'branch-canonical');
    },
  );

  testWidgets(
    'participant remote search exposes and selects a typed client outside preload',
    (tester) async {
      final actions = _RecordingActions(
        searchResults: const [
          LessonClientRef(
            type: 'student',
            id: 'student-z',
            label: 'Зинаида Заречная',
            branchId: 'branch-z',
          ),
        ],
      );
      await tester.pumpWidget(
        _host(
          LessonParticipantSection(
            model: LessonParticipantSectionModel(
              session: _session(),
              draft: _draft(),
              references: _references(),
            ),
            onSearchClients: actions.searchClients,
            onClientChanged: actions.selectClient,
            onBranchChanged: actions.selectBranch,
            onRoomChanged: actions.selectRoom,
            onTeacherChanged: actions.selectTeacher,
          ),
        ),
      );

      expect(find.text('Зинаида Заречная'), findsNothing);
      final clientField = find.byKey(const ValueKey('lesson-client-field'));
      await tester.tap(clientField);
      await tester.enterText(
        find.descendant(of: clientField, matching: find.byType(TextField)),
        'Зинаида',
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(actions.searchedQueries, ['Зинаида']);
      expect(find.text('Зинаида Заречная'), findsWidgets);
      await tester.tap(find.text('Зинаида Заречная').last);
      await tester.pumpAndSettle();

      expect(
        actions.client,
        const LessonClientRef(
          type: 'student',
          id: 'student-z',
          label: 'Зинаида Заречная',
          branchId: 'branch-z',
        ),
      );

      final selectedDraft = _draft().copyWith(client: actions.client);
      await tester.pumpWidget(
        _host(
          LessonParticipantSection(
            model: LessonParticipantSectionModel(
              session: _session(draft: selectedDraft),
              draft: selectedDraft,
              references: _references(),
            ),
            onSearchClients: actions.searchClients,
            onClientChanged: actions.selectClient,
            onBranchChanged: actions.selectBranch,
            onRoomChanged: actions.selectRoom,
            onTeacherChanged: actions.selectTeacher,
          ),
        ),
      );
      final synchronizedPicker = tester.widget<SearchablePickerField>(
        find.byKey(const ValueKey('lesson-client-field')),
      );
      expect(synchronizedPicker.selectedId, 'student:student-z');
      expect(synchronizedPicker.selectedLabel, 'Зинаида Заречная · Student');
    },
  );

  testWidgets(
    'participant trusts fresh remote client data when preload has the same id',
    (tester) async {
      final baseReferences = _references();
      final draft = _draft().copyWith(
        client: const LessonClientRef(
          type: 'lead',
          id: 'lead-a',
          label: 'Олег',
        ),
      );
      final references = LessonEditorReferenceState(
        teachers: baseReferences.teachers,
        clients: [
          LessonEditorReferenceItem(
            id: 'student:student-a',
            label: 'Анна Старое Имя',
            raw: const {
              'ref': {'type': 'student', 'id': 'student-a'},
            },
            branchId: 'branch-old',
          ),
          baseReferences.clients.last,
        ],
        branches: baseReferences.branches,
        rooms: baseReferences.rooms,
        subscriptions: baseReferences.subscriptions,
        catalog: baseReferences.catalog,
      );
      final actions = _RecordingActions(
        searchResults: const [
          LessonClientRef(
            type: 'student',
            id: 'student-a',
            label: 'Анна Новое Имя',
            branchId: 'branch-fresh',
          ),
        ],
      );
      await tester.pumpWidget(
        _host(
          LessonParticipantSection(
            model: LessonParticipantSectionModel(
              session: _session(draft: draft),
              draft: draft,
              references: references,
            ),
            onSearchClients: actions.searchClients,
            onClientChanged: actions.selectClient,
            onBranchChanged: actions.selectBranch,
            onRoomChanged: actions.selectRoom,
            onTeacherChanged: actions.selectTeacher,
          ),
        ),
      );

      final clientField = find.byKey(const ValueKey('lesson-client-field'));
      await tester.tap(clientField);
      await tester.enterText(
        find.descendant(of: clientField, matching: find.byType(TextField)),
        'Новое Имя',
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Анна Новое Имя').last);
      await tester.pumpAndSettle();

      expect(actions.client?.type, 'student');
      expect(actions.client?.id, 'student-a');
      expect(actions.client?.label, 'Анна Новое Имя');
      expect(actions.client?.branchId, 'branch-fresh');
    },
  );

  testWidgets(
    'edit keeps an ineligible current teacher label out of replacement items',
    (tester) async {
      final draft = _draft().copyWith(teacherId: 'teacher-old');
      final base = _references();
      final references = LessonEditorReferenceState(
        teachers: const [
          LessonEditorReferenceItem(
            id: 'teacher-old',
            label: 'Архивный Преподаватель',
            raw: {},
            status: 'inactive',
            assignedBranchIds: {},
          ),
          LessonEditorReferenceItem(
            id: 'teacher-new',
            label: 'Новый Преподаватель',
            raw: {},
            status: 'active',
            assignedBranchIds: {'branch-a'},
          ),
        ],
        clients: base.clients,
        branches: base.branches,
        rooms: base.rooms,
        subscriptions: base.subscriptions,
        catalog: base.catalog,
      );
      await tester.pumpWidget(
        _host(
          LessonParticipantSection(
            model: LessonParticipantSectionModel(
              session: _session(isEdit: true, draft: draft),
              draft: draft,
              references: references,
            ),
            onSearchClients: (_) async => const [],
            onClientChanged: (_) {},
            onBranchChanged: (_) {},
            onRoomChanged: (_) {},
            onTeacherChanged: (_) {},
          ),
        ),
      );

      final picker = tester.widget<SearchablePickerField>(
        find.byKey(const ValueKey('lesson-teacher-field')),
      );
      expect(picker.selectedLabel, 'Архивный Преподаватель');
      expect(picker.items.map((item) => item.id), ['teacher-new']);
    },
  );

  testWidgets('financial section emits every editable financial intent', (
    tester,
  ) async {
    final actions = _RecordingActions();
    final draft = _financialDraft();
    await tester.pumpWidget(
      _host(
        SingleChildScrollView(
          child: LessonFinancialSection(
            model: LessonFinancialSectionModel(
              session: _session(draft: draft),
              draft: draft,
              references: _financialReferences(),
              isSaving: false,
              requiresCompensationValue: true,
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
        ?.call('fixed');
    await tester.enterText(
      find.byKey(const ValueKey('lesson-compensation-value-field')),
      '135,50',
    );
    await tester.enterText(
      find.byKey(const ValueKey('lesson-compensation-override-reason-field')),
      'Причина',
    );
    tester
        .widget<DropdownButtonFormField<String>>(
          find.byKey(const ValueKey('lesson-charge-type-field')),
        )
        .onChanged
        ?.call('personal_account');
    final subscription = tester
        .widgetList<SearchablePickerField>(find.byType(SearchablePickerField))
        .singleWhere((picker) => picker.label == 'Абонемент *');
    subscription.onSelected(subscription.items.single);

    expect(actions.trial, isTrue);
    expect(actions.completion, 'standard.success');
    expect(actions.settlement, 'paid');
    expect(actions.compensationRule, 'fixed');
    expect(actions.compensationValue, '135,50');
    expect(actions.compensationReason, 'Причина');
    expect(actions.funding, 'personal_account');
    expect(actions.subscription, 'subscription-a');
    expect(find.text('Результат и расчёты'), findsOneWidget);
  });

  testWidgets(
    'compensation fields reset visible model values for every rule change',
    (tester) async {
      final actions = _RecordingActions();

      Future<void> pumpRule(String rule, String? valueMinor, String reason) =>
          tester.pumpWidget(
            _host(
              SingleChildScrollView(
                child: LessonFinancialSection(
                  model: LessonFinancialSectionModel(
                    session: _session(
                      draft: _financialDraft(
                        rule: rule,
                        valueMinor: valueMinor,
                        reason: reason,
                      ),
                    ),
                    draft: _financialDraft(
                      rule: rule,
                      valueMinor: valueMinor,
                      reason: reason,
                    ),
                    references: _financialReferences(),
                    isSaving: false,
                    requiresCompensationValue: true,
                    compensationNeedsReason: true,
                  ),
                  actions: actions,
                ),
              ),
            ),
          );

      String visibleValue(Key key) => tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(key),
              matching: find.byType(EditableText),
            ),
          )
          .controller
          .text;

      const valueKey = ValueKey('lesson-compensation-value-field');
      const reasonKey = ValueKey('lesson-compensation-override-reason-field');
      await pumpRule('percent', '12000', 'Начальная причина');
      await tester.enterText(find.byKey(valueKey), '135');
      await tester.enterText(find.byKey(reasonKey), 'Процент вручную');
      expect(actions.compensationValue, '135');
      expect(actions.compensationReason, 'Процент вручную');

      await pumpRule('fixed', null, '');
      expect(visibleValue(valueKey), '2500');
      expect(visibleValue(reasonKey), isEmpty);
      await tester.enterText(find.byKey(valueKey), '3000');
      await tester.enterText(find.byKey(reasonKey), 'Фикс вручную');
      expect(actions.compensationValue, '3000');
      expect(actions.compensationReason, 'Фикс вручную');

      await pumpRule('hourly', null, '');
      expect(visibleValue(valueKey), '1000');
      expect(visibleValue(reasonKey), isEmpty);
      await tester.enterText(find.byKey(valueKey), '1250');
      await tester.enterText(find.byKey(reasonKey), 'Час вручную');
      expect(actions.compensationValue, '1250');
      expect(actions.compensationReason, 'Час вручную');

      await pumpRule('percent', null, '');
      expect(visibleValue(valueKey), '120');
      expect(visibleValue(reasonKey), isEmpty);
    },
  );

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

  testWidgets('editor view keeps loading and loaded adaptive surfaces', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host(
        LessonEditorView(
          model: _viewModel(
            isLoading: true,
            references: const LessonEditorReferenceState.empty(),
          ),
          actions: _RecordingActions(),
          pageMode: true,
        ),
      ),
    );
    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.text('Загрузка данных...'), findsOneWidget);

    final createActions = _RecordingActions();
    await tester.pumpWidget(
      _host(
        LessonEditorView(
          model: _viewModel(leadNoteSource: 'Имя лида не является флагом'),
          actions: createActions,
          pageMode: false,
          title: 'Пробное занятие',
        ),
      ),
    );
    final createDialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
    final createTitleRow = createDialog.title! as Row;
    expect(
      ((createTitleRow.children.last as Expanded).child as Text).data,
      'Пробное занятие',
    );
    expect(find.byType(Scaffold), findsNothing);
    expect(find.text('Отмена'), findsOneWidget);
    expect(find.text('Создать'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('lesson-client-field'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const ValueKey('lesson-date-field'))).dy,
      ),
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('lesson-date-field'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const ValueKey('lesson-trial-toggle'))).dy,
      ),
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('lesson-trial-toggle'))).dy,
      lessThan(
        tester
            .getTopLeft(find.byKey(const ValueKey('lesson-snapshot-preview')))
            .dy,
      ),
    );

    await tester.pumpWidget(
      _host(
        LessonEditorView(
          model: _viewModel(isEdit: true),
          actions: _RecordingActions(),
          pageMode: true,
        ),
      ),
    );
    final editDialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
    final editTitleRow = editDialog.title! as Row;
    expect(
      ((editTitleRow.children.last as Expanded).child as Text).data,
      'Перенести или изменить занятие',
    );
    expect(find.byType(SafeArea), findsWidgets);
    expect(find.byType(BackButton), findsOneWidget);
    expect(find.text('Перейти к расчёту'), findsOneWidget);
  });

  testWidgets('saving locks only compensation and submit for create', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final draft = _financialDraft(
      valueMinor: '13500',
      reason: 'Индивидуальная причина',
    );
    await tester.pumpWidget(
      _host(
        LessonEditorView(
          model: _viewModel(
            draft: draft,
            isSaving: true,
            references: _financialReferences(),
          ),
          actions: _RecordingActions(),
        ),
      ),
    );

    expect(
      tester
          .widget<SearchablePickerField>(
            find.byKey(const ValueKey('lesson-client-field')),
          )
          .enabled,
      isTrue,
    );
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byKey(const ValueKey('lesson-branch-field:branch-a')),
          )
          .onChanged,
      isNotNull,
    );
    expect(
      tester
          .widget<SearchablePickerField>(
            find.byKey(const ValueKey('lesson-room-field')),
          )
          .enabled,
      isTrue,
    );
    expect(
      tester
          .widget<SearchablePickerField>(
            find.byKey(const ValueKey('lesson-teacher-field')),
          )
          .enabled,
      isTrue,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('lesson-date-field')),
          )
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('lesson-time-field')),
          )
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<DropdownButtonFormField<int>>(
            find.byKey(const ValueKey('lesson-duration-field')),
          )
          .onChanged,
      isNotNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('lesson-run-schedule-analyzer')),
          )
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('lesson-trial-toggle')),
          )
          .onChanged,
      isNotNull,
    );
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byKey(const ValueKey('lesson-completion-type-field')),
          )
          .onChanged,
      isNotNull,
    );
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byKey(const ValueKey('lesson-settlement-type-field')),
          )
          .onChanged,
      isNotNull,
    );
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byKey(const ValueKey('lesson-compensation-rule-field')),
          )
          .onChanged,
      isNull,
    );
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('lesson-compensation-value-field')),
          )
          .enabled,
      isFalse,
    );
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(
              const ValueKey('lesson-compensation-override-reason-field'),
            ),
          )
          .enabled,
      isFalse,
    );
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byKey(const ValueKey('lesson-charge-type-field')),
          )
          .onChanged,
      isNotNull,
    );
    expect(
      tester
          .widgetList<SearchablePickerField>(find.byType(SearchablePickerField))
          .singleWhere((picker) => picker.label == 'Абонемент *')
          .enabled,
      isTrue,
    );
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Отмена'))
          .onPressed,
      isNotNull,
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });

  testWidgets('saving preserves snapshot locks and editable schedule in edit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final draft = _financialDraft(valueMinor: '13500');
    await tester.pumpWidget(
      _host(
        LessonEditorView(
          model: _viewModel(
            draft: draft,
            isEdit: true,
            isSaving: true,
            references: _financialReferences(),
          ),
          actions: _RecordingActions(),
        ),
      ),
    );

    expect(
      tester
          .widget<SearchablePickerField>(
            find.byKey(const ValueKey('lesson-client-field')),
          )
          .enabled,
      isFalse,
    );
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byKey(const ValueKey('lesson-branch-field:branch-a')),
          )
          .onChanged,
      isNotNull,
    );
    expect(
      tester
          .widget<SearchablePickerField>(
            find.byKey(const ValueKey('lesson-room-field')),
          )
          .enabled,
      isTrue,
    );
    expect(
      tester
          .widget<SearchablePickerField>(
            find.byKey(const ValueKey('lesson-teacher-field')),
          )
          .enabled,
      isTrue,
    );
    for (final key in const [
      ValueKey('lesson-date-field'),
      ValueKey('lesson-time-field'),
      ValueKey('lesson-run-schedule-analyzer'),
    ]) {
      expect(
        tester.widget<OutlinedButton>(find.byKey(key)).onPressed,
        isNotNull,
      );
    }
    expect(
      tester
          .widget<DropdownButtonFormField<int>>(
            find.byKey(const ValueKey('lesson-duration-field')),
          )
          .onChanged,
      isNotNull,
    );
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('lesson-trial-toggle')),
          )
          .onChanged,
      isNull,
    );
    expect(
      tester
          .widget<InputDecorator>(
            find.byKey(const ValueKey('lesson-completion-type-field')),
          )
          .decoration
          .enabled,
      isFalse,
    );
    for (final key in const [
      ValueKey('lesson-settlement-type-field'),
      ValueKey('lesson-compensation-rule-field'),
      ValueKey('lesson-charge-type-field'),
    ]) {
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(find.byKey(key))
            .onChanged,
        isNull,
      );
    }
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('lesson-compensation-value-field')),
          )
          .enabled,
      isFalse,
    );
    expect(
      find.byKey(const ValueKey('lesson-compensation-override-reason-field')),
      findsNothing,
    );
    expect(
      tester
          .widgetList<SearchablePickerField>(find.byType(SearchablePickerField))
          .singleWhere((picker) => picker.label == 'Абонемент *')
          .enabled,
      isFalse,
    );
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Отмена'))
          .onPressed,
      isNotNull,
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });

  test('presentation files use only the approved import surface and own no state', () {
    const allowedImports = <String, Set<String>>{
      'lib/features/admin/presentation/widgets/lesson_editor/lesson_editor_view.dart':
          {
            'package:flutter/material.dart',
            'package:magic_music_crm/core/models/lesson_schedule_analysis.dart',
            'package:magic_music_crm/core/theme/app_theme.dart',
            'package:magic_music_crm/core/theme/design_tokens.dart',
            '../lesson_decision/lesson_decision_models.dart',
            'lesson_editor_decision_policy.dart',
            'lesson_editor_feedback.dart',
            'lesson_editor_models.dart',
            'lesson_financial_section.dart',
            'lesson_participant_section.dart',
            'lesson_schedule_section.dart',
          },
      'lib/features/admin/presentation/widgets/lesson_editor/lesson_participant_section.dart':
          {
            'package:flutter/material.dart',
            'package:magic_music_crm/core/widgets/searchable_picker_field.dart',
            'package:magic_music_crm/core/widgets/searchable_select.dart',
            'lesson_editor_models.dart',
          },
      'lib/features/admin/presentation/widgets/lesson_editor/lesson_schedule_section.dart':
          {
            'dart:async',
            'package:flutter/material.dart',
            'package:magic_music_crm/core/models/lesson_schedule_analysis.dart',
            'package:magic_music_crm/core/navigation/entity_link_text.dart',
            'package:magic_music_crm/core/theme/design_tokens.dart',
            'lesson_editor_models.dart',
          },
      'lib/features/admin/presentation/widgets/lesson_editor/lesson_financial_section.dart':
          {
            'package:flutter/material.dart',
            'package:flutter/services.dart',
            'package:magic_music_crm/core/theme/app_theme.dart',
            'package:magic_music_crm/core/widgets/searchable_picker_field.dart',
            'package:magic_music_crm/core/widgets/searchable_select.dart',
            '../lesson_decision/lesson_decision_models.dart',
            '../lesson_form_rules.dart',
            'lesson_editor_feedback.dart',
            'lesson_editor_models.dart',
          },
      'lib/features/admin/presentation/widgets/lesson_editor/lesson_editor_feedback.dart':
          {
            'package:flutter/material.dart',
            'package:magic_music_crm/core/models/lesson_schedule_analysis.dart',
            'package:magic_music_crm/core/theme/design_tokens.dart',
            'lesson_editor_models.dart',
          },
    };
    final importPattern = RegExp(r"^import '([^']+)';$", multiLine: true);
    for (final path in _lessonEditorPresentationFiles) {
      final source = File(path).readAsStringSync();
      expect(
        importPattern
            .allMatches(source)
            .map((match) => match.group(1)!)
            .toSet(),
        allowedImports[path],
        reason: path,
      );
      expect(_forbiddenUsesIn(source), isEmpty, reason: path);
    }
  });

  test('state ownership guard rejects construction but permits injection', () {
    const forbiddenFixtures = <String, String>{
      'final owner = ScrollController();':
          'controller or notifier construction',
      'final owner = PageController();': 'controller or notifier construction',
      'final owner = TabController(length: 2, vsync: this);':
          'controller or notifier construction',
      'final owner = FocusNode();': 'focus ownership construction',
      'final owner = StreamController<int>();':
          'controller or notifier construction',
      'final owner = ValueNotifier<int>(0);':
          'controller or notifier construction',
      'final owner = _LessonController();':
          'controller or notifier construction',
      'final owner = _DraftNotifier<int>();':
          'controller or notifier construction',
      'final owner = AnimationController.unbounded(vsync: this);':
          'controller or notifier construction',
      'final owner = StreamController<int>.broadcast();':
          'controller or notifier construction',
    };
    for (final fixture in forbiddenFixtures.entries) {
      expect(
        _forbiddenUsesIn(fixture.key),
        contains(fixture.value),
        reason: fixture.key,
      );
    }

    expect(
      _forbiddenUsesIn('final ScrollController? scrollController;'),
      isEmpty,
    );
  });
}

class _RecordingActions implements LessonEditorActions {
  _RecordingActions({this.searchResults = const []});

  final List<LessonClientRef> searchResults;
  final List<String> searchedQueries = [];
  bool? trial;
  String? completion;
  String? settlement;
  String? compensationRule;
  String? compensationValue;
  String? compensationReason;
  String? funding;
  String? subscription;
  LessonClientRef? client;
  String? branch;
  String? room;
  String? teacher;
  DateTime? date;
  TimeOfDay? time;
  int? duration;
  int saveCount = 0;
  int cancelCount = 0;

  @override
  Future<void> analyzeSchedule() async {}

  @override
  Future<void> applySuggestion(ScheduleSuggestion value) async {}

  @override
  void cancel() => cancelCount++;

  @override
  void changeCompensationValue(String value) => compensationValue = value;

  @override
  void changePlannedSettlementReason(String value) =>
      compensationReason = value;

  @override
  void openConstraint(LessonConstraintViolation value) {}

  @override
  Future<void> save() async => saveCount++;

  @override
  Future<List<LessonClientRef>> searchClients(String query) async {
    searchedQueries.add(query);
    return searchResults;
  }

  @override
  void selectBranch(String? value) => branch = value;

  @override
  void selectClient(LessonClientRef? value) => client = value;

  @override
  void selectCompensationRule(String? value) => compensationRule = value;

  @override
  void selectCompletion(String value) => completion = value;

  @override
  void selectDate(DateTime value) => date = value;

  @override
  void selectDuration(int value) => duration = value;

  @override
  void selectFunding(String value) => funding = value;

  @override
  void selectRoom(String? value) => room = value;

  @override
  void selectSettlement(String? value) => settlement = value;

  @override
  void selectSubscription(String? value) => subscription = value;

  @override
  void selectTeacher(String? value) => teacher = value;

  @override
  void selectTime(TimeOfDay value) => time = value;

  @override
  void selectTrial(bool value) => trial = value;
}
