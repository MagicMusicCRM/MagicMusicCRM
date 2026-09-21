import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/workspace/people_search_action.dart';
import 'package:magic_music_crm/core/widgets/lesson_settlement_corner.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/lesson_settlement_report_dialog.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/staff_detail_dialog.dart';

class _Api extends MagicApiClient {
  _Api()
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());
  final calls = <(String, Map<String, dynamic>)>[];
  Completer<void>? searchGate;
  bool failSearch = false;
  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    calls.add((path, {...?queryParameters}));
    if (const [
      '/crm/clients/search',
      '/crm/teachers',
      '/crm/staff',
    ].contains(path)) {
      if (searchGate != null) await searchGate!.future;
      if (failSearch) throw StateError('Search unavailable');
    }
    if (path == '/crm/clients/search') {
      return {
            'items': [
              {
                'ref': {'type': 'lead', 'id': 'lead'},
                'label': 'Анна',
                'links': [
                  {
                    'rel': 'convertedStudent',
                    'ref': {'type': 'student', 'id': 'student'},
                  },
                ],
              },
              {
                'ref': {'type': 'student', 'id': 'student'},
                'label': 'Анна',
                'links': [],
              },
            ],
          }
          as T;
    }
    if (path == '/crm/teachers') {
      return {
            'items': [
              {'id': 'teacher', 'firstName': 'Андрей', 'lastName': 'Учитель'},
            ],
          }
          as T;
    }
    if (path == '/crm/staff') {
      return {
            'items': [
              {
                'id': 'staff',
                'firstName': 'Антон',
                'lastName': 'Администратор',
                'role': 'admin',
              },
            ],
          }
          as T;
    }
    if (path == '/crm/configuration/lesson-decisions') {
      return {
            'settlementTypes': [
              {
                'stableKey': 'trial_lesson',
                'label': 'Пробный урок',
                'order': 7,
                'allowedContexts': ['settle'],
              },
            ],
            'teacherCompensationRules': [
              {
                'stableKey': 'trial_lesson',
                'label': 'Пробный урок — без оплаты',
                'order': 5,
              },
            ],
          }
          as T;
    }
    return {'items': []} as T;
  }
}

Widget _host(
  _Api api,
  Widget child, {
  Set<String> capabilities = const {
    'crm.client.read.basic',
    'schedule.lesson.read.assigned',
  },
}) => ProviderScope(
  overrides: [
    magicCrmServiceProvider.overrideWithValue(MagicCrmService(api)),
    capabilitySnapshotProvider.overrideWith(
      (ref) async => CapabilitySnapshot(
        accountId: 'admin',
        role: 'admin',
        accessVersion: 1,
        capabilities: capabilities,
        scopes: const {},
      ),
    ),
  ],
  child: MaterialApp(theme: AppTheme.production, home: Scaffold(body: child)),
);

