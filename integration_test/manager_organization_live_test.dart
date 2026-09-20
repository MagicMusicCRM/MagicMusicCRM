import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/manage_entities_widget.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_reference_cards.dart';
import 'live_audit_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Manager organization read scope and denied mutations',
    (tester) async {
      final h = LiveAuditHarness(tester, 'manager', 'manager-org');
      await h.initialize(size: const Size(1440, 1400));
      final crm = h.scope.read(magicCrmServiceProvider);
      final branchId = h.fixture['branchId'] as String;
      final foreignId = h.fixture['foreignBranchId'] as String;
      Future<void> mount(String area) async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await h.mount(
          SystemSettingsRouteScreen(key: UniqueKey(), initialArea: area),
        );
        await h.quiet();
      }

      Future<void> rejected(Future<Object?> Function() call, int status) async {
        try {
          await call();
          fail('Request must be denied');
        } on MagicApiException catch (error) {
          expect(error.statusCode, status);
        }
      }

      await h.check(
        'BRANCH-SCOPE',
        'Управляющий видит только назначенный филиал',
        () async {
          await mount('organization');
          await h.waitFor(
            () => find.text('HTTP test').evaluate().isNotEmpty,
            'Assigned branch shown',
          );
          expect(find.text('MANAGER-FOREIGN'), findsNothing);
          final rows = await crm.listBranches();
          expect(rows.map((r) => r['id']).toList(), [branchId]);
        },
      );
      await h.check(
        'BRANCH-SEARCH',
        'Поиск, пустой результат и очистка фильтра',
        () async {
          final field = find.byWidgetPredicate(
            (w) =>
                w is TextField &&
                w.decoration?.labelText == 'Поиск по названию',
          );
          await h.tap(field);
          await tester.enterText(field, 'нет-такого');
          await tester.pump();
          expect(find.text('Ничего не найдено'), findsOneWidget);
          await h.tap(field);
          await tester.enterText(field, 'http');
          await tester.pump();
          expect(find.text('HTTP test'), findsOneWidget);
          await tester.enterText(field, '');
          await tester.pump();
        },
      );
      await h.check(
        'BRANCH-READONLY',
        'Без выданного права редактирование и lifecycle недоступны',
        () async {
          expect(find.text('Новый филиал'), findsNothing);
          expect(find.text('Показать архив'), findsNothing);
          expect(find.byTooltip('Проверить закрытие'), findsNothing);
          final tile = find.ancestor(
            of: find.text('HTTP test'),
            matching: find.byType(ListTile),
          );
          expect(tester.widget<ListTile>(tile).onTap, isNull);
        },
      );
      await h.check(
        'BRANCH-REFRESH',
        'Кнопка обновления перечитывает разрешённый список',
        () async {
          final before = h.requests.length;
          await h.tap(find.byKey(const ValueKey('refresh-branch-catalog')));
          await h.quiet();
          expect(
            h.requests
                .skip(before)
                .any(
                  (r) =>
                      r['method'] == 'GET' && r['path'] == '/api/crm/branches',
                ),
            true,
          );
          expect(find.text('HTTP test'), findsOneWidget);
        },
      );
      await h.check(
        'ROOM-SCOPE',
        'API аудиторий выдаёт собственные и скрывает чужие',
        () async {
          expect((await crm.listRooms(branchId: branchId)).length, 2);
          expect(await crm.listRooms(branchId: foreignId), isEmpty);
        },
      );
      await h.check(
        'BRANCH-DENY',
        'Прямой PATCH филиала без права изменения отклоняется',
        () async {
          await rejected(
            () => h.api.patch<Map<String, dynamic>>(
              '/crm/branches/$branchId',
              data: {'name': 'MANAGER-FORBIDDEN'},
            ),
            403,
          );
          expect((await crm.listBranches()).single['name'], 'HTTP test');
        },
        expectedHttpErrors: [
          (
            method: 'PATCH',
            path: '/api/crm/branches/$branchId',
            status: 403,
            maxCount: 1,
          ),
        ],
      );
      await h.check(
        'HOURS-READONLY',
        'Часы назначенного филиала доступны только для чтения',
        () async {
          await mount('schedule');
          await h.waitFor(
            () =>
                find.byType(BranchHoursCard).evaluate().isNotEmpty &&
                find.byType(Switch).evaluate().length == 7,
            'Weekly hours rendered',
          );
          await h.quiet();
          expect(
            tester
                .widgetList<Switch>(find.byType(Switch))
                .every((w) => w.onChanged == null),
            true,
          );
          expect(find.text('Сохранить'), findsNothing);
          expect(find.text('Добавить'), findsNothing);
          final hours = await crm.getBranchScheduleHours(branchId);
          h.facts.add({'step': h.currentStep, 'hours': hours});
          expect((hours['weekly'] as List).length, 7);
        },
      );
      await h.check(
        'HOURS-FOREIGN',
        'Прямое чтение часов чужого филиала отклоняется',
        () async {
          await rejected(() => crm.getBranchScheduleHours(foreignId), 404);
        },
        expectedHttpErrors: [
          (
            method: 'GET',
            path: '/api/crm/schedule-reference/branches/$foreignId/hours',
            status: 404,
            maxCount: 1,
          ),
        ],
      );
      await h.check(
        'HOURS-DENY',
        'Прямая запись часов без права изменения отклоняется',
        () async {
          final hours = await crm.getBranchScheduleHours(branchId);
          await rejected(
            () => h.api.put<Map<String, dynamic>>(
              '/crm/schedule-reference/branches/$branchId/hours',
              data: {
                'expectedVersion': hours['version'],
                'timezone': 'Europe/Moscow',
                'weekly': [
                  {'weekday': 1, 'open': '09:00', 'close': '21:00'},
                ],
                'exceptions': [],
              },
            ),
            403,
          );
          expect(
            (await crm.getBranchScheduleHours(branchId))['weekly'],
            hours['weekly'],
          );
        },
        expectedHttpErrors: [
          (
            method: 'PUT',
            path: '/api/crm/schedule-reference/branches/$branchId/hours',
            status: 403,
            maxCount: 1,
          ),
        ],
      );
      await h.finish();
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
