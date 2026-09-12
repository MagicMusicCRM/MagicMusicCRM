import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store_contract.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/services/crm_realtime_provider.dart';
import 'package:magic_music_crm/core/services/magic_realtime_service.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/widgets/magic_page_state.dart';
import 'package:magic_music_crm/core/workspace/workspace_store.dart';

import 'evidence_screenshot.dart';

/// Local authenticated product runtime. Business API responses and access rights
/// are never mocked. Trace excludes credentials, headers and response bodies.
class LiveAuditHarness {
  LiveAuditHarness(this.tester, this.role, this.suite);
  final WidgetTester tester;
  final String role, suite;
  late final Map<String, dynamic> fixture;
  late final MagicApiClient api;
  late final ProviderContainer scope;
  final steps = <Map<String, dynamic>>[];
  final requests = <Map<String, dynamic>>[];
  final facts = <Map<String, dynamic>>[];
  final pending = <RequestOptions>{};
  String currentStep = 'setup';
  late Map<String, dynamic> access;

  Future<void> initialize({
    Size size = const Size(1280, 900),
    AccountWorkspaceStore? workspaceStore,
  }) async {
    final raw = Platform.environment['HTTP_JOURNEY_FIXTURE'];
    expect(raw, isNotNull, reason: 'Use the isolated HTTP journey runner');
    fixture = jsonDecode(raw!) as Map<String, dynamic>;
    final uri = Uri.parse(fixture['baseUrl'] as String);
    expect(uri.host, '127.0.0.1');
    expect(uri.scheme, 'http');
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    api = MagicApiClient(
      baseUrl: uri.toString(),
      tokenStore: MemoryMagicTokenStore(),
    );
    addTearDown(() => api.rawDio.close(force: true));
    api.rawDio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          options.extra['auditStep'] = currentStep;
          pending.add(options);
          handler.next(options);
        },
        onResponse: (response, handler) {
          trace(response.requestOptions, response.statusCode);
          handler.next(response);
        },
        onError: (error, handler) {
          trace(
            error.requestOptions,
            error.response?.statusCode,
            error: error.type.name,
          );
          handler.next(error);
        },
      ),
    );
    final account = (fixture['accounts'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((account) => account['role'] == role);
    final login = await api.post<Map<String, dynamic>>(
      '/auth/login',
      authenticated: false,
      data: {'email': account['email'], 'password': fixture['password']},
    );
    await api.saveTokens(
      MagicApiTokens.fromJson(
        Map<String, dynamic>.from(login['session'] as Map),
      ),
    );
    final realtime = MagicRealtimeService(api: api, apiBaseUrl: uri.toString());
    addTearDown(realtime.resetSession);
    scope = ProviderContainer(
      overrides: [
        magicApiClientProvider.overrideWithValue(api),
        magicRealtimeServiceProvider.overrideWithValue(realtime),
        accountWorkspaceStoreProvider.overrideWithValue(
          workspaceStore ??
              AccountWorkspaceStore(InMemoryWorkspaceKeyValueStore()),
        ),
        // Push delivery is a separate audit boundary; all loads use real HTTP.
        crmRealtimeProvider.overrideWith(
          (ref) => const Stream<CrmChangedEvent>.empty(),
        ),
      ],
    );
    addTearDown(scope.dispose);
    final snapshot = await scope.read(capabilitySnapshotProvider.future);
    expect(snapshot.role, role);
    access = {
      'role': snapshot.role,
      'capabilities': snapshot.capabilities.toList(),
    };
    addTearDown(save);
  }

  void trace(RequestOptions options, int? status, {String? error}) {
    pending.remove(options);
    requests.add({
      'step': options.extra['auditStep'] ?? currentStep,
      'method': options.method,
      'path': options.uri.path,
      'status': status,
      'error': ?error,
      if (options.method == 'PATCH' && options.data is Map)
        'requestKeys': (options.data as Map).keys.map((key) => '$key').toList(),
    });
  }

  Future<void> mount(Widget child) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: scope,
        child: RepaintBoundary(
          key: evidenceRootKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            home: child,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> waitFor(bool Function() ready, String description) async {
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (!ready() && DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(ready(), isTrue, reason: description);
  }

  Future<void> quiet() async {
    await tester.pump(const Duration(milliseconds: 400));
    await waitFor(() => pending.isEmpty, 'HTTP requests settled');
    await tester.pump(const Duration(milliseconds: 600));
    await waitFor(() => pending.isEmpty, 'Deferred HTTP requests settled');
  }

  Future<void> tap(Finder finder) async {
    await waitFor(
      () => finder.evaluate().isNotEmpty,
      'Control exists: $finder',
    );
    if (finder.hitTestable().evaluate().isEmpty) {
      await tester.ensureVisible(finder.first);
    }
    await waitFor(
      () => finder.hitTestable().evaluate().isNotEmpty,
      'Control is reachable: $finder',
    );
    await tester.tap(finder.hitTestable().first);
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> check(
    String id,
    String description,
    Future<void> Function() work, {
    List<({String method, String path, int status, int maxCount})>
        expectedHttpErrors =
        const [],
  }) async {
    currentStep = id;
    final start = requests.length;
    String? failure;
    try {
      await work();
      await quiet();
      final exception = tester.takeException();
      if (exception != null) throw StateError(exception.toString());
      final errorStates = tester
          .widgetList<MagicPageState>(find.byType(MagicPageState))
          .where(
            (widget) =>
                widget.kind == MagicPageStateKind.error ||
                widget.kind == MagicPageStateKind.forbidden,
          )
          .map((widget) => widget.title ?? widget.kind.name)
          .toList();
      expect(
        errorStates,
        isEmpty,
        reason:
            'An error screen is not a working destination even when HTTP returned 200',
      );
      final failedHttp = requests
          .skip(start)
          .where(
            (request) =>
                request['status'] == null || (request['status'] as int) >= 400,
          )
          .toList();
      for (final expected in expectedHttpErrors) {
        final matching = failedHttp
            .where(
              (r) =>
                  r['method'] == expected.method &&
                  r['path'] == expected.path &&
                  r['status'] == expected.status,
            )
            .toList();
        expect(
          matching.length,
          lessThanOrEqualTo(expected.maxCount),
          reason: 'Expected boundary rejection must not become a request loop',
        );
        failedHttp.removeWhere(matching.contains);
      }
      expect(
        failedHttp,
        isEmpty,
        reason:
            'Visible section must load without rejected or failed HTTP requests',
      );
    } catch (error) {
      failure = error.toString();
      tester.takeException();
    }
    final screenshot = '$suite-$role-$id';
    try {
      await captureEvidence(tester, screenshot);
    } catch (_) {
      /* Preserve text evidence even if rendering failed. */
    }
    steps.add({
      'id': id,
      'description': description,
      'status': failure == null ? 'PASS' : 'FAIL',
      'failure': ?failure,
      'requestStart': start,
      'requestEnd': requests.length,
      if (expectedHttpErrors.isNotEmpty)
        'expectedHttpErrors': expectedHttpErrors
            .map(
              (r) => {
                'method': r.method,
                'path': r.path,
                'status': r.status,
                'maxCount': r.maxCount,
              },
            )
            .toList(),
      'screenshot': '$screenshot.png',
    });
    debugPrint(
      'AUDIT $role $id ${failure == null ? "PASS" : "FAIL: $failure"}',
    );
    save();
  }

  void save() {
    File(
      '${Platform.environment['EVIDENCE_SCREENSHOT_DIR']}/$suite-$role.json',
    ).writeAsStringSync(
      jsonEncode({
        'role': role,
        'suite': suite,
        'access': access,
        'steps': steps,
        'requests': requests,
        'facts': facts,
        'scope':
            'Authenticated product runtime; in-memory token/workspace storage; local HTTP and messenger WebSocket; CRM invalidation stream disabled; local Debug build.',
      }),
    );
  }

  void blocked(String id, String description, String prerequisite) {
    steps.add({
      'id': id,
      'description': description,
      'status': 'BLOCKED',
      'prerequisite': prerequisite,
    });
    save();
  }

  Future<void> finish() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    save();
    expect(
      steps
          .where((step) => step['status'] == 'FAIL')
          .map((step) => step['id'])
          .toList(),
      isEmpty,
      reason:
          'See per-step evidence; independent sections were still checked after failures',
    );
  }
}
