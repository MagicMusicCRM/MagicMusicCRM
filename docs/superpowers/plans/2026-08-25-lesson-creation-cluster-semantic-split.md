# Lesson Creation Cluster Semantic Split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Delete the lesson-creation god state, decision-flow brain UI, presentation API extension, and `part` cycle by replacing them with typed, directly tested semantic owners without changing lesson behavior.

**Architecture:** Keep `CreateLessonDialog` and `lesson_decision_flow.dart` as real public composition boundaries. Move immutable models, legacy normalization, reference loading, decision policy, schedule analysis, command orchestration, and bounded UI sections into focused collaborators; route all network work through the existing `MagicCrmService`.

**Tech Stack:** Flutter 3, Dart 3, Riverpod 3, Dio, Flutter Test, RepoWise, Sentrux

**Spec:** `docs/superpowers/specs/2026-08-25-lesson-creation-cluster-semantic-split-design.md`

## Global Constraints

- Preserve the current `CreateLessonDialog` constructor, `show` entry, adaptive desktop/mobile surfaces, route name `lesson-editor`, widget keys, Russian copy, and `Future<bool?>` result semantics.
- Preserve all lesson routes, payload keys, response shapes, expected versions, mutation identities, signed preview tokens, stale recovery, and authoritative `422` constraint behavior.
- Preserve the preview transport fail-open rule; the authoritative create transaction remains fail-closed.
- Preserve frozen client/group/participant/trial facts, edit no-op rejection, completed-reschedule `free_lesson/none`, group overrides, and the three independent create decisions.
- Widgets and form state must not call `MagicApiClient` directly; network calls go through `MagicCrmService`.
- Do not create a replacement god controller, parallel provider graph, API repository, schedule engine, or financial truth model.
- Target every new structural owner at RepoWise health `>= 7.0`, max CCN `<= 10`, no god/brain finding, and combined package deficit reduction `>= 85%`.
- Keep the package in rollback-safe commits. After every structural commit run focused tests, `flutter analyze` on changed Dart files, `git diff --check`, Sentrux health/rules, and `repowise update --index-only`.
- Stop on unexplained Sentrux quality `< 5748`, depth `> 13`, acyclicity below `10000`, or either architecture rule failing.
- Preserve unrelated working-tree changes and never include them in package commits.

---

## Baseline checkpoint

- [ ] Run the existing focused contract before production edits.

Run:

```powershell
flutter test test/features/admin/presentation/widgets/create_lesson_dialog_test.dart test/features/admin/create_lesson_student_search_test.dart test/features/admin/presentation/widgets/lesson_form_rules_test.dart test/features/schedule/lesson_decision_flow_test.dart test/features/schedule/lesson_form_test.dart --reporter compact
```

Expected: `52/52` tests pass.

- [ ] Start a Sentrux package session and record quality `5748`, depth `13`, acyclicity `10000`, and rules `2/2`.
- [ ] Confirm `git status --short --branch` is clean at `d1d24ea3` or a direct descendant containing only this plan.

### Task 1: Extract the public lesson-decision model contract

**Files:**

- Create: `lib/features/admin/presentation/widgets/lesson_decision/lesson_decision_models.dart`
- Modify: `lib/features/admin/presentation/widgets/lesson_decision_flow.dart:11-145`
- Create: `test/features/schedule/lesson_decision_models_test.dart`

**Interfaces:**

- Consumes: raw configuration/preview maps already returned by the backend.
- Produces: `LessonDecisionOperation.apiKey`, `.title`, `.actionLabel`, `.catalogContext`; `LessonDecisionCatalogItem`, `LessonDecisionCatalog`, `LessonDecisionPreview`, `LessonDecisionParticipant`, and `LessonDecisionRequest`.

- [ ] **Step 1: Write the failing public-model tests**

```dart
test('pins operation API and catalog contracts', () {
  expect(LessonDecisionOperation.reschedule.apiKey, 'reschedule');
  expect(LessonDecisionOperation.cancel.apiKey, 'cancel');
  expect(LessonDecisionOperation.settle.catalogContext, 'settle');
  expect(LessonDecisionOperation.plannedSettlement.apiKey, 'planned-settlement');
  expect(LessonDecisionOperation.plannedSettlement.catalogContext, 'settle');
  expect(LessonDecisionOperation.correction.apiKey, 'settlement-correction');
  expect(LessonDecisionOperation.correction.catalogContext, 'settle');
});

test('filters and orders the server catalog by operation context', () {
  final catalog = LessonDecisionCatalog.fromJson({
    'settlementTypes': [
      {'stableKey': 'late', 'label': 'Поздно', 'order': 20, 'allowedContexts': ['cancel']},
      {'stableKey': 'free', 'label': 'Бесплатно', 'order': 10, 'allowedContexts': ['settle']},
    ],
    'teacherCompensationRules': [
      {'stableKey': 'standard', 'label': 'Стандарт', 'order': 1, 'mode': 'standard'},
    ],
  }, LessonDecisionOperation.plannedSettlement);

  expect(catalog.settlementTypes.map((item) => item.key), ['free']);
  expect(catalog.compensationRules.single.key, 'standard');
});
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```powershell
flutter test test/features/schedule/lesson_decision_models_test.dart --reporter compact
```

Expected: FAIL because the semantic model module and public getters do not exist.

- [ ] **Step 3: Move the model implementation and add the edit request**

Use these exact public operation getters so later files do not recreate endpoint switches:

```dart
enum LessonDecisionOperation { reschedule, cancel, settle, plannedSettlement, correction }

extension LessonDecisionOperationContract on LessonDecisionOperation {
  String get apiKey => switch (this) {
    LessonDecisionOperation.reschedule => 'reschedule',
    LessonDecisionOperation.cancel => 'cancel',
    LessonDecisionOperation.settle => 'settle',
    LessonDecisionOperation.plannedSettlement => 'planned-settlement',
    LessonDecisionOperation.correction => 'settlement-correction',
  };

  String get catalogContext => switch (this) {
    LessonDecisionOperation.plannedSettlement ||
    LessonDecisionOperation.correction => 'settle',
    _ => apiKey,
  };
}

class LessonDecisionRequest {
  const LessonDecisionRequest({
    required this.operation,
    required this.lesson,
    this.successor,
    this.initialSettlementTypeKey,
    this.initialCompensationRuleKey,
    this.initialCompensationValueMinor,
  });

  final LessonDecisionOperation operation;
  final Map<String, dynamic> lesson;
  final Map<String, dynamic>? successor;
  final String? initialSettlementTypeKey;
  final String? initialCompensationRuleKey;
  final String? initialCompensationValueMinor;
}
```

Move the existing factories/getters for catalog, preview, and participant without changing JSON keys or defaults. Add `export 'lesson_decision/lesson_decision_models.dart';` to `lesson_decision_flow.dart` and import it internally.

- [ ] **Step 4: Run GREEN and the existing decision tests**

```powershell
dart format lib/features/admin/presentation/widgets/lesson_decision test/features/schedule/lesson_decision_models_test.dart
flutter test test/features/schedule/lesson_decision_models_test.dart test/features/schedule/lesson_decision_flow_test.dart test/features/schedule/lesson_form_test.dart --reporter compact
flutter analyze lib/features/admin/presentation/widgets/lesson_decision lib/features/admin/presentation/widgets/lesson_decision_flow.dart
git diff --check
```

Expected: all tests pass and analyzer reports no issues.

- [ ] **Step 5: Commit**

```powershell
git add -- lib/features/admin/presentation/widgets/lesson_decision lib/features/admin/presentation/widgets/lesson_decision_flow.dart test/features/schedule/lesson_decision_models_test.dart
git commit -m "refactor(lessons): extract decision models"
```

### Task 2: Move schedule analysis and lesson commands behind MagicCrmService

**Files:**

- Create: `lib/core/models/lesson_schedule_analysis.dart`
- Modify: `lib/core/services/magic_crm_service_schedule.dart`
- Modify: `lib/features/admin/presentation/widgets/create_lesson_dialog.dart`
- Modify: `lib/features/crm/presentation/client_card/schedule_plan_constraint_interpreter.dart`
- Modify: `test/core/services/magic_crm_service_test.dart`
- Modify: `test/features/schedule/lesson_form_test.dart`
- Delete: `lib/features/admin/presentation/widgets/schedule_conflicts_api.dart`

**Interfaces:**

- Consumes: `MagicCrmService._api`, current V4 endpoints, `MagicMutationIdentity`.
- Produces: canonical schedule-analysis models and `MagicCrmSchedule` methods for analysis, create, decision catalog, preview, and commit.

- [ ] **Step 1: Add failing service-routing tests**

Append to the existing `MagicCrmService` group using its `_FakeAdapter`:

```dart
test('owns lesson analysis, catalog, preview and create routes', () async {
  final adapter = _FakeAdapter([
    _FakeResponse(path: '/crm/lessons/constraints/preview', statusCode: 200, body: {'valid': true, 'violations': [], 'suggestions': []}),
    _FakeResponse(path: '/crm/configuration/lesson-decisions', statusCode: 200, body: {'settlementTypes': [], 'teacherCompensationRules': []}),
    _FakeResponse(path: '/crm/lessons/lesson-a/reschedule/preview', statusCode: 200, body: {'canConfirm': true, 'previewToken': 'token-a'}),
    _FakeResponse(path: '/crm/lessons', statusCode: 201, body: {'id': 'lesson-created'}),
  ]);
  final service = MagicCrmService(_client(adapter));

  await service.analyzeLessonSchedule(
    clientType: 'student', clientId: 'student-a', teacherId: 'teacher-a',
    branchId: 'branch-a', roomId: 'room-a',
    scheduledAt: '2026-08-26T10:00:00.000Z', durationMinutes: 60,
  );
  await service.getLessonDecisionCatalog(branchId: 'branch-a');
  await service.previewLessonDecision(
    lessonId: 'lesson-a', operationKey: 'reschedule', data: {'expectedVersion': 2},
  );
  await service.createLessonRaw({'clientRef': {'type': 'student', 'id': 'student-a'}});

  expect(adapter.requests.map((request) => request.path), [
    '/crm/lessons/constraints/preview',
    '/crm/configuration/lesson-decisions',
    '/crm/lessons/lesson-a/reschedule/preview',
    '/crm/lessons',
  ]);
});
```

- [ ] **Step 2: Verify RED**

```powershell
flutter test test/core/services/magic_crm_service_test.dart --plain-name "owns lesson analysis, catalog, preview and create routes"
```

Expected: FAIL because these methods are still an extension on `MagicApiClient` in presentation code.

- [ ] **Step 3: Move models and add the canonical service methods**

Relocate the complete live class bodies from
`schedule_conflicts_api.dart:9-147` to the core model file: keep every field,
constructor default, JSON key, list filter, and `fromViolations` validity rule
byte-equivalent. Replace only the error parser with this pure function:

```dart
List<LessonConstraintViolation>? lessonConstraintViolationsFromDetails(Object? details) {
  if (details is! Map) return null;
  final raw = details['violations'];
  if (raw is! List) return null;
  return [
    for (final item in raw)
      if (item is Map)
        LessonConstraintViolation.fromJson(Map<String, dynamic>.from(item)),
  ];
}
```

Add these exact methods to `MagicCrmSchedule`:

```dart
Future<Map<String, dynamic>> getLessonDecisionCatalog({String? branchId}) =>
    _api.get<Map<String, dynamic>>(
      '/crm/configuration/lesson-decisions',
      queryParameters: {'branchId': branchId},
    );

