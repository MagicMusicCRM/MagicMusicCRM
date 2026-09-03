import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/widgets/searchable_picker_field.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_decision/lesson_decision_models.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_editor/lesson_editor_data_controller.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_editor/lesson_editor_models.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_editor/lesson_participant_section.dart';

const _lead = {
  'ref': {'type': 'lead', 'id': 'lead-a'},
  'clientId': 'client-a',
  'label': 'Анна',
  'branchId': 'branch-a',
  'links': [
    {
      'rel': 'convertedStudent',
      'ref': {'type': 'student', 'id': 'student-a'},
    },
  ],
};

const _student = {
  'ref': {'type': 'student', 'id': 'student-a'},
  'clientId': 'client-a',
  'label': 'Анна Новая',
  'branchId': 'branch-b',
};

void main() {
  test(
    'preload and search collapse conversion refs without matching names',
    () async {
      final controller = _controller(
        rows: [
          _lead,
          _student,
          {
            'ref': {'type': 'lead', 'id': 'lead-b'},
            'clientId': 'client-b',
            'label': 'Анна Новая',
          },
        ],
      );

      final patch = await controller.loadInitial(_session());
      final found = await controller.searchClients('Анна');

      expect(patch!.references.clients.map((item) => item.id), [
        'student:student-a',
        'lead:lead-b',
      ]);
      expect(found.map((client) => client.key), [
        'student:student-a',
        'lead:lead-b',
      ]);
      expect(found.first.label, 'Анна Новая');
      expect(found.first.branchId, 'branch-b');
    },
  );

  test(
    'canonical client identity joins rows even without conversion links',
    () async {
      final controller = _controller(
        rows: [
          {..._lead, 'links': []},
          _student,
        ],
      );

      final found = await controller.searchClients('Анна');

      expect(found.map((client) => client.key), ['student:student-a']);
      expect(found.single.label, 'Анна Новая');
    },
  );

  test(
    'a converted lead outside the student search page selects the linked student',
    () async {
      final controller = _controller(rows: [_lead]);

      final found = await controller.searchClients('Анна');

      expect(found.single.key, 'student:student-a');
    },
  );

  test(
    'creation from converted lead loads the authoritative student and subscriptions',
    () async {
      final resolved = <String>[];
      final subscriptions = <String>[];
      final controller = _controller(
        rows: [_lead, _student],
        resolve: ({required type, required id}) async {
          resolved.add('$type:$id');
          return type == 'lead' ? _lead : _student;
        },
        subscriptions: (id) async {
          subscriptions.add(id);
          return [];
        },
      );

      final patch = await controller.loadInitial(_session(client: _leadRef));

      expect(patch!.draft!.client!.key, 'student:student-a');
      expect(patch.draft!.client!.label, 'Анна Новая');
      expect(patch.draft!.branchId, 'branch-b');
      expect(patch.references.clients.map((item) => item.id), [
        'student:student-a',
      ]);
      expect(resolved, ['lead:lead-a', 'student:student-a']);
      expect(subscriptions, ['student-a']);
    },
  );

  test('an existing lesson keeps its authoritative lead participant', () async {
    final controller = _controller(
      rows: [_lead, _student],
      resolve: ({required type, required id}) async {
        fail(
          'An existing lesson participant must not be replaced by resolution.',
        );
      },
    );

    final patch = await controller.loadInitial(
      _session(client: _leadRef, isEdit: true),
    );

    expect(patch!.draft!.client, _leadRef);
  });

  for (final isEdit in [true, false]) {
    testWidgets(
      'locked participant has no chooser (${isEdit ? 'edit' : 'seeded create'})',
      (tester) async {
        var searched = false;
        var changed = false;
        final session = _session(client: _studentRef, isEdit: isEdit);
        await tester.pumpWidget(
          MaterialApp(
            home: Material(
              child: LessonParticipantSection(
                model: LessonParticipantSectionModel(
                  session: session,
                  draft: session.draft,
                  references: const LessonEditorReferenceState.empty(),
                ),
                onSearchClients: (_) async {
                  searched = true;
                  return [];
                },
                onClientChanged: (_) => changed = true,
                onBranchChanged: (_) {},
                onRoomChanged: (_) {},
                onTeacherChanged: (_) {},
              ),
            ),
          ),
        );

        final clientField = find.byKey(const ValueKey('lesson-client-field'));
        expect(
          find.descendant(
            of: clientField,
            matching: find.byType(SearchablePickerField),
          ),
          findsNothing,
        );
        expect(tester.widget(clientField), isA<InputDecorator>());
        expect(find.text('Анна Новая · Ученик'), findsOneWidget);
        expect(find.text('Введите имя или ФИО клиента'), findsNothing);
        await tester.tap(clientField, warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(searched, isFalse);
        expect(changed, isFalse);
      },
    );
  }
}

const _leadRef = LessonClientRef(type: 'lead', id: 'lead-a', label: 'Анна');
const _studentRef = LessonClientRef(
  type: 'student',
  id: 'student-a',
  label: 'Анна Новая',
);

LessonEditorDataController _controller({
  List<Map<String, dynamic>> rows = const [],
  LessonEditorClientResolver? resolve,
  LessonEditorRowsById? subscriptions,
}) => LessonEditorDataController.forTesting(
  listRooms: (_) async => [],
  loadCatalog: (_) async =>
      const LessonDecisionCatalog(settlementTypes: [], compensationRules: []),
  listSubscriptions: subscriptions ?? (_) async => [],
  listBranches: () async => [
    {'id': 'branch-a', 'name': 'Центр'},
    {'id': 'branch-b', 'name': 'Север'},
  ],
  searchClients: (_) async => rows,
  resolveClient: resolve ?? ({required type, required id}) async => null,
);

LessonEditorSession _session({LessonClientRef? client, bool isEdit = false}) =>
    LessonEditorSession(
      draft: LessonEditorDraft(
        localStart: DateTime(2026, 9, 2, 10),
        durationMinutes: 60,
        isTrial: false,
        completionType: 'standard.success',
        clientChargeType: 'none',
        client: client,
      ),
      snapshot: isEdit
          ? const LessonEditorSnapshot(
              lessonId: 'lesson-a',
              expectedVersion: 1,
              rawLesson: {'id': 'lesson-a', 'lead_id': 'lead-a'},
              clientLocked: true,
              initialSchedulePayload: {},
              initialCompensationRuleKey: null,
              initialCompensationValueMinor: null,
            )
          : null,
      seededClient: client,
    );
