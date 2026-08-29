import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_decision/lesson_decision_models.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_editor/lesson_editor_data_controller.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_editor/lesson_editor_decision_policy.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_editor/lesson_editor_models.dart';

void main() {
  const emptyCatalog = LessonDecisionCatalog(
    settlementTypes: [],
    compensationRules: [],
  );

  test(
    'remote client search forwards query and returns typed metadata',
    () async {
      final api = _ClientSearchApi();
      final controller = LessonEditorDataController.fromCrm(
        MagicCrmService(api),
      );

      final clients = await controller.searchClients('  Зинаида  ');

      expect(api.queryParameters, {'q': 'Зинаида', 'limit': 50});
      expect(clients, const [
        LessonClientRef(
          type: 'student',
          id: 'student-z',
          label: 'Зинаида Заречная',
          branchId: 'branch-z',
        ),
      ]);
    },
  );

  group('revision ownership', () {
    test('discards the slower room response after branch changes', () async {
      final branchA = Completer<List<Map<String, dynamic>>>();
      final branchB = Completer<List<Map<String, dynamic>>>();
      final controller = LessonEditorDataController.forTesting(
        listRooms: (branchId) =>
            branchId == 'branch-a' ? branchA.future : branchB.future,
        loadCatalog: (_) async => emptyCatalog,
        listSubscriptions: (_) async => const [],
      );

      final slow = controller.loadBranch('branch-a');
      final fast = controller.loadBranch('branch-b');
      branchB.complete([
        {'id': 'room-b', 'name': 'B', 'branch_id': 'branch-b'},
      ]);

      expect((await fast)?.branchId, 'branch-b');
      branchA.complete([
        {'id': 'room-a', 'name': 'A', 'branch_id': 'branch-a'},
      ]);
      expect(await slow, isNull);
    });

    test('discards the slower catalog response after branch changes', () async {
      final catalogA = Completer<LessonDecisionCatalog>();
      final catalogB = Completer<LessonDecisionCatalog>();
      final controller = LessonEditorDataController.forTesting(
        listRooms: (branchId) async => [
          {'id': 'room-$branchId', 'branch_id': branchId},
        ],
        loadCatalog: (branchId) =>
            branchId == 'branch-a' ? catalogA.future : catalogB.future,
        listSubscriptions: (_) async => const [],
      );

      final slow = controller.loadBranch('branch-a');
      final fast = controller.loadBranch('branch-b');
      catalogB.complete(emptyCatalog);

      expect((await fast)?.branchId, 'branch-b');
      catalogA.complete(emptyCatalog);
      expect(await slow, isNull);
    });

    test(
      'discards subscriptions for the previously selected student',
      () async {
        final first = Completer<List<Map<String, dynamic>>>();
        final controller = LessonEditorDataController.forTesting(
          listRooms: (_) async => const [],
          loadCatalog: (_) async => emptyCatalog,
          listSubscriptions: (studentId) =>
              studentId == 'student-a' ? first.future : Future.value(const []),
        );

        final stale = controller.loadSubscriptions(
          const LessonClientRef(type: 'student', id: 'student-a', label: 'A'),
        );
        await controller.loadSubscriptions(
          const LessonClientRef(type: 'student', id: 'student-b', label: 'B'),
        );
        first.complete([
          {'id': 'subscription-a', 'status': 'active'},
        ]);

        expect(await stale, isNull);
      },
    );

    test('invalidates an outstanding initial reference load', () async {
      final teachers = Completer<List<Map<String, dynamic>>>();
      final controller = LessonEditorDataController.forTesting(
        listRooms: (_) async => const [],
        loadCatalog: (_) async => emptyCatalog,
        listSubscriptions: (_) async => const [],
        listTeachers: () => teachers.future,
        listBranches: () async => const [],
        searchClients: (_) async => const [],
      );

      final pending = controller.loadInitial(_session());
      controller.invalidateClientSelection();
      teachers.complete(const []);

      expect(await pending, isNull);
    });

    test(
      'stale initial resolver cannot steal ownership from a newer selection',
      () async {
        final resolvedInitial = Completer<Map<String, dynamic>?>();
        final selectedSubscriptions = Completer<List<Map<String, dynamic>>>();
        final controller = LessonEditorDataController.forTesting(
          listRooms: (_) async => const [],
          loadCatalog: (_) async => emptyCatalog,
          listSubscriptions: (_) => selectedSubscriptions.future,
          resolveClient: ({required type, required id}) =>
              resolvedInitial.future,
        );

        final staleInitial = controller.loadInitial(
          _session(
            client: const LessonClientRef(
              type: 'student',
              id: 'student-a',
              label: 'A',
            ),
          ),
        );
        final newerSelection = controller.selectClient(
          const LessonClientRef(type: 'student', id: 'student-b', label: 'B'),
          draft: _draft(),
          references: _references(),
        );

        resolvedInitial.complete({
          'ref': {'type': 'student', 'id': 'student-a'},
          'label': 'Resolved A',
        });
        expect(await staleInitial, isNull);

        selectedSubscriptions.complete(const []);
        expect((await newerSelection)?.draft?.client?.id, 'student-b');
      },
    );

    test(
      'discards a client cascade invalidated while its branch loads',
      () async {
        final rooms = Completer<List<Map<String, dynamic>>>();
        final catalog = Completer<LessonDecisionCatalog>();
        final controller = LessonEditorDataController.forTesting(
          listRooms: (_) => rooms.future,
          loadCatalog: (_) => catalog.future,
          listSubscriptions: (_) async => const [],
        );
        final references = _references(
          branches: const [
            LessonEditorReferenceItem(
              id: 'branch-a',
              label: 'A',
              raw: {'id': 'branch-a'},
            ),
            LessonEditorReferenceItem(
              id: 'branch-b',
              label: 'B',
              raw: {'id': 'branch-b'},
            ),
          ],
        );

        final pending = controller.selectClient(
          const LessonClientRef(
            type: 'student',
            id: 'student-a',
            label: 'A',
            branchId: 'branch-b',
          ),
          draft: _draft(branchId: 'branch-a'),
          references: references,
        );
        controller.invalidateClientSelection();
        rooms.complete(const []);
        catalog.complete(emptyCatalog);

        expect(await pending, isNull);
      },
    );

    test('discards a client cascade when the active branch changes', () async {
      final subscriptions = Completer<List<Map<String, dynamic>>>();
      final controller = LessonEditorDataController.forTesting(
        listRooms: (_) async => const [],
        loadCatalog: (_) async => emptyCatalog,
        listSubscriptions: (_) => subscriptions.future,
      );
      final references = _references(
        branches: const [
          LessonEditorReferenceItem(
            id: 'branch-a',
            label: 'A',
            raw: {'id': 'branch-a'},
          ),
          LessonEditorReferenceItem(
            id: 'branch-b',
            label: 'B',
            raw: {'id': 'branch-b'},
          ),
        ],
      );

      final pending = controller.selectClient(
        const LessonClientRef(
          type: 'student',
          id: 'student-a',
          label: 'A',
          branchId: 'branch-a',
        ),
        draft: _draft(branchId: 'branch-a'),
        references: references,
      );
      await controller.loadBranch('branch-b');
      subscriptions.complete(const []);

      expect(await pending, isNull);
    });
  });

  group('initial defaults', () {
    test(
      'uses resolved client branch and prepends an omitted selected client',
      () async {
        final controller = LessonEditorDataController.forTesting(
          listRooms: (branchId) async => [
            {
              'id': 'room-b',
              'name': 'Room B',
              'branch_id': branchId,
              'lifecycle_state': 'active',
            },
          ],
          loadCatalog: (_) async => emptyCatalog,
          listSubscriptions: (_) async => const [
            {'id': 'subscription-old', 'status': 'paused'},
            {'id': 'subscription-b', 'status': 'active'},
          ],
          listTeachers: () async => const [
            {
              'id': 'teacher-a',
              'first_name': 'Anna',
              'status': 'active',
              'assigned_branches': [
                {'id': 'branch-a'},
              ],
            },
          ],
          listBranches: () async => const [
            {'id': 'branch-a', 'name': 'A'},
            {'id': 'branch-b', 'name': 'B'},
          ],
          searchClients: (_) async => const [
            {
              'ref': {'type': 'lead', 'id': 'lead-a'},
              'label': 'Lead A',
              'branchId': 'branch-a',
            },
          ],
          resolveClient: ({required type, required id}) async => {
            'ref': {'type': type, 'id': id},
            'label': 'Resolved Student',
            'branchId': 'branch-b',
            'lifecycleState': 'active',
          },
        );

        final patch = await controller.loadInitial(
          _session(
            client: const LessonClientRef(
              type: 'student',
              id: 'student-a',
              label: 'Seed Student',
            ),
            branchId: 'branch-a',
            teacherId: 'teacher-a',
            roomId: 'room-a',
            subscriptionId: 'subscription-old',
          ),
        );

        expect(patch?.branchId, 'branch-b');
        expect(patch?.draft?.client?.label, 'Resolved Student');
        expect(patch?.draft?.client?.branchId, 'branch-b');
        expect(patch?.draft?.branchId, 'branch-b');
        expect(patch?.draft?.teacherId, isNull);
        expect(patch?.draft?.roomId, isNull);
        expect(patch?.draft?.subscriptionId, isNull);
        expect(patch?.references.clients.map((item) => item.id), [
          'student:student-a',
          'lead:lead-a',
        ]);
        expect(patch?.references.subscriptions.map((item) => item.id), [
          'subscription-b',
        ]);
      },
    );

    test(
      'falls back from a missing client branch to the seeded branch',
      () async {
        final controller = _initialController(
          branches: const [
            {'id': 'branch-a', 'name': 'A'},
            {'id': 'branch-b', 'name': 'B'},
          ],
        );

        final patch = await controller.loadInitial(
          _session(
            client: const LessonClientRef(
              type: 'student',
              id: 'student-a',
              label: 'A',
              branchId: 'missing',
            ),
            branchId: 'branch-b',
          ),
        );

        expect(patch?.branchId, 'branch-b');
        expect(patch?.draft?.branchId, 'branch-b');
      },
    );

    test('uses the first branch when seeded choices are invalid', () async {
      final controller = _initialController(
        branches: const [
          {'id': 'branch-a', 'name': 'A'},
          {'id': 'branch-b', 'name': 'B'},
        ],
      );

      final patch = await controller.loadInitial(_session(branchId: 'missing'));

      expect(patch?.branchId, 'branch-a');
      expect(patch?.draft?.branchId, 'branch-a');
    });
  });

  group('branch and client cascades', () {
    test('clears a selected room outside the returned active branch', () async {
      final controller = LessonEditorDataController.forTesting(
        listRooms: (_) async => const [
          {
            'id': 'room-archived',
            'name': 'Archived',
            'branch_id': 'branch-a',
            'lifecycle_state': 'archived',
          },
          {
            'id': 'room-other',
            'name': 'Other',
            'branch_id': 'branch-b',
            'lifecycle_state': 'active',
          },
          {
            'id': 'room-active',
            'name': 'Active',
            'branch_id': 'branch-a',
            'lifecycle_state': 'active',
          },
        ],
        loadCatalog: (_) async => emptyCatalog,
        listSubscriptions: (_) async => const [],
      );

      final patch = await controller.loadBranch(
        'branch-a',
        draft: _draft(branchId: 'branch-b', roomId: 'room-archived'),
      );

      expect(patch?.draft?.branchId, 'branch-a');
      expect(patch?.draft?.roomId, isNull);
      expect(patch?.references.rooms.map((item) => item.id), ['room-active']);
    });

    test('client branch change resets scoped and catalog selections', () async {
      final sourceAllowedContexts = <String>['settle'];
      final sourceSettlementTypes = <LessonDecisionCatalogItem>[
        LessonDecisionCatalogItem(
          key: 'settlement-b',
          label: 'B',
          order: 1,
          allowedContexts: sourceAllowedContexts,
        ),
      ];
      final newCatalog = LessonDecisionCatalog(
        settlementTypes: sourceSettlementTypes,
        compensationRules: const [
          LessonDecisionCatalogItem(
            key: 'rule-b',
            label: 'Rule B',
            order: 1,
            mode: 'fixed',
            value: '250000',
          ),
        ],
        defaultDurationMinutes: 75,
      );
      final controller = LessonEditorDataController.forTesting(
        listRooms: (_) async => const [
          {
            'id': 'room-b',
            'name': 'B',
            'branch_id': 'branch-b',
            'lifecycle_state': 'active',
          },
        ],
        loadCatalog: (_) async => newCatalog,
        listSubscriptions: (_) async => const [
          {'id': 'subscription-b', 'status': 'active'},
        ],
      );
      final references = _references(
        branches: const [
          LessonEditorReferenceItem(
            id: 'branch-a',
            label: 'A',
            raw: {'id': 'branch-a'},
          ),
          LessonEditorReferenceItem(
            id: 'branch-b',
            label: 'B',
            raw: {'id': 'branch-b'},
          ),
        ],
        catalog: emptyCatalog,
      );

      final patch = await controller.selectClient(
        const LessonClientRef(
          type: 'student',
          id: 'student-b',
          label: 'Student B',
          branchId: 'branch-b',
        ),
        draft: _draft(
          branchId: 'branch-a',
          teacherId: 'teacher-a',
          roomId: 'room-a',
          subscriptionId: 'subscription-a',
          settlementTypeKey: 'settlement-a',
          compensationRuleKey: 'rule-a',
          compensationValueMinor: '999000',
          plannedSettlementReason: 'Старое индивидуальное значение',
        ),
        references: references,
      );

      expect(patch?.branchId, 'branch-b');
      expect(patch?.draft?.client?.id, 'student-b');
      expect(patch?.draft?.branchId, 'branch-b');
      expect(patch?.draft?.teacherId, isNull);
      expect(patch?.draft?.roomId, isNull);
      expect(patch?.draft?.settlementTypeKey, isNull);
      expect(patch?.draft?.compensationRuleKey, isNull);
      expect(patch?.draft?.compensationValueMinor, isNull);
      expect(patch?.draft?.plannedSettlementReason, isEmpty);
      expect(patch?.draft?.subscriptionId, isNull);
      expect(patch?.appliesCatalogDefaults, isTrue);
      sourceAllowedContexts.add('cancel');
      sourceSettlementTypes.add(
        const LessonDecisionCatalogItem(
          key: 'settlement-mutated',
          label: 'Mutated',
          order: 2,
        ),
      );
      expect(
        patch?.references.catalog?.settlementTypes.map((item) => item.key),
        ['settlement-b'],
      );
      expect(
        patch?.references.catalog?.settlementTypes.single.allowedContexts,
        ['settle'],
      );
      expect(
        () => patch?.references.catalog?.settlementTypes.add(
          const LessonDecisionCatalogItem(
            key: 'forbidden',
            label: 'Forbidden',
            order: 3,
          ),
        ),
        throwsUnsupportedError,
      );
      expect(
        () => patch?.references.catalog?.settlementTypes.single.allowedContexts
            .add('forbidden'),
        throwsUnsupportedError,
      );
      expect(patch?.references.subscriptions.map((item) => item.id), [
        'subscription-b',
      ]);

      const policy = LessonEditorDecisionPolicy();
      final projected = policy.applyReferenceDefaults(
        _session(),
        patch!.draft!,
        patch.references,
        patch.appliesCatalogDefaults,
      );
      final ready = projected.draft.copyWith(
        teacherId: 'teacher-b',
        roomId: 'room-b',
      );
      expect(projected.draft.durationMinutes, 75);
      expect(projected.draft.compensationRuleKey, 'rule-b');
      expect(projected.draft.compensationValueMinor, '250000');
      expect(projected.draft.plannedSettlementReason, isEmpty);
      expect(
        policy
            .createPayload(
              session: _session(),
              draft: ready,
              references: patch.references,
              canManageTeacherCompensation: true,
            )
            .containsKey('plannedSettlementReason'),
        isFalse,
      );
    });

    test(
      'catalog defaults are scoped away from same-branch client and subscription patches',
      () async {
        final controller = LessonEditorDataController.forTesting(
          listRooms: (_) async => const [],
          loadCatalog: (_) async => const LessonDecisionCatalog(
            settlementTypes: [],
            compensationRules: [],
            defaultDurationMinutes: 75,
          ),
          listSubscriptions: (_) async => const [
            {'id': 'subscription-a', 'status': 'active'},
          ],
        );
        final references = _references(
          branches: const [
            LessonEditorReferenceItem(
              id: 'branch-a',
              label: 'A',
              raw: {'id': 'branch-a'},
            ),
          ],
          catalog: emptyCatalog,
        );
        final draft = _draft(branchId: 'branch-a');

        final branch = await controller.loadBranch(
          'branch-a',
          draft: draft,
          references: references,
        );
        final client = await controller.selectClient(
          const LessonClientRef(
            type: 'student',
            id: 'student-a',
            label: 'A',
            branchId: 'branch-a',
          ),
          draft: draft,
          references: branch!.references,
        );
        final subscriptions = await controller.loadSubscriptions(
          client!.draft!.client,
          draft: client.draft,
          references: client.references,
        );

        expect(branch.appliesCatalogDefaults, isTrue);
        expect(client.appliesCatalogDefaults, isFalse);
        expect(subscriptions?.appliesCatalogDefaults, isFalse);
      },
    );

    test(
      'invalid client branch preserves the existing branch selections',
      () async {
        var branchLoads = 0;
        final controller = LessonEditorDataController.forTesting(
          listRooms: (_) async {
            branchLoads += 1;
            return const [];
          },
          loadCatalog: (_) async => emptyCatalog,
          listSubscriptions: (_) async => const [],
        );
        final references = _references(
          branches: const [
            LessonEditorReferenceItem(
              id: 'branch-a',
              label: 'A',
              raw: {'id': 'branch-a'},
            ),
          ],
          rooms: const [
            LessonEditorReferenceItem(
              id: 'room-a',
              label: 'A',
              branchId: 'branch-a',
              status: 'active',
              raw: {'id': 'room-a'},
            ),
          ],
          catalog: emptyCatalog,
        );

        final patch = await controller.selectClient(
          const LessonClientRef(
            type: 'lead',
            id: 'lead-a',
            label: 'Lead A',
            branchId: 'missing',
          ),
          draft: _draft(
            branchId: 'branch-a',
            teacherId: 'teacher-a',
            roomId: 'room-a',
            settlementTypeKey: 'settlement-a',
            compensationRuleKey: 'rule-a',
          ),
          references: references,
        );

        expect(branchLoads, 0);
        expect(patch?.draft?.branchId, 'branch-a');
        expect(patch?.draft?.teacherId, 'teacher-a');
        expect(patch?.draft?.roomId, 'room-a');
        expect(patch?.draft?.settlementTypeKey, 'settlement-a');
        expect(patch?.draft?.compensationRuleKey, 'rule-a');
        expect(patch?.references.rooms.single.id, 'room-a');
        expect(patch?.references.catalog?.settlementTypes, isEmpty);
        expect(patch?.references.catalog?.compensationRules, isEmpty);
      },
    );
  });

  group('immutable patches', () {
    test('reference state snapshots and freezes constructor lists', () {
      final sourceTags = <String>['seed'];
      final sourceAssignments = <String>{'branch-a'};
      final sourceRooms = <LessonEditorReferenceItem>[
        LessonEditorReferenceItem(
          id: 'room-a',
          label: 'A',
          raw: {
            'id': 'room-a',
            'metadata': <String, dynamic>{'tags': sourceTags},
          },
          assignedBranchIds: sourceAssignments,
        ),
      ];
      final sourceContexts = <String>['settle'];
      final sourceCatalogItems = <LessonDecisionCatalogItem>[
        LessonDecisionCatalogItem(
          key: 'settlement-a',
          label: 'A',
          order: 1,
          allowedContexts: sourceContexts,
        ),
      ];

      final references = _references(
        rooms: sourceRooms,
        catalog: LessonDecisionCatalog(
          settlementTypes: sourceCatalogItems,
          compensationRules: const [],
        ),
      );
      sourceRooms.clear();
      sourceTags.add('mutated');
      sourceAssignments.add('branch-b');
      sourceContexts.add('cancel');
      sourceCatalogItems.clear();

      expect(references.rooms.map((item) => item.id), ['room-a']);
      expect(references.rooms.single.raw['metadata'], {
        'tags': ['seed'],
      });
      expect(references.rooms.single.assignedBranchIds, {'branch-a'});
      expect(references.catalog?.settlementTypes.map((item) => item.key), [
        'settlement-a',
      ]);
      expect(references.catalog?.settlementTypes.single.allowedContexts, [
        'settle',
      ]);
      expect(references.rooms.clear, throwsUnsupportedError);
      expect(
        () => (references.rooms.single.raw['metadata']['tags'] as List).add(
          'forbidden',
        ),
        throwsUnsupportedError,
      );
      expect(
        () => references.rooms.single.assignedBranchIds.add('forbidden'),
        throwsUnsupportedError,
      );
    });

    test('returned patch detaches and freezes nested reference data', () async {
      final sourceTags = <String>['seed'];
      final sourceRaw = <String, dynamic>{
        'id': 'teacher-a',
        'metadata': <String, dynamic>{'tags': sourceTags},
      };
      final sourceAssignments = <String>{'branch-a'};
      final sourceTeachers = <LessonEditorReferenceItem>[
        LessonEditorReferenceItem(
          id: 'teacher-a',
          label: 'Teacher A',
          raw: sourceRaw,
          assignedBranchIds: sourceAssignments,
        ),
      ];
      final sourceClients = <LessonEditorReferenceItem>[
        const LessonEditorReferenceItem(
          id: 'student:student-a',
          label: 'Student A',
          raw: {'id': 'student-a'},
        ),
      ];
      final sourceBranches = <LessonEditorReferenceItem>[
        const LessonEditorReferenceItem(
          id: 'branch-a',
          label: 'Branch A',
          raw: {'id': 'branch-a'},
        ),
      ];
      final sourceRooms = <LessonEditorReferenceItem>[
        const LessonEditorReferenceItem(
          id: 'room-a',
          label: 'Room A',
          raw: {'id': 'room-a'},
        ),
      ];
      final sourceCatalogContexts = <String>['settle'];
      final sourceCatalogItems = <LessonDecisionCatalogItem>[
        LessonDecisionCatalogItem(
          key: 'settlement-a',
          label: 'Settlement A',
          order: 1,
          allowedContexts: sourceCatalogContexts,
        ),
      ];
      final sourceSubscriptionTags = <String>['active'];
      final sourceSubscriptionRows = <Map<String, dynamic>>[
        {
          'id': 'subscription-a',
          'status': 'active',
          'metadata': <String, dynamic>{'tags': sourceSubscriptionTags},
        },
      ];
      final references = _references(
        teachers: sourceTeachers,
        clients: sourceClients,
        branches: sourceBranches,
        rooms: sourceRooms,
        catalog: LessonDecisionCatalog(
          settlementTypes: sourceCatalogItems,
          compensationRules: const [],
        ),
      );
      final controller = LessonEditorDataController.forTesting(
        listRooms: (_) async => const [],
        loadCatalog: (_) async => emptyCatalog,
        listSubscriptions: (_) async => sourceSubscriptionRows,
      );

      final patch = await controller.loadSubscriptions(
        const LessonClientRef(
          type: 'student',
          id: 'student-a',
          label: 'Student A',
        ),
        references: references,
      );
      final returned = patch!.references;

      sourceTeachers.clear();
      sourceClients.clear();
      sourceBranches.clear();
      sourceRooms.clear();
      sourceTags.add('mutated');
      (sourceRaw['metadata'] as Map<String, dynamic>)['extra'] = true;
      sourceAssignments.add('branch-b');
      sourceCatalogContexts.add('cancel');
      sourceCatalogItems.clear();
      sourceSubscriptionTags.add('mutated');
      sourceSubscriptionRows.clear();

      expect(returned.teachers.map((item) => item.id), ['teacher-a']);
      expect(returned.clients.map((item) => item.id), ['student:student-a']);
      expect(returned.branches.map((item) => item.id), ['branch-a']);
      expect(returned.rooms.map((item) => item.id), ['room-a']);
      expect(returned.subscriptions.map((item) => item.id), ['subscription-a']);
      expect(returned.teachers, isNot(same(references.teachers)));
      expect(returned.teachers.single.assignedBranchIds, {'branch-a'});
      expect(returned.teachers.single.raw['metadata'], {
        'tags': ['seed'],
      });
      expect(returned.subscriptions.single.raw['metadata'], {
        'tags': ['active'],
      });
      expect(returned.catalog?.settlementTypes.single.allowedContexts, [
        'settle',
      ]);

      for (final collection in [
        returned.teachers,
        returned.clients,
        returned.branches,
        returned.rooms,
        returned.subscriptions,
      ]) {
        expect(collection.clear, throwsUnsupportedError);
      }
      expect(
        () =>
            (returned.teachers.single.raw['metadata'] as Map)['extra'] = false,
        throwsUnsupportedError,
      );
      expect(
        () => (returned.teachers.single.raw['metadata']['tags'] as List).add(
          'forbidden',
        ),
        throwsUnsupportedError,
      );
      expect(
        () => returned.teachers.single.assignedBranchIds.add('forbidden'),
        throwsUnsupportedError,
      );
    });
  });

  group('subscriptions', () {
    test('keeps only active rows and clears a missing selection', () async {
      final controller = LessonEditorDataController.forTesting(
        listRooms: (_) async => const [],
        loadCatalog: (_) async => emptyCatalog,
        listSubscriptions: (_) async => const [
          {'id': 'active-a', 'package_name': 'A', 'status': 'active'},
          {'id': 'paused-a', 'package_name': 'P', 'status': 'paused'},
        ],
      );

      final patch = await controller.loadSubscriptions(
        const LessonClientRef(type: 'student', id: 'student-a', label: 'A'),
        draft: _draft(subscriptionId: 'missing'),
      );

      expect(patch?.references.subscriptions.map((item) => item.id), [
        'active-a',
      ]);
      expect(patch?.draft?.subscriptionId, isNull);
    });

    test(
      'subscription failure clears stale funding without losing selection',
      () async {
        final controller = LessonEditorDataController.forTesting(
          listRooms: (_) async => const [],
          loadCatalog: (_) async => emptyCatalog,
          listSubscriptions: (_) async =>
              throw const FormatException('commerce unavailable'),
        );

        final patch = await controller.loadSubscriptions(
          const LessonClientRef(type: 'student', id: 'student-a', label: 'A'),
          draft: _draft(
            branchId: 'branch-a',
            subscriptionId: 'subscription-old',
          ),
          references: _references(
            subscriptions: const [
              LessonEditorReferenceItem(
                id: 'subscription-old',
                label: 'Old',
                status: 'active',
                raw: {'id': 'subscription-old'},
              ),
            ],
          ),
        );

        expect(patch?.branchId, 'branch-a');
        expect(patch?.references.subscriptions, isEmpty);
        expect(patch?.draft?.subscriptionId, isNull);
      },
    );

    test(
      'non-student selection clears subscriptions without a request',
      () async {
        var requests = 0;
        final controller = LessonEditorDataController.forTesting(
          listRooms: (_) async => const [],
          loadCatalog: (_) async => emptyCatalog,
          listSubscriptions: (_) async {
            requests += 1;
            return const [];
          },
        );

        final patch = await controller.loadSubscriptions(
          const LessonClientRef(type: 'lead', id: 'lead-a', label: 'A'),
          draft: _draft(branchId: 'branch-a', subscriptionId: 'subscription-a'),
          references: _references(
            subscriptions: const [
              LessonEditorReferenceItem(
                id: 'subscription-a',
                label: 'A',
                status: 'active',
                raw: {'id': 'subscription-a'},
              ),
            ],
          ),
        );

        expect(requests, 0);
        expect(patch?.branchId, 'branch-a');
        expect(patch?.references.subscriptions, isEmpty);
        expect(patch?.draft?.subscriptionId, isNull);
      },
    );
  });
}