Future<LessonScheduleAnalysis> analyzeLessonSchedule({
  required String clientType,
  required String clientId,
  required String teacherId,
  required String branchId,
  required String roomId,
  required String scheduledAt,
  required int durationMinutes,
  String? excludeLessonId,
}) async {
  final response = await _api.post<Map<String, dynamic>>(
    '/crm/lessons/constraints/preview',
    data: {
      'clientRef': {'type': clientType, 'id': clientId},
      'teacherId': teacherId,
      'branchId': branchId,
      'roomId': roomId,
      'scheduledAt': scheduledAt,
      'durationMinutes': durationMinutes,
      'excludeLessonId': ?excludeLessonId,
    },
  );
  return LessonScheduleAnalysis.fromJson(response);
}

Future<Map<String, dynamic>> createLessonRaw(Map<String, dynamic> data) =>
    _api.post<Map<String, dynamic>>('/crm/lessons', data: data);

Future<Map<String, dynamic>> previewLessonDecision({
  required String lessonId,
  required String operationKey,
  required Map<String, dynamic> data,
}) => _api.post<Map<String, dynamic>>(
  '/crm/lessons/$lessonId/$operationKey/preview',
  data: data,
);

Future<Map<String, dynamic>> commitLessonDecision({
  required String lessonId,
  required String operationKey,
  required Map<String, dynamic> data,
  required MagicMutationIdentity identity,
  required bool usePut,
}) => usePut
    ? _api.request<Map<String, dynamic>>(
        'PUT',
        '/crm/lessons/$lessonId/$operationKey',
        data: data,
        mutationIdentity: identity,
      )
    : _api.postIdempotent<Map<String, dynamic>>(
        '/crm/lessons/$lessonId/$operationKey',
        data: data,
        identity: identity,
      );
```

Update all three model consumers to the core import. Change current dialog calls from `ref.read(magicApiClientProvider)` to `_crm`. Delete the old presentation extension once `rg` reports no import.

- [ ] **Step 4: Run GREEN and behavior gates**

```powershell
dart format lib/core/models/lesson_schedule_analysis.dart lib/core/services/magic_crm_service_schedule.dart lib/features/admin/presentation/widgets/create_lesson_dialog.dart lib/features/crm/presentation/client_card/schedule_plan_constraint_interpreter.dart test/core/services/magic_crm_service_test.dart test/features/schedule/lesson_form_test.dart
flutter test test/core/services/magic_crm_service_test.dart test/features/schedule/lesson_form_test.dart test/features/admin/presentation/widgets/create_lesson_dialog_test.dart --reporter compact
flutter analyze lib/core/models/lesson_schedule_analysis.dart lib/core/services/magic_crm_service_schedule.dart lib/features/admin/presentation/widgets/create_lesson_dialog.dart
rg -n "schedule_conflicts_api|ScheduleConflictsApi|magicApiClientProvider" lib/features/admin/presentation/widgets/create_lesson_dialog.dart lib/features/crm/presentation/client_card/schedule_plan_constraint_interpreter.dart test/features/schedule/lesson_form_test.dart
git diff --check
```

Expected: tests/analyzer pass; final `rg` returns no old API extension or direct client provider in the dialog.

- [ ] **Step 5: Commit**

```powershell
git add -- lib/core/models/lesson_schedule_analysis.dart lib/core/services/magic_crm_service_schedule.dart lib/features/admin/presentation/widgets/create_lesson_dialog.dart lib/features/crm/presentation/client_card/schedule_plan_constraint_interpreter.dart test/core/services/magic_crm_service_test.dart test/features/schedule/lesson_form_test.dart lib/features/admin/presentation/widgets/schedule_conflicts_api.dart
git commit -m "refactor(lessons): own lesson API in CRM service"
```

### Task 3: Introduce typed editor session and legacy mapper

**Files:**

- Create: `lib/features/admin/presentation/widgets/lesson_editor/lesson_editor_models.dart`
- Create: `lib/features/admin/presentation/widgets/lesson_editor/lesson_editor_initial_mapper.dart`
- Create: `test/features/admin/lesson_editor_initial_mapper_test.dart`

**Interfaces:**

- Consumes: `LessonEditorInitialInput` mirroring `CreateLessonDialog` constructor arguments.
- Produces: immutable `LessonEditorSession`, `LessonEditorDraft`, `LessonEditorSnapshot`, `LessonClientRef`, and `LessonEditorReferenceState`.

- [ ] **Step 1: Write failing mapper tests**

```dart
test('normalizes a frozen group edit from legacy aliases', () {
  final session = const LessonEditorInitialMapper().map(LessonEditorInitialInput(
    initialDate: null,
    initialDurationMinutes: null,
    initialRoomId: null,
    initialBranchId: null,
    initialIsTrial: false,
    lesson: {
      'id': 'lesson-a', 'version': 4, 'group_id': 'group-a',
      'group_name': 'Ансамбль', 'teacher_id': 'teacher-a',
      'branch_id': 'branch-a', 'room_id': 'room-a',
      'scheduled_at': '2026-08-26T10:00:00.000Z',
      'duration_minutes': 90, 'is_trial': true,
    },
  ));

  expect(session.isEdit, isTrue);
  expect(session.draft.client, const LessonClientRef(type: 'group', id: 'group-a', label: 'Ансамбль'));
  expect(session.snapshot?.expectedVersion, 4);
  expect(session.snapshot?.clientLocked, isTrue);
  expect(session.draft.isTrial, isTrue);
});

test('keeps lead trial creation independent from funding', () {
  final session = const LessonEditorInitialMapper().map(const LessonEditorInitialInput(
    initialDate: null, initialDurationMinutes: 45,
    initialRoomId: null, initialBranchId: 'branch-a',
    initialIsTrial: true, lesson: null,
    leadId: 'lead-a', leadName: 'Анна',
  ));
  expect(session.draft.client?.type, 'lead');
  expect(session.draft.isTrial, isTrue);
  expect(session.draft.clientChargeType, 'none');
});
```

- [ ] **Step 2: Verify RED**

```powershell
flutter test test/features/admin/lesson_editor_initial_mapper_test.dart --reporter compact
```

Expected: FAIL because the typed session does not exist.

- [ ] **Step 3: Implement exact immutable boundaries**

Use this field contract; `copyWith` must use a private sentinel so nullable ids can be explicitly cleared:

```dart
const _lessonEditorAbsent = Object();

class LessonClientRef {
  const LessonClientRef({
    required this.type,
    required this.id,
    required this.label,
    this.branchId,
  });
  final String type;
  final String id;
  final String label;
  final String? branchId;
  String get key => '$type:$id';

  @override
  bool operator ==(Object other) =>
      other is LessonClientRef &&
      other.type == type &&
      other.id == id &&
      other.label == label &&
      other.branchId == branchId;

  @override
  int get hashCode => Object.hash(type, id, label, branchId);
}

class LessonEditorDraft {
  const LessonEditorDraft({
    required this.localStart,
    required this.durationMinutes,
    required this.isTrial,
    required this.completionType,
    required this.clientChargeType,
    this.client,
    this.teacherId,
    this.branchId,
    this.roomId,
    this.subscriptionId,
    this.settlementTypeKey,
    this.compensationRuleKey,
    this.compensationValueMinor,
    this.plannedSettlementReason = '',
  });

  final DateTime localStart;
  final int durationMinutes;
  final bool isTrial;
  final String completionType;
  final String clientChargeType;
  final LessonClientRef? client;
  final String? teacherId;
  final String? branchId;
  final String? roomId;
  final String? subscriptionId;
  final String? settlementTypeKey;
  final String? compensationRuleKey;
  final String? compensationValueMinor;
  final String plannedSettlementReason;

  LessonEditorDraft copyWith({
    DateTime? localStart,
    int? durationMinutes,
    bool? isTrial,
    String? completionType,
    String? clientChargeType,
    Object? client = _lessonEditorAbsent,
    Object? teacherId = _lessonEditorAbsent,
    Object? branchId = _lessonEditorAbsent,
    Object? roomId = _lessonEditorAbsent,
    Object? subscriptionId = _lessonEditorAbsent,
    Object? settlementTypeKey = _lessonEditorAbsent,
    Object? compensationRuleKey = _lessonEditorAbsent,
    Object? compensationValueMinor = _lessonEditorAbsent,
    String? plannedSettlementReason,
  }) => LessonEditorDraft(
    localStart: localStart ?? this.localStart,
    durationMinutes: durationMinutes ?? this.durationMinutes,
    isTrial: isTrial ?? this.isTrial,
    completionType: completionType ?? this.completionType,
    clientChargeType: clientChargeType ?? this.clientChargeType,
    client: identical(client, _lessonEditorAbsent)
        ? this.client
        : client as LessonClientRef?,
    teacherId: identical(teacherId, _lessonEditorAbsent)
        ? this.teacherId
        : teacherId as String?,
    branchId: identical(branchId, _lessonEditorAbsent)
        ? this.branchId
        : branchId as String?,
    roomId: identical(roomId, _lessonEditorAbsent)
        ? this.roomId
        : roomId as String?,
    subscriptionId: identical(subscriptionId, _lessonEditorAbsent)
        ? this.subscriptionId
        : subscriptionId as String?,
    settlementTypeKey: identical(settlementTypeKey, _lessonEditorAbsent)
        ? this.settlementTypeKey
        : settlementTypeKey as String?,
    compensationRuleKey: identical(compensationRuleKey, _lessonEditorAbsent)
        ? this.compensationRuleKey
        : compensationRuleKey as String?,
    compensationValueMinor:
        identical(compensationValueMinor, _lessonEditorAbsent)
        ? this.compensationValueMinor
        : compensationValueMinor as String?,
    plannedSettlementReason:
        plannedSettlementReason ?? this.plannedSettlementReason,
  );
}

