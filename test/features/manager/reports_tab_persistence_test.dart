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

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
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

    expect(find.text('Финансовые операции'), findsOneWidget);

    // Move to «Управление» (index 3), as a tab tap would.
    controller.index = 3;
    await tester.pump();
    expect(controller.index, 3);

    // Force a parent rebuild with the SAME initialTab — the realtime-event
    // scenario that used to yank the tab back.
    key.currentState!.bump();
    await tester.pumpAndSettle();

    expect(
      controller.index,
      3,
      reason: 'a rebuild with an unchanged initialTab must not reset the tab',
    );
  });

  testWidgets('financial operations live inside Analytics with one action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [magicApiClientProvider.overrideWithValue(_FakeApiClient())],
        child: const MaterialApp(
          home: Scaffold(body: ReportsWidget(role: 'director', initialTab: 1)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('finance-operations')), findsOneWidget);
    expect(find.byKey(const ValueKey('add-payment')), findsOneWidget);
    expect(find.text('Добавить оплату'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
  });
}