void main() {
  testWidgets(
    'desktop search opens the existing staff card and dismisses results',
    (tester) async {
      final api = _Api();
      await tester.pumpWidget(
        _host(
          api,
          const Align(
            alignment: Alignment.topRight,
            child: SizedBox(
              width: 300,
              child: PeopleSearchAction(inline: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Ан');
      await tester.pumpAndSettle(const Duration(milliseconds: 350));
      await tester.tap(find.text('Антон Администратор'));
      await tester.pumpAndSettle();
      expect(find.byType(StaffDetailDialog), findsOneWidget);
      expect(find.byKey(const ValueKey('people-search-results')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  Widget inlineHost(_Api api, {Set<String>? capabilities}) => _host(
    api,
    const Align(
      alignment: Alignment.topRight,
      child: SizedBox(width: 300, child: PeopleSearchAction(inline: true)),
    ),
    capabilities: capabilities ?? const {'crm.client.read.basic'},
  );

  testWidgets(
    'desktop search accepts typing directly and closes on Escape and outside click',
    (tester) async {
      final api = _Api();
      await tester.pumpWidget(inlineHost(api));
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('global-people-search-field'));
      expect(field, findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(field);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
      await tester.enterText(field, 'А');
      await tester.pump(const Duration(milliseconds: 400));
      expect(api.calls, isEmpty);
      await tester.enterText(field, 'Ан');
      await tester.pumpAndSettle(const Duration(milliseconds: 350));
      expect(api.calls, hasLength(3));
      expect(find.text('Анна'), findsOneWidget);
      expect(find.text('Андрей Учитель'), findsOneWidget);
      expect(find.text('Антон Администратор'), findsOneWidget);
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('people-search-results')), findsNothing);
      await tester.tap(field);
      await tester.pumpAndSettle();
      expect(find.text('Анна'), findsOneWidget);
      await tester.tapAt(const Offset(30, 450));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('people-search-results')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('clearing desktop query ignores a late response', (tester) async {
    final api = _Api()..searchGate = Completer<void>();
    await tester.pumpWidget(inlineHost(api));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Ан');
    await tester.pump(const Duration(milliseconds: 350));
    expect(api.calls, hasLength(3));
    await tester.tap(find.byTooltip('Очистить поиск'));
    await tester.pump();
    api.searchGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Анна'), findsNothing);
    expect(find.text('Введите минимум 2 символа'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop search error can retry without leaving the header', (
    tester,
  ) async {
    final api = _Api()..failSearch = true;
    await tester.pumpWidget(inlineHost(api));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Ан');
    await tester.pumpAndSettle(const Duration(milliseconds: 350));
    expect(find.text('Повторить'), findsOneWidget);
    api.failSearch = false;
    await tester.tap(find.text('Повторить'));
    await tester.pumpAndSettle(const Duration(milliseconds: 350));
    expect(find.text('Анна'), findsOneWidget);
    expect(api.calls, hasLength(6));
  });

  testWidgets(
    'desktop search without capability is hidden and never requests',
    (tester) async {
      final api = _Api();
      await tester.pumpWidget(inlineHost(api, capabilities: const {}));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(api.calls, isEmpty);
    },
  );

  testWidgets(
    'search is debounced, includes staff and collapses converted leads',
    (tester) async {
      final api = _Api();
      await tester.pumpWidget(_host(api, const PeopleSearchAction()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('global-people-search')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'А');
      await tester.pump(const Duration(milliseconds: 400));
      expect(api.calls, isEmpty);
      await tester.enterText(find.byType(TextField), 'Ан');
      await tester.pump(const Duration(milliseconds: 299));
      expect(api.calls, isEmpty);
      await tester.pumpAndSettle(const Duration(milliseconds: 301));
      expect(api.calls, hasLength(3));
      expect(find.text('Анна'), findsOneWidget);
      expect(find.text('Ученик'), findsOneWidget);
      expect(find.text('Лид'), findsNothing);
      expect(find.text('Андрей Учитель'), findsOneWidget);
      expect(find.text('Антон Администратор'), findsOneWidget);
    },
  );
  testWidgets('search without capability is hidden and does not request data', (
    tester,
  ) async {
    final api = _Api();
    await tester.pumpWidget(
      _host(api, const PeopleSearchAction(), capabilities: const {}),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('global-people-search')), findsNothing);
    expect(api.calls, isEmpty);
  });
  testWidgets(
    'teacher lesson report sends the selected rule, period and branch',
    (tester) async {
      final api = _Api();
      // Resolve access before mounting the report, as in the actual action.
      await tester.pumpWidget(
        _host(
          api,
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showLessonSettlementReport(
                context,
                from: DateTime(2026, 9, 1),
                to: DateTime(2026, 10, 1),
                branchId: 'branch',
                teacherId: 'teacher',
                initialType: 'trial_lesson',
                teacherPayments: true,
              ),
              child: const Text('Открыть'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Открыть'));
      await tester.pumpAndSettle();
      final request = api.calls
          .where((call) => call.$1 == '/crm/lessons')
          .single
          .$2;
      expect(request, containsPair('compensationRuleKey', 'trial_lesson'));
      expect(request, containsPair('branchId', 'branch'));
      expect(request, containsPair('includeClosed', true));
      expect(request.containsKey('settlementTypeKey'), isFalse);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('settlement background contains date on a 39 by 40 tile', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 39,
            height: 40,
            child: LessonSettlementCorner(
              settlementTypeKey: 'trial_lesson',
              timeline: true,
              child: Center(
                child: Text('30.09', style: TextStyle(fontSize: 9)),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('settlement-background-trial_lesson')),
      findsOneWidget,
    );
    expect(LessonSettlementCorner.colorFor(null), isNull);
    expect(LessonSettlementCorner.colorFor('lesson'), isNotNull);
    expect(LessonSettlementCorner.colorFor('unknown'), isNotNull);
    final date = tester.getRect(find.text('30.09'));
    final corner = tester.getRect(
      find.byKey(const ValueKey('settlement-background-trial_lesson')),
    );
    expect(corner.contains(date.center), isTrue);
  });
}