class LessonEditorSnapshot {
  const LessonEditorSnapshot({
    required this.lessonId,
    required this.expectedVersion,
    required this.rawLesson,
    required this.clientLocked,
    required this.initialSchedulePayload,
    required this.initialCompensationRuleKey,
    required this.initialCompensationValueMinor,
  });
  final String lessonId;
  final int? expectedVersion;
  final Map<String, dynamic> rawLesson;
  final bool clientLocked;
  final Map<String, dynamic> initialSchedulePayload;
  final String? initialCompensationRuleKey;
  final String? initialCompensationValueMinor;
}

class LessonEditorInitialInput {
  const LessonEditorInitialInput({
    required this.initialDate,
    required this.initialRoomId,
    required this.initialBranchId,
    required this.initialDurationMinutes,
    required this.lesson,
    required this.initialIsTrial,
    this.leadId,
    this.leadName,
    this.clientType,
    this.clientId,
    this.clientName,
  });
  final DateTime? initialDate;
  final String? initialRoomId;
  final String? initialBranchId;
  final int? initialDurationMinutes;
  final Map<String, dynamic>? lesson;
  final bool initialIsTrial;
  final String? leadId;
  final String? leadName;
  final String? clientType;
  final String? clientId;
  final String? clientName;
}

class LessonEditorSession {
  const LessonEditorSession({
    required this.draft,
    required this.snapshot,
    required this.seededClient,
  });
  final LessonEditorDraft draft;
  final LessonEditorSnapshot? snapshot;
  final LessonClientRef? seededClient;
  bool get isEdit => snapshot != null;
  bool get isGroupEdit => isEdit && draft.client?.type == 'group';
}

class LessonEditorReferenceItem {
  const LessonEditorReferenceItem({
    required this.id,
    required this.label,
    required this.raw,
    this.branchId,
    this.status,
    this.assignedBranchIds = const {},
  });
  final String id;
  final String label;
  final Map<String, dynamic> raw;
  final String? branchId;
  final String? status;
  final Set<String> assignedBranchIds;
}

class LessonEditorReferenceState {
  const LessonEditorReferenceState({
    required this.teachers,
    required this.clients,
    required this.branches,
    required this.rooms,
    required this.subscriptions,
    required this.catalog,
  });
  const LessonEditorReferenceState.empty()
      : teachers = const [],
        clients = const [],
        branches = const [],
        rooms = const [],
        subscriptions = const [],
        catalog = null;
  final List<LessonEditorReferenceItem> teachers;
  final List<LessonEditorReferenceItem> clients;
  final List<LessonEditorReferenceItem> branches;
  final List<LessonEditorReferenceItem> rooms;
  final List<LessonEditorReferenceItem> subscriptions;
  final LessonDecisionCatalog? catalog;
}
```

Normalize these aliases only in the mapper; downstream owners read typed fields:

| Typed value | Accepted live input keys |
|---|---|
| group id/name | `group_id` / `groupId`, `group_name` / `groupName` |
| client | `lead_id` + `lead_name`, else `student_id` + `student_name`, else constructor seed |
| schedule owner ids | `teacher_id`, `branch_id`, `room_id` |
| schedule | `scheduled_at`, `duration_minutes` |
| trial/completion | `snapshot_trial` or `is_trial`, `completion_type` |
| funding | `client_charge_type`, `subscription_id` |
| settlement | `settlement_type_key` / `settlementTypeKey` |
| compensation rule | `teacher_compensation_rule_key` / `teacherCompensationRuleKey` |
| compensation value | `teacher_compensation_value_minor` / `teacherCompensationValueMinor` |

Preserve the constructor precedence already pinned by tests: explicit client
seed, then lead seed; an edit lesson overrides both. Keep the exact Moscow
conversion: server UTC is shown at UTC+3; local date/time is serialized later by
subtracting three hours with `DateTime.utc`.

- [ ] **Step 4: Run GREEN**

```powershell
dart format lib/features/admin/presentation/widgets/lesson_editor test/features/admin/lesson_editor_initial_mapper_test.dart
flutter test test/features/admin/lesson_editor_initial_mapper_test.dart test/features/admin/presentation/widgets/create_lesson_dialog_test.dart --reporter compact
flutter analyze lib/features/admin/presentation/widgets/lesson_editor
git diff --check
```

- [ ] **Step 5: Commit**

```powershell
git add -- lib/features/admin/presentation/widgets/lesson_editor/lesson_editor_models.dart lib/features/admin/presentation/widgets/lesson_editor/lesson_editor_initial_mapper.dart test/features/admin/lesson_editor_initial_mapper_test.dart
git commit -m "refactor(lessons): add typed editor session"
```

### Task 4: Extract reference loading and stale-request ownership

**Files:**

- Create: `lib/features/admin/presentation/widgets/lesson_editor/lesson_editor_data_controller.dart`
- Create: `test/features/admin/lesson_editor_data_controller_test.dart`

**Interfaces:**

- Consumes: `MagicCrmService` callbacks and typed `LessonEditorSession`/`LessonEditorDraft`.
- Produces: `Future<LessonEditorLoadPatch?> loadInitial`, `loadBranch`, `selectClient`, and `loadSubscriptions`; `null` means a stale continuation.

Use these exact test seams and patch boundary; production code passes the
current draft/references and applies the returned values in one `setState`:

```dart
typedef LessonEditorRowsById = Future<List<Map<String, dynamic>>> Function(
  String id,
);
typedef LessonEditorRows = Future<List<Map<String, dynamic>>> Function();
typedef LessonEditorCatalogLoader = Future<LessonDecisionCatalog> Function(
  String branchId,
);
typedef LessonEditorClientResolver = Future<Map<String, dynamic>?> Function({
  required String type,
  required String id,
});

class LessonEditorLoadPatch {
  const LessonEditorLoadPatch({
    required this.branchId,
    required this.draft,
    required this.references,
  });
  final String? branchId;
  final LessonEditorDraft? draft;
  final LessonEditorReferenceState references;
}

Future<List<Map<String, dynamic>>> _emptyRows() async => const [];
Future<List<Map<String, dynamic>>> _emptyRowsById(String _) async => const [];
Future<Map<String, dynamic>?> _emptyResolvedClient({
  required String type,
  required String id,
}) async => null;
```

- [ ] **Step 1: Write failing revision-guard tests**

```dart
// Test file import required for both race tests:
import 'dart:async';

test('discards the slower room response after branch changes', () async {
  final branchA = Completer<List<Map<String, dynamic>>>();
  final branchB = Completer<List<Map<String, dynamic>>>();
  final controller = LessonEditorDataController.forTesting(
    listRooms: (branchId) => branchId == 'branch-a' ? branchA.future : branchB.future,
    loadCatalog: (_) async => const LessonDecisionCatalog(settlementTypes: [], compensationRules: []),
    listSubscriptions: (_) async => const [],
  );

  final slow = controller.loadBranch('branch-a');
  final fast = controller.loadBranch('branch-b');
  branchB.complete([{'id': 'room-b', 'name': 'B'}]);
  expect((await fast)?.branchId, 'branch-b');
  branchA.complete([{'id': 'room-a', 'name': 'A'}]);
  expect(await slow, isNull);
});

test('discards subscriptions for the previously selected student', () async {
  final first = Completer<List<Map<String, dynamic>>>();
  final controller = LessonEditorDataController.forTesting(
    listRooms: (_) async => const [],
    loadCatalog: (_) async => const LessonDecisionCatalog(settlementTypes: [], compensationRules: []),
    listSubscriptions: (studentId) => studentId == 'student-a' ? first.future : Future.value(const []),
  );
  final stale = controller.loadSubscriptions(const LessonClientRef(type: 'student', id: 'student-a', label: 'A'));
  await controller.loadSubscriptions(const LessonClientRef(type: 'student', id: 'student-b', label: 'B'));
  first.complete([{'id': 'subscription-a', 'status': 'active'}]);
  expect(await stale, isNull);
});
```

- [ ] **Step 2: Verify RED**

```powershell
flutter test test/features/admin/lesson_editor_data_controller_test.dart --reporter compact
```

- [ ] **Step 3: Implement one owner for all four revisions**

```dart
abstract interface class LessonEditorDataLoader {
  Future<LessonEditorLoadPatch?> loadInitial(LessonEditorSession session);
  Future<LessonEditorLoadPatch?> selectClient(
    LessonClientRef? client, {
    required LessonEditorDraft draft,
    required LessonEditorReferenceState references,
  });
  Future<LessonEditorLoadPatch?> loadBranch(
    String branchId, {
    LessonEditorDraft? draft,
    LessonEditorReferenceState references =
        const LessonEditorReferenceState.empty(),
  });
  Future<LessonEditorLoadPatch?> loadSubscriptions(
    LessonClientRef? client, {
    LessonEditorDraft? draft,
    LessonEditorReferenceState references =
        const LessonEditorReferenceState.empty(),
  });
  void invalidateClientSelection();
}

class LessonEditorDataController implements LessonEditorDataLoader {
  LessonEditorDataController.forTesting({
    required LessonEditorRowsById listRooms,
    required LessonEditorCatalogLoader loadCatalog,
    required LessonEditorRowsById listSubscriptions,
    LessonEditorRows listTeachers = _emptyRows,
    LessonEditorRows listBranches = _emptyRows,
    LessonEditorRows searchClients = _emptyRows,
    LessonEditorClientResolver resolveClient = _emptyResolvedClient,
  }) : _listRooms = listRooms,
       _loadCatalog = loadCatalog,
       _listSubscriptions = listSubscriptions,
       _listTeachers = listTeachers,
       _listBranches = listBranches,
       _searchClients = searchClients,
       _resolveClient = resolveClient;

