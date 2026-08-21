import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/widgets/searchable_picker_field.dart';
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
  }) : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  final bool controlBranchLoads;
  final bool controlSubscriptionLoads;
  final roomResponses = <String, Completer<Map<String, dynamic>>>{};
  final catalogResponses = <String, Completer<Map<String, dynamic>>>{};
  final commerceResponses = <String, Completer<Map<String, dynamic>>>{};
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
                  'branchId': _branchAId,
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
            return await commerceResponses
                    .putIfAbsent(studentId, Completer<Map<String, dynamic>>.new)
                    .future
                as T;
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
  'defaultLessonDurationMinutes': suffix == 'А' ? 45 : 90,
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

Widget _controlledHost(_ControlledApiClient client) {
  return ProviderScope(
    overrides: [magicApiClientProvider.overrideWithValue(client)],
    child: const MaterialApp(
      home: Scaffold(body: CreateLessonDialog(initialBranchId: _branchAId)),
    ),
  );
}

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

    client.commerceResponses[_studentBId]!.complete(
      _commerceResponse(_studentBId, 'Абонемент Б'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Абонемент Б · остаток 8'), findsWidgets);

    client.commerceResponses[_studentAId]!.complete(
      _commerceResponse(_studentAId, 'Абонемент А'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Абонемент Б · остаток 8'), findsWidgets);
    expect(find.text('Абонемент А · остаток 8'), findsNothing);
  });
}
