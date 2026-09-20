import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/manage_entities_widget.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/reference_catalog_settings.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/reference_catalog_lifecycle_dialog.dart';

import 'live_audit_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final role in ['director', 'manager']) {
    testWidgets(
      '$role reference catalogs save and lifecycle',
      (tester) async {
        final h = LiveAuditHarness(tester, role, 'reference');
        await h.initialize(size: const Size(1440, 1200));
        final crm = h.scope.read(magicCrmServiceProvider);
        Future<void> input(Finder field, String value) async {
          await h.tap(field);
          await tester.enterText(field, value);
          await tester.pump();
        }

        await h.check('OPEN', 'Настройки организации → Справочники', () async {
          await h.mount(
            const SystemSettingsRouteScreen(initialArea: 'organization'),
          );
          await h.waitFor(
            () => find.text('Справочники').evaluate().isNotEmpty,
            'Organization settings loaded',
          );
          await h.tap(find.text('Справочники'));
          await h.waitFor(
            () => find.byType(ReferenceCatalogSettings).evaluate().isNotEmpty,
            'Reference catalog opened',
          );
          await h.quiet();
        });
        for (final type in ['discipline', 'loss_reason']) {
          h.currentStep = '$type-setup';
          final archiveFilter = find.widgetWithText(
            FilterChip,
            'Показать архив',
          );
          if (tester.widget<FilterChip>(archiveFilter).selected) {
            await h.tap(archiveFilter);
            await h.quiet();
          }
          final initialName = 'REFERENCE-$type';
          final renamed = '$initialName-UPDATED';
          String? id;
          var restored = false;
          Future<List<Map<String, dynamic>>> rows({bool archived = false}) =>
              type == 'discipline'
              ? crm.listDisciplines(includeArchived: archived)
              : crm.listLossReasons(includeArchived: archived);
          Future<Map<String, dynamic>> row() async {
            final value = (await rows(
              archived: role == 'director',
            )).singleWhere((r) => r['id'] == id);
            h.facts.add({
              'step': h.currentStep,
              'entityType': type,
              'entity': value,
            });
            return value;
          }

          Future<void> lifecycle() async {
            await h.tap(find.byKey(ValueKey('reference-$id')));
            await h.waitFor(
              () => find
                  .byKey(const ValueKey('reference-reason-field'))
                  .evaluate()
                  .isNotEmpty,
              'Lifecycle preview loaded',
            );
            await h.quiet();
          }

          if (type == 'loss_reason') await h.tap(find.text('Причины отказа'));
          if (role == 'manager') {
            await h.check(
              '$type-READONLY',
              'Управляющий читает $type без изменения и архива',
              () async {
                final item = (await rows()).singleWhere(
                  (r) => r['name'] == 'REFERENCE-READONLY-$type',
                );
                expect(find.text('REFERENCE-READONLY-$type'), findsOneWidget);
                expect(
                  find.byKey(const ValueKey('create-reference-button')),
                  findsNothing,
                );
                expect(
                  tester
                      .widget<FilterChip>(
                        find.widgetWithText(FilterChip, 'Показать архив'),
                      )
                      .onSelected,
                  isNull,
                );
                expect(
                  tester
                      .widget<ListTile>(
                        find.byKey(ValueKey('reference-${item['id']}')),
                      )
                      .onTap,
                  isNull,
                );
              },
            );
            continue;
          }
          await h.check(
            '$type-CANCEL',
            'Отмена создания $type не сохраняет запись',
            () async {
              await h.tap(
                find.byKey(const ValueKey('create-reference-button')),
              );
              await input(
                find.byKey(const ValueKey('new-reference-name-field')),
                '$initialName-CANCEL',
              );
              await h.tap(find.widgetWithText(TextButton, 'Отмена'));
              expect(
                (await rows()).any((r) => r['name'] == '$initialName-CANCEL'),
                isFalse,
              );
            },
          );
          await h.check(
            '$type-CREATE',
            'Валидация пустого названия и создание $type',
            () async {
              await h.tap(
                find.byKey(const ValueKey('create-reference-button')),
              );
              await h.tap(
                find.byKey(const ValueKey('submit-reference-button')),
              );
              expect(find.text('Введите название.'), findsOneWidget);
              await input(
                find.byKey(const ValueKey('new-reference-name-field')),
                initialName,
              );
              if (type == 'loss_reason') {
                await h.tap(
                  find.widgetWithText(DropdownButtonFormField<String>, 'Тип'),
                );
                await h.tap(find.text('Пауза').last);
              }
              await h.tap(
                find.byKey(const ValueKey('submit-reference-button')),
              );
              await h.quiet();
              final value = (await rows()).singleWhere(
                (r) => r['name'] == initialName,
              );
              id = value['id'] as String;
              expect(find.text(initialName), findsOneWidget);
              if (type == 'loss_reason') expect(value['kind'], 'paused');
              await row();
            },
          );
          if (id == null) {
            h.blocked(
              '$type-LIFECYCLE',
              'Жизненный цикл справочника',
              'No created entity',
            );
            continue;
          }
          await h.check(
            '$type-SEARCH',
            'Поиск $type без учёта регистра и очистка фильтра',
            () async {
              final search = find.widgetWithText(
                TextField,
                'Поиск по справочнику',
              );
              await input(search, initialName.toLowerCase());
              expect(find.text(initialName), findsOneWidget);
              await input(search, 'NO-MATCH-AUDIT');
              expect(find.text(initialName), findsNothing);
              expect(
                find.text('В справочнике пока нет записей.'),
                findsOneWidget,
              );
              await input(search, '');
              expect(find.text(initialName), findsOneWidget);
            },
          );
          await h.check(
            '$type-REASON',
            'Preview и обязательная причина изменения $type',
            () async {
              await lifecycle();
              await input(
                find.byKey(const ValueKey('reference-name-field')),
                renamed,
              );
              final before = h.requests.length;
              await h.tap(
                find.byKey(const ValueKey('rename-reference-button')),
              );
              expect(
                find.text('Укажите понятную причину (минимум 3 символа).'),
                findsOneWidget,
              );
              expect(
                h.requests.skip(before).where((r) => r['method'] != 'GET'),
                isEmpty,
              );
            },
          );
          await h.check(
            '$type-RENAME',
            'Переименовать $type и проверить серверную историю',
            () async {
              await input(
                find.byKey(const ValueKey('reference-reason-field')),
                'REFERENCE-RENAME',
              );
              await h.tap(
                find.byKey(const ValueKey('rename-reference-button')),
              );
              await h.quiet();
              expect((await row())['name'], renamed);
              final history = await crm.listReferenceCatalogHistory(
                entityType: type,
                id: id!,
              );
              h.facts.add({'step': h.currentStep, 'history': history});
              expect(history.any((r) => r['operation'] == 'rename'), isTrue);
            },
          );
          await h.check(
            '$type-CLOSE-REFRESH',
            'Закрытие редактора показывает новое название $type в списке',
            () async {
              await h.tap(find.widgetWithText(TextButton, 'Закрыть'));
              await h.quiet();
              expect(
                find.byType(ReferenceCatalogLifecycleDialog),
                findsNothing,
              );
              expect(find.text(renamed), findsOneWidget);
              expect(find.text(initialName), findsNothing);
            },
          );
          await h.check(
            '$type-ARCHIVE-CANCEL',
            'Закрытие preview не архивирует $type',
            () async {
              await lifecycle();
              await input(
                find.byKey(const ValueKey('reference-reason-field')),
                'REFERENCE-NO-COMMIT',
              );
              await h.tap(find.widgetWithText(TextButton, 'Закрыть'));
              final value = await row();
              expect(
                value['lifecycleState'] ?? value['lifecycle_state'],
                'active',
              );
            },
          );
          await h.check(
            '$type-ARCHIVE',
            'Архивировать $type с причиной и обновить активный список',
            () async {
              await lifecycle();
              await input(
                find.byKey(const ValueKey('reference-reason-field')),
                'REFERENCE-ARCHIVE',
              );
              await h.tap(
                find.byKey(const ValueKey('reference-lifecycle-button')),
              );
              await h.quiet();
              expect(
                find.byType(ReferenceCatalogLifecycleDialog),
                findsNothing,
              );
              final value = await row();
              expect(
                value['lifecycleState'] ?? value['lifecycle_state'],
                'archived',
              );
              expect(find.byKey(ValueKey('reference-$id')), findsNothing);
            },
          );
          await h.check(
            '$type-RESTORE',
            'Показать архив и восстановить $type без потери истории',
            () async {
              await h.tap(find.widgetWithText(FilterChip, 'Показать архив'));
              await h.quiet();
              expect(find.text(renamed), findsOneWidget);
              await lifecycle();
              await input(
                find.byKey(const ValueKey('reference-reason-field')),
                'REFERENCE-RESTORE',
              );
              await h.tap(
                find.byKey(const ValueKey('reference-lifecycle-button')),
              );
              await h.quiet();
              final value = await row();
              restored =
                  (value['lifecycleState'] ?? value['lifecycle_state']) ==
                  'active';
              expect(
                value['lifecycleState'] ?? value['lifecycle_state'],
                'active',
              );
              await h.tap(find.widgetWithText(FilterChip, 'Показать архив'));
              await h.quiet();
              expect(find.text(renamed), findsOneWidget);
            },
          );
          await h.check(
            '$type-HISTORY',
            'История $type содержит выполненные операции и не добавляет неуспешное восстановление',
            () async {
              if (find
                  .byType(ReferenceCatalogLifecycleDialog)
                  .evaluate()
                  .isEmpty) {
                await lifecycle();
              }
              final history = await crm.listReferenceCatalogHistory(
                entityType: type,
                id: id!,
              );
              h.facts.add({'step': h.currentStep, 'history': history});
              expect(
                history.map((r) => r['operation']),
                containsAll(['rename', 'archive', if (restored) 'restore']),
              );
              if (!restored) {
                expect(
                  history.where((r) => r['operation'] == 'restore'),
                  isEmpty,
                );
              }
              await h.tap(find.text('История (${history.length})'));
              expect(find.text('Название изменено'), findsOneWidget);
              expect(find.text('Запись архивирована'), findsOneWidget);
              if (restored) {
                expect(find.text('Запись восстановлена'), findsOneWidget);
              }
              await h.tap(find.widgetWithText(TextButton, 'Закрыть'));
            },
          );
          if (!restored) {
            h.blocked(
              '$type-RESTORED-HISTORY',
              'Повторное открытие восстановленной записи и её история',
              'Restore command failed; archived state retained',
            );
          }
          if (find
              .byType(ReferenceCatalogLifecycleDialog)
              .evaluate()
              .isNotEmpty) {
            await h.tap(find.widgetWithText(TextButton, 'Закрыть'));
          }
        }
        await h.finish();
      },
      timeout: const Timeout(Duration(minutes: 9)),
    );
  }
}