  LessonEditorDataController.fromCrm(MagicCrmService crm)
      : this.forTesting(
          listRooms: (branchId) => crm.listRooms(branchId: branchId, limit: 100),
          loadCatalog: (branchId) async => LessonDecisionCatalog.fromJson(
            await crm.getLessonDecisionCatalog(branchId: branchId),
            LessonDecisionOperation.settle,
          ),
          listSubscriptions: (studentId) => crm.listSubscriptions(studentId: studentId, limit: 50),
          listTeachers: () => crm.listTeachers(limit: 100),
          listBranches: () => crm.listBranches(limit: 100),
          searchClients: () => crm.searchClientRefs(limit: 50),
          resolveClient: ({required type, required id}) => crm.resolveClientRef(type: type, id: id),
        );

  final LessonEditorRowsById _listRooms;
  final LessonEditorCatalogLoader _loadCatalog;
  final LessonEditorRowsById _listSubscriptions;
  final LessonEditorRows _listTeachers;
  final LessonEditorRows _listBranches;
  final LessonEditorRows _searchClients;
  final LessonEditorClientResolver _resolveClient;

  int _branchRevision = 0;
  int _catalogRevision = 0;
  int _subscriptionRevision = 0;
  int _clientRevision = 0;
}
```

Implement the five current workflows with these explicit transitions:

- `loadInitial` captures `_clientRevision`, optionally resolves the seeded
  client, awaits teachers/branches/client refs in parallel, prepends the
  resolved selected row when search omitted it, selects client branch → seeded
  valid branch → first branch, awaits `loadBranch`, rejects a changed client
  revision, then awaits `loadSubscriptions`;
- `selectClient` increments `_clientRevision`, clears teacher/room/catalog and
  financial selections only when the valid client branch changes, awaits the
  branch patch, rejects a changed client/key/branch, then loads subscriptions;
- `loadBranch` increments both room and catalog revisions, awaits both requests
  in parallel, and returns `null` unless both revisions and branch id still
  match; it clears a selected room not present in the returned active branch;
- `loadSubscriptions` increments its revision, returns an empty patch for
  non-students, filters returned rows to `status == 'active'`, clears a missing
  selected subscription, and rejects a changed student id;
- `invalidateClientSelection` increments client, branch, catalog, and
  subscription revisions so disposal or a new selection invalidates every
  outstanding continuation.

The controller returns immutable reference/draft patches; it never calls
`setState`, checks `mounted`, navigates, or catches an error only to show UI.

- [ ] **Step 4: Run GREEN and stale regression tests**

```powershell
dart format lib/features/admin/presentation/widgets/lesson_editor/lesson_editor_data_controller.dart test/features/admin/lesson_editor_data_controller_test.dart
flutter test test/features/admin/lesson_editor_data_controller_test.dart test/features/admin/presentation/widgets/create_lesson_dialog_test.dart test/features/admin/create_lesson_student_search_test.dart --reporter compact
flutter analyze lib/features/admin/presentation/widgets/lesson_editor/lesson_editor_data_controller.dart
git diff --check
```

- [ ] **Step 5: Commit**

```powershell
git add -- lib/features/admin/presentation/widgets/lesson_editor/lesson_editor_data_controller.dart test/features/admin/lesson_editor_data_controller_test.dart
git commit -m "refactor(lessons): extract editor data loading"
```

### Task 5: Extract pure lesson decision policy and payload construction

**Files:**

- Create: `lib/features/admin/presentation/widgets/lesson_editor/lesson_editor_decision_policy.dart`
- Create: `test/features/admin/lesson_editor_decision_policy_test.dart`
- Modify: `lib/features/admin/presentation/widgets/lesson_form_rules.dart`

**Interfaces:**

- Consumes: typed draft/session/reference state and compensation input.
- Produces: `LessonEditorValidation`, funding defaults, create payload, schedule payload, financial-change decision, and `LessonDecisionRequest`.

- [ ] **Step 1: Write the failing validation and payload matrix**

```dart
const policy = LessonEditorDecisionPolicy();

LessonDecisionCatalogItem _catalogItem({
  String key = 'standard',
  String? mode,
  int hourShareBasisPoints = 10000,
  String fixedPenaltyMinor = '0',
}) => LessonDecisionCatalogItem(
  key: key,
  label: key,
  order: 0,
  mode: mode,
  hourShareBasisPoints: hourShareBasisPoints,
  fixedPenaltyMinor: fixedPenaltyMinor,
);

LessonEditorDraft _draft({
  String clientChargeType = 'personal_account',
  String? subscriptionId,
  String? settlementTypeKey = 'standard',
  String? compensationRuleKey = 'standard',
  String? compensationValueMinor,
}) => LessonEditorDraft(
  localStart: DateTime(2026, 8, 26, 13),
  durationMinutes: 60,
  isTrial: false,
  completionType: 'standard',
  clientChargeType: clientChargeType,
  client: const LessonClientRef(
    type: 'student', id: 'student-a', label: 'Анна',
  ),
  teacherId: 'teacher-a', branchId: 'branch-a', roomId: 'room-a',
  subscriptionId: subscriptionId,
  settlementTypeKey: settlementTypeKey,
  compensationRuleKey: compensationRuleKey,
  compensationValueMinor: compensationValueMinor,
);

LessonEditorSession _createSession(LessonEditorDraft draft) =>
    LessonEditorSession(draft: draft, snapshot: null, seededClient: draft.client);

LessonEditorReferenceState _references({
  List<LessonDecisionCatalogItem>? settlements,
  List<LessonDecisionCatalogItem>? compensationRules,
}) => LessonEditorReferenceState(
  teachers: const [], clients: const [], branches: const [], rooms: const [],
  subscriptions: const [],
  catalog: LessonDecisionCatalog(
    settlementTypes: settlements ?? [_catalogItem()],
    compensationRules: compensationRules ?? [_catalogItem()],
  ),
);

test('none funding is legal only for a zero-charge settlement', () {
  final paid = _catalogItem(hourShareBasisPoints: 10000, fixedPenaltyMinor: '0');
  final free = _catalogItem(hourShareBasisPoints: 0, fixedPenaltyMinor: '0');
  final paidDraft = _draft(clientChargeType: 'none');
  final freeDraft = _draft(clientChargeType: 'none');
  expect(policy.validate(
    session: _createSession(paidDraft), draft: paidDraft,
    references: _references(settlements: [paid]),
  ).message,
      'Для платного списания выберите абонемент или личный счёт');
  expect(policy.validate(
    session: _createSession(freeDraft), draft: freeDraft,
    references: _references(settlements: [free]),
  ).isValid, isTrue);
});

test('builds three independent create decisions', () {
  final payload = policy.createPayload(
    draft: _draft(
      settlementTypeKey: 'standard', compensationRuleKey: 'teacher-percent',
      compensationValueMinor: '12500', clientChargeType: 'subscription',
      subscriptionId: 'subscription-a',
    ),
    references: _references(),
  );
  expect(payload['financialDecision'], {
    'settlementTypeKey': 'standard',
    'teacherCompensationRuleKey': 'teacher-percent',
    'teacherCompensationValueMinor': '12500',
  });
  expect(payload['clientChargeType'], 'subscription');
  expect(payload['subscriptionId'], 'subscription-a');
});
```

- [ ] **Step 2: Verify RED**

```powershell
flutter test test/features/admin/lesson_editor_decision_policy_test.dart --reporter compact
```

- [ ] **Step 3: Implement named predicates instead of one compound conditional**

```dart
class LessonEditorValidation {
  const LessonEditorValidation.valid() : message = null;
  const LessonEditorValidation.invalid(this.message);
  final String? message;
  bool get isValid => message == null;
}

class LessonEditorDecisionPolicy {
  const LessonEditorDecisionPolicy();

  bool isNoCharge(LessonDecisionCatalogItem? settlement) =>
      settlement?.hourShareBasisPoints == 0 && settlement?.fixedPenaltyMinor == '0';