class _ClientSearchApi extends MagicApiClient {
  _ClientSearchApi()
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  Map<String, dynamic>? queryParameters;

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    expect(path, '/crm/clients/search');
    this.queryParameters = Map<String, dynamic>.from(queryParameters ?? {});
    return <String, dynamic>{
          'items': [
            {
              'ref': {'type': 'student', 'id': 'student-z'},
              'label': 'Зинаида Заречная',
              'branchId': 'branch-z',
              'lifecycleState': 'active',
              'tombstone': false,
            },
          ],
        }
        as T;
  }
}

LessonEditorDataController _initialController({
  required List<Map<String, dynamic>> branches,
}) => LessonEditorDataController.forTesting(
  listRooms: (_) async => const [],
  loadCatalog: (_) async =>
      const LessonDecisionCatalog(settlementTypes: [], compensationRules: []),
  listSubscriptions: (_) async => const [],
  listBranches: () async => branches,
);

LessonEditorSession _session({
  LessonClientRef? client,
  String? branchId,
  String? teacherId,
  String? roomId,
  String? subscriptionId,
}) => LessonEditorSession(
  draft: _draft(
    client: client,
    branchId: branchId,
    teacherId: teacherId,
    roomId: roomId,
    subscriptionId: subscriptionId,
  ),
  snapshot: null,
  seededClient: client,
);

