import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store_contract.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/services/crm_realtime_provider.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/client_card.dart';
import 'package:magic_music_crm/features/crm/presentation/client_forms/client_create_dialogs.dart';

import 'evidence_screenshot.dart';

// Real dialogs, providers, role capabilities and HTTP; only the delivery of one
// committed response is interrupted. A widget harness does not prove menu reachability.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final autosave = Platform.environment['CLIENT_AUDIT_MODE'] == 'autosave';
  for (final role in ['admin', 'manager', 'director']) {
    for (final entity in ['lead', 'student']) {
      testWidgets(
        '$role/$entity ${autosave ? "autosave recovery" : "creation response-loss recovery"}',
        (tester) async {
          final raw = Platform.environment['HTTP_JOURNEY_FIXTURE'];
          expect(
            raw,
            isNotNull,
            reason: 'Run http-journey-check.cjs --client-persistence',
          );
          final fixture = jsonDecode(raw!) as Map<String, dynamic>;
          final uri = Uri.parse(fixture['baseUrl'] as String);
          expect(uri.scheme, 'http');
          expect(uri.host, '127.0.0.1');
          final account = (fixture['accounts'] as List)
              .cast<Map<String, dynamic>>()
              .singleWhere((a) => a['role'] == role);
          final marker = 'AUDIT-$role-$entity';
          final checkpoints = <String>[];
          final retryIds = <String>[];
          final requestKeys = <String>[];
          final responses = <Response<dynamic>>[];
          final resultFile = File(
            '${Platform.environment['EVIDENCE_SCREENSHOT_DIR']}/client-$role-$entity.json',
          );
          void record(String checkpoint) {
            checkpoints.add(checkpoint);
            resultFile.writeAsStringSync(
              jsonEncode({
                'role': role,
                'entity': entity,
                'marker': marker,
                'checkpoints': checkpoints,
                'retryIds': retryIds,
                'requestKeys': requestKeys,
              }),
            );
          }

          addTearDown(() => record('test-finished'));
          await initializeDateFormatting('ru');
          tester.view.physicalSize = const Size(1440, 1100);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final api = MagicApiClient(
            baseUrl: uri.toString(),
            tokenStore: MemoryMagicTokenStore(),
          );
          addTearDown(() => api.rawDio.close(force: true));
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
          final scope = ProviderContainer(
            overrides: [
              magicApiClientProvider.overrideWithValue(api),
              crmRealtimeProvider.overrideWith(
                (ref) => const Stream<CrmChangedEvent>.empty(),
              ),
            ],
          );
          addTearDown(scope.dispose);
          final access = await scope.read(capabilitySnapshotProvider.future);
          expect(access.role, role);
          record('real-role-authenticated');
          final crm = scope.read(magicCrmServiceProvider);
          var loseResponse = false;
          var trackRetry = false;
          var rejectUpdate = false;
          final endpoint = '/crm/${entity}s';
          api.rawDio.interceptors.add(
            InterceptorsWrapper(
              onRequest: (options, handler) {
                if (rejectUpdate &&
                    options.method == 'PATCH' &&
                    options.uri.path.contains('$endpoint/')) {
                  rejectUpdate = false;
                  handler.reject(
                    DioException(
                      requestOptions: options,
                      type: DioExceptionType.connectionError,
                      message: 'Synthetic unavailable connection before PATCH',
                    ),
                  );
                  return;
                }
                if (options.method == 'POST' &&
                    options.uri.path.endsWith(endpoint)) {
                  requestKeys.add(
                    options.headers['Idempotency-Key'].toString(),
                  );
                }
                handler.next(options);
              },
              onResponse: (response, handler) {
                responses.add(response);
                if (trackRetry &&
                    response.requestOptions.method == 'POST' &&
                    response.requestOptions.uri.path.endsWith(endpoint)) {
                  retryIds.add((response.data as Map)['id'].toString());
                  if (loseResponse) {
                    loseResponse = false;
                    handler.reject(
                      DioException(
                        requestOptions: response.requestOptions,
                        type: DioExceptionType.connectionError,
                        message: 'Synthetic response loss after commit',
                      ),
                    );
                    return;
                  }
                }
                handler.next(response);
              },
            ),
          );
          Future<void> waitFor(
            bool Function() ready,
            String description,
          ) async {
            final deadline = DateTime.now().add(const Duration(seconds: 20));
            while (!ready() && DateTime.now().isBefore(deadline)) {
              await tester.pump(const Duration(milliseconds: 100));
            }
            if (!ready()) {
              await captureEvidence(tester, 'client-$role-$entity-failure');
            }
            expect(ready(), isTrue, reason: '$role/$entity: $description');
            expect(tester.takeException(), isNull);
          }

          Future<void> tap(Finder finder) async {
            await waitFor(
              () => finder.evaluate().isNotEmpty,
              'Control exists: $finder',
            );
            if (finder.hitTestable().evaluate().isEmpty) {
              await tester.ensureVisible(finder);
            }
            await tester.pump(const Duration(milliseconds: 200));
            // A transient error SnackBar can cover the footer retry button.
            // Wait for actual pointer reachability instead of tapping through it.
            await waitFor(
              () => finder.hitTestable().evaluate().isNotEmpty,
              'Control is reachable after transient overlays: $finder',
            );
            await tester.tap(finder.hitTestable());
            await tester.pump(const Duration(milliseconds: 300));
          }

          Future<void> show(Widget Function(BuildContext) builder) async {
            await tester.pumpWidget(
              UncontrolledProviderScope(
                container: scope,
                child: RepaintBoundary(
                  key: evidenceRootKey,
                  child: MaterialApp(
                    theme: AppTheme.light,
                    home: Scaffold(body: Builder(builder: builder)),
                  ),
                ),
              ),
            );
            await tester.pump(const Duration(milliseconds: 300));
          }

          Future<Map<String, dynamic>> read(String id) async =>
              entity == 'student'
              ? await crm.getStudent(id)
              : Map<String, dynamic>.from(
                  (await crm.getLeadCard(id))['lead'] as Map,
                );
          Map<String, dynamic>? created;
          Future<void> form(String firstName) async {
            created = null;
            await show(
              (context) => FilledButton(
                onPressed: () async {
                  created = await showDialog<Map<String, dynamic>>(
                    context: context,
                    builder: (_) => entity == 'student'
                        ? StudentCreateDialog(
                            initialBranchId: fixture['branchId'] as String,
                          )
                        : const LeadCreateDialog(),
                  );
                },
                child: const Text('Открыть создание'),
              ),
            );
            await tap(find.text('Открыть создание'));
            await waitFor(
              () => find.byKey(Key('$entity-first-name')).evaluate().isNotEmpty,
              'Metadata loaded',
            );
            final before = requestKeys.length;
            await tap(find.byKey(Key('$entity-submit')));
            expect(find.text('Укажите имя.'), findsOneWidget);
            expect(
              requestKeys.length,
              before,
              reason: 'Invalid form must not POST',
            );
            record('required-fields-block-request');
            await tester.enterText(
              find.byKey(Key('$entity-first-name')),
              firstName,
            );
            await tester.enterText(
              find.byKey(Key('$entity-last-name')),
              marker,
            );
            await tester.enterText(
              find.descendant(
                of: find.byKey(Key('$entity-phone')),
                matching: find.byType(TextField),
              ),
              '9995554433',
            );
            await tap(find.byKey(Key('$entity-source')));
            await tap(find.text('Сайт').last);
          }

          Future<void> card(String id) async {
            final saved = await read(id);
            await show(
              (context) => ClientCard(
                key: UniqueKey(),
                lead: saved,
                entityType: entity,
                routed: true,
                initialSection: 'overview',
                capabilitySnapshot: access,
              ),
            );
            await waitFor(
              () => find
                  .widgetWithText(TextFormField, 'Имя')
                  .evaluate()
                  .isNotEmpty,
              'Card loaded',
            );
            await tester.pump(const Duration(seconds: 1));
          }

          Future<void> editName(String name, {bool failure = false}) async {
            final finder = find.widgetWithText(TextFormField, 'Имя');
            final before = responses
                .where((r) => r.requestOptions.method == 'PATCH')
                .length;
            await tester.enterText(finder, name);
            await tester.pump(const Duration(seconds: 2));
            if (failure) {
              await waitFor(
                () => find
                    .byKey(const Key('client-autosave-retry'))
                    .evaluate()
                    .isNotEmpty,
                'Failed autosave visible',
              );
            } else {
              await waitFor(
                () =>
                    responses
                        .where((r) => r.requestOptions.method == 'PATCH')
                        .length >
                    before,
                'PATCH succeeded',
              );
              await waitFor(
                () => find.text('Сохранено').evaluate().isNotEmpty,
                'Saved UI indicator',
              );
            }
          }

          await form('Создан');
          await tap(find.byKey(Key('$entity-submit')));
          await waitFor(() => created != null, 'Created client returned');
          final id = created!['id'] as String;
          expect((await read(id))['first_name'], 'Создан');
          record('created-readback');
          await card(id);
          await editName('Изменён');
          expect((await read(id))['first_name'], 'Изменён');
          record('autosave-readback');
          await card(id);
          expect(
            tester
                    .widget<TextFormField>(
                      find.widgetWithText(TextFormField, 'Имя'),
                    )
                    .controller
                    ?.text ??
                tester
                    .widget<TextFormField>(
                      find.widgetWithText(TextFormField, 'Имя'),
                    )
                    .initialValue,
            'Изменён',
          );
          record('autosave-reopened');
          if (autosave) {
            rejectUpdate = true;
            await editName('ПослеСбоя', failure: true);
            expect((await read(id))['first_name'], 'Изменён');
            record('failed-autosave-no-write');
            await captureEvidence(
              tester,
              'client-$role-$entity-autosave-before-retry',
            );
            final retry = find.byKey(const Key('client-autosave-retry'));
            debugPrint(
              'AUTOSAVE_CONTROL ${tester.getRect(retry)} VIEW ${tester.view.physicalSize} HIT ${retry.hitTestable().evaluate().length}',
            );
            await tap(retry);
            await waitFor(
              () => find.text('Сохранено').evaluate().isNotEmpty,
              'Retry saved',
            );
            expect((await read(id))['first_name'], 'ПослеСбоя');
            record('autosave-retry-readback');
            await card(id);
            expect(
              tester
                      .widget<TextFormField>(
                        find.widgetWithText(TextFormField, 'Имя'),
                      )
                      .controller
                      ?.text ??
                  tester
                      .widget<TextFormField>(
                        find.widgetWithText(TextFormField, 'Имя'),
                      )
                      .initialValue,
              'ПослеСбоя',
            );
            record('autosave-retry-reopened');
            await tester.pumpWidget(const SizedBox.shrink());
            return;
          }
          await form('Повтор');
          trackRetry = true;
          loseResponse = true;
          await tap(find.byKey(Key('$entity-submit')));
          await waitFor(
            () =>
                retryIds.isNotEmpty &&
                find
                    .textContaining('Проверьте данные и повторите попытку.')
                    .evaluate()
                    .isNotEmpty,
            'Lost committed response keeps form open',
          );
          expect((await read(retryIds.single))['first_name'], 'Повтор');
          expect(
            tester
                .widget<TextField>(find.byKey(Key('$entity-first-name')))
                .controller!
                .text,
            'Повтор',
          );
          record('response-lost-draft-retained');
          await captureEvidence(tester, 'client-$role-$entity-retry');
          await tap(find.byKey(Key('$entity-submit')));
          await waitFor(
            () => created != null,
            'Explicit creation retry completed',
          );
          record('creation-retry-returned');
          expect(
            created!['id'],
            retryIds.first,
            reason: 'A retry must return the original committed client',
          );
          expect(retryIds.toSet(), hasLength(1));
          record('creation-retry-exactly-once');
          await tester.pumpWidget(const SizedBox.shrink());
        },
        timeout: const Timeout(Duration(minutes: 3)),
      );
    }
  }
}