  LessonEditorValidation validate({
    required LessonEditorSession session,
    required LessonEditorDraft draft,
    required LessonEditorReferenceState references,
  }) {
    if (!session.isGroupEdit && draft.client == null) {
      return const LessonEditorValidation.invalid('Заполните обязательные поля корректно');
    }
    if (draft.teacherId == null || draft.branchId == null || draft.roomId == null) {
      return const LessonEditorValidation.invalid('Заполните обязательные поля корректно');
    }
    if (!session.isEdit &&
        draft.clientChargeType == 'subscription' &&
        draft.subscriptionId == null) {
      return const LessonEditorValidation.invalid(
        'Заполните обязательные поля корректно',
      );
    }
    final settlement = references.catalog?.settlementTypes
        .where((item) => item.key == draft.settlementTypeKey)
        .firstOrNull;
    if (!session.isEdit &&
        draft.clientChargeType == 'none' &&
        !isNoCharge(settlement)) {
      return const LessonEditorValidation.invalid(
        'Для платного списания выберите абонемент или личный счёт',
      );
    }
    if (!session.isEdit &&
        (draft.settlementTypeKey == null ||
            draft.compensationRuleKey == null)) {
      return const LessonEditorValidation.invalid(
        'Заполните обязательные поля корректно',
      );
    }
    final rule = references.catalog?.compensationRules
        .where((item) => item.key == draft.compensationRuleKey)
        .firstOrNull;
    final valueRequired = switch (rule?.mode) {
      'percent' || 'fixed' || 'hourly' => true,
      _ => false,
    };
    if (valueRequired && draft.compensationValueMinor == null) {
      return const LessonEditorValidation.invalid(
        'Введите корректный процент или сумму оплаты преподавателю',
      );
    }
    if (!session.isEdit &&
        compensationNeedsReason(draft: draft, rule: rule) &&
        draft.plannedSettlementReason.trim().isEmpty) {
      return const LessonEditorValidation.invalid(
        'Укажите причину индивидуального значения оплаты преподавателю',
      );
    }
    if (session.isEdit && session.snapshot?.expectedVersion == null) {
      return const LessonEditorValidation.invalid(
        'Обновите расписание: версия занятия не получена',
      );
    }
    if (session.isEdit &&
        !hasScheduleChanges(session: session, draft: draft) &&
        !hasFinancialChanges(session: session, draft: draft)) {
      return const LessonEditorValidation.invalid(
        'Измените параметры расписания или оплату преподавателю',
      );
    }
    return const LessonEditorValidation.valid();
  }
}
```

Implement these public pure method boundaries; do not expose widget controllers or
raw service calls from the policy:

```dart
LessonEditorDraft applyFundingDefault({
  required LessonEditorDraft draft,
  required LessonEditorReferenceState references,
});
Map<String, dynamic> schedulePayload(LessonEditorDraft draft);
Map<String, dynamic> createPayload({
  required LessonEditorDraft draft,
  required LessonEditorReferenceState references,
});
bool hasScheduleChanges({
  required LessonEditorSession session,
  required LessonEditorDraft draft,
});
bool hasFinancialChanges({
  required LessonEditorSession session,
  required LessonEditorDraft draft,
});
bool compensationNeedsReason({
  required LessonEditorDraft draft,
  required LessonDecisionCatalogItem? rule,
});
LessonDecisionRequest editRequest({
  required LessonEditorSession session,
  required LessonEditorDraft draft,
});
```

`schedulePayload` must return only `teacherId`, `branchId`, `roomId`,
`scheduledAt`, and `durationMinutes`. Serialize Moscow wall time with the
existing `DateTime.utc(year, month, day, hour - 3, minute)` rule.
`createPayload` adds `clientRef`, trial/completion, client funding,
compatibility charge/rate hints, the three-field `financialDecision`, optional
reason/subscription, and lead note. `editRequest` chooses reschedule when the
schedule differs; otherwise it chooses correction for completed/done states or
planned settlement. Move compensation parsing/formatting and snapshot labels
behind named pure helpers. Compatibility money fields remain request/display
hints; backend responses remain authoritative.

- [ ] **Step 4: Run GREEN and current rules tests**

```powershell
dart format lib/features/admin/presentation/widgets/lesson_editor/lesson_editor_decision_policy.dart lib/features/admin/presentation/widgets/lesson_form_rules.dart test/features/admin/lesson_editor_decision_policy_test.dart
flutter test test/features/admin/lesson_editor_decision_policy_test.dart test/features/admin/presentation/widgets/lesson_form_rules_test.dart test/features/schedule/lesson_form_test.dart --reporter compact
flutter analyze lib/features/admin/presentation/widgets/lesson_editor/lesson_editor_decision_policy.dart
git diff --check
```

- [ ] **Step 5: Commit**

```powershell
git add -- lib/features/admin/presentation/widgets/lesson_editor/lesson_editor_decision_policy.dart lib/features/admin/presentation/widgets/lesson_form_rules.dart test/features/admin/lesson_editor_decision_policy_test.dart
git commit -m "refactor(lessons): extract editor decision policy"
```

### Task 6: Extract the lesson decision command controller

**Files:**

- Create: `lib/features/admin/presentation/widgets/lesson_decision/lesson_decision_controller.dart`
- Modify: `lib/features/admin/presentation/widgets/lesson_decision_flow.dart:147-366`
- Modify: `lib/features/admin/presentation/widgets/create_lesson_dialog.dart`
- Modify: `lib/features/admin/presentation/widgets/schedule_widget_actions.dart`
- Modify: `test/features/schedule/lesson_decision_flow_test.dart`
- Modify: `test/features/schedule/lesson_form_test.dart`
- Modify: `integration_test/modal_device_test.dart`
- Modify: `integration_test/lesson_settlement_device_test.dart`

**Interfaces:**

- Consumes: `MagicCrmService`, decision models, `MagicMutationIdentity`.
- Produces: public `LessonDecisionController` and the existing
  `showLessonDecisionFlow` signature with `MagicCrmService crm` replacing the
  raw API-client parameter.

- [ ] **Step 1: Add failing direct controller tests**

Add
`import 'package:magic_music_crm/core/services/magic_crm_service.dart';`,
create the controller through the existing `_LessonDecisionApi`, and pin:

```dart
test('keeps one mutation identity between preview and commit', () async {
  final api = _LessonDecisionApi();
  final controller = LessonDecisionController(
    crm: MagicCrmService(api),
    operation: LessonDecisionOperation.reschedule,
    lesson: {'id': 'lesson-a', 'version': 3},
    successor: {'scheduledAt': '2026-08-26T10:00:00.000Z'},
  );
  final preview = await controller.preview(
    reason: 'Перенос', settlementTypeKey: 'standard',
    compensationRuleKey: 'standard',
  );
  await controller.commit(preview);
  expect(api.identities, hasLength(1));
  expect(api.commits.single['previewToken'], 'signed-preview');
});

test('clears preview identity and adopts current version after stale commit', () {
  final controller = LessonDecisionController(
    crm: MagicCrmService(_LessonDecisionApi()),
    operation: LessonDecisionOperation.reschedule,
    lesson: {'id': 'lesson-a', 'version': 3},
    successor: {'scheduledAt': '2026-08-26T10:00:00.000Z'},
  );
  final recovered = controller.recoverStaleCommit(MagicApiException(
    statusCode: 409,
    message: 'stale',
    details: {'code': 'STALE_LESSON_VERSION', 'currentVersion': 7},
  ));
  expect(recovered?.message, contains('Версия обновлена'));
  expect(() => controller.commit(const LessonDecisionPreview({'canConfirm': true, 'previewToken': 'old'})),
      throwsStateError);
});
```

- [ ] **Step 2: Verify RED**

```powershell
flutter test test/features/schedule/lesson_decision_flow_test.dart --plain-name "keeps one mutation identity between preview and commit"
```

- [ ] **Step 3: Move command behavior and migrate consumers atomically**

The controller constructor becomes:

```dart
LessonDecisionController({
  required MagicCrmService crm,
  required this.operation,
  required this.lesson,
  this.successor,
  this.initialSettlementTypeKey,
  this.initialCompensationRuleKey,
  this.initialCompensationValueMinor,
}) : _crm = crm,
     _expectedVersion = (lesson['version'] as num?)?.toInt();
```

Replace raw calls with `getLessonDecisionCatalog`, `previewLessonDecision`, and `commitLessonDecision`. Keep payload assembly, `MagicMutationIdentity.create('lesson-${operation.apiKey}-${lesson['id']}')`, `usePut` only for planned settlement, participant normalization, completed detection, and stale messages byte-equivalent.

Change all production/tests/device callers from `api:` to `crm:`. `lesson_decision_flow.dart` exports the controller and keeps only adaptive-surface construction plus form imports.

- [ ] **Step 4: Run GREEN across every direct consumer**

```powershell
dart format lib/features/admin/presentation/widgets/lesson_decision lib/features/admin/presentation/widgets/lesson_decision_flow.dart lib/features/admin/presentation/widgets/create_lesson_dialog.dart lib/features/admin/presentation/widgets/schedule_widget_actions.dart test/features/schedule/lesson_decision_flow_test.dart test/features/schedule/lesson_form_test.dart integration_test/modal_device_test.dart integration_test/lesson_settlement_device_test.dart
flutter test test/features/schedule/lesson_decision_flow_test.dart test/features/schedule/lesson_form_test.dart test/features/admin/presentation/widgets/create_lesson_dialog_test.dart --reporter compact
flutter analyze lib/features/admin/presentation/widgets/lesson_decision lib/features/admin/presentation/widgets/lesson_decision_flow.dart lib/features/admin/presentation/widgets/schedule_widget_actions.dart
rg -n "showLessonDecisionFlow\([\s\S]*api:|LessonDecisionController\([\s\S]*api:|magicApiClientProvider" lib/features/admin/presentation/widgets test/features/schedule
git diff --check
```

Expected: tests/analyzer pass; `rg` finds no decision-flow direct API injection.

- [ ] **Step 5: Commit**

```powershell
git add -- lib/features/admin/presentation/widgets/lesson_decision lib/features/admin/presentation/widgets/lesson_decision_flow.dart lib/features/admin/presentation/widgets/create_lesson_dialog.dart lib/features/admin/presentation/widgets/schedule_widget_actions.dart test/features/schedule/lesson_decision_flow_test.dart test/features/schedule/lesson_form_test.dart integration_test/modal_device_test.dart integration_test/lesson_settlement_device_test.dart
git commit -m "refactor(lessons): extract decision controller"
```

### Task 7: Split lesson decision form and presentation sections

**Files:**

- Create: `lib/features/admin/presentation/widgets/lesson_decision/lesson_decision_form.dart`
- Create: `lib/features/admin/presentation/widgets/lesson_decision/lesson_decision_sections.dart`
- Modify: `lib/features/admin/presentation/widgets/lesson_decision_flow.dart:368-1100`
- Modify: `test/features/schedule/lesson_decision_flow_test.dart`

**Interfaces:**

- Consumes: `LessonDecisionController`, catalog/model types, callbacks internal to the form.
- Produces: bounded `LessonDecisionForm` lifecycle owner and stateless sections; `lesson_decision_flow.dart` becomes a small entry/export file.

- [ ] **Step 1: Add failing ownership and section tests**

```dart
import 'dart:io';

Widget _host(Widget child) => MaterialApp(home: Material(child: child));

testWidgets('completed reschedule section explains forced reversal', (tester) async {
  await tester.pumpWidget(_host(LessonDecisionCompletedNotice(
    sourceScheduledAt: DateTime(2026, 8, 25, 13),
    successorScheduledAt: DateTime(2026, 8, 26, 13),
  )));
  expect(find.byKey(const Key('lesson-decision-completed-notice')), findsOneWidget);
  expect(find.textContaining('бесплатное'), findsOneWidget);
});

test('flow entry contains no form state or section implementation', () {
  final source = File('lib/features/admin/presentation/widgets/lesson_decision_flow.dart').readAsStringSync();
  expect(source, isNot(contains('class _LessonDecisionFormState')));
  expect(source, isNot(contains('class _LessonDecisionPreviewCard')));
  expect(source.split('\n').length, lessThan(120));
});
```

- [ ] **Step 2: Verify RED**

```powershell
flutter test test/features/schedule/lesson_decision_flow_test.dart --reporter compact
```

- [ ] **Step 3: Move form state and stateless sections**

`LessonDecisionForm` owns only the form key, reason/compensation controllers, typed draft selections, catalog/preview/error, load/calculate/commit/recover lifecycle, and disposal. Move `_DecisionClientOverrides`, move summary, completed notice, catalog label, preview card, and error into `lesson_decision_sections.dart` with typed constructor inputs and callbacks.

The completed notice is a public stateless section with this stable contract:

```dart
class LessonDecisionCompletedNotice extends StatelessWidget {
  const LessonDecisionCompletedNotice({
    required this.sourceScheduledAt,
    required this.successorScheduledAt,
    super.key,
  });
  final DateTime sourceScheduledAt;
  final DateTime successorScheduledAt;
}
```

The flow entry must reduce to this shape:

```dart
export 'lesson_decision/lesson_decision_controller.dart';
export 'lesson_decision/lesson_decision_models.dart';

