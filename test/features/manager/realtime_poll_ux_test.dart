import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/services/crm_realtime_provider.dart';
import 'package:magic_music_crm/core/widgets/skeletons.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/finance_widget.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/leads_widget.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/reports_widget.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/students_board_widget.dart';

class _CountingApiClient extends MagicApiClient {
  _CountingApiClient({
    List<Map<String, dynamic>> studentItems = const [],
    this.studentStages = const [
      {
        'key': 'learning',
        'label': 'Обучаются',
        'style': 'green',
        'active': true,
        'allowedTransitions': <dynamic>[],
      },
    ],
  }) : studentItems = studentItems
           .map((item) => Map<String, dynamic>.from(item))
           .toList(),
       super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  final counts = <String, int>{};
  final List<Map<String, dynamic>> studentItems;
  final List<Map<String, dynamic>> studentStages;
  final patches = <({String path, Map<String, dynamic> data})>[];

  int count(String path) => counts[path] ?? 0;

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    counts[path] = count(path) + 1;
    await Future<void>.delayed(Duration.zero);
    return switch (path) {
          '/crm/payments' => <String, dynamic>{
            'items': <dynamic>[],
            'totalAmount': 0,
            'totalCount': 0,
          },
          '/crm/expenses' => <String, dynamic>{
            'items': <dynamic>[],
            'total': 0,
          },
          '/crm/leads/board' => <String, dynamic>{
            'columns': <dynamic>[],
            'total_count': 0,
          },
          '/crm/reports/finance' => <String, dynamic>{
            'summary': <String, dynamic>{
              'attendance': 0,
              'revenue': 0,
              'totalLessons': 0,
            },
            'monthly': <dynamic>[],
            'teachers': <dynamic>[],
            'rooms': <dynamic>[],
          },
          '/analytics/sources' => <String, dynamic>{'sources': <dynamic>[]},
          '/analytics/data-quality' => <String, dynamic>{},
          '/analytics/responsible' => <String, dynamic>{'items': <dynamic>[]},
          '/analytics/finance/monthly' => <String, dynamic>{
            'items': <dynamic>[],
          },
          '/crm/lead-statuses' => <String, dynamic>{'items': <dynamic>[]},
          '/crm/branches' => <String, dynamic>{
            'items': <dynamic>[
              <String, dynamic>{
                'id': 'branch-a',
                'name': 'Сокол',
                'createdAt': '2026-06-25T00:00:00.000Z',
              },
            ],
          },
          '/crm/students/search' => <String, dynamic>{
            'items': studentItems,
            'totalCount': studentItems.length,
          },
          '/crm/client-pipelines' => <String, dynamic>{
            'clientType': queryParameters?['clientType'],
            'branchId': queryParameters?['branchId'],
            'source': 'school',
            'schoolVersion': 1,
            'branchVersion': 0,
            'stages': studentStages,
            'remediationStatuses': <dynamic>[],
          },
          _ => <String, dynamic>{'items': <dynamic>[]},
        }
        as T;
  }

  @override
  Future<T> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    final body = Map<String, dynamic>.from(data! as Map);
    patches.add((path: path, data: body));
    final id = path.split('/').last;
    final student = studentItems.singleWhere((item) => item['id'] == id);
    student['status'] = body['status'];
    return Map<String, dynamic>.from(student) as T;
  }
}

