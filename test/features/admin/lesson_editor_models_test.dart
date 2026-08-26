import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_decision/lesson_decision_models.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_editor/lesson_editor_models.dart';

void main() {
  test('manually constructed snapshots default to a captured baseline', () {
    const snapshot = LessonEditorSnapshot(
      lessonId: 'lesson-1',
      expectedVersion: 4,
      rawLesson: {},
      clientLocked: true,
      initialSchedulePayload: {},
      initialCompensationRuleKey: 'teacher-standard',
      initialCompensationValueMinor: null,
    );

    expect(snapshot.compensationBaselineCaptured, isTrue);
  });

  test('draft copyWith distinguishes omitted values from explicit null', () {
    const client = LessonClientRef(type: 'student', id: 's-1', label: 'Анна');
    final draft = LessonEditorDraft(
      localStart: DateTime(2026, 8, 26, 14, 30),
      durationMinutes: 45,
      isTrial: true,
      completionType: 'completed',
      clientChargeType: 'subscription',
      client: client,
      teacherId: 'teacher-1',
      branchId: 'branch-1',
      roomId: 'room-1',
      subscriptionId: 'subscription-1',
      settlementTypeKey: 'regular',
      compensationRuleKey: 'fixed',
      compensationValueMinor: '1200',
      plannedSettlementReason: 'Причина',
    );

    final preserved = draft.copyWith(durationMinutes: 60);
    expect(preserved.client, client);
    expect(
      preserved.client.hashCode,
      const LessonClientRef(type: 'student', id: 's-1', label: 'Анна').hashCode,
    );
    expect(preserved.teacherId, 'teacher-1');
    expect(preserved.branchId, 'branch-1');
    expect(preserved.roomId, 'room-1');
    expect(preserved.subscriptionId, 'subscription-1');
    expect(preserved.settlementTypeKey, 'regular');
    expect(preserved.compensationRuleKey, 'fixed');
    expect(preserved.compensationValueMinor, '1200');

    final cleared = draft.copyWith(
      client: null,
      teacherId: null,
      branchId: null,
      roomId: null,
      subscriptionId: null,
      settlementTypeKey: null,
      compensationRuleKey: null,
      compensationValueMinor: null,
    );
    expect(cleared.client, isNull);
    expect(cleared.teacherId, isNull);
    expect(cleared.branchId, isNull);
    expect(cleared.roomId, isNull);
    expect(cleared.subscriptionId, isNull);
    expect(cleared.settlementTypeKey, isNull);
    expect(cleared.compensationRuleKey, isNull);
    expect(cleared.compensationValueMinor, isNull);
    expect(
      draft.withDate(DateTime(2026, 9, 2)).localStart,
      DateTime(2026, 9, 2, 14, 30),
    );
    expect(draft.withTime(9, 15).localStart, DateTime(2026, 8, 26, 9, 15));
  });

  test('reference state deeply freezes rows and catalog defaults', () {
    final nestedList = <String>['first'];
    final nestedSet = <String>{'branch-1'};
    final raw = <String, dynamic>{
      'nested': <String, dynamic>{'list': nestedList, 'set': nestedSet},
    };
    final contexts = <String>['create'];
    final settlementTypes = <LessonDecisionCatalogItem>[
      LessonDecisionCatalogItem(
        key: 'regular',
        label: 'Обычное',
        order: 1,
        allowedContexts: contexts,
      ),
    ];
    final teachers = <LessonEditorReferenceItem>[
      LessonEditorReferenceItem(
        id: 'teacher-1',
        label: 'Ирина',
        raw: raw,
        assignedBranchIds: nestedSet,
      ),
    ];
    final state = LessonEditorReferenceState(
      teachers: teachers,
      clients: const [],
      branches: const [],
      rooms: const [],
      subscriptions: const [],
      catalog: LessonDecisionCatalog(
        settlementTypes: settlementTypes,
        compensationRules: const [],
        defaultDurationMinutes: 75,
      ),
    );

    nestedList.add('late');
    nestedSet.add('branch-2');
    contexts.add('edit');
    teachers.clear();
    settlementTypes.clear();

    final frozenNested = state.teachers.single.raw['nested']! as Map;
    expect(frozenNested['list'], ['first']);
    expect(frozenNested['set'], {'branch-1'});
    expect(state.teachers.single.assignedBranchIds, {'branch-1'});
    expect(state.catalog!.settlementTypes.single.allowedContexts, ['create']);
    expect(state.catalog!.defaultDurationMinutes, 75);
    expect(() => frozenNested['late'] = true, throwsUnsupportedError);
    expect(
      () => state.teachers.add(state.teachers.single),
      throwsUnsupportedError,
    );
    expect(
      () => state.catalog!.settlementTypes.single.allowedContexts.add('late'),
      throwsUnsupportedError,
    );
  });

  test('initial input copies every value from its typed source', () {
    final lesson = <String, dynamic>{'id': 'lesson-1'};
    final input = LessonEditorInitialInput.fromSource(_InitialSource(lesson));

    expect(input.initialDate, DateTime(2026, 8, 28, 11));
    expect(input.initialRoomId, 'room-1');
    expect(input.initialBranchId, 'branch-1');
    expect(input.initialDurationMinutes, 75);
    expect(input.lesson, same(lesson));
    expect(input.initialIsTrial, isTrue);
    expect(input.leadId, 'lead-1');
    expect(input.leadName, 'Лид');
    expect(input.clientType, 'student');
    expect(input.clientId, 'student-1');
    expect(input.clientName, 'Анна');
  });
}

class _InitialSource implements LessonEditorInitialSource {
  const _InitialSource(this.lesson);

  @override
  final Map<String, dynamic> lesson;

  @override
  DateTime get initialDate => DateTime(2026, 8, 28, 11);

  @override
  String get initialRoomId => 'room-1';

  @override
  String get initialBranchId => 'branch-1';

  @override
  int get initialDurationMinutes => 75;

  @override
  bool get initialIsTrial => true;

  @override
  String get leadId => 'lead-1';

  @override
  String get leadName => 'Лид';

  @override
  String get clientType => 'student';

  @override
  String get clientId => 'student-1';

  @override
  String get clientName => 'Анна';
}
