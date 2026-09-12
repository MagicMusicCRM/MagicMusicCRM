import 'dart:async';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/navigation/entity_route_registry.dart';
import 'package:magic_music_crm/core/widgets/skeletons.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/crm/presentation/client_forms/client_forms_api.dart';
import 'package:magic_music_crm/features/crm/presentation/staff_workspace_screen.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/manager_overview_widget.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/reports_widget.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/clients_widget.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_tasks_view.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_widget.dart';
import 'live_audit_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru'));
  for (final role in ['manager', 'director'])
    testWidgets(
      '$role overview runtime and destinations',
      (tester) async {
        final h = LiveAuditHarness(tester, role, 'overview-runtime');
        await h.initialize(size: const Size(1600, 1400));
        bool fail = false;
        Completer<void>? hold;
        final responses = <Map<String, dynamic>>[];
        h.api.rawDio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (o, handler) async {
              if (o.uri.path.endsWith('/dashboard/manager')) {
                if (hold != null) await hold!.future;
                if (fail) {
                  h.trace(o, 503, error: 'injectedDashboardFailure');
                  handler.reject(
                    DioException(
                      requestOptions: o,
                      type: DioExceptionType.badResponse,
                      response: Response(
                        requestOptions: o,
                        statusCode: 503,
                        data: {'message': 'AUDIT unavailable'},
                      ),
                    ),
                  );
                  return;
                }
              }
              handler.next(o);
            },
            onResponse: (r, handler) {
              if (r.requestOptions.uri.path.endsWith('/dashboard/manager'))
                responses.add(Map<String, dynamic>.from(r.data as Map));
              handler.next(r);
            },
          ),
        );
        Future<void> open({bool wait = true}) async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await h.mount(
            StaffWorkspaceScreen(
              initialLink: EntityRouteRegistry.sectionRootLink('overview'),
            ),
          );
          if (wait) await h.quiet();
        }

        Finder tile(String title) => find
            .ancestor(
              of: find.descendant(
                of: find.byType(ManagerOverviewWidget),
                matching: find.text(title),
              ),
              matching: find.byType(InkWell),
            )
            .first;
        String tileText(String title) => tester
            .widgetList<Text>(
              find.descendant(of: tile(title), matching: find.byType(Text)),
            )
            .map((w) => w.data ?? '')
            .join('|');
        await h.check(
          'LOADING',
          'При задержке API обзор показывает загрузку и затем данные',
          () async {
            hold = Completer<void>();
            await open(wait: false);
            expect(find.byType(DashboardStatsSkeleton), findsOneWidget);
            hold!.complete();
            hold = null;
            await h.quiet();
            expect(find.text('Новые лиды'), findsOneWidget);
          },
        );
        await h.check(
          'ERROR',
          'Недоступный API обзора показывает понятную ошибку и Повторить',
          () async {
            fail = true;
            await open();
            expect(find.text('Повторить'), findsOneWidget);
          },
          expectedHttpErrors: const [
            (
              method: 'GET',
              path: '/api/crm/dashboard/manager',
              status: 503,
              maxCount: 1,
            ),
          ],
        );
        await h.check(
          'RETRY',
          'Повторить загружает обзор после восстановления API',
          () async {
            fail = false;
            await h.tap(find.text('Повторить'));
            await h.quiet();
            expect(find.text('Новые лиды'), findsOneWidget);
          },
        );
        await h.check(
          'REFRESH',
          'Потянуть обзор для обновления после реального создания лида',
          () async {
            final old = tileText('Новые лиды'),
                count = responses.length,
                forms = h.scope.read(clientFormsApiProvider),
                crm = h.scope.read(magicCrmServiceProvider),
                branch = h.fixture['branchId'] as String;
            final sources = await forms.listSources(),
                pipeline = await crm.getClientPipeline(
                  clientType: 'lead',
                  branchId: branch,
                );
            final lead = await forms.createLead(
              identity: MagicMutationIdentity.create('audit.fixture.lead'),
              firstName: 'AUDIT-OVERVIEW',
              lastName: role,
              phone: '+79995556677',
              sourceId: sources.first['id'],
              branchId: branch,
              status: pipeline.activeStages.first.key,
              customFields: [],
            );
            final scroll = find
                .descendant(
                  of: find.byType(ManagerOverviewWidget),
                  matching: find.byType(SingleChildScrollView),
                )
                .first;
            await tester.drag(scroll, const Offset(0, 500));
            await h.waitFor(
              () => responses.length > count,
              'Pull to refresh requested dashboard',
            );
            await h.quiet();
            expect(tileText('Новые лиды'), isNot(old));
            h.facts.add({
              'step': h.currentStep,
              'leadId': lead['id'],
              'before': old,
              'after': tileText('Новые лиды'),
              'dashboard': responses.last,
            });
          },
        );
        final items = [
          ('STUDENTS', 'Активные ученики', 'students'),
          ('LEADS', 'Новые лиды', 'leads'),
          ('TASKS', 'Открытые задачи', 'tasks'),
          ('OVERDUE', 'Просроченные задачи', 'overdue'),
          ('TRIAL', 'Пробные занятия', 'schedule'),
          ('CONFLICTS', 'Конфликты расписания', 'schedule'),
          ('ROOMS', 'Загрузка аудиторий', 'reports'),
          ('STAFF', 'Действия сотрудников', 'reports'),
          if (role == 'director') ...[
            ('REVENUE', 'Выручка', 'reports'),
            ('EXPECTED', 'Ожидаемые платежи', 'reports'),
            ('DEBT', 'Ученики с долгом', 'reports'),
          ],
        ];
        for (final item in items) {
          await h.check(
            'KPI-${item.$1}',
            'Показатель ${item.$2} открывает соответствующую выборку',
            () async {
              await open();
              await h.tap(tile(item.$2));
              await h.quiet();
              switch (item.$3) {
                case 'students':
                  expect(find.byType(ClientsWidget), findsOneWidget);
                  expect(
                    find.byKey(const Key('students-search')),
                    findsOneWidget,
                  );
                  break;
                case 'leads':
                  expect(find.byKey(const Key('leads-search')), findsOneWidget);
                  break;
                case 'tasks':
                case 'overdue':
                  final view = tester.widget<SharedTasksView>(
                    find.byType(SharedTasksView),
                  );
                  expect(
                    view.state.query.state,
                    item.$3 == 'overdue' ? 'overdue' : 'open',
                  );
                  h.facts.add({
                    'step': h.currentStep,
                    'state': view.state.query.state,
                    'day': view.state.query.day?.toIso8601String(),
                  });
                  break;
                case 'schedule':
                  expect(find.byType(ScheduleWidget), findsOneWidget);
                  break;
                case 'reports':
                  expect(find.byType(ReportsWidget), findsOneWidget);
                  break;
              }
            },
          );
        }
        await h.finish();
      },
      timeout: const Timeout(Duration(minutes: 8)),
    );
}
