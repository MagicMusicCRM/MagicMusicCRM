import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/update/update_prompt.dart';
import 'package:magic_music_crm/core/update/windows_update_coordinator.dart';
import 'package:magic_music_crm/core/update/windows_update_service.dart';

const _manifest = UpdateManifest(
  buildNumber: 143,
  version: '1.2.2+143',
  url: 'https://example.test/update.zip',
);

void main() {
  testWidgets('global indicator overlays any routed child', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: WindowsUpdateOverlay(
          manifest: _manifest,
          onPressed: _noop,
          child: Scaffold(body: Text('Экран входа')),
        ),
      ),
    );

    expect(find.text('Экран входа'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('windows-update-indicator')),
      findsOneWidget,
    );
    expect(find.text('Обновить 1.2.2+143'), findsOneWidget);
  });

  testWidgets(
    'helper launch failure closes progress and shows recoverable error',
    (tester) async {
      final service = _FailingUpdateService();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () => unawaited(
                  showWindowsUpdateDialog(context, _manifest, service: service),
                ),
                child: const Text('Проверить'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Проверить'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Обновить и перезапустить'));
      await tester.pumpAndSettle();

      expect(service.applyCalls, 1);
      expect(find.text('Загружаем обновление…'), findsNothing);
      expect(find.text('Не удалось запустить обновление'), findsOneWidget);
      expect(find.text('Скачать вручную'), findsOneWidget);

      await tester.tap(find.text('Закрыть'));
      await tester.pumpAndSettle();
      expect(windowsUpdateCoordinator.isBusy, isFalse);
    },
  );

  testWidgets(
    'startup prompt and rapid overlay triggers create one delayed launch',
    (tester) async {
      expect(windowsUpdateCoordinator.isBusy, isFalse);
      final navigatorKey = GlobalKey<NavigatorState>();
      final service = _DelayedUpdateService();
      UpdateManifest? available;
      late StateSetter setHostState;
      late VoidCallback triggerOverlay;

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: StatefulBuilder(
            builder: (context, setState) {
              setHostState = setState;
              return StreamBuilder<bool>(
                stream: windowsUpdateCoordinator.activity,
                initialData: windowsUpdateCoordinator.isBusy,
                builder: (context, activity) {
                  triggerOverlay = () {
                    unawaited(
                      showWindowsUpdateDialog(
                        context,
                        _manifest,
                        service: service,
                      ),
                    );
                  };
                  return WindowsUpdateOverlay(
                    manifest: available,
                    flowActive:
                        activity.data ?? windowsUpdateCoordinator.isBusy,
                    onPressed: triggerOverlay,
                    child: const Scaffold(body: Text('CRM')),
                  );
                },
              );
            },
          ),
        ),
      );

      final startupFlow = checkAndPromptWindowsUpdate(
        navigatorKey: navigatorKey,
        manifestUrl: 'https://example.test/latest.json',
        service: service,
        onUpdateAvailable: (manifest) {
          setHostState(() => available = manifest);
        },
      );
      await tester.pumpAndSettle();

      expect(service.checkCalls, 1);
      expect(windowsUpdateCoordinator.isBusy, isTrue);
      expect(
        find.byKey(const ValueKey('windows-update-indicator')),
        findsNothing,
      );

      triggerOverlay();
      triggerOverlay();
      triggerOverlay();
      await tester.pump();
      expect(service.applyCalls, 0);

      await tester.tap(find.text('Обновить и перезапустить'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(service.applyCalls, 1);

      triggerOverlay();
      triggerOverlay();
      await tester.pump();
      expect(service.applyCalls, 1);
      expect(
        find.byKey(const ValueKey('windows-update-indicator')),
        findsNothing,
      );

      service.release();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Не удалось запустить обновление'), findsOneWidget);

      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      await startupFlow;

      expect(service.applyCalls, 1);
      expect(windowsUpdateCoordinator.isBusy, isFalse);
      expect(
        find.byKey(const ValueKey('windows-update-indicator')),
        findsOneWidget,
      );
    },
  );
}

void _noop() {}

class _FailingUpdateService extends WindowsUpdateService {
  _FailingUpdateService() : super(manifestUrl: '');

  int applyCalls = 0;

  @override
  Future<void> applyAndRestart(UpdateManifest manifest) async {
    applyCalls++;
    throw StateError('blocked');
  }
}

class _DelayedUpdateService extends WindowsUpdateService {
  _DelayedUpdateService() : super(manifestUrl: '');

  final Completer<void> _release = Completer<void>();
  int checkCalls = 0;
  int applyCalls = 0;

  @override
  bool get isSupported => true;

  @override
  Future<UpdateManifest?> check() async {
    checkCalls++;
    return _manifest;
  }

  @override
  Future<void> applyAndRestart(UpdateManifest manifest) async {
    await windowsUpdateCoordinator.runLaunch(() async {
      applyCalls++;
      await _release.future;
      throw StateError('delayed failure');
    });
  }

  void release() {
    if (!_release.isCompleted) _release.complete();
  }
}
