import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_reference_controller.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_reference_models.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_reference_settings.dart';

void main() {
  group('ScheduleReferenceController', () {
    test(
      'branch save keeps typed draft data and chains returned version',
      () async {
        final api = _ScheduleReferenceApi();
        final controller = _controller(
          api,
          section: ScheduleReferenceSection.branchHours,
        );

        await controller.loadCatalogs();
        controller.setBranchDayEnabled(2, true);
        controller.setBranchTime(2, 'open', '10:15');
        controller.replaceBranchException({
          'date': '2026-09-01',
          'closed': false,
          'open': '11:00',
          'close': '16:00',
          'reason': null,
        });
        await controller.saveBranchHours();

        final body = api.lastPut(
          '/crm/schedule-reference/branches/branch-a/hours',
        );
        expect(body['expectedVersion'], 2);
        expect(body['timezone'], 'Europe/Moscow');
        expect(body['weekly'], [
          {'weekday': 1, 'open': '09:00', 'close': '21:00', 'source': 'server'},
          {'weekday': 2, 'open': '10:15', 'close': '21:00'},
        ]);
        expect(body['exceptions'], [
          {
            'date': '2026-09-01',
            'closed': false,
            'open': '11:00',
            'close': '16:00',
          },
        ]);
        expect((body['exceptions'] as List).single, isNot(contains('reason')));
        expect(controller.state.branchDraft?.version, 3);
      },
    );

    test('assignment response version feeds availability mutation', () async {
      final api = _ScheduleReferenceApi();
      final controller = _controller(api);

      await controller.loadCatalogs();
      await controller.saveAssignments();
      await controller.saveAvailability();

      expect(
        api.lastPut('/crm/schedule-reference/teachers/teacher-a/branches'),
        {
          'expectedVersion': 3,
          'assignments': [
            {'branchId': 'branch-a', 'activeFrom': '1970-01-01'},
          ],
        },
      );
      final availability = api.lastPut(
        '/crm/schedule-reference/teachers/teacher-a/availability',
      );
      expect(availability['expectedVersion'], 4);
      expect(availability['rules'], contains(containsPair('weekday', 1)));
      expect(controller.state.teacherDraft?.version, 5);
    });

    test('duplicate recurring rules stay preserved and lock editing', () async {
      final api = _ScheduleReferenceApi(
        teacherAvailability: const [
          {
            'kind': 'recurring',
            'available': true,
            'timezone': 'Europe/Moscow',
            'weekday': 1,
            'localStart': '09:00',
            'localEnd': '13:00',
            'validFrom': '2026-01-01',
          },
          {
            'kind': 'recurring',
            'available': true,
            'timezone': 'Europe/Moscow',
            'weekday': 1,
            'localStart': '14:00',
            'localEnd': '18:00',
            'validFrom': '2026-01-01',
          },
        ],
      );
      final controller = _controller(api);

      await controller.loadCatalogs();
      expect(controller.availabilityLocked, isTrue);
      controller.setRecurringTime(1, 'localStart', '08:00');
      expect(
        controller.state.teacherDraft!.recurring[1]!['localStart'],
        '09:00',
      );

      await controller.saveAvailability();
      final rules =
          api.lastPut(
                '/crm/schedule-reference/teachers/teacher-a/availability',
              )['rules']!
              as List<dynamic>;
      expect(rules.where((rule) => rule['weekday'] == 1), hasLength(2));
      expect(rules, contains(containsPair('localStart', '14:00')));
    });

    test('late schedule response cannot replace the newer selection', () async {
      final first = Completer<Map<String, dynamic>>();
      final second = Completer<Map<String, dynamic>>();
      final api = _ScheduleReferenceApi(
        scheduleGates: {'teacher-a': first, 'teacher-b': second},
      );
      final controller = _controller(api);

      final initialLoad = controller.loadCatalogs();
      await pumpEventQueue();
      expect(controller.state.teacherId, 'teacher-a');

      final latestLoad = controller.selectTeacher('teacher-b');
      second.complete(api.scheduleReference('teacher-b', version: 9));
      await latestLoad;
      first.complete(api.scheduleReference('teacher-a', version: 3));
      await initialLoad;

      expect(controller.state.teacherId, 'teacher-b');
      expect(controller.state.teacherDraft?.version, 9);
      expect(controller.state.teacherDraft?.assignments, contains('branch-b'));
      expect(controller.state.error, isNull);
    });

    test('late schedule failure cannot replace the newer success', () async {
      final first = Completer<Map<String, dynamic>>();
      final second = Completer<Map<String, dynamic>>();
      final api = _ScheduleReferenceApi(
        scheduleGates: {'teacher-a': first, 'teacher-b': second},
      );
      final controller = _controller(api);

      final initialLoad = controller.loadCatalogs();
      await pumpEventQueue();
      final latestLoad = controller.selectTeacher('teacher-b');
      second.complete(api.scheduleReference('teacher-b', version: 9));
      await latestLoad;
      first.completeError(StateError('stale offline'));
      await initialLoad;

      expect(controller.state.teacherId, 'teacher-b');
      expect(controller.state.teacherDraft?.version, 9);
      expect(controller.state.error, isNull);
    });

    test(
      'new recurring and interval rules keep deterministic time semantics',
      () async {
        final api = _ScheduleReferenceApi();
        final controller = _controller(api);
        await controller.loadCatalogs();

        controller.setRecurringEnabled(2, true);
        controller.addUnavailableInterval({
          'startsAt': '2026-08-27T12:00:00+03:00',
          'endsAt': '2026-08-27T13:30:00+03:00',
          'reason': '  Репетиция  ',
        });

        expect(controller.state.teacherDraft!.recurring[2], {
          'kind': 'recurring',
          'available': true,
          'timezone': 'Europe/Moscow',
          'weekday': 2,
          'localStart': '09:00',
          'localEnd': '21:00',
          'validFrom': '2026-08-27',
        });
        expect(controller.state.teacherDraft!.intervals.single, {
          'kind': 'interval',
          'available': false,
          'startsAt': '2026-08-27T09:00:00.000Z',
          'endsAt': '2026-08-27T10:30:00.000Z',
          'reason': 'Репетиция',
        });
        expect(
          () => controller.addUnavailableInterval({
            'startsAt': '2026-08-27T12:00:00Z',
            'endsAt': '2026-08-27T13:00:00Z',
            'reason': ' ',
          }),
          throwsArgumentError,
        );
      },
    );

    test('read-only controller fails closed for every mutation', () async {
      final api = _ScheduleReferenceApi();
      final controller = _controller(api, canEdit: false);
      await controller.loadCatalogs();
      final original =
          controller.state.teacherDraft!.recurring[1]!['localStart'];

      controller.setAssignment('branch-b', true);
      controller.setRecurringTime(1, 'localStart', '07:00');
      controller.addUnavailableInterval({
        'startsAt': '2026-08-27T12:00:00Z',
        'endsAt': '2026-08-27T13:00:00Z',
        'reason': 'Недоступен',
      });
      await controller.saveAssignments();
      await controller.saveAvailability();

      expect(
        controller.state.teacherDraft!.assignments,
        isNot(contains('branch-b')),
      );
      expect(
        controller.state.teacherDraft!.recurring[1]!['localStart'],
        original,
      );
      expect(controller.state.teacherDraft!.intervals, isEmpty);

      final branchController = _controller(
        api,
        section: ScheduleReferenceSection.branchHours,
        canEdit: false,
      );
      await branchController.loadCatalogs();
      branchController.setBranchDayEnabled(2, true);
      branchController.setBranchTime(1, 'open', '07:00');
      branchController.replaceBranchException({
        'date': '2026-09-01',
        'closed': true,
      });
      branchController.removeBranchException('2026-09-01');
      await branchController.saveBranchHours();
      expect(branchController.state.branchDraft!.weekly, isNot(contains(2)));
      expect(branchController.state.branchDraft!.weekly[1]!['open'], '09:00');
      expect(branchController.state.branchDraft!.exceptions, isEmpty);
      expect(api.puts, isEmpty);
    });
  });

  group('ScheduleReferenceSettings', () {
    for (final entry in const {
      ScheduleReferenceSection.branchHours:
          'Не удалось загрузить часы работы филиала.',
      ScheduleReferenceSection.teacherSchedule:
          'Не удалось загрузить график преподавателя.',
    }.entries) {
      testWidgets('shows exact ${entry.key.name} retry copy', (tester) async {
        final api = _ScheduleReferenceApi(failCatalogs: true);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              magicCrmServiceProvider.overrideWithValue(MagicCrmService(api)),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: ScheduleReferenceSettings(
                  canEdit: true,
                  section: entry.key,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text(entry.value), findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'Повторить'), findsOneWidget);
      });
    }
  });
}

