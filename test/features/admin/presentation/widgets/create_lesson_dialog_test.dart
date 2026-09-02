import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/entity_presentation_resolver.dart';
import 'package:magic_music_crm/core/widgets/searchable_picker_field.dart';
import 'package:magic_music_crm/core/workspace/workspace_controller.dart';
import 'package:magic_music_crm/core/workspace/workspace_navigation_scope.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/create_lesson_dialog.dart';

const _branchAId = '11111111-1111-4111-8111-111111111111';
const _branchBId = '11111111-1111-4111-8111-111111111112';
const _studentAId = '33333333-3333-4333-8333-333333333331';
const _studentBId = '33333333-3333-4333-8333-333333333332';
const _roomAId = '55555555-5555-4555-8555-555555555551';
const _roomBId = '55555555-5555-4555-8555-555555555552';

class _FakeApiClient extends MagicApiClient {
  _FakeApiClient()
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/crm/students/33333333-3333-3333-3333-333333333333/commerce') {
      return <String, dynamic>{
            'projection': 'admin_scoped',
            'student': {
              'studentId': '33333333-3333-3333-3333-333333333333',
              'accounts': const [],
              'subscriptions': const [],
              'movements': const [],
              'technicalHistory': const [],
              'lessonBalance': {
                'activeSubscriptionCount': 0,
                'total': 0,
                'used': 0,
                'reserved': 0,
                'paid': 0,
                'available': 0,
                'debts': const [],
                'nextPaymentAt': null,
                'expiresAt': null,
              },
            },
          }
          as T;
    }
    return <String, dynamic>{'items': const []} as T;
  }
}

class _ControlledApiClient extends MagicApiClient {
  _ControlledApiClient({
    this.controlBranchLoads = false,
    this.controlSubscriptionLoads = false,
    this.controlInitialRoomLoad = false,
  }) : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  final bool controlBranchLoads;
  final bool controlSubscriptionLoads;
  final bool controlInitialRoomLoad;
  final initialRoomResponse = Completer<Map<String, dynamic>>();
  final roomResponses = <String, Completer<Map<String, dynamic>>>{};
  final catalogResponses = <String, Completer<Map<String, dynamic>>>{};
  final commerceResponses = <String, List<Completer<Map<String, dynamic>>>>{};
  final _roomCallCounts = <String, int>{};
  final _catalogCallCounts = <String, int>{};

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    switch (path) {
      case '/crm/teachers':
        return <String, dynamic>{'items': const []} as T;
      case '/crm/branches':
        return <String, dynamic>{
              'items': const [
                {'id': _branchAId, 'name': 'Филиал А'},
                {'id': _branchBId, 'name': 'Филиал Б'},
              ],
            }
            as T;
      case '/crm/clients/search':
        return <String, dynamic>{
              'items': const [
                {
                  'ref': {'type': 'student', 'id': _studentAId},
                  'label': 'Ученик А',
                  'branchId': _branchBId,
                  'lifecycleState': 'active',
                  'tombstone': false,
                  'version': 1,
                  'links': [],
                },
                {
                  'ref': {'type': 'student', 'id': _studentBId},
                  'label': 'Ученик Б',
                  'branchId': _branchAId,
                  'lifecycleState': 'active',
                  'tombstone': false,
                  'version': 1,
                  'links': [],
                },
              ],
            }
            as T;
      case '/crm/rooms':
        final branchId = queryParameters!['branchId'].toString();
        final callCount = (_roomCallCounts[branchId] ?? 0) + 1;
        _roomCallCounts[branchId] = callCount;
        if (controlInitialRoomLoad &&
            branchId == _branchAId &&
            callCount == 1) {
          return await initialRoomResponse.future as T;
        }
        if (controlBranchLoads && (branchId != _branchAId || callCount > 1)) {
          return await roomResponses
                  .putIfAbsent(branchId, Completer<Map<String, dynamic>>.new)
                  .future
              as T;
        }
        return _roomResponse(branchId, branchId == _branchAId ? 'А' : 'Б') as T;
      case '/crm/configuration/lesson-decisions':
        final branchId = queryParameters!['branchId'].toString();
        final callCount = (_catalogCallCounts[branchId] ?? 0) + 1;
        _catalogCallCounts[branchId] = callCount;
        if (controlBranchLoads && (branchId != _branchAId || callCount > 1)) {
          return await catalogResponses
                  .putIfAbsent(branchId, Completer<Map<String, dynamic>>.new)
                  .future
              as T;
        }
        return _catalogResponse(branchId == _branchAId ? 'А' : 'Б') as T;
      default:
        if (path.startsWith('/crm/students/') && path.endsWith('/commerce')) {
          final studentId = path.split('/')[3];
          if (controlSubscriptionLoads) {
            final response = Completer<Map<String, dynamic>>();
            commerceResponses.putIfAbsent(studentId, () => []).add(response);
            return await response.future as T;
          }
          return _commerceResponse(studentId, 'Абонемент') as T;
        }
        return <String, dynamic>{'items': const []} as T;
    }
  }
}

