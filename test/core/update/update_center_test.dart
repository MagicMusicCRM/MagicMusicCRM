import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/update/release_history.dart';
import 'package:magic_music_crm/core/update/update_center.dart';
import 'package:magic_music_crm/core/update/windows_update_service.dart';

const _installed = InstalledAppVersion(version: '1.5.12+192', buildNumber: 192);

const _available = UpdateManifest(
  buildNumber: 193,
  version: '1.5.13+193',
  url: 'https://api.magicmusiccrm.ru/downloads/app.zip',
  sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  notes: 'Исправлена проверка обновлений.',
);

void main() {
  testWidgets('version button shows a notification dot for a newer build', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppVersionButton(
            hasUpdate: true,
            versionLoader: () async => _installed,
            onPressed: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('app-version-update-dot')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('windows-update-indicator')),
      findsNothing,
    );

    final button = find.byKey(const ValueKey('app-version-button'));
    expect(tester.getSize(button), const Size(68, 48));
    expect(find.byIcon(Icons.info_outline_rounded), findsOneWidget);
    final ink = tester.widget<InkWell>(button);
    expect(ink.borderRadius, BorderRadius.circular(10));

    final buttonRect = tester.getRect(button);
    final dotRect = tester.getRect(
      find.byKey(const ValueKey('app-version-update-dot')),
    );
    expect(dotRect.top, greaterThanOrEqualTo(buttonRect.top));
    expect(dotRect.right, lessThanOrEqualTo(buttonRect.right));
  });

  testWidgets('version button opens full update history and manual check', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var installed = false;
    final service = _AvailableUpdateService();
    final repository = _HistoryRepository();

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Align(
                alignment: Alignment.bottomLeft,
                child: AppVersionButton(
                  versionLoader: () async => _installed,
                  onPressed: () {
                    unawaited(
                      showUpdatesCenter(
                        context,
                        service: service,
                        historyRepository: repository,
                        onInstall: (_) async => installed = true,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1.5.12'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('app-version-button')));
    await tester.pumpAndSettle();

    expect(find.text('Обновления'), findsOneWidget);
    expect(find.text('История версий'), findsOneWidget);
    expect(find.textContaining('1.5.12+192'), findsWidgets);
    expect(find.text('Исправлена важная ошибка.'), findsOneWidget);

    await tester.tap(find.text('Проверить'));
    await tester.pumpAndSettle();

    expect(service.checkCalls, 1);
    expect(find.text('Доступна версия 1.5.13+193'), findsOneWidget);
    expect(find.text('Новая версия найдена.'), findsOneWidget);
    expect(find.text('Установить'), findsOneWidget);

    await tester.tap(find.text('Установить'));
    await tester.pumpAndSettle();
    expect(installed, isTrue);
    expect(find.text('Обновления'), findsNothing);
  });
}

class _AvailableUpdateService extends WindowsUpdateService {
  _AvailableUpdateService() : super(manifestUrl: '');

  int checkCalls = 0;

  @override
  Future<WindowsUpdateCheckResult> checkDetailed() async {
    checkCalls++;
    return const WindowsUpdateCheckResult(
      WindowsUpdateCheckStatus.available,
      manifest: _available,
    );
  }
}

class _HistoryRepository extends ReleaseHistoryRepository {
  _HistoryRepository() : super();

  static const _history = <AppReleaseNote>[
    AppReleaseNote(
      version: '1.5.12+192',
      buildNumber: 192,
      date: '15 августа 2026',
      title: 'Понятный интерфейс',
      summary: 'Интерфейс стал проще.',
      changes: ['Исправлена важная ошибка.'],
    ),
  ];

  @override
  Future<List<AppReleaseNote>> load() async => _history;

  @override
  Future<List<AppReleaseNote>> loadBundled() async => _history;
}
