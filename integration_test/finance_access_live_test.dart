import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_token_store_contract.dart';
import 'package:magic_music_crm/core/security/access_management.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/services/access_invalidation_provider.dart';
import 'package:magic_music_crm/core/services/magic_realtime_service.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/client_card.dart';
import 'live_audit_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru'));
  for (final role in [
    'admin',
    'manager',
  ].where((r) => r == Platform.environment['ACCESS_AUDIT_ROLE'])) {
    testWidgets(
      '$role finance permission real UI and HTTP',
      (tester) async {
        final h = LiveAuditHarness(tester, role, 'finance-access');
        await h.initialize(size: const Size(1500, 1200));
        final director = (h.fixture['accounts'] as List)
            .cast<Map<String, dynamic>>()
            .singleWhere((a) => a['role'] == 'director');
        final api = MagicApiClient(
          baseUrl: h.fixture['baseUrl'],
          tokenStore: MemoryMagicTokenStore(),
        );
        addTearDown(() => api.rawDio.close(force: true));
        final login = await api.post<Map<String, dynamic>>(
          '/auth/login',
          authenticated: false,
          data: {'email': director['email'], 'password': h.fixture['password']},
        );
        await api.saveTokens(
          MagicApiTokens.fromJson(
            Map<String, dynamic>.from(login['session'] as Map),
          ),
        );
        final service = MagicAccessManagementService(api),
            before = await h.scope.read(capabilitySnapshotProvider.future),
            student = h.fixture['students'][0] as String,
            endpoint = '/crm/students/$student/commerce';
        final conn = await h.scope.read(magicRealtimeServiceProvider).connect();
        addTearDown(conn.dispose);
        bool connected = false;
        conn.onConnect(() => connected = true);
        conn.connect();
        Future<void> unmount() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }

        Future<void> open() async {
          final row = await h.api.get<Map<String, dynamic>>(
            '/crm/students/$student',
          );
          await h.mount(
            Consumer(
              builder: (context, ref, child) {
                ref.watch(accessInvalidationProvider);
                final access = ref
                    .watch(capabilitySnapshotProvider)
                    .asData
                    ?.value;
                return Scaffold(
                  body: ClientCard(
                    lead: row,
                    entityType: 'student',
                    routed: true,
                    initialSection: 'payments',
                    capabilitySnapshot: access,
                  ),
                );
              },
            ),
          );
          await h.quiet();
        }

        Future<void> change(String effect) async {
          final access = await service.getUserAccess(before.accountId);
          await service.setOverride(
            userId: before.accountId,
            capabilityKey: 'commerce.client_finance.read',
            effect: effect,
            expectedVersion: access.accessVersion,
            emergencySurface: false,
            reasonCode: 'audit.finance_access',
            identity: MagicMutationIdentity.create('audit.finance_access'),
          );
        }

        await h.check(
          'OPEN',
          'Карточка загружает финансы с исходным разрешением',
          () async {
            await open();
            await h.waitFor(() => connected, 'Authenticated socket connected');
            expect(find.byType(ClientCard), findsOneWidget);
            expect(before.allows('commerce.client_finance.read'), true);
            expect(
              h.requests.any(
                (r) => r['path'] == '/api$endpoint' && r['status'] == 200,
              ),
              true,
            );
          },
        );
        await h.check(
          'REVOKE-EVENT',
          'Отзыв финансового разрешения доставляется открытой сессии',
          () async {
            await change('deny');
            await h.waitFor(
              () =>
                  h.scope
                      .read(capabilitySnapshotProvider)
                      .asData
                      ?.value
                      .allows('commerce.client_finance.read') ==
                  false,
              'Finance permission invalidated',
            );
            final current = h.scope
                .read(capabilitySnapshotProvider)
                .asData!
                .value;
            h.facts.add({
              'step': h.currentStep,
              'beforeVersion': before.accessVersion,
              'afterVersion': current.accessVersion,
              'allowed': current.allows('commerce.client_finance.read'),
            });
            await unmount();
          },
          expectedHttpErrors: [
            (method: 'GET', path: '/api$endpoint', status: 403, maxCount: 3),
          ],
        );
        await h.check(
          'DENIED-UI',
          'Повторное открытие скрывает финансы без запрещённого запроса',
          () async {
            final n = h.requests.length;
            await open();
            h.facts.add({
              'step': h.currentStep,
              'paymentControl': find
                  .byKey(const Key('open-payment-form'))
                  .evaluate()
                  .length,
              'subscriptionLabels': find.text('Абонементы').evaluate().length,
              'http': h.requests.skip(n).toList(),
            });
            expect(
              h.requests.skip(n).where((r) => r['path'] == '/api$endpoint'),
              isEmpty,
              reason: 'Hidden finance must not request a forbidden resource',
            );
            expect(find.byKey(const Key('open-payment-form')), findsNothing);
            expect(find.text('Абонементы'), findsNothing);
          },
        );
        await h.check(
          'SERVER-GUARD',
          'Сервер запрещает чтение финансов после отзыва',
          () async {
            await unmount();
            bool denied = false;
            final gate = InterceptorsWrapper(
              onError: (error, next) {
                if (error.requestOptions.uri.path == '/api$endpoint') {
                  denied = error.response?.statusCode == 403;
                }
                next.next(error);
              },
            );
            h.api.rawDio.interceptors.add(gate);
            Object? failure;
            try {
              await h.api.get<Map<String, dynamic>>(endpoint);
            } catch (e) {
              failure = e;
            }
            h.api.rawDio.interceptors.remove(gate);
            h.facts.add({'step': h.currentStep, 'http403': denied});
            expect(failure, isNotNull);
            expect(denied, true);
          },
          expectedHttpErrors: [
            (method: 'GET', path: '/api$endpoint', status: 403, maxCount: 1),
          ],
        );
        // Expected denied-UI behavior is recorded as a finding for this audit.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        h.save();
      },
      timeout: const Timeout(Duration(minutes: 4)),
    );
  }
}