LessonEditorDraft _draft({
  LessonClientRef? client,
  String? branchId,
  String? teacherId,
  String? roomId,
  String? subscriptionId,
  String? settlementTypeKey,
  String? compensationRuleKey,
  String? compensationValueMinor,
  String plannedSettlementReason = '',
}) => LessonEditorDraft(
  localStart: DateTime(2026, 8, 25, 10),
  durationMinutes: 60,
  isTrial: false,
  completionType: 'standard.success',
  clientChargeType: 'none',
  client: client,
  teacherId: teacherId,
  branchId: branchId,
  roomId: roomId,
  subscriptionId: subscriptionId,
  settlementTypeKey: settlementTypeKey,
  compensationRuleKey: compensationRuleKey,
  compensationValueMinor: compensationValueMinor,
  plannedSettlementReason: plannedSettlementReason,
);

LessonEditorReferenceState _references({
  List<LessonEditorReferenceItem> teachers = const [],
  List<LessonEditorReferenceItem> clients = const [],
  List<LessonEditorReferenceItem> branches = const [],
  List<LessonEditorReferenceItem> rooms = const [],
  List<LessonEditorReferenceItem> subscriptions = const [],
  LessonDecisionCatalog? catalog,
}) => LessonEditorReferenceState(
  teachers: teachers,
  clients: clients,
  branches: branches,
  rooms: rooms,
  subscriptions: subscriptions,
  catalog: catalog,
);