Map<String, dynamic> _roomResponse(String branchId, String suffix) => {
  'items': [
    {
      'id': suffix == 'А' ? _roomAId : _roomBId,
      'name': 'Зал $suffix',
      'branchId': branchId,
    },
  ],
};

Map<String, dynamic> _catalogResponse(String suffix) => {
  'defaultLessonDurationMinutes': suffix == 'А' ? 75 : 90,
  'settlementTypes': [
    {
      'stableKey': 'settlement_$suffix',
      'label': 'Списание $suffix',
      'colorToken': 'success',
      'allowedContexts': const ['settle'],
      'active': true,
      'order': 0,
      'hourShareBasisPoints': 10000,
      'fixedPenaltyMinor': '0',
    },
  ],
  'teacherCompensationRules': const [
    {
      'stableKey': 'standard',
      'label': 'Стандартная ставка',
      'mode': 'standard',
      'value': '0',
      'active': true,
      'order': 0,
    },
  ],
};

Map<String, dynamic> _commerceResponse(String studentId, String name) => {
  'projection': 'admin_scoped',
  'student': {
    'studentId': studentId,
    'accounts': const [],
    'subscriptions': [
      {
        'id': 'subscription-$studentId',
        'status': 'active',
        'startsAt': '2026-08-01T00:00:00.000Z',
        'expiresAt': null,
        'units': const {
          'total': 12,
          'used': 4,
          'reserved': 0,
          'paid': 12,
          'available': 8,
          'remaining': 8,
        },
        'financial': const {
          'actualPaidMinor': '3000000',
          'obligationMinor': '3000000',
          'debtMinor': '0',
          'overpaymentMinor': '0',
          'nextPaymentAt': null,
        },
        'terms': {
          'displayName': name,
          'validityDays': null,
          'basePriceMinor': '3000000',
          'finalPriceMinor': '3000000',
          'currencyCode': 'RUB',
          'discount': const {'type': 'none'},
          'surcharge': const {'type': 'none'},
        },
        'installments': const [],
      },
    ],
    'movements': const [],
    'technicalHistory': const [],
    'lessonBalance': const {
      'activeSubscriptionCount': 1,
      'total': 12,
      'used': 4,
      'reserved': 0,
      'paid': 12,
      'available': 8,
      'debts': [],
      'nextPaymentAt': null,
      'expiresAt': null,
    },
  },
};

Widget _host(Map<String, dynamic> lesson) {
  return ProviderScope(
    overrides: [magicApiClientProvider.overrideWithValue(_FakeApiClient())],
    child: MaterialApp(
      home: Scaffold(body: CreateLessonDialog(lesson: lesson)),
    ),
  );
}

Widget _controlledHost(
  _ControlledApiClient client, {
  int? initialDurationMinutes,
  Map<String, dynamic>? lesson,
}) {
  return ProviderScope(
    overrides: [magicApiClientProvider.overrideWithValue(client)],
    child: MaterialApp(
      home: Scaffold(
        body: CreateLessonDialog(
          lesson: lesson,
          key: ValueKey('lesson-$initialDurationMinutes'),
          initialBranchId: _branchAId,
          initialDurationMinutes: initialDurationMinutes,
        ),
      ),
    ),
  );
}

