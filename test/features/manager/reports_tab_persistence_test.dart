import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/reports_widget.dart';

/// The reports view must not throw the user out of the sub-tab they're reading.
///
/// Regression: `didUpdateWidget` compared the target tab to the CURRENT tab
/// index instead of to `oldWidget.initialTab`, so any parent rebuild (and
/// MessengerScreen rebuilds on every realtime crm event) forced the tab back to
/// `initialTab`. A director sitting on «Управление» got yanked to «Аналитика»
/// mid-read on every payment/lesson event elsewhere.

class _FakeApiClient extends MagicApiClient {
  _FakeApiClient()
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  final Map<String, Map<String, dynamic>> queries = {};
  final List<String> requests = [];

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    requests.add(path);
    queries[path] = Map<String, dynamic>.from(queryParameters ?? const {});
    return <String, dynamic>{
          'items': <dynamic>[],
          'monthly': <dynamic>[],
          'summary': <String, dynamic>{},
        }
        as T;
  }
}

/// Wrapper that can be forced to rebuild WITHOUT changing initialTab — that is
/// exactly the situation the bug fired on.
class _Rebuildable extends StatefulWidget {
  const _Rebuildable({super.key});
  @override
  State<_Rebuildable> createState() => _RebuildableState();
}

class _RebuildableState extends State<_Rebuildable> {
  int _n = 0;
  void bump() => setState(() => _n++);
  @override
  Widget build(BuildContext context) {
    // _n is read so bump() marks this dirty, but it MUST NOT feed into a key —
    // a changed key would remount ReportsWidget (fresh State + TabController)
    // and never exercise didUpdateWidget. A plain rebuild hands down a new
    // ReportsWidget with the same initialTab → didUpdateWidget, which is the bug
    // path. `SizedBox(height: 0)` keeps _n live without affecting layout.
    return Column(
      children: [
        SizedBox(height: _n * 0.0),
        // NON-const on purpose: each rebuild must hand down a FRESH
        // ReportsWidget so didUpdateWidget actually fires (a const child would
        // be canonicalised and never update — masking the bug). This mirrors
        // MessengerScreen, which builds ReportsWidget inline every rebuild.
        Expanded(
          // ignore: prefer_const_constructors
          child: ReportsWidget(role: 'director', initialTab: 0),
        ),
      ],
    );
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('ru', null));

  testWidgets(
    'teacher settlements is an analytics tab and retains its period',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = _FakeApiClient();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [magicApiClientProvider.overrideWithValue(api)],
          child: const MaterialApp(
            home: Scaffold(body: ReportsWidget(role: 'director')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Расчёты преподавателей'), findsOneWidget);
      expect(find.text('Преподаватели'), findsNothing);
      expect(api.queries.containsKey('/crm/reports/teacher-stats'), isFalse);
      await tester.tap(find.text('Расчёты преподавателей'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('Неделя'), findsOneWidget);
      expect(find.text('Месяц'), findsOneWidget);
      await tester.tap(find.text('Год'));
      await tester.pumpAndSettle();
      final query = api.queries['/crm/reports/teacher-stats']!;
      final from = DateTime.parse(query['from'] as String).toLocal();
      final to = DateTime.parse(query['to'] as String).toLocal();
      expect(from, DateTime(DateTime.now().year));
      expect(to, DateTime(DateTime.now().year + 1));
      final reportCalls = api.requests
          .where((path) => path == '/crm/reports/teacher-stats')
          .length;
      await tester.tap(find.text('Обзор'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Расчёты преподавателей'));
      await tester.pumpAndSettle();
      expect(api.queries['/crm/reports/teacher-stats'], query);
      expect(
        api.requests.where((path) => path == '/crm/reports/teacher-stats'),
        hasLength(reportCalls),
        reason:
            'returning to the section retains its filters and loaded report',
      );
    },
  );

  testWidgets('legacy teacher report link opens the tab and respects access', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _FakeApiClient();
    Widget host(String role) => ProviderScope(
      overrides: [magicApiClientProvider.overrideWithValue(api)],
      child: MaterialApp(
        home: Scaffold(body: ReportsWidget(role: role, initialTab: 5)),
      ),
    );
    await tester.pumpWidget(host('director'));
    await tester.pumpAndSettle();
    expect(find.text('Неделя'), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 2);
    final requestCount = api.requests.length;
    await tester.pumpWidget(host('teacher'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reports-forbidden')), findsOneWidget);
    expect(find.text('Расчёты преподавателей'), findsNothing);
    expect(api.requests, hasLength(requestCount));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a parent rebuild does not reset the selected reports tab', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final key = GlobalKey<_RebuildableState>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [magicApiClientProvider.overrideWithValue(_FakeApiClient())],
        child: MaterialApp(
          home: Scaffold(body: _Rebuildable(key: key)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Hold the reports TabController — it persists across a plain rebuild, so a
    // reset shows up as its index changing under us.
    final controller = tester.widget<TabBar>(find.byType(TabBar)).controller!;
    expect(controller.index, 0);

    expect(find.text('Обзор'), findsOneWidget);
    expect(find.text('Журналы'), findsOneWidget);

    // Move to the operational journals, as a tab tap would.
    controller.index = 1;
    await tester.pump();
    expect(controller.index, 1);

    // Force a parent rebuild with the SAME initialTab — the realtime-event
    // scenario that used to yank the tab back.
    key.currentState!.bump();
    await tester.pumpAndSettle();

    expect(
      controller.index,
      1,
      reason: 'a rebuild with an unchanged initialTab must not reset the tab',
    );
  });

  testWidgets('financial operations live inside Analytics with one action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final api = _FakeApiClient();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [magicApiClientProvider.overrideWithValue(api)],
        child: const MaterialApp(
          home: Scaffold(body: ReportsWidget(role: 'director', initialTab: 1)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('finance-operations')), findsOneWidget);
    expect(find.byKey(const ValueKey('add-payment')), findsNothing);
    expect(
      find.text('Новая оплата проводится в карточке ученика'),
      findsOneWidget,
    );
    expect(find.byType(FloatingActionButton), findsNothing);

    await tester.tap(find.byKey(const ValueKey('analytics-journal-finance')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Действия').last);
    await tester.pumpAndSettle();

    final payments = api.queries['/crm/payments']!;
    final activity = api.queries['/crm/activity']!;
    expect(activity['from'], payments['from']);
    expect(activity['to'], payments['to']);
  });

  testWidgets('analytics fits the system width matrix at 200% text', (
    tester,
  ) async {
    for (final width in const [360.0, 600.0, 840.0, 1000.0, 1200.0]) {
      tester.view.physicalSize = Size(width, 1600);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            magicApiClientProvider.overrideWithValue(_FakeApiClient()),
          ],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: const Scaffold(
              body: ReportsWidget(role: 'director', initialTab: 0),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: 'analytics overflowed at width ${width.toInt()}',
      );
      expect(find.text('Обзор'), findsOneWidget);
    }
    addTearDown(tester.view.reset);
  });
}