Future<bool?> showLessonDecisionFlow(
  BuildContext context, {
  required MagicCrmService crm,
  required LessonDecisionOperation operation,
  required Map<String, dynamic> lesson,
  Map<String, dynamic>? successor,
  String? initialSettlementTypeKey,
  String? initialCompensationRuleKey,
  String? initialCompensationValueMinor,
}) {
  final controller = LessonDecisionController(
    crm: crm,
    operation: operation,
    lesson: lesson,
    successor: successor,
    initialSettlementTypeKey: initialSettlementTypeKey,
    initialCompensationRuleKey: initialCompensationRuleKey,
    initialCompensationValueMinor: initialCompensationValueMinor,
  );
  return showMagicAdaptiveSurface<bool>(
    context,
    kind: AppSurfaceKind.quickView,
    title: operation.title,
    subtitle: 'Сначала расчёт, затем подтверждение',
    icon: Icons.rule_rounded,
    builder: (_) => LessonDecisionForm(controller: controller),
  );
}
```

- [ ] **Step 4: Run GREEN and measure owners**

```powershell
dart format lib/features/admin/presentation/widgets/lesson_decision lib/features/admin/presentation/widgets/lesson_decision_flow.dart test/features/schedule/lesson_decision_flow_test.dart
flutter test test/features/schedule/lesson_decision_flow_test.dart test/features/schedule/lesson_form_test.dart --reporter compact
flutter analyze lib/features/admin/presentation/widgets/lesson_decision lib/features/admin/presentation/widgets/lesson_decision_flow.dart
repowise health --file lib/features/admin/presentation/widgets/lesson_decision_flow.dart --format json
git diff --check
```

Expected: no brain/god finding; entry file under 120 physical lines; each new owner max CCN `<= 10`.

- [ ] **Step 5: Commit**

```powershell
git add -- lib/features/admin/presentation/widgets/lesson_decision lib/features/admin/presentation/widgets/lesson_decision_flow.dart test/features/schedule/lesson_decision_flow_test.dart
git commit -m "refactor(lessons): split decision presentation"
```

### Task 8: Extract schedule analysis and save orchestration

**Files:**

- Create: `lib/features/admin/presentation/widgets/lesson_editor/lesson_editor_schedule_controller.dart`
- Create: `lib/features/admin/presentation/widgets/lesson_editor/lesson_editor_save_flow.dart`
- Create: `test/features/admin/lesson_editor_schedule_controller_test.dart`
- Create: `test/features/admin/lesson_editor_save_flow_test.dart`

**Interfaces:**

- Consumes: `MagicCrmService`, editor policy/session/draft/reference state.
- Produces: `LessonEditorScheduleController.analyze/applySuggestion`; `LessonEditorSaveFlow.save`; typed `LessonSaveCreated`, `LessonSaveViolations`, `LessonSaveDecision`, `LessonSaveBusy`, and `LessonSaveFailure` outcomes.

- [ ] **Step 1: Write failing command-order and outcome tests**

```dart
import 'dart:async';

Map<String, dynamic> _violationJson(String code) => {
  'code': code,
  'resource': {'type': 'room', 'id': 'room-a'},
  'conflictingLessonIds': ['lesson-existing'],
  'ruleIds': ['room-overlap'],
};

LessonEditorSaveCommand _createCommand() => LessonEditorSaveCommand(
  scheduleRequest: const LessonEditorScheduleRequest(
    clientType: 'student', clientId: 'student-a',
    teacherId: 'teacher-a', branchId: 'branch-a', roomId: 'room-a',
    scheduledAt: '2026-08-26T10:00:00.000Z', durationMinutes: 60,
  ),
  payload: const {
    'clientRef': {'type': 'student', 'id': 'student-a'},
    'teacherId': 'teacher-a', 'branchId': 'branch-a', 'roomId': 'room-a',
    'scheduledAt': '2026-08-26T10:00:00.000Z', 'durationMinutes': 60,
  },
);

test('preview transport failure still reaches authoritative create', () async {
  var createCalls = 0;
  final flow = LessonEditorSaveFlow.forTesting(
    preview: (_) async => throw StateError('preview unavailable'),
    create: (_) async { createCalls++; return {'id': 'lesson-a'}; },
  );
  final result = await flow.save(_createCommand());
  expect(result, isA<LessonSaveCreated>());
  expect(createCalls, 1);
});

test('authoritative 422 returns violations and keeps the draft', () async {
  final flow = LessonEditorSaveFlow.forTesting(
    preview: (_) async => const LessonScheduleAnalysis(valid: true, violations: [], suggestions: []),
    create: (_) async => throw MagicApiException(
      statusCode: 422, message: 'conflict',
      details: {'violations': [_violationJson('ROOM_OVERLAP')]},
    ),
  );
  final result = await flow.save(_createCommand());
  expect(result, isA<LessonSaveViolations>());
});

test('coalesces a double submit into one create call', () async {
  final completer = Completer<Map<String, dynamic>>();
  var calls = 0;
  final flow = LessonEditorSaveFlow.forTesting(
    preview: (_) async => const LessonScheduleAnalysis(valid: true, violations: [], suggestions: []),
    create: (_) { calls++; return completer.future; },
  );
  final first = flow.save(_createCommand());
  expect(await flow.save(_createCommand()), isA<LessonSaveBusy>());
  completer.complete({'id': 'lesson-a'});
  await first;
  expect(calls, 1);
});
```

- [ ] **Step 2: Verify RED**

```powershell
flutter test test/features/admin/lesson_editor_schedule_controller_test.dart test/features/admin/lesson_editor_save_flow_test.dart --reporter compact
```

- [ ] **Step 3: Implement typed orchestration with no BuildContext**

```dart
class LessonEditorScheduleRequest {
  const LessonEditorScheduleRequest({
    required this.clientType,
    required this.clientId,
    required this.teacherId,
    required this.branchId,
    required this.roomId,
    required this.scheduledAt,
    required this.durationMinutes,
    this.excludeLessonId,
  });
  final String clientType;
  final String clientId;
  final String teacherId;
  final String branchId;
  final String roomId;
  final String scheduledAt;
  final int durationMinutes;
  final String? excludeLessonId;
}

class LessonEditorSaveCommand {
  const LessonEditorSaveCommand({
    required this.scheduleRequest,
    required this.payload,
    this.decisionRequest,
  });
  final LessonEditorScheduleRequest scheduleRequest;
  final Map<String, dynamic> payload;
  final LessonDecisionRequest? decisionRequest;
}

sealed class LessonSaveOutcome { const LessonSaveOutcome(); }
final class LessonSaveCreated extends LessonSaveOutcome {
  const LessonSaveCreated(this.lesson);
  final Map<String, dynamic> lesson;
}
final class LessonSaveViolations extends LessonSaveOutcome {
  const LessonSaveViolations(this.violations);
  final List<LessonConstraintViolation> violations;
}
final class LessonSaveDecision extends LessonSaveOutcome {
  const LessonSaveDecision(this.request);
  final LessonDecisionRequest request;
}
final class LessonSaveBusy extends LessonSaveOutcome { const LessonSaveBusy(); }
final class LessonSaveFailure extends LessonSaveOutcome {
  const LessonSaveFailure(this.error, this.stackTrace);
  final Object error;
  final StackTrace stackTrace;
}

typedef LessonSchedulePreview = Future<LessonScheduleAnalysis> Function(
  LessonEditorScheduleRequest request,
);
typedef LessonCreate = Future<Map<String, dynamic>> Function(
  Map<String, dynamic> payload,
);

class LessonEditorSaveFlow {
  LessonEditorSaveFlow.forTesting({
    required LessonSchedulePreview preview,
    required LessonCreate create,
  }) : _preview = preview,
       _create = create;

  LessonEditorSaveFlow.fromCrm(MagicCrmService crm)
      : this.forTesting(
          preview: (request) => crm.analyzeLessonSchedule(
            clientType: request.clientType,
            clientId: request.clientId,
            teacherId: request.teacherId,
            branchId: request.branchId,
            roomId: request.roomId,
            scheduledAt: request.scheduledAt,
            durationMinutes: request.durationMinutes,
            excludeLessonId: request.excludeLessonId,
          ),
          create: crm.createLessonRaw,
        );

  final LessonSchedulePreview _preview;
  final LessonCreate _create;
  bool _saving = false;

  Future<LessonSaveOutcome> save(LessonEditorSaveCommand command) async {
    if (_saving) return const LessonSaveBusy();
    _saving = true;
    try {
      if (command.decisionRequest case final request?) {
        return LessonSaveDecision(request);
      }
      try {
        final preview = await _preview(command.scheduleRequest);
        if (!preview.valid) return LessonSaveViolations(preview.violations);
      } catch (_) {
        // The authoritative create transaction repeats every hard constraint.
      }
      final lesson = await _create(command.payload);
      return LessonSaveCreated(lesson);
    } on MagicApiException catch (error, stackTrace) {
      final violations = lessonConstraintViolationsFromDetails(error.details);
      if (violations != null && violations.isNotEmpty) {
        return LessonSaveViolations(violations);
      }
      return LessonSaveFailure(error, stackTrace);
    } catch (error, stackTrace) {
      return LessonSaveFailure(error, stackTrace);
    } finally {
      _saving = false;
    }
  }
}
```

The schedule owner has this exact boundary:

```dart
class LessonEditorScheduleController {
  LessonEditorScheduleController({
    required LessonEditorDecisionPolicy policy,
    required Future<LessonScheduleAnalysis> Function(
      LessonEditorScheduleRequest request,
    ) analyze,
  }) : _policy = policy,
       _analyze = analyze;

  final LessonEditorDecisionPolicy _policy;
  final LessonSchedulePreview _analyze;

