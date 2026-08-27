import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_reference_cards.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_reference_controller.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_reference_settings.dart';

const _branchPath = '/crm/schedule-reference/branches/branch-a/hours';
const _assignmentPath = '/crm/schedule-reference/teachers/teacher-a/branches';
const _availabilityPath =
    '/crm/schedule-reference/teachers/teacher-a/availability';

void main() {
  test('branch edits stay locked until returned version is chained', () async {
    final gate = Completer<Map<String, dynamic>>();
    final api = _SavingApi(putGates: {_branchPath: gate});
    final controller = _controller(
      api,
      section: ScheduleReferenceSection.branchHours,
    );
    await controller.loadCatalogs();
    final original = controller.state.branchDraft;

    final firstSave = controller.saveBranchHours();
    await pumpEventQueue();
    expect(controller.state.saving, isTrue);
    controller.setBranchDayEnabled(2, true);
    controller.setBranchTime(1, 'open', '07:00');
    controller.replaceBranchException({'date': '2026-09-02', 'closed': true});
    controller.removeBranchException('2026-09-01');
    expect(controller.state.branchDraft, same(original));

    gate.complete({'version': 7});
    await firstSave;
    expect(controller.state.branchDraft?.version, 7);
    await controller.saveBranchHours();
    expect(api.expectedVersions(_branchPath), [2, 7]);
  });

  test(
    'assignment edits stay locked until returned version is chained',
    () async {
      final gate = Completer<Map<String, dynamic>>();
      final api = _SavingApi(putGates: {_assignmentPath: gate});
      final controller = _controller(api);
      await controller.loadCatalogs();
      final original = controller.state.teacherDraft;

      final firstSave = controller.saveAssignments();
      await pumpEventQueue();
      expect(controller.state.saving, isTrue);
      controller.setAssignment('branch-a', false);
      controller.setAssignment('branch-b', true);
      expect(controller.state.teacherDraft, same(original));

      gate.complete({'version': 7});
      await firstSave;
      expect(controller.state.teacherDraft?.version, 7);
      await controller.saveAssignments();
      expect(api.expectedVersions(_assignmentPath), [3, 7]);
    },
  );

  test(
    'availability edits stay locked until returned version is chained',
    () async {
      final gate = Completer<Map<String, dynamic>>();
      final api = _SavingApi(putGates: {_availabilityPath: gate});
      final controller = _controller(api);
      await controller.loadCatalogs();
      final original = controller.state.teacherDraft;
      final interval = original!.intervals.single;

      final firstSave = controller.saveAvailability();
      await pumpEventQueue();
      expect(controller.state.saving, isTrue);
      controller.setRecurringEnabled(2, true);
      controller.setRecurringTime(1, 'localStart', '07:00');
      controller.addUnavailableInterval({
        'startsAt': '2026-09-02T09:00:00Z',
        'endsAt': '2026-09-02T10:00:00Z',
        'reason': 'Репетиция',
      });
      controller.removeUnavailableInterval(interval);
      expect(controller.state.teacherDraft, same(original));

      gate.complete({'version': 7});
      await firstSave;
      expect(controller.state.teacherDraft?.version, 7);
      await controller.saveAvailability();
      expect(api.expectedVersions(_availabilityPath), [3, 7]);
    },
  );

  testWidgets('branch edit controls disable while a save is pending', (
    tester,
  ) async {
    final gate = Completer<Map<String, dynamic>>();
    final api = _SavingApi(putGates: {_branchPath: gate});
    await _pumpSettings(
      tester,
      api,
      section: ScheduleReferenceSection.branchHours,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
    await tester.pump();
    final card = find.byType(BranchHoursCard);

    expect(
      tester
          .widgetList<Switch>(
            find.descendant(of: card, matching: find.byType(Switch)),
          )
          .every((control) => control.onChanged == null),
      isTrue,
    );
    expect(
      tester
          .widgetList<TextButton>(
            find.descendant(of: card, matching: find.byType(TextButton)),
          )
          .every((control) => control.onPressed == null),
      isTrue,
    );
    expect(
      tester
          .widgetList<IconButton>(
            find.descendant(of: card, matching: find.byType(IconButton)),
          )
          .every((control) => control.onPressed == null),
      isTrue,
    );

    gate.complete({'version': 7});
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('teacher edit controls disable while a save is pending', (
    tester,
  ) async {
    final gate = Completer<Map<String, dynamic>>();
    final api = _SavingApi(putGates: {_assignmentPath: gate});
    await _pumpSettings(tester, api);

    await tester.tap(find.widgetWithText(FilledButton, 'Сохранить').first);
    await tester.pump();
    final assignmentsCard = find.byType(TeacherAssignmentsCard);
    final availabilityCard = find.byType(TeacherAvailabilityCard);

    expect(
      tester
          .widgetList<CheckboxListTile>(
            find.descendant(
              of: assignmentsCard,
              matching: find.byType(CheckboxListTile),
            ),
          )
          .every((control) => control.onChanged == null),
      isTrue,
    );
    expect(
      tester
          .widgetList<Switch>(
            find.descendant(
              of: availabilityCard,
              matching: find.byType(Switch),
            ),
          )
          .every((control) => control.onChanged == null),
      isTrue,
    );
    expect(
      tester
          .widgetList<TextButton>(
            find.descendant(
              of: availabilityCard,
              matching: find.byType(TextButton),
            ),
          )
          .every((control) => control.onPressed == null),
      isTrue,
    );
    expect(
      tester
          .widgetList<IconButton>(
            find.descendant(
              of: availabilityCard,
              matching: find.byType(IconButton),
            ),
          )
          .every((control) => control.onPressed == null),
      isTrue,
    );

    gate.complete({'version': 7});
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
  });
}

ScheduleReferenceController _controller(
  _SavingApi api, {
  ScheduleReferenceSection section = ScheduleReferenceSection.teacherSchedule,
}) => ScheduleReferenceController(
  crm: MagicCrmService(api),
  section: section,
  canEdit: true,
  clock: () => DateTime(2026, 8, 27, 12),
);

Future<void> _pumpSettings(
  WidgetTester tester,
  _SavingApi api, {
  ScheduleReferenceSection section = ScheduleReferenceSection.teacherSchedule,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        magicCrmServiceProvider.overrideWithValue(MagicCrmService(api)),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: ScheduleReferenceSettings(canEdit: true, section: section),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _SavingApi extends MagicApiClient {
  _SavingApi({required Map<String, Completer<Map<String, dynamic>>> putGates})
    : _putGates = Map.of(putGates),
      super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  final Map<String, Completer<Map<String, dynamic>>> _putGates;
  final puts = <String, List<Map<String, dynamic>>>{};

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/crm/branches') {
      return <String, dynamic>{'items': _branches} as T;
    }
    if (path == '/crm/teachers') {
      return <String, dynamic>{'items': _teachers} as T;
    }
    if (path == _branchPath) return _branchHours as T;
    if (path == '/crm/schedule-reference') return _teacherReference as T;
    throw StateError('Unexpected GET $path');
  }

  @override
  Future<T> put<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    final body = Map<String, dynamic>.from(data! as Map);
    puts.putIfAbsent(path, () => []).add(body);
    final gate = _putGates.remove(path);
    final result = gate == null
        ? {'version': (body['expectedVersion'] as num).toInt() + 1}
        : await gate.future;
    return result as T;
  }

  List<int> expectedVersions(String path) => [
    for (final body in puts[path]!) (body['expectedVersion'] as num).toInt(),
  ];

  static const _branches = <Map<String, dynamic>>[
    {'id': 'branch-a', 'name': 'Сокол'},
    {'id': 'branch-b', 'name': 'Спортивная'},
  ];
  static const _teachers = <Map<String, dynamic>>[
    {'id': 'teacher-a', 'firstName': 'Мария', 'lastName': 'Петрова'},
  ];
  static const _branchHours = <String, dynamic>{
    'version': 2,
    'timezone': 'Europe/Moscow',
    'weekly': [
      {'weekday': 1, 'open': '09:00', 'close': '21:00'},
    ],
    'exceptions': [
      {'date': '2026-09-01', 'closed': true},
    ],
  };
  static const _teacherReference = <String, dynamic>{
    'branch': _branchHours,
    'teacher': {
      'version': 3,
      'assignments': [
        {'branchId': 'branch-a', 'activeFrom': null},
      ],
      'availability': [
        {
          'kind': 'recurring',
          'available': true,
          'timezone': 'Europe/Moscow',
          'weekday': 1,
          'localStart': '10:00',
          'localEnd': '18:00',
          'validFrom': '2026-01-01',
        },
        {
          'kind': 'interval',
          'available': false,
          'startsAt': '2026-09-01T09:00:00Z',
          'endsAt': '2026-09-01T10:00:00Z',
          'reason': 'Репетиция',
        },
      ],
    },
  };
}
