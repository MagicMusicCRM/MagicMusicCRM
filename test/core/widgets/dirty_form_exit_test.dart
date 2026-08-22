import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/forms/dirty_form_exit.dart';

void main() {
  testWidgets('all exit sources use the same Save Discard Cancel decision', (
    tester,
  ) async {
    var discarded = 0;
    final controller = DirtyFormExitController(
      onSave: () async => true,
      onDiscard: () => discarded++,
    );
    addTearDown(controller.dispose);
    final routeContext = await _openHarness(tester, controller);
    controller.markDirty();
    await tester.pump();

    for (final reason in DirtyFormExitReason.values) {
      final result = controller.requestExit(routeContext, reason: reason);
      await tester.pumpAndSettle();
      expect(find.text('Сохранить изменения?'), findsOneWidget);
      expect(find.text('Сохранить'), findsOneWidget);
      expect(find.text('Не сохранять'), findsOneWidget);
      expect(find.text('Остаться'), findsOneWidget);
      await tester.tap(find.text('Остаться'));
      await tester.pumpAndSettle();
      expect(await result, isFalse);
      expect(find.text('Рабочая форма'), findsOneWidget);
      expect(controller.dirty, isTrue);
    }

    final discard = controller.requestExit(
      routeContext,
      reason: DirtyFormExitReason.tabClose,
      discardedResult: false,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Не сохранять'));
    await tester.pumpAndSettle();
    expect(await discard, isTrue);
    expect(discarded, 1);
    expect(find.text('Источник'), findsOneWidget);
  });

  testWidgets('failed Save keeps errors draft and idempotency metadata', (
    tester,
  ) async {
    var saveSucceeds = false;
    var serverError = '409 version conflict';
    const identity = 'stable-idempotency-key';
    final draft = <String, String>{'name': 'Анна'};
    final controller = DirtyFormExitController(
      onSave: () async {
        if (!saveSucceeds) {
          serverError = 'Сеть недоступна';
          return false;
        }
        return true;
      },
    );
    addTearDown(controller.dispose);
    await _openHarness(tester, controller);
    controller.markDirty();
    await tester.pump();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();

    expect(find.text('Рабочая форма'), findsOneWidget);
    expect(controller.dirty, isTrue);
    expect(serverError, 'Сеть недоступна');
    expect(draft, {'name': 'Анна'});
    expect(identity, 'stable-idempotency-key');

    saveSucceeds = true;
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(find.text('Источник'), findsOneWidget);
    expect(controller.dirty, isFalse);
  });

  testWidgets('busy mutation cannot be dismissed by system Back', (
    tester,
  ) async {
    final controller = DirtyFormExitController(onSave: () async => true);
    addTearDown(controller.dispose);
    await _openHarness(tester, controller);
    controller.markDirty();
    controller.setBusy(true);
    await tester.pump();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Рабочая форма'), findsOneWidget);
    expect(find.text('Сохранить изменения?'), findsNothing);
  });

  test('generic dirty form code does not import workspace', () {
    final source = File(
      'lib/core/forms/dirty_form_exit.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('/workspace/')));
  });
}

Future<BuildContext> _openHarness(
  WidgetTester tester,
  DirtyFormExitController controller,
) async {
  final routeKey = GlobalKey();
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Column(
            children: [
              const Text('Источник'),
              FilledButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => DirtyFormExitScope(
                      controller: controller,
                      savedResult: true,
                      discardedResult: false,
                      child: Scaffold(
                        key: routeKey,
                        body: const Text('Рабочая форма'),
                      ),
                    ),
                  ),
                ),
                child: const Text('Открыть форму'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Открыть форму'));
  await tester.pumpAndSettle();
  return routeKey.currentContext!;
}