  LessonEditorScheduleRequest requestFor({
    required LessonEditorSession session,
    required LessonEditorDraft draft,
  }) {
    final client = draft.client;
    final teacherId = draft.teacherId;
    final branchId = draft.branchId;
    final roomId = draft.roomId;
    if (client == null ||
        teacherId == null ||
        branchId == null ||
        roomId == null) {
      throw StateError('Lesson schedule request is incomplete');
    }
    final payload = _policy.schedulePayload(draft);
    return LessonEditorScheduleRequest(
      clientType: client.type,
      clientId: client.id,
      teacherId: teacherId,
      branchId: branchId,
      roomId: roomId,
      scheduledAt: payload['scheduledAt']! as String,
      durationMinutes: draft.durationMinutes,
      excludeLessonId: session.snapshot?.lessonId,
    );
  }

  Future<LessonScheduleAnalysis> analyze({
    required LessonEditorSession session,
    required LessonEditorDraft draft,
  }) => _analyze(requestFor(session: session, draft: draft));

  LessonEditorDraft applySuggestion(
    LessonEditorDraft draft,
    ScheduleSuggestion suggestion,
  ) => draft.copyWith(
    teacherId: suggestion.teacherId ?? draft.teacherId,
    roomId: suggestion.roomId ?? draft.roomId,
    localStart: suggestion.startAt ?? draft.localStart,
  );
}
```

It owns no navigation or widget state.

- [ ] **Step 4: Run GREEN**

```powershell
dart format lib/features/admin/presentation/widgets/lesson_editor/lesson_editor_schedule_controller.dart lib/features/admin/presentation/widgets/lesson_editor/lesson_editor_save_flow.dart test/features/admin/lesson_editor_schedule_controller_test.dart test/features/admin/lesson_editor_save_flow_test.dart
flutter test test/features/admin/lesson_editor_schedule_controller_test.dart test/features/admin/lesson_editor_save_flow_test.dart test/features/schedule/lesson_form_test.dart --reporter compact
flutter analyze lib/features/admin/presentation/widgets/lesson_editor/lesson_editor_schedule_controller.dart lib/features/admin/presentation/widgets/lesson_editor/lesson_editor_save_flow.dart
git diff --check
```

- [ ] **Step 5: Commit**

```powershell
git add -- lib/features/admin/presentation/widgets/lesson_editor/lesson_editor_schedule_controller.dart lib/features/admin/presentation/widgets/lesson_editor/lesson_editor_save_flow.dart test/features/admin/lesson_editor_schedule_controller_test.dart test/features/admin/lesson_editor_save_flow_test.dart
git commit -m "refactor(lessons): extract editor command flows"
```

### Task 9: Build bounded lesson editor sections with typed callbacks

**Files:**

- Create: `lib/features/admin/presentation/widgets/lesson_editor/lesson_editor_view.dart`
- Create: `lib/features/admin/presentation/widgets/lesson_editor/lesson_participant_section.dart`
- Create: `lib/features/admin/presentation/widgets/lesson_editor/lesson_schedule_section.dart`
- Create: `lib/features/admin/presentation/widgets/lesson_editor/lesson_financial_section.dart`
- Create: `lib/features/admin/presentation/widgets/lesson_editor/lesson_editor_feedback.dart`
- Create: `test/features/admin/lesson_editor_sections_test.dart`

**Interfaces:**

- Consumes: `LessonEditorViewModel` with draft/references/loading flags and `LessonEditorActions` callback interface.
- Produces: normal-import stateless presentation; no service/provider/navigation access.

- [ ] **Step 1: Add failing section contract tests**

```dart
import 'dart:io';

Widget _host(Widget child) => MaterialApp(home: Material(child: child));

const _suggestion = ScheduleSuggestion(
  kind: 'SAME_TIME_ROOM', rank: 1, score: 100,
  roomId: 'room-b', roomName: 'Класс B',
);

