import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_token_store_contract.dart';
import 'package:magic_music_crm/core/services/section_unseen_service.dart';
import 'package:magic_music_crm/features/crm/presentation/staff_workspace_screen.dart';

import 'live_audit_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru'));
  testWidgets('Moscow midnight updates real task list and navigation badge', (
    tester,
  ) async {
    final fixture =
        jsonDecode(Platform.environment['HTTP_JOURNEY_FIXTURE']!) as Map;
    final clockFile = File(fixture['clockFile'] as String);
    DateTime now() => DateTime.fromMillisecondsSinceEpoch(
      (jsonDecode(clockFile.readAsStringSync()) as Map)['ms'] as int,
      isUtc: true,
    );
    final h = LiveAuditHarness(tester, 'admin', 'task-midnight');
    await h.initialize(size: const Size(1440, 1000), dayClock: now);
    final director = (h.fixture['accounts'] as List).cast<Map>().singleWhere(
      (row) => row['role'] == 'director',
    );
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
    final date = now().add(const Duration(hours: 3));
    await h.check(
      'SEED',
      'Две задачи сегодня и три завтра, включая интервальную',
      () async {
        for (final (offset, count) in [(0, 2), (1, 3)]) {
          for (var i = 1; i <= count; i++) {
            final start = DateTime.utc(
              date.year,
              date.month,
              date.day + offset,
              7,
              i,
            );
            await api.post<Map<String, dynamic>>(
              '/crm/shared-tasks',
              data: {
                'title': 'MIDNIGHT-$offset-$i',
                'allDay': i != 3,
                'startAt': start.toIso8601String(),
                if (i == 3)
                  'endAt': start
                      .add(const Duration(hours: 1))
                      .toIso8601String(),
                'audiences': [
                  {'type': 'branch', 'targetId': h.fixture['branchId']},
                ],
              },
            );
          }
        }
        await h.mount(const StaffWorkspaceScreen());
        await h.tap(find.text('Задачи'));
        await h.waitFor(
          () => find.text('MIDNIGHT-0-1').evaluate().isNotEmpty,
          'Today list loaded',
        );
        expect(find.text('MIDNIGHT-1-1'), findsNothing);
        expect((await h.scope.read(sectionUnseenProvider.future))['tasks'], 2);
        expect(find.text('2'), findsWidgets);
      },
    );
    await h.check(
      'ROLLOVER',
      'Список, badge и сервер переходят на новый день без действия пользователя',
      () async {
        final controlDir = h.fixture['controlDir'] as String;
        File('$controlDir/advance').writeAsStringSync('advance');
        await h.waitFor(
          () => File('$controlDir/advanced.json').existsSync(),
          'SQL and API clocks advanced together',
        );
        await tester.pump(const Duration(seconds: 11));
        await h.quiet();
        final server = await h.api.get<Map<String, dynamic>>(
          '/crm/sections/unseen',
        );
        expect(server['tasks'], 3);
        expect(find.text('MIDNIGHT-0-1'), findsNothing);
        expect(find.text('MIDNIGHT-1-1'), findsOneWidget);
        expect((await h.scope.read(sectionUnseenProvider.future))['tasks'], 3);
        expect(find.text('3'), findsWidgets);
        final list = await h.api.get<Map<String, dynamic>>(
          '/crm/shared-tasks?scope=mine&state=open',
        );
        expect((list['counters'] as Map)['today'], 3);
        h.facts.add({
          'step': h.currentStep,
          'sqlAndApiNow': now().toIso8601String(),
          'navigationBadge': 3,
          'serverBadge': server['tasks'],
          'counters': list['counters'],
        });
      },
    );
    await h.check(
      'REOPEN',
      'Повторное открытие читает сохранённые задачи нового дня',
      () async {
        await tester.pumpWidget(const SizedBox.shrink());
        await h.mount(const StaffWorkspaceScreen());
        await h.tap(find.text('Задачи'));
        await h.waitFor(
          () => find.text('MIDNIGHT-1-3').evaluate().isNotEmpty,
          'Interval task retained',
        );
        expect(find.text('MIDNIGHT-0-1'), findsNothing);
        expect(
          (await h.api.get<Map<String, dynamic>>(
            '/crm/sections/unseen',
          ))['tasks'],
          3,
        );
      },
    );
    await h.finish();
  });
}