Widget _showHost({
  required bool isDesktop,
  required WorkspaceController controller,
  required ValueNotifier<bool?> result,
}) {
  return ProviderScope(
    overrides: [magicApiClientProvider.overrideWithValue(_FakeApiClient())],
    child: MaterialApp(
      home: WorkspaceNavigationScope(
        controller: controller,
        isDesktop: isDesktop,
        child: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                result.value = await CreateLessonDialog.show(context);
              },
              child: const Text('Открыть занятие'),
            ),
          ),
        ),
      ),
    ),
  );
}

WorkspaceController _workspaceController() => WorkspaceController(
  accountId: 'account-1',
  initialLink: EntityLink.typed(
    entityType: EntityLinkType.chat,
    entityId: 'home',
  ),
  titleResolver: const EntityPresentationResolver().pageTitle,
  sharedScope: WorkspaceSharedScope(
    session: Object(),
    cache: Object(),
    realtime: Object(),
  ),
);

Future<void> _selectPickerOption(
  WidgetTester tester,
  Key field,
  String option,
) async {
  await tester.ensureVisible(find.byKey(field));
  await tester.tap(find.byKey(field));
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(
      of: find.byType(Scrollbar).last,
      matching: find.text(option),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  for (final state in ['scheduled', 'successfully_completed']) {
    testWidgets('settlement selector remains editable for $state lessons', (
      tester,
    ) async {
      await tester.pumpWidget(
        _controlledHost(
          _ControlledApiClient(),
          lesson: {
            'id': 'lesson-edit',
            'version': 2,
            'lifecycle_state': state,
            'student_id': _studentAId,
            'student_name': 'Ученик А',
            'branch_id': _branchAId,
            'room_id': _roomAId,
            'scheduled_at': '2026-08-31T07:00:00Z',
            'duration_minutes': 60,
            'settlement_type_key': 'settlement_А',
          },
        ),
      );
      await tester.pumpAndSettle();
      final field = tester.widget<DropdownButtonFormField<String>>(
        find.byKey(const ValueKey('lesson-settlement-type-field')),
      );
      expect(field.onChanged, isNotNull);
    });
  }

  testWidgets(
    'mobile show uses the lesson editor route and returns its result',
    (tester) async {
      final controller = _workspaceController();
      final result = ValueNotifier<bool?>(true);
      addTearDown(controller.dispose);
      addTearDown(result.dispose);
      await tester.pumpWidget(
        _showHost(isDesktop: false, controller: controller, result: result),
      );

      await tester.tap(find.text('Открыть занятие'));
      await tester.pumpAndSettle();

      final dialogContext = tester.element(find.text('Новое занятие'));
      final route = ModalRoute.of(dialogContext);
      expect(route?.settings.name, 'lesson-editor');
      expect((route as MaterialPageRoute).fullscreenDialog, isTrue);
      expect(find.byType(BackButton), findsOneWidget);

      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      expect(result.value, isNull);
    },
  );

  testWidgets('desktop show uses a dialog surface and returns its result', (
    tester,
  ) async {
    final controller = _workspaceController();
    final result = ValueNotifier<bool?>(true);
    addTearDown(controller.dispose);
    addTearDown(result.dispose);
    await tester.pumpWidget(
      _showHost(isDesktop: true, controller: controller, result: result),
    );

    await tester.tap(find.text('Открыть занятие'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);

    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(result.value, isNull);
  });

  testWidgets('create view keeps stable fields and active feedback surfaces', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_controlledHost(_ControlledApiClient()));
    await tester.pumpAndSettle();

    for (final key in <Key>[
      const ValueKey('lesson-client-field'),
      const ValueKey('lesson-branch-field:$_branchAId'),
      const ValueKey('lesson-teacher-field'),
      const ValueKey('lesson-room-field'),
      const ValueKey('lesson-date-field'),
      const ValueKey('lesson-time-field'),
      const ValueKey('lesson-duration-field'),
      const ValueKey('lesson-trial-toggle'),
      const ValueKey('lesson-snapshot-preview'),
      const ValueKey('lesson-run-schedule-analyzer'),
    ]) {
      expect(find.byKey(key), findsOneWidget);
    }

    final analyzer = find.byKey(const ValueKey('lesson-run-schedule-analyzer'));
    await tester.ensureVisible(analyzer);
    await tester.tap(analyzer);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('lesson-conflict-inspector')),
      findsOneWidget,
    );

    await tester.ensureVisible(find.text('Создать'));
    await tester.tap(find.text('Создать'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('lesson-form-validation-error')),
      findsOneWidget,
    );
  });

  testWidgets(
    'non-positive constructor durations use catalog default; positive stays explicit',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      for (final entry in const {0: 75, -15: 75, 45: 45}.entries) {
        await tester.pumpWidget(
          _controlledHost(
            _ControlledApiClient(),
            initialDurationMinutes: entry.key,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(ValueKey('lesson-duration-selection-${entry.value}')),
          findsOneWidget,
          reason: 'constructor duration ${entry.key}',
        );
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets('creating with an old initial date keeps the 30-day boundary', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final oldInitialDate = DateTime.now().subtract(const Duration(days: 31));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [magicApiClientProvider.overrideWithValue(_FakeApiClient())],
        child: MaterialApp(
          home: Scaffold(body: CreateLessonDialog(initialDate: oldInitialDate)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final beforeOpening = DateTime.now();
    await tester.tap(find.byKey(const ValueKey('lesson-date-field')));
    await tester.pumpAndSettle();
    final afterOpening = DateTime.now();

    final picker = tester.widget<DatePickerDialog>(
      find.byType(DatePickerDialog),
    );
    final beforeLowerBound = DateTime(
      beforeOpening.year,
      beforeOpening.month,
      beforeOpening.day - 30,
    );
    final afterLowerBound = DateTime(
      afterOpening.year,
      afterOpening.month,
      afterOpening.day - 30,
    );
    expect(picker.firstDate, anyOf(beforeLowerBound, afterLowerBound));
    expect(picker.initialDate, picker.firstDate);
  });

  testWidgets('editing a lesson older than 30 days opens the date picker', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final oldLessonDate = DateTime.now().toUtc().subtract(
      const Duration(days: 31),
    );
    // This is the smallest fixture adapted from v4's editable lesson:
    // only the existing edit-path fields needed to open the date picker.
    final lesson = <String, dynamic>{
      'id': '66666666-6666-6666-6666-666666666666',
      'version': 7,
      'student_id': '33333333-3333-3333-3333-333333333333',
      'student_name': 'Иван Прилежный',
      'scheduled_at': oldLessonDate.toIso8601String(),
      'duration_minutes': 60,
    };

    await tester.pumpWidget(_host(lesson));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('lesson-date-field')));
    await tester.pumpAndSettle();

    expect(find.byType(DatePickerDialog), findsOneWidget);
  });

  testWidgets('older branch loads do not replace the latest room and catalog', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final client = _ControlledApiClient(controlBranchLoads: true);

    await tester.pumpWidget(_controlledHost(client));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('lesson-branch-field:$_branchAId')),
    );
    await tester.pump();
    await tester.tap(find.text('Филиал Б').last);
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('lesson-branch-field:$_branchBId')),
    );
    await tester.pump();
    await tester.tap(find.text('Филиал А').last);
    await tester.pump();

    client.roomResponses[_branchAId]!.complete(_roomResponse(_branchAId, 'А'));
    client.catalogResponses[_branchAId]!.complete(_catalogResponse('А'));
    await tester.pumpAndSettle();
    await _selectPickerOption(
      tester,
      const ValueKey('lesson-room-field'),
      'Зал А',
    );
    expect(find.text('Списание А'), findsOneWidget);

    client.roomResponses[_branchBId]!.complete(_roomResponse(_branchBId, 'Б'));
    client.catalogResponses[_branchBId]!.complete(_catalogResponse('Б'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<SearchablePickerField>(
            find.byKey(const ValueKey('lesson-room-field')),
          )
          .selectedId,
      _roomAId,
    );
    expect(find.text('Списание А'), findsOneWidget);
    expect(find.text('Списание Б'), findsNothing);
  });

  testWidgets('stale catalog failure does not affect the latest branch', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final client = _ControlledApiClient(controlBranchLoads: true);

    await tester.pumpWidget(_controlledHost(client));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('lesson-branch-field:$_branchAId')),
    );
    await tester.pump();
    await tester.tap(find.text('Филиал Б').last);
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('lesson-branch-field:$_branchBId')),
    );
    await tester.pump();
    await tester.tap(find.text('Филиал А').last);
    await tester.pump();

    client.roomResponses[_branchAId]!.complete(_roomResponse(_branchAId, 'А'));
    client.catalogResponses[_branchAId]!.complete(_catalogResponse('А'));
    await tester.pumpAndSettle();
    client.roomResponses[_branchBId]!.complete(_roomResponse(_branchBId, 'Б'));
    client.catalogResponses[_branchBId]!.completeError(
      StateError('stale catalog failure'),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('lesson-branch-field:$_branchAId')),
      findsOneWidget,
    );
    expect(find.text('Списание А'), findsOneWidget);
  });

  testWidgets('older subscription load does not replace the latest client', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final client = _ControlledApiClient(controlSubscriptionLoads: true);

    await tester.pumpWidget(_controlledHost(client));
    await tester.pumpAndSettle();
    await _selectPickerOption(
      tester,
      const ValueKey('lesson-client-field'),
      'Ученик А',
    );
    await _selectPickerOption(
      tester,
      const ValueKey('lesson-client-field'),
      'Ученик Б',
    );

    client.commerceResponses[_studentBId]!.single.complete(
      _commerceResponse(_studentBId, 'Абонемент Б'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Абонемент Б · остаток 8'), findsWidgets);

    client.commerceResponses[_studentAId]!.single.complete(
      _commerceResponse(_studentAId, 'Абонемент А'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Абонемент Б · остаток 8'), findsWidgets);
    expect(find.text('Абонемент А · остаток 8'), findsNothing);
  });

  testWidgets(
    'stale cross-branch client load cannot supersede latest subscriptions',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final client = _ControlledApiClient(
        controlBranchLoads: true,
        controlSubscriptionLoads: true,
      );

      await tester.pumpWidget(_controlledHost(client));
      await tester.pumpAndSettle();
      await _selectPickerOption(
        tester,
        const ValueKey('lesson-client-field'),
        'Ученик А',
      );
      await _selectPickerOption(
        tester,
        const ValueKey('lesson-client-field'),
        'Ученик Б',
      );
      await _selectPickerOption(
        tester,
        const ValueKey('lesson-client-field'),
        'Ученик А',
      );

      client.roomResponses[_branchBId]!.complete(
        _roomResponse(_branchBId, 'Б'),
      );
      client.catalogResponses[_branchBId]!.complete(_catalogResponse('Б'));
      await tester.pumpAndSettle();
      client.commerceResponses[_studentAId]!.first.complete(
        _commerceResponse(_studentAId, 'Абонемент А'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Абонемент А · остаток 8'), findsWidgets);
      expect(client.commerceResponses[_studentAId], hasLength(1));
    },
  );

  testWidgets('startup waits for its owned references before interaction', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final client = _ControlledApiClient(
      controlSubscriptionLoads: true,
      controlInitialRoomLoad: true,
    );

    await tester.pumpWidget(_controlledHost(client));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    client.initialRoomResponse.complete(_roomResponse(_branchAId, 'А'));
    await tester.pumpAndSettle();
    await _selectPickerOption(
      tester,
      const ValueKey('lesson-client-field'),
      'Ученик А',
    );
    client.commerceResponses[_studentAId]!.first.complete(
      _commerceResponse(_studentAId, 'Абонемент А'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Абонемент А · остаток 8'), findsWidgets);
    expect(client.commerceResponses[_studentAId], hasLength(1));
  });
}