LessonScheduleSectionModel _scheduleModel({
  List<ScheduleSuggestion> suggestions = const [],
}) => LessonScheduleSectionModel(
  draft: LessonEditorDraft(
    localStart: DateTime(2026, 8, 26, 13), durationMinutes: 60,
    isTrial: false, completionType: 'standard',
    clientChargeType: 'personal_account',
    client: const LessonClientRef(
      type: 'student', id: 'student-a', label: 'Анна',
    ),
    teacherId: 'teacher-a', branchId: 'branch-a', roomId: 'room-a',
  ),
  analysis: LessonScheduleAnalysis(
    valid: suggestions.isEmpty,
    violations: const [],
    suggestions: suggestions,
  ),
  isAnalyzing: false,
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

testWidgets('schedule section emits analyzer and suggestion intents', (tester) async {
  var analyzed = false;
  ScheduleSuggestion? applied;
  await tester.pumpWidget(_host(LessonScheduleSection(
    model: _scheduleModel(suggestions: [_suggestion]),
    onAnalyze: () => analyzed = true,
    onApplySuggestion: (value) => applied = value,
    onDateChanged: (_) {}, onTimeChanged: (_) {}, onDurationChanged: (_) {},
  )));
  await tester.tap(find.byKey(const ValueKey('lesson-run-schedule-analyzer')));
  await tester.tap(find.textContaining('Применить'));
  expect(analyzed, isTrue);
  expect(applied, _suggestion);
});

test('presentation files do not import API, services, Riverpod or navigation providers', () {
  for (final path in _lessonEditorPresentationFiles) {
    final source = File(path).readAsStringSync();
    expect(source, isNot(contains('magic_api_client')));
    expect(source, isNot(contains('magic_crm_service')));
    expect(source, isNot(contains('flutter_riverpod')));
    expect(source, isNot(contains('schedule_navigation_provider')));
  }
});
```

- [ ] **Step 2: Verify RED**

```powershell
flutter test test/features/admin/lesson_editor_sections_test.dart --reporter compact
```

- [ ] **Step 3: Move the current view in semantic slices**

Define immutable view contracts and one callback surface instead of exposing
state:

```dart
class LessonEditorViewModel {
  const LessonEditorViewModel({
    required this.session,
    required this.draft,
    required this.references,
    required this.analysis,
    required this.isLoading,
    required this.isSaving,
    required this.isAnalyzing,
    required this.validationMessage,
  });
  final LessonEditorSession session;
  final LessonEditorDraft draft;
  final LessonEditorReferenceState references;
  final LessonScheduleAnalysis? analysis;
  final bool isLoading;
  final bool isSaving;
  final bool isAnalyzing;
  final String? validationMessage;
}

class LessonScheduleSectionModel {
  const LessonScheduleSectionModel({
    required this.draft,
    required this.analysis,
    required this.isAnalyzing,
    required this.minimumDate,
    required this.maximumDate,
  });
  final LessonEditorDraft draft;
  final LessonScheduleAnalysis? analysis;
  final bool isAnalyzing;
  final DateTime minimumDate;
  final DateTime maximumDate;
}

abstract interface class LessonEditorActions {
  void selectClient(LessonClientRef? value);
  void selectBranch(String? value);
  void selectRoom(String? value);
  void selectTeacher(String? value);
  void selectDate(DateTime value);
  void selectTime(TimeOfDay value);
  void selectDuration(int value);
  void selectSettlement(String? value);
  void selectCompensationRule(String? value);
  void selectFunding(String value);
  Future<void> analyzeSchedule();
  Future<void> applySuggestion(ScheduleSuggestion value);
  Future<void> save();
  void cancel();
  void openConstraint(LessonConstraintViolation value);
}

class LessonScheduleSection extends StatelessWidget {
  const LessonScheduleSection({
    required this.model,
    required this.onAnalyze,
    required this.onApplySuggestion,
    required this.onDateChanged,
    required this.onTimeChanged,
    required this.onDurationChanged,
    super.key,
  });
  final LessonScheduleSectionModel model;
  final FutureOr<void> Function() onAnalyze;
  final FutureOr<void> Function(ScheduleSuggestion value) onApplySuggestion;
  final ValueChanged<DateTime> onDateChanged;
  final ValueChanged<TimeOfDay> onTimeChanged;
  final ValueChanged<int> onDurationChanged;
}
```

Import `dart:async` in `lesson_schedule_section.dart` for `FutureOr`; the test
uses the same public constructor and no private production state.

Relocate the live widget tree by exact responsibility and retain every key/copy
from its source range:

| Source range in `create_lesson_dialog_view.dart` | Destination |
|---|---|
| `117-191` adaptive shell/loading/client picker | `lesson_editor_view.dart` + `lesson_participant_section.dart` |
| `192-293` branch/room/teacher controls | `lesson_participant_section.dart` |
| `294-383` date/time/duration/analyzer | `lesson_schedule_section.dart` |
| `384-590` trial/completion/financial controls | `lesson_financial_section.dart` |
| `591-671` snapshot/validation/actions | `lesson_editor_feedback.dart` |
| `673-746` responsive/date/time helpers | the section that exclusively calls each helper |

Keep the date rule: rolling `-30` days for create, while an older existing
lesson date remains selectable on edit. `LessonEditorView` contains only the
adaptive page/dialog shell, scroll view, section ordering, and action row.

- [ ] **Step 4: Run GREEN and current visual contracts**

```powershell
dart format lib/features/admin/presentation/widgets/lesson_editor test/features/admin/lesson_editor_sections_test.dart
flutter test test/features/admin/lesson_editor_sections_test.dart test/features/admin/presentation/widgets/create_lesson_dialog_test.dart test/features/schedule/lesson_form_test.dart --reporter compact
flutter analyze lib/features/admin/presentation/widgets/lesson_editor
git diff --check
```

- [ ] **Step 5: Commit**

```powershell
git add -- lib/features/admin/presentation/widgets/lesson_editor test/features/admin/lesson_editor_sections_test.dart
git commit -m "refactor(lessons): split editor presentation"
```

### Task 10: Rewire the public dialog shell and delete the god implementation

**Files:**

- Modify: `lib/features/admin/presentation/widgets/create_lesson_dialog.dart`
- Delete: `lib/features/admin/presentation/widgets/create_lesson_dialog_view.dart`
- Modify: `test/features/admin/presentation/widgets/create_lesson_dialog_test.dart`
- Modify: `test/features/admin/create_lesson_student_search_test.dart`
- Modify: `test/features/schedule/lesson_form_test.dart`
- Create: `test/features/admin/lesson_creation_architecture_test.dart`

**Interfaces:**

- Consumes: all owners created in Tasks 1-9.
- Produces: stable public `CreateLessonDialog`; a bounded composition state implementing `LessonEditorActions`; no `part`, private cross-file state, workflow duplication, or direct API access.

- [ ] **Step 1: Add the failing architecture acceptance test**

```dart
import 'dart:io';

test('lesson creation has no part cycle or god implementation', () {
  final shell = File('lib/features/admin/presentation/widgets/create_lesson_dialog.dart').readAsStringSync();
  expect(shell, isNot(contains("part 'create_lesson_dialog_view.dart'")));
  expect(shell, isNot(contains('magicApiClientProvider')));
  expect(shell, isNot(contains('Future<void> _loadData')));
  expect(shell, isNot(contains('String? _saveValidationMessage')));
  expect(shell.split('\n').length, lessThan(320));
  expect(File('lib/features/admin/presentation/widgets/create_lesson_dialog_view.dart').existsSync(), isFalse);
});
```

- [ ] **Step 2: Verify RED**

```powershell
flutter test test/features/admin/lesson_creation_architecture_test.dart --reporter compact
```

- [ ] **Step 3: Compose the typed owners and preserve UI-only lifecycle**

The final state owns only:

```dart
class _CreateLessonDialogState extends ConsumerState<CreateLessonDialog>
    implements LessonEditorActions {
  late LessonEditorSession _session;
  late LessonEditorDraft _draft;
  LessonEditorReferenceState _references = const LessonEditorReferenceState.empty();
  late LessonEditorDataController _data;
  late LessonEditorScheduleController _schedule;
  late LessonEditorSaveFlow _saveFlow;
  final _scrollController = ScrollController(keepScrollOffset: false);
  final _compensationController = TextEditingController();
  final _reasonController = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _analyzing = false;
  Object? _loadError;
  LessonEditorValidation _validation = const LessonEditorValidation.valid();
  LessonScheduleAnalysis? _analysis;
}
```

`initState` maps constructor input, creates collaborators from `ref.read(magicCrmServiceProvider)`, and starts one `_load`. Action methods update typed draft or invoke one collaborator. `save` maps typed outcomes to violation surface, `showLessonDecisionFlow`, Russian SnackBar, and `Navigator.pop(context, true)`. Constraint navigation remains only here through `scheduleNavigationProvider`.

Delete every old helper after its behavior has a semantic owner. Do not leave delegates with the old names. Delete `create_lesson_dialog_view.dart` and remove all `part` declarations.

- [ ] **Step 4: Run the full focused cluster and structural measures**

```powershell
dart format lib/features/admin/presentation/widgets/create_lesson_dialog.dart test/features/admin/presentation/widgets/create_lesson_dialog_test.dart test/features/admin/create_lesson_student_search_test.dart test/features/schedule/lesson_form_test.dart test/features/admin/lesson_creation_architecture_test.dart
flutter test test/features/admin/lesson_creation_architecture_test.dart test/features/admin/presentation/widgets/create_lesson_dialog_test.dart test/features/admin/create_lesson_student_search_test.dart test/features/admin/presentation/widgets/lesson_form_rules_test.dart test/features/schedule/lesson_decision_flow_test.dart test/features/schedule/lesson_form_test.dart --reporter compact
flutter analyze lib/features/admin/presentation/widgets/create_lesson_dialog.dart lib/features/admin/presentation/widgets/lesson_editor lib/features/admin/presentation/widgets/lesson_decision lib/features/admin/presentation/widgets/lesson_decision_flow.dart
rg -n "part 'create_lesson_dialog_view|part of 'create_lesson_dialog|magicApiClientProvider|_CreateLessonDialogState.*god" lib/features/admin/presentation/widgets
git diff --check
```

Expected: focused baseline plus all new tests pass; analyzer is clean; `rg` finds no part cycle or direct API provider.

- [ ] **Step 5: Commit**

```powershell
git add -- lib/features/admin/presentation/widgets/create_lesson_dialog.dart lib/features/admin/presentation/widgets/create_lesson_dialog_view.dart test/features/admin/presentation/widgets/create_lesson_dialog_test.dart test/features/admin/create_lesson_student_search_test.dart test/features/schedule/lesson_form_test.dart test/features/admin/lesson_creation_architecture_test.dart
git commit -m "refactor(lessons): remove lesson editor god state"
```

### Task 11: Pair owners, run full verification, and re-rank the global queue

**Files:**

- Modify: direct tests from Tasks 1-10 when RepoWise reports a truthful missing owner test.
- Modify: `docs/superpowers/specs/2026-08-25-production-code-health-recovery-design.md`
- Modify: `docs/superpowers/plans/2026-08-25-lesson-creation-cluster-semantic-split.md`

**Interfaces:**

- Consumes: final Package 8 tree and all recovery-program gates.
- Produces: exact indexed evidence, updated all-god-owner count, and the next highest-impact production package.

- [x] **Step 1: Run every focused test once more**

```powershell
flutter test test/core/services/magic_crm_service_test.dart test/features/admin/lesson_editor_initial_mapper_test.dart test/features/admin/lesson_editor_data_controller_test.dart test/features/admin/lesson_editor_decision_policy_test.dart test/features/admin/lesson_editor_schedule_controller_test.dart test/features/admin/lesson_editor_save_flow_test.dart test/features/admin/lesson_editor_sections_test.dart test/features/admin/lesson_creation_architecture_test.dart test/features/admin/presentation/widgets/create_lesson_dialog_test.dart test/features/admin/create_lesson_student_search_test.dart test/features/admin/presentation/widgets/lesson_form_rules_test.dart test/features/schedule/lesson_decision_models_test.dart test/features/schedule/lesson_decision_flow_test.dart test/features/schedule/lesson_form_test.dart --reporter compact
```

- [x] **Step 2: Run full Flutter verification**

```powershell
flutter test --reporter compact
flutter analyze
git diff --check
```

Expected: at least the pre-package `1,016/1,016` tests plus all new tests pass; analyzer has zero issues.

- [x] **Step 3: Refresh and inspect RepoWise**

```powershell
repowise update --index-only
repowise health --file lib/features/admin/presentation/widgets/create_lesson_dialog.dart --format json
repowise health --file lib/features/admin/presentation/widgets/lesson_decision_flow.dart --format json
repowise health --format json
```

Use MCP `get_health` on every new production owner. Build the exact
`changed_files` list for MCP `get_risk` from
`git diff --name-only d1d24ea3..HEAD -- lib`, and pass the same list as
`targets`. Require no god/brain finding, no unresolved target, no new cycle,
no breaking API, no missing live consumer, and combined weighted deficit
`<= 2,230` (`85%` reduction from `14,868`).

- [x] **Step 4: Close Sentrux session**

Run Sentrux rescan, health, rules, and session end. Require quality `>= 5748`, depth `<= 13`, acyclicity `10000`, and rules `2/2`.

- [x] **Step 5: Record evidence and commit**

Update the recovery spec with before/after NLOC, max CCN, health, deficit, focused/full test totals, RepoWise risk, Sentrux metrics, and the new production god-class count. Mark this plan's verified outcome only with the exact final commit.

```powershell
git add -- docs/superpowers/specs/2026-08-25-production-code-health-recovery-design.md docs/superpowers/plans/2026-08-25-lesson-creation-cluster-semantic-split.md
git commit -m "docs(lessons): record creation cluster evidence"
git status --short --branch
```

Expected: clean worktree. Re-rank the remaining 25-or-fewer production god owners by recoverable weighted deficit and continue the global program; do not mark the global goal complete.

## Verified Package 8 outcome

Package 8 production is fixed at
`861d89d77b0f25d3224e8a4d6f8770ae99aa1191`; Task 11 changes evidence only.
The public constructor, route, Russian copy, service boundary, decision
commands, and all characterized create/edit outcomes remain covered.

- Focused verification included the listed cluster plus
  `lesson_editor_models_test.dart`, both picker/select tests, and the Task 9
  props/state ownership guard: `205/205`, exit `0`, `39.108s`.
- Full verification passed `1,105/1,105`, exit `0`, `159.389s`; analyzer found
  zero issues in `11.710s`, and diff-check exited zero in `0.026s`. A separate
  truthful full-coverage run passed `1,105/1,105` in `221.442s` and RepoWise
  ingested `336` exact files at `71.57%` lines on the same SHA.
- The two old owners moved from `2,124` NLOC, max CCN `35/28`, and deficit
  `14,868` to `298/37`-NLOC public shells, health `3.99/6.50`, max CCN `12/1`,
  coverage `90.73%/100%`, and shell deficit `1,251`. No god/brain or part cycle
  remains in the package's semantic owners or public shells.
- The 16 new semantic owners total `6,623` weighted-deficit points. With the
  shells, the exact portfolio is `7,874`, so the original `<=2,230`/85% gate is
  not met. The owner accepts this instead of metric gaming: all sub-7 semantic
  owners have `85.53-100%` truthful coverage, max CCN `<=10`, and deductions
  dominated by the package's own fix history and `9-12` co-change peers. The
  shell's CCN-12 `save` is the separately recorded UI-lifecycle exception.
- RepoWise coverage is exact at production SHA `861d89d7`; the final index is
  exact at docs SHA `8ad0594c`. Its indexed dashboard is `1,596` files, health
  `6.70`, and hotspot health `5.90`; the distinct live CLI scan is `1,695`
  files, health `6.82`, and hotspot health `4.69` while using the
  production-SHA LCOV. The production recount is `25` god findings in `25`
  files. PR blast score is `6.27` with empty breaking-change, conformance,
  cycle, and broken-consumer arrays. Dart-filtered change risk is
  Elevated/high, percentile `100`, score `9.9`, probability `99.1%`. The three
  predicted labels name schedule section, feedback, and decision form; the
  first two have their direct sections test and the form has `90.50%` ingested
  flow-suite coverage, so none is a truthful missing owner test.

Sentrux is accepted at `5736` instead of `5748`: the reviewed structural fixes
improved `5723 -> 5736`, and the remaining 12 points require unrelated global
cleanup. Fresh results are depth `13`, acyclicity `10000`/raw `0`, equality
`6310`/raw `0.3690247236570714`, modularity `5406`/raw
`0.31095361747322303`, redundancy `4777`/raw `0.5222544113774032`, and rules
`2/2`; session end is stable. Package 8 is accepted with these explicit metric
exceptions, while the global recovery goal remains open.

The next highest-impact production package is
`server/src/crm/commerce/subscription-lifecycle.service.ts`: health `1.04`,
`1,350` NLOC, max CCN `14`, recoverable weighted deficit `9,396`. It leads the
remaining 25-owner queue ahead of `crm.service.ts` (`7,381`) and
`lesson-transition.service.ts` (`7,076`).
