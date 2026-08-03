import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:magic_music_crm/core/navigation/app_back_policy.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/widgets/v7/v7.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('API35 system Back respects overlay route and local order', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.dark, home: const _BackDeviceHome()),
    );

    await tester.tap(find.text('Частичный лист'));
    await tester.pumpAndSettle();
    debugPrint('V6_BACK_PARTIAL_READY');
    await _waitUntilGone(tester, find.text('Частичный лист открыт'));
    expect(find.text('Главная Back QA'), findsOneWidget);

    await tester.tap(find.text('Полный лист'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Развернуть'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Вложенный диалог'));
    await tester.pumpAndSettle();
    debugPrint('V6_BACK_DIALOG_READY');
    await _waitUntilGone(tester, find.text('Диалог поверх листа'));
    expect(find.text('Свернуть'), findsOneWidget);

    debugPrint('V6_BACK_FULL_READY');
    await _waitUntilGone(tester, find.text('Полный лист открыт'));
    expect(find.text('Главная Back QA'), findsOneWidget);

    await tester.tap(find.text('Вложенный маршрут'));
    await tester.pumpAndSettle();
    debugPrint('V6_BACK_ROUTE_READY');
    await _waitUntilGone(tester, find.text('Экран второго уровня'));

    expect(find.text('Локальная история: есть'), findsOneWidget);
    debugPrint('V6_BACK_LOCAL_READY');
    await _waitUntilGone(tester, find.text('Локальная история: есть'));
    expect(find.text('Локальная история: закрыта'), findsOneWidget);
    debugPrint('V6_BACK_DEVICE_PASS');
  });
}

Future<void> _waitUntilGone(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 300; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    if (finder.evaluate().isEmpty) return;
  }
  fail('ADB Back did not dismiss the expected surface.');
}

class _BackDeviceHome extends StatefulWidget {
  const _BackDeviceHome();

  @override
  State<_BackDeviceHome> createState() => _BackDeviceHomeState();
}

class _BackDeviceHomeState extends State<_BackDeviceHome> {
  var _hasLocalHistory = true;

  @override
  Widget build(BuildContext context) {
    return AppBackScope(
      hasLocalHistory: _hasLocalHistory,
      onBack: () => setState(() => _hasLocalHistory = false),
      child: Scaffold(
        appBar: AppBar(title: const Text('Главная Back QA')),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('Локальная история: ${_hasLocalHistory ? 'есть' : 'закрыта'}'),
            FilledButton(
              onPressed: () => _openSheet(context, full: false),
              child: const Text('Частичный лист'),
            ),
            FilledButton(
              onPressed: () => _openSheet(context, full: true),
              child: const Text('Полный лист'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => const _SecondLevel()),
              ),
              child: const Text('Вложенный маршрут'),
            ),
          ],
        ),
      ),
    );
  }

  void _openSheet(BuildContext context, {required bool full}) {
    showMagicSheet<void>(
      context,
      title: full ? 'Полный лист открыт' : 'Частичный лист открыт',
      builder: (sheetContext) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (full)
            FilledButton(
              onPressed: () => showDialog<void>(
                context: sheetContext,
                builder: (_) =>
                    const AlertDialog(title: Text('Диалог поверх листа')),
              ),
              child: const Text('Вложенный диалог'),
            ),
          const SizedBox(height: 600),
        ],
      ),
    );
  }
}

class _SecondLevel extends StatelessWidget {
  const _SecondLevel();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('Экран второго уровня'),
      ),
    );
  }
}
