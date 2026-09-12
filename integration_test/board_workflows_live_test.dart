import 'dart:ui' show PointerDeviceKind;
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/navigation/entity_route_registry.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/crm/presentation/client_forms/client_forms_api.dart';
import 'package:magic_music_crm/features/crm/presentation/staff_workspace_screen.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/students_board_columns.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/students_board_card.dart';
import 'live_audit_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru'));
  for (final role in ['admin', 'manager', 'director']) {
    testWidgets(
      '$role client board filters and drag status',
      (tester) async {
        final h = LiveAuditHarness(tester, role, 'board-workflows');
        await h.initialize(size: const Size(1800, 1400));
        final crm = h.scope.read(magicCrmServiceProvider),
            forms = h.scope.read(clientFormsApiProvider),
            branch = h.fixture['branchId'] as String;
        final source = (await forms.listSources()).first['id'] as String,
            people = await crm.listResponsibleStaff(),
            stages = await crm.listLeadStatuses(limit: 100);
        final pipeline = await crm.getClientPipeline(
              clientType: 'lead',
              branchId: branch,
            ),
            studentPipeline = await crm.getClientPipeline(
              clientType: 'student',
              branchId: branch,
            );
        final lead = await forms.createLead(
          identity: MagicMutationIdentity.create('audit.fixture.lead'),
          firstName: 'AUDIT-BOARD-$role-A',
          lastName: 'Тест',
          phone: '+79992221111',
          sourceId: source,
          branchId: branch,
          status: pipeline.activeStages.first.key,
          customFields: [],
        );
        final other = await forms.createLead(
          identity: MagicMutationIdentity.create('audit.fixture.lead'),
          firstName: 'AUDIT-BOARD-$role-B',
          lastName: 'Тест',
          phone: '+79992222222',
          sourceId: source,
          branchId: branch,
          status: pipeline.activeStages.first.key,
          customFields: [],
        );
        await h.api.patch<Map<String, dynamic>>(
          '/crm/leads/${lead['id']}',
          data: {
            'assignedTo': people[0]['id'],
            'expectedVersion': lead['version'],
          },
        );
        await h.api.patch<Map<String, dynamic>>(
          '/crm/leads/${other['id']}',
          data: {
            'assignedTo': people[1]['id'],
            'expectedVersion': other['version'],
          },
        );
        final student = await forms.createStudent(
          identity: MagicMutationIdentity.create('audit.fixture.student'),
          firstName: 'AUDIT-BOARD-STUDENT-$role',
          lastName: 'Тест',
          phone: '+79992223333',
          sourceId: source,
          branchId: branch,
          status: studentPipeline.activeStages.first.key,
          customFields: [],
        );
        final query = <Map<String, dynamic>>[];
        h.api.rawDio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (o, handler) {
              if (o.method == 'GET' && o.uri.path.endsWith('/leads/board'))
                query.add(Map<String, dynamic>.from(o.queryParameters));
              handler.next(o);
            },
          ),
        );
        Finder key(String v) => find.byKey(ValueKey(v));
        Future<void> open() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await h.mount(
            StaffWorkspaceScreen(
              initialLink: EntityRouteRegistry.sectionRootLink('clients'),
            ),
          );
          await h.quiet();
        }

        Future<void> search(String k, String text) async {
          await h.tap(key(k));
          await tester.enterText(key(k), text);
          await tester.pump(const Duration(milliseconds: 500));
          await h.quiet();
        }

        Future<void> dropdown(String label, String value) async {
          final f = find.byWidgetPredicate(
            (w) =>
                w is DropdownButtonFormField<String> &&
                (w.key as ValueKey?)?.value.toString().startsWith('$label:') ==
                    true,
          );
          await h.tap(f);
          await h.tap(find.text(value).last);
          await h.quiet();
        }

        Future<void> drag(Finder source, Finder target) async {
          await tester.ensureVisible(source);
          await tester.ensureVisible(target);
          await tester.pump();
          final gesture = await tester.startGesture(
            tester.getCenter(source),
            kind: PointerDeviceKind.mouse,
          );
          await gesture.moveBy(const Offset(14, 0));
          await tester.pump(const Duration(milliseconds: 100));
          await gesture.moveTo(
            tester.getTopLeft(target) + const Offset(150, 140),
          );
          await tester.pump(const Duration(milliseconds: 400));
          await gesture.up();
          await h.quiet();
        }

        await h.check('OPEN', 'Два новых лида видны в доске', () async {
          await open();
          await search('leads-search', 'AUDIT-BOARD-$role');
          expect(find.text('AUDIT-BOARD-$role-A Тест'), findsOneWidget);
          expect(find.text('AUDIT-BOARD-$role-B Тест'), findsOneWidget);
          await h.tap(find.text('Фильтры'));
        });
        await h.check(
          'RESPONSIBLE',
          'Ответственный фильтрует реальную выборку и исключает другого лида',
          () async {
            await dropdown('Ответственный', people[0]['name']);
            expect(query.last['assignedTo'], people[0]['id']);
            expect(find.text('AUDIT-BOARD-$role-A Тест'), findsOneWidget);
            expect(find.text('AUDIT-BOARD-$role-B Тест'), findsNothing);
            await dropdown('Ответственный', 'Все');
          },
        );
        final initialLead = Map<String, dynamic>.from(
          (await crm.getLeadCard(lead['id']))['lead'] as Map,
        );
        final initialStatus =
            initialLead['status_id'] ??
            initialLead['statusId'] ??
            initialLead['status'];
        final target = stages.firstWhere(
          (s) =>
              s['key'] != initialStatus &&
              s['key'] != 'unassigned' &&
              s['requiresReason'] != true &&
              s['terminal'] != true,
        );
        await h.check(
          'STATUS',
          'Фильтр статуса исключает лидов других колонок и сбрасывается',
          () async {
            await dropdown('Статус', target['label']);
            expect(query.last['statusId'], target['key']);
            expect(find.text('AUDIT-BOARD-$role-A Тест'), findsNothing);
            await dropdown('Статус', 'Все');
            expect(find.text('AUDIT-BOARD-$role-A Тест'), findsOneWidget);
          },
        );
        await h.check(
          'PERIOD',
          'Период обращения передаёт точные границы дня и очищается',
          () async {
            await h.tap(key('lead-filter-period'));
            final d = find.byType(DateRangePickerDialog),
                loc = MaterialLocalizations.of(tester.element(d));
            await h.tap(find.byTooltip(loc.inputDateModeButtonLabel));
            final fields = find.descendant(
              of: d,
              matching: find.byType(TextField),
            );
            final date = DateTime.now();
            for (var i = 0; i < 2; i++) {
              await h.tap(fields.at(i));
              await tester.enterText(fields.at(i), loc.formatCompactDate(date));
            }
            await h.tap(find.text(loc.okButtonLabel).last);
            await h.quiet();
            expect(
              DateTime.parse(query.last['from']),
              DateTime(date.year, date.month, date.day).toUtc(),
            );
            expect(
              DateTime.parse(query.last['to']),
              DateTime(date.year, date.month, date.day + 1).toUtc(),
            );
            expect(find.text('AUDIT-BOARD-$role-A Тест'), findsOneWidget);
            await h.tap(key('lead-filter-period-clear'));
            await h.quiet();
            expect(query.last['from'], isNull);
            await h.tap(find.text('Свернуть'));
          },
        );
        await h.check(
          'LEAD-DRAG',
          'Перетащить лида в другую колонку и проверить сохранённый статус',
          () async {
            final s = find.byWidgetPredicate(
              (w) =>
                  w is Draggable<({String id, int version})> &&
                  w.data?.id == lead['id'],
            );
            final t = find.ancestor(
              of: find.text(target['label']).first,
              matching: find.byType(DragTarget<({String id, int version})>),
            );
            await drag(s, t);
            final row = Map<String, dynamic>.from(
              (await crm.getLeadCard(lead['id']))['lead'] as Map,
            );
            h.facts.add({
              'step': h.currentStep,
              'id': lead['id'],
              'target': target,
              'row': row,
            });
            expect(
              row['status_id'] ?? row['statusId'] ?? row['status'],
              target['key'],
            );
          },
        );
        await h.check(
          'LEAD-REOPEN',
          'После открытия заново лид находится в выбранной колонке',
          () async {
            await open();
            await search('leads-search', 'AUDIT-BOARD-$role-A');
            final t = find.ancestor(
              of: find.text(target['label']).first,
              matching: find.byType(DragTarget<({String id, int version})>),
            );
            expect(
              find.descendant(
                of: t,
                matching: find.text('AUDIT-BOARD-$role-A Тест'),
              ),
              findsOneWidget,
            );
          },
        );
        final old = studentPipeline.activeStages.first;
        final next = studentPipeline.activeStages.firstWhere(
          (s) =>
              s.key != old.key &&
              !s.requiresReason &&
              !s.terminal &&
              (old.allowedTransitions.isEmpty ||
                  old.allowedTransitions.contains(s.key)),
        );
        await h.check(
          'STUDENT-DRAG',
          'Перетащить ученика в разрешённый статус',
          () async {
            await open();
            await h.tap(find.text('Ученики').first);
            await h.quiet();
            await search('students-search', 'AUDIT-BOARD-STUDENT-$role');
            final s = find.byWidgetPredicate(
              (w) => w is StudentBoardCard && w.student['id'] == student['id'],
            );
            final t = find.byWidgetPredicate(
              (w) => w is StudentStatusColumn && w.column.status == next.key,
            );
            await drag(s, t);
            final row = await crm.getStudent(student['id']);
            h.facts.add({
              'step': h.currentStep,
              'id': student['id'],
              'target': next.key,
              'row': row,
            });
            expect(row['status'], next.key);
          },
        );
        await h.check(
          'STUDENT-REOPEN',
          'Статус ученика сохраняется при повторном открытии доски',
          () async {
            await open();
            await h.tap(find.text('Ученики').first);
            await h.quiet();
            await search('students-search', 'AUDIT-BOARD-STUDENT-$role');
            final t = find.byWidgetPredicate(
              (w) => w is StudentStatusColumn && w.column.status == next.key,
            );
            expect(
              find.descendant(
                of: t,
                matching: find.text('AUDIT-BOARD-STUDENT-$role Тест'),
              ),
              findsOneWidget,
            );
          },
        );
        h.facts.add({
          'leadId': lead['id'],
          'otherLeadId': other['id'],
          'studentId': student['id'],
        });
        await h.finish();
      },
      timeout: const Timeout(Duration(minutes: 6)),
    );
  }
}
