import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/group_detail_dialog.dart';

void main() {
  testWidgets('writable group card exposes group schedule authoring', (
    tester,
  ) async {
    final api = _GroupDetailApi();
    await _pump(tester, api, canWrite: true);

    expect(
      find.byKey(const Key('recurring-schedule-plan-section')),
      findsOneWidget,
    );
    expect(find.text('Добавить ученика'), findsOneWidget);
    final addSchedule = find.byKey(const Key('schedule-plan-add'));
    await tester.ensureVisible(addSchedule);
    await tester.tap(addSchedule);
    await tester.pumpAndSettle();

    expect(find.text('Участники группового расписания'), findsOneWidget);
    expect(find.text('Анна Смирнова'), findsWidgets);
    expect(api.paths, contains('/crm/students/student-1/commerce'));
    expect(api.schedulePlanQuery, containsPair('groupId', 'group-1'));
  });

  testWidgets(
    'read-only group card hides mutations and skips finance loading',
    (tester) async {
      final api = _GroupDetailApi();
      await _pump(tester, api, canWrite: false);

      expect(
        find.byKey(const Key('recurring-schedule-plan-section')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('schedule-plan-add')), findsNothing);
      expect(find.text('Добавить ученика'), findsNothing);
      expect(api.paths, isNot(contains('/crm/students/student-1/commerce')));
    },
  );

  testWidgets('manager adds and removes a payer student from the group', (
    tester,
  ) async {
    final api = _GroupDetailApi();
    await _pump(tester, api, canWrite: true);

    await tester.tap(find.text('Добавить ученика'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Пётр Плательщик'));
    await tester.pumpAndSettle();

    expect(api.postPaths, contains('/crm/groups/group-1/students:student-2'));
    expect(find.text('Пётр Плательщик'), findsOneWidget);

    final payerTile = find.ancestor(
      of: find.text('Пётр Плательщик'),
      matching: find.byType(ListTile),
    );
    await tester.tap(
      find.descendant(of: payerTile, matching: find.byType(IconButton)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Удалить'));
    await tester.pumpAndSettle();

    expect(api.deletePaths, contains('/crm/groups/group-1/students/student-2'));
    expect(find.text('Пётр Плательщик'), findsNothing);
  });
}

Future<void> _pump(
  WidgetTester tester,
  _GroupDetailApi api, {
  required bool canWrite,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1200, 900);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [magicApiClientProvider.overrideWithValue(api)],
      child: MaterialApp(
        home: Scaffold(
          body: GroupDetailDialog(
            group: const {
              'id': 'group-1',
              'name': 'Вокальная группа',
              'branch_id': 'branch-1',
              'branches': {'id': 'branch-1', 'name': 'Сокол'},
            },
            canWrite: canWrite,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _GroupDetailApi extends MagicApiClient {
  _GroupDetailApi()
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  final List<String> paths = [];
  final List<String> postPaths = [];
  final List<String> deletePaths = [];
  final List<Map<String, dynamic>> groupStudents = [
    {
      'id': 'student-1',
      'firstName': 'Анна',
      'lastName': 'Смирнова',
      'email': 'anna@example.test',
    },
  ];
  Map<String, dynamic>? schedulePlanQuery;

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    paths.add(path);
    if (path == '/crm/groups/group-1/students') {
      return <String, dynamic>{'items': groupStudents} as T;
    }
    if (path == '/crm/students') {
      return <String, dynamic>{
            'items': [
              {
                'id': 'student-1',
                'firstName': 'Анна',
                'lastName': 'Смирнова',
                'email': 'anna@example.test',
              },
              {
                'id': 'student-2',
                'firstName': 'Пётр',
                'lastName': 'Плательщик',
                'email': 'payer@example.test',
              },
            ],
          }
          as T;
    }
    if (RegExp(r'^/crm/students/student-[12]/commerce$').hasMatch(path)) {
      final studentId = path.split('/')[3];
      return <String, dynamic>{
            'projection': 'manager_scoped',
            'student': {
              'studentId': studentId,
              'accounts': <dynamic>[],
              'subscriptions': const [
                {
                  'id': 'subscription-1',
                  'status': 'active',
                  'startsAt': '2026-08-01T00:00:00.000Z',
                  'expiresAt': null,
                  'units': {
                    'total': '12',
                    'used': '2',
                    'reserved': '1',
                    'paid': '12',
                    'available': '9',
                    'remaining': '10',
                  },
                  'financial': {
                    'actualPaidMinor': '1200000',
                    'obligationMinor': '1200000',
                    'debtMinor': '0',
                    'overpaymentMinor': '0',
                    'nextPaymentAt': null,
                  },
                  'terms': {
                    'displayName': 'Вокал 12',
                    'validityDays': null,
                    'basePriceMinor': '1200000',
                    'finalPriceMinor': '1200000',
                    'currencyCode': 'RUB',
                    'discount': {'type': 'none'},
                  },
                  'installments': <dynamic>[],
                },
              ],
              'movements': <dynamic>[],
              'technicalHistory': <dynamic>[],
              'lessonBalance': {
                'activeSubscriptionCount': 1,
                'total': '12',
                'used': '2',
                'reserved': '1',
                'paid': '12',
                'available': '9',
                'debts': <dynamic>[],
                'nextPaymentAt': null,
                'expiresAt': null,
              },
            },
          }
          as T;
    }
    if (path == '/crm/schedule-plans') {
      schedulePlanQuery = {...?queryParameters};
      return <String, dynamic>{'items': <dynamic>[]} as T;
    }
    return <String, dynamic>{'items': <dynamic>[]} as T;
  }

  @override
  Future<T> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/crm/groups/group-1/students') {
      final studentId = (data as Map)['studentId']?.toString();
      postPaths.add('$path:$studentId');
      if (studentId == 'student-2') {
        groupStudents.add({
          'id': 'student-2',
          'firstName': 'Пётр',
          'lastName': 'Плательщик',
          'email': 'payer@example.test',
        });
      }
      return <String, dynamic>{'success': true} as T;
    }
    return <String, dynamic>{} as T;
  }

  @override
  Future<T> delete<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    deletePaths.add(path);
    if (path.endsWith('/student-2')) {
      groupStudents.removeWhere((item) => item['id'] == 'student-2');
    }
    return <String, dynamic>{'success': true} as T;
  }
}
