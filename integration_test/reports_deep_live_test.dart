import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/reports_widget.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/manager_overview_widget.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/reporting_panel.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/reporting_models.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/reporting_data_source.dart';
import 'live_audit_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru'));
  for (final role in ['manager', 'director']) {
    testWidgets(
      '$role reports filters and drilldowns',
      (tester) async {
        final h = LiveAuditHarness(tester, role, 'reports-deep');
        await h.initialize(size: const Size(1550, 1450));
        final access = await h.scope.read(capabilitySnapshotProvider.future);
        final branch = h.fixture['branchId'] as String;
        final queries = <Map<String, dynamic>>[];
        h.api.rawDio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (o, handler) {
              if (o.method == 'GET') {
                queries.add({
                  'path': o.uri.path,
                  'query': Map<String, dynamic>.from(o.queryParameters),
                  'step': h.currentStep,
                });
              }
              handler.next(o);
            },
          ),
        );
        Future<void> reports() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await h.mount(
            Scaffold(
              body: ReportsWidget(role: role, accessSnapshot: access),
            ),
          );
          await h.quiet();
        }

        Map<String, dynamic> lastQuery(String part) =>
            queries.lastWhere((q) => (q['path'] as String).contains(part));
        await h.check('OPEN', 'Открыть общий отчёт', () async {
          await reports();
          expect(find.byKey(const Key('reporting-content')), findsOneWidget);
        });
        await h.check(
          'BRANCH',
          'Фильтр филиала меняет реальные аналитические запросы',
          () async {
            await h.tap(find.byKey(const Key('dashboard-scope')).first);
            await h.tap(find.text('HTTP test').last);
            await h.quiet();
            expect(
              (lastQuery('/client-status')['query'] as Map)['branchId'],
              branch,
            );
          },
        );
        await h.check(
          'PERIOD-CANCEL',
          'Отмена выбора периода сохраняет фильтр',
          () async {
            final before = Map.from(
              lastQuery('/client-status')['query'] as Map,
            );
            await h.tap(find.byKey(const Key('dashboard-period-custom')).first);
            await h.quiet();
            final loc = MaterialLocalizations.of(
              tester.element(find.byType(DateRangePickerDialog)),
            );
            if (find.text(loc.cancelButtonLabel).evaluate().isNotEmpty) {
              await h.tap(find.text(loc.cancelButtonLabel).last);
            } else {
              await h.tap(find.byTooltip(loc.closeButtonTooltip).last);
            }
            await h.quiet();
            expect(lastQuery('/client-status')['query'], before);
          },
        );
        await h.check(
          'JOURNAL',
          'Открыть журнал действий с тем же филиалом',
          () async {
            await h.tap(find.text('Журналы').first);
            await h.quiet();
            expect(
              find.widgetWithText(TextField, 'Поиск действий'),
              findsOneWidget,
            );
            expect(
              (lastQuery('/crm/activity')['query'] as Map)['branchId'],
              branch,
            );
          },
        );
        await h.check(
          'JOURNAL-SEARCH',
          'Поиск действий передаёт строку и показывает пустой результат',
          () async {
            await tester.enterText(
              find.widgetWithText(TextField, 'Поиск действий'),
              'AUDIT-NO-SUCH-ACTION',
            );
            await tester.pump(const Duration(seconds: 1));
            await h.quiet();
            expect(
              (lastQuery('/crm/activity')['query'] as Map)['q'],
              'AUDIT-NO-SUCH-ACTION',
            );
            expect(find.text('Нет действий за период'), findsOneWidget);
          },
        );
        await h.check(
          'JOURNAL-TYPE',
          'Фильтр объекта передаёт student',
          () async {
            await h.tap(find.byKey(const ValueKey('Объект-all')));
            await h.tap(find.text('Ученики').last);
            await h.quiet();
            expect(
              (lastQuery('/crm/activity')['query'] as Map)['entityType'],
              'student',
            );
          },
        );
        await h.check(
          'JOURNAL-RESET',
          'Сброс убирает поиск и тип объекта',
          () async {
            await h.tap(find.text('Сбросить').last);
            await h.quiet();
            final q = lastQuery('/crm/activity')['query'] as Map;
            expect(q['q'] == null || q['q'] == '', isTrue);
            expect(q['entityType'], isNull);
          },
        );
        if (role == 'director') {
          await h.check(
            'FINANCE-JOURNAL',
            'Переключить журнал на финансовые операции',
            () async {
              await h.tap(find.byKey(const Key('analytics-journal-activity')));
              await h.tap(find.text('Финансовые операции').last);
              await h.quiet();
              expect(find.text('Расход'), findsWidgets);
            },
          );
        }
        final now = DateTime.now(),
            filter = DashboardFilter(
              from: DateTime(now.year, 1, 1),
              to: DateTime(now.year, 12, 31),
              branchId: branch,
            );
        EntityLink? opened;
        await h.check(
          'STATUS-DRILLDOWN',
          'Открыть список учеников из статуса и проверить предикат',
          () async {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump();
            await h.mount(
              Scaffold(
                body: ReportingPanel(
                  role: role,
                  filter: filter,
                  accessSnapshot: access,
                  onOpenEntity: (l) => opened = l,
                ),
              ),
            );
            await h.quiet();
            await h.tap(find.text('active').first);
            await h.quiet();
            expect(
              find.byKey(const Key('reporting-drilldown')),
              findsOneWidget,
            );
            final q = lastQuery('/client-status/clients')['query'] as Map;
            expect(q['clientType'], 'student');
            expect(q['status'], 'active');
            expect(q['branchId'], branch);
            expect(find.byType(ListTile), findsWidgets);
          },
        );
        await h.check(
          'ENTITY-LINK',
          'Строка раскрытия передаёт ссылку на существующего ученика',
          () async {
            await h.tap(find.byType(ListTile).first);
            expect(opened, isNotNull);
            expect(
              (h.fixture['students'] as List).contains(opened!.entityId),
              isTrue,
            );
            h.facts.add({
              'step': h.currentStep,
              'entityLink': opened!.toJson(),
            });
          },
        );
        await h.check(
          'LESSON-DRILLDOWN',
          'Возврат и раскрытие успешных занятий сохраняют даты и филиал',
          () async {
            await h.tap(find.text('К отчёту'));
            await h.tap(find.text('Успешно завершённые занятия').first);
            await h.quiet();
            expect(
              find.byKey(const Key('reporting-drilldown')),
              findsOneWidget,
            );
            final q = lastQuery('/lesson-success/lessons')['query'] as Map;
            for (final k in ['from', 'to', 'branchId']) {
              expect(q[k], filter.apiFilter[k]);
            }
            await h.tap(find.text('К отчёту'));
          },
        );
        if (role == 'director') {
          await h.check(
            'FINANCE-NONZERO',
            'Финансовая сводка включает настоящие 5000 ₽ прихода и 2000 ₽ расхода',
            () async {
              final data = await h.scope
                  .read(reportingDataSourceProvider)
                  .loadSchoolFinance(filter);
              h.facts.add({'step': h.currentStep, 'finance': data});
              expect(data['revenueMinor'], '500000');
              expect(data['expensesMinor'], '200000');
            },
          );
        }
        await h.check(
          'OVERVIEW-PERIODS',
          'Обзор переключает 7 дней, месяц и квартал',
          () async {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump();
            await h.mount(Scaffold(body: ManagerOverviewWidget(role: role)));
            await h.quiet();
            for (final label in ['7 дней', 'Месяц', 'Год', 'Период']) {
              await h.tap(find.text(label).first);
              await h.quiet();
            }
            expect(find.text('Активные ученики'), findsWidgets);
          },
        );
        h.facts.add({'step': 'HTTP-QUERIES', 'queries': queries});
        await h.finish();
      },
      timeout: const Timeout(Duration(minutes: 10)),
    );
  }
}
