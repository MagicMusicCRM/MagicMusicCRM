import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:magic_music_crm/core/update/update_center.dart';
import 'package:magic_music_crm/core/update/release_history.dart';
import 'package:magic_music_crm/core/update/windows_update_service.dart';
import 'live_audit_harness.dart';

class AuditBuildService extends WindowsUpdateService {
  AuditBuildService(Dio dio)
    : super(
        manifestUrl: 'https://api.magicmusiccrm.ru/downloads/latest-v2.json',
        dio: dio,
      );
  @override
  int get installedBuild => 220;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('actual updates center transport and offline history', (
    tester,
  ) async {
    final h = LiveAuditHarness(tester, 'director', 'update-center');
    await h.initialize(size: const Size(1400, 1200));
    final historyText = await rootBundle.loadString(releaseHistoryAssetPath),
        history = parseReleaseHistory(
          await rootBundle.loadString(releaseHistoryAssetPath),
        );
    var mode = 'current';
    final requests = <Map<String, dynamic>>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      requests.add({'path': request.uri.path, 'mode': mode});
      request.response.headers.contentType = ContentType.json;
      if (mode == 'offline') {
        request.response.statusCode = 503;
        request.response.write('{}');
      } else if (request.uri.path.endsWith('release-history.json')) {
        request.response.write(mode == 'invalid-history' ? '{}' : historyText);
      } else if (mode == 'invalid') {
        request.response.write(
          '{"buildNumber":221,"version":"invalid","url":"https://untrusted.example.test/app.zip"}',
        );
      } else {
        request.response.write(
          jsonEncode({
            'buildNumber': mode == 'available' ? 221 : 220,
            'version': mode == 'available' ? '1.5.41+221' : '1.5.40+220',
            'url': 'https://api.magicmusiccrm.ru/downloads/audit.zip',
            'sha256': 'a' * 64,
            'notes': 'Синтетический кандидат аудита',
          }),
        );
      }
      await request.response.close();
    });
    final transport = Dio();
    final transportErrors = <String>[];
    addTearDown(() => transport.close(force: true));
    // Preserve product trust checks; route only transport to isolated localhost.
    transport.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, handler) {
          if (o.uri.host != 'api.magicmusiccrm.ru') {
            handler.reject(
              DioException(
                requestOptions: o,
                error: StateError('Unexpected audit transport host'),
              ),
            );
            return;
          }
          o.path = 'http://127.0.0.1:${server.port}${o.uri.path}';
          o.baseUrl = '';
          handler.next(o);
        },
        onError: (error, handler) {
          transportErrors.add(
            '${error.requestOptions.path}: ${error.type.name}; ${error.message}; cause=${error.error}; stack=${error.stackTrace}',
          );
          handler.next(error);
        },
      ),
    );
    final service = AuditBuildService(transport);
    UpdateManifest? installed;
    Future<void> open() async {
      await h.mount(
        Scaffold(
          body: Builder(
            builder: (context) => AppVersionButton(
              versionLoader: () async => const InstalledAppVersion(
                version: '1.5.40+220',
                buildNumber: 220,
              ),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => UpdatesCenterDialog(
                  service: service,
                  historyRepository: ReleaseHistoryRepository(
                    dio: transport,
                    remoteUrl:
                        'https://api.magicmusiccrm.ru/downloads/release-history.json',
                  ),
                  versionLoader: () async => const InstalledAppVersion(
                    version: '1.5.40+220',
                    buildNumber: 220,
                  ),
                  onInstall: (m) async => installed = m,
                ),
              ),
            ),
          ),
        ),
      );
      await h.tap(find.byKey(const ValueKey('app-version-button')));
      await h.waitFor(
        () => find.textContaining(history.first.title).evaluate().isNotEmpty,
        'History rendered',
      );
    }

    Future<void> check(String expected) async {
      await h.tap(find.text('Проверить'));
      await h.waitFor(
        () => find.text(expected).evaluate().isNotEmpty,
        expected,
      );
    }

    await h.check(
      'VERSION-HISTORY',
      'Версия и настоящая история выпусков через HTTP',
      () async {
        await open();
        expect(find.textContaining('1.5.40+220'), findsWidgets);
        expect(
          requests.any(
            (r) => (r['path'] as String).endsWith('release-history.json'),
          ),
          true,
        );
      },
    );
    await h.check('CURRENT', 'Ручная проверка актуальной версии', () async {
      await check('Установлена актуальная версия.');
      expect(find.text('Установить'), findsNothing);
    });
    await h.check('AVAILABLE', 'Обнаружение новой версии', () async {
      mode = 'available';
      await check('Новая версия найдена.');
      expect(find.text('Установить'), findsOneWidget);
    });
    await h.check(
      'DEFER-REOPEN',
      'Закрытие без установки и повторное открытие сохраняют доступное обновление',
      () async {
        await h.tap(find.byTooltip('Закрыть'));
        expect(installed, isNull);
        await open();
        expect(find.text('Установить'), findsOneWidget);
      },
    );
    await h.check(
      'INSTALL-DISPATCH',
      'Кнопка установки передаёт проверенный manifest штатному обработчику',
      () async {
        await h.tap(find.text('Установить'));
        await h.waitFor(() => installed != null, 'Install callback');
        expect(installed!.buildNumber, 221);
        expect(find.byType(UpdatesCenterDialog), findsNothing);
      },
    );
    await h.check(
      'OFFLINE-HISTORY',
      'При недоступной сети история читается из настоящего bundle',
      () async {
        mode = 'offline';
        await open();
        expect(find.textContaining(history.first.title), findsOneWidget);
        await check(
          'Не удалось проверить обновления. Проверьте интернет и повторите.',
        );
      },
    );
    await h.check(
      'RETRY',
      'Повторная проверка после восстановления сети',
      () async {
        mode = 'current';
        await check('Установлена актуальная версия.');
        expect(find.text('Установить'), findsNothing);
      },
    );
    await h.check(
      'INVALID',
      'Некорректный manifest не допускается к установке',
      () async {
        mode = 'invalid';
        await check(
          'Сервер обновлений вернул некорректные данные. Попробуйте позже.',
        );
        expect(find.text('Установить'), findsNothing);
      },
    );
    await h.check(
      'INVALID-HISTORY',
      'Некорректная удалённая история заменяется встроенной',
      () async {
        await h.tap(find.byTooltip('Закрыть'));
        mode = 'invalid-history';
        await open();
        expect(find.textContaining(history.first.title), findsOneWidget);
        await h.tap(find.byTooltip('Закрыть'));
      },
    );
    h.facts.add({
      'transportRequests': requests,
      'transportErrors': transportErrors,
      'historyEndpointTrusted': isTrustedReleaseHistoryEndpoint(
        'https://api.magicmusiccrm.ru/downloads/release-history.json',
      ),
      'installedManifestBuild': installed?.buildNumber,
      'boundaries':
          'Build number is 220; trusted network endpoints route to local server; installation callback recorded separately from OS helper',
    });
    await h.finish();
  });
}