ScheduleReferenceController _controller(
  _ScheduleReferenceApi api, {
  ScheduleReferenceSection section = ScheduleReferenceSection.teacherSchedule,
  bool canEdit = true,
}) => ScheduleReferenceController(
  crm: MagicCrmService(api),
  section: section,
  canEdit: canEdit,
  clock: () => DateTime(2026, 8, 27, 12),
);

class _ScheduleReferenceApi extends MagicApiClient {
  _ScheduleReferenceApi({
    this.failCatalogs = false,
    this.teacherAvailability = _defaultAvailability,
    this.scheduleGates = const {},
  }) : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  static const _defaultAvailability = <Map<String, dynamic>>[
    {
      'kind': 'recurring',
      'available': true,
      'timezone': 'Europe/Moscow',
      'weekday': 1,
      'localStart': '10:00',
      'localEnd': '18:00',
      'validFrom': '2026-01-01',
    },
  ];

  final bool failCatalogs;
  final List<Map<String, dynamic>> teacherAvailability;
  final Map<String, Completer<Map<String, dynamic>>> scheduleGates;
  final puts = <String, List<Map<String, dynamic>>>{};

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/crm/branches') {
      if (failCatalogs) throw StateError('offline');
      return <String, dynamic>{'items': _branches} as T;
    }
    if (path == '/crm/teachers') {
      return <String, dynamic>{'items': _teachers} as T;
    }
    if (path == '/crm/schedule-reference/branches/branch-a/hours') {
      return _branchHours as T;
    }
    if (path == '/crm/schedule-reference') {
      final teacherId = queryParameters!['teacherId']! as String;
      final gate = scheduleGates[teacherId];
      return (gate == null ? scheduleReference(teacherId) : await gate.future)
          as T;
    }
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
    return <String, dynamic>{
          'version': (body['expectedVersion'] as num).toInt() + 1,
        }
        as T;
  }

  Map<String, dynamic> lastPut(String path) => puts[path]!.last;

  Map<String, dynamic> scheduleReference(String teacherId, {int version = 3}) =>
      {
        'branch': _branchHours,
        'teacher': {
          'version': version,
          'assignments': [
            {
              'branchId': teacherId == 'teacher-b' ? 'branch-b' : 'branch-a',
              'activeFrom': null,
            },
          ],
          'availability': teacherAvailability,
        },
      };

  static const _branches = <Map<String, dynamic>>[
    {'id': 'branch-a', 'name': 'Сокол'},
    {'id': 'branch-b', 'name': 'Спортивная'},
  ];
  static const _teachers = <Map<String, dynamic>>[
    {'id': 'teacher-a', 'firstName': 'Мария', 'lastName': 'Петрова'},
    {'id': 'teacher-b', 'firstName': 'Анна', 'lastName': 'Соколова'},
  ];
  static const _branchHours = <String, dynamic>{
    'version': 2,
    'timezone': 'Europe/Moscow',
    'weekly': [
      {
        'weekday': 1,
        'open': '09:00',
        'close': '21:00',
        'source': 'server',
        'unused': null,
      },
    ],
    'exceptions': <Map<String, dynamic>>[],
  };
}