Widget _host({
  required Widget child,
  required _CountingApiClient api,
  required Stream<CrmChangedEvent> realtime,
  CapabilitySnapshot snapshot = const CapabilitySnapshot(
    accountId: 'manager-test',
    role: 'manager',
    accessVersion: 1,
    capabilities: <String>{},
    scopes: <String, String>{},
  ),
}) {
  return ProviderScope(
    overrides: [
      magicApiClientProvider.overrideWithValue(api),
      crmRealtimeProvider.overrideWith((ref) => realtime),
      capabilitySnapshotProvider.overrideWith((ref) async => snapshot),
    ],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  testWidgets('FinanceWidget ignores fallback realtime poll refreshes', (
    tester,
  ) async {
    final api = _CountingApiClient();
    final realtime = StreamController<CrmChangedEvent>.broadcast();
    addTearDown(realtime.close);

    await tester.pumpWidget(
      _host(api: api, realtime: realtime.stream, child: const FinanceWidget()),
    );
    await tester.pumpAndSettle();

    final initialPayments = api.count('/crm/payments');
    final initialExpenses = api.count('/crm/expenses');
    expect(initialPayments, 1);
    expect(initialExpenses, 1);

    realtime.add(const CrmChangedEvent(entity: 'payment', action: 'poll'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(api.count('/crm/payments'), initialPayments);
    expect(api.count('/crm/expenses'), initialExpenses);
  });

  testWidgets('LeadsWidget keeps search stable during fallback realtime poll', (
    tester,
  ) async {
    final api = _CountingApiClient();
    final realtime = StreamController<CrmChangedEvent>.broadcast();
    addTearDown(realtime.close);

    await tester.pumpWidget(
      _host(api: api, realtime: realtime.stream, child: const LeadsWidget()),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Ан');
    await tester.pump(const Duration(milliseconds: 500));
    final beforePoll = api.count('/crm/leads/board');

    realtime.add(const CrmChangedEvent(entity: 'lead', action: 'poll'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(api.count('/crm/leads/board'), beforePoll);
  });

  testWidgets(
    'lead search keeps focus and board while typing every character',
    (tester) async {
      final api = _CountingApiClient();
      final realtime = StreamController<CrmChangedEvent>.broadcast();
      addTearDown(realtime.close);
      await tester.pumpWidget(
        _host(api: api, realtime: realtime.stream, child: const LeadsWidget()),
      );
      await tester.pumpAndSettle();

      const key = ValueKey('leads-search');
      final initialCalls = api.count('/crm/leads/board');
      await tester.tap(find.byKey(key));
      for (final value in const ['А', 'Ан', 'Анн', 'Анна']) {
        await tester.enterText(find.byKey(key), value);
        await tester.pump(const Duration(milliseconds: 80));
        final field = tester.widget<TextField>(find.byKey(key));
        expect(field.controller!.text, value);
        expect(
          tester
              .widget<EditableText>(
                find.descendant(
                  of: find.byKey(key),
                  matching: find.byType(EditableText),
                ),
              )
              .focusNode
              .hasFocus,
          isTrue,
        );
        expect(api.count('/crm/leads/board'), initialCalls);
        expect(find.byType(KanbanSkeleton), findsNothing);
      }
      await tester.pump(const Duration(milliseconds: 400));
      expect(api.count('/crm/leads/board'), initialCalls + 1);
      await tester.pumpAndSettle();
      expect(find.byType(KanbanSkeleton), findsNothing);
    },
  );

  testWidgets('ReportsWidget ignores fallback realtime poll refreshes', (
    tester,
  ) async {
    final api = _CountingApiClient();
    final realtime = StreamController<CrmChangedEvent>.broadcast();
    addTearDown(realtime.close);

    await tester.pumpWidget(
      _host(
        api: api,
        realtime: realtime.stream,
        // KVA-239: финансовая аналитика в Отчётах доступна director.
        child: const ReportsWidget(role: 'director'),
      ),
    );
    await tester.pumpAndSettle();

    final initialReports = api.count('/analytics/v4/school-finance');
    expect(initialReports, 1);

    realtime.add(const CrmChangedEvent(entity: 'lesson', action: 'poll'));
    await tester.pump(const Duration(milliseconds: 1000));

    expect(api.count('/analytics/v4/school-finance'), initialReports);
  });

  testWidgets('StudentsBoardWidget ignores fallback realtime poll refreshes', (
    tester,
  ) async {
    final api = _CountingApiClient();
    final realtime = StreamController<CrmChangedEvent>.broadcast();
    addTearDown(realtime.close);

    await tester.pumpWidget(
      _host(
        api: api,
        realtime: realtime.stream,
        child: const StudentsBoardWidget(),
      ),
    );
    await tester.pumpAndSettle();

    final initialSearch = api.count('/crm/students/search');
    expect(initialSearch, 1);
    expect(find.byKey(const ValueKey('students-create')), findsNothing);

    realtime.add(const CrmChangedEvent(entity: 'student', action: 'poll'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(api.count('/crm/students/search'), initialSearch);
  });

  testWidgets('student chat action exists only for a linked app account', (
    tester,
  ) async {
    final api = _CountingApiClient(
      studentItems: const [
        {
          'id': 'student-linked',
          'status': 'learning',
          'branchId': 'branch-a',
          'firstName': 'Анна',
          'linkedUserId': 'client-a',
          'isAppAccount': true,
        },
        {
          'id': 'student-crm-only',
          'status': 'learning',
          'branchId': 'branch-a',
          'firstName': 'Борис',
          'linkedUserId': null,
          'isAppAccount': false,
        },
      ],
    );
    final realtime = StreamController<CrmChangedEvent>.broadcast();
    addTearDown(realtime.close);

    await tester.pumpWidget(
      _host(
        api: api,
        realtime: realtime.stream,
        child: const StudentsBoardWidget(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Написать в чат'), findsOneWidget);
  });

  testWidgets(
    'Student board enforces configured transitions and refreshes stage counts',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = _CountingApiClient(
        studentItems: const [
          {
            'id': 'student-a',
            'status': 'learning',
            'branch_id': 'branch-a',
            'first_name': 'Анна',
            'last_name': 'Иванова',
          },
        ],
        studentStages: const [
          {
            'key': 'learning',
            'label': 'Обучаются',
            'style': 'green',
            'active': true,
            'allowedTransitions': <dynamic>['paused'],
          },
          {
            'key': 'paused',
            'label': 'Пауза',
            'style': 'amber',
            'active': true,
            'allowedTransitions': <dynamic>[],
          },
          {
            'key': 'inactive',
            'label': 'Завершили',
            'style': 'gray',
            'active': true,
            'allowedTransitions': <dynamic>[],
          },
        ],
      );
      final realtime = StreamController<CrmChangedEvent>.broadcast();
      addTearDown(realtime.close);
      await tester.pumpWidget(
        _host(
          api: api,
          realtime: realtime.stream,
          snapshot: const CapabilitySnapshot(
            accountId: 'manager-test',
            role: 'manager',
            accessVersion: 1,
            capabilities: <String>{'crm.client.write'},
            scopes: <String, String>{'client': 'branch'},
          ),
          child: const StudentsBoardWidget(),
        ),
      );
      await tester.pumpAndSettle();

      Finder target(String label) => find.ancestor(
        of: find.text(label),
        matching: find.byType(DragTarget<Map<String, dynamic>>),
      );
      Finder countIn(String label, String count) =>
          find.descendant(of: target(label), matching: find.text(count));
      final details = DragTargetDetails<Map<String, dynamic>>(
        data: api.studentItems.single,
        offset: Offset.zero,
      );
      final paused = tester.widget<DragTarget<Map<String, dynamic>>>(
        target('Пауза'),
      );
      final inactive = tester.widget<DragTarget<Map<String, dynamic>>>(
        target('Завершили'),
      );

      expect(countIn('Обучаются', '1'), findsOneWidget);
      expect(countIn('Пауза', '0'), findsOneWidget);
      expect(inactive.onWillAcceptWithDetails!(details), isFalse);
      expect(paused.onWillAcceptWithDetails!(details), isTrue);

      paused.onAcceptWithDetails!(details);
      await tester.pumpAndSettle();

      expect(api.patches, hasLength(1));
      expect(api.patches.single.path, '/crm/students/student-a');
      expect(api.patches.single.data['status'], 'paused');
      expect(countIn('Обучаются', '0'), findsOneWidget);
      expect(countIn('Пауза', '1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('student search is local and keeps focus while typing', (
    tester,
  ) async {
    final api = _CountingApiClient();
    final realtime = StreamController<CrmChangedEvent>.broadcast();
    addTearDown(realtime.close);
    await tester.pumpWidget(
      _host(
        api: api,
        realtime: realtime.stream,
        child: const StudentsBoardWidget(),
      ),
    );
    await tester.pumpAndSettle();

    const key = ValueKey('students-search');
    final initialCalls = api.count('/crm/students/search');
    await tester.tap(find.byKey(key));
    for (final value in const ['И', 'Ив', 'Ива', 'Иван']) {
      await tester.enterText(find.byKey(key), value);
      await tester.pump(const Duration(milliseconds: 80));
      final field = tester.widget<TextField>(find.byKey(key));
      expect(field.controller!.text, value);
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: find.byKey(key),
                matching: find.byType(EditableText),
              ),
            )
            .focusNode
            .hasFocus,
        isTrue,
      );
      expect(api.count('/crm/students/search'), initialCalls);
      expect(find.byType(KanbanSkeleton), findsNothing);
    }
  });

  testWidgets(
    'student board actions remain usable at phone/tablet/desktop widths',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final sizes = [
        const Size(360, 690),
        const Size(840, 900),
        const Size(1200, 800),
      ];
      for (final size in sizes) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        final api = _CountingApiClient();
        final realtime = StreamController<CrmChangedEvent>.broadcast();
        await tester.pumpWidget(
          _host(
            api: api,
            realtime: realtime.stream,
            snapshot: const CapabilitySnapshot(
              accountId: 'director-test',
              role: 'director',
              accessVersion: 1,
              capabilities: <String>{'crm.client.write'},
              scopes: <String, String>{},
            ),
            child: const StudentsBoardWidget(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('students-search')), findsOneWidget);
        expect(find.widgetWithText(OutlinedButton, 'Фильтры'), findsOneWidget);
        expect(find.byKey(const ValueKey('students-create')), findsOneWidget);
        expect(find.byTooltip('Настроить воронку'), findsNothing);
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Фильтры'),
            )
            .onPressed!();
        await tester.pump();
        expect(
          find.byKey(const ValueKey('students-filters-panel')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull, reason: 'viewport $size');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await realtime.close();
      }
    },
  );
}
