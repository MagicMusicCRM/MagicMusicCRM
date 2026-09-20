import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/manage_entities_widget.dart';

import 'live_audit_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final role in ['director', 'manager']) {
    testWidgets(
      '$role package catalog controls',
      (tester) async {
        final h = LiveAuditHarness(tester, role, 'catalog');
        await h.initialize(size: const Size(1440, 1200));
        final crm = h.scope.read(magicCrmServiceProvider);
        Finder field(String label) => find.widgetWithText(TextFormField, label);
        Future<void> edit(String label, String text) async {
          await h.tap(field(label));
          await tester.enterText(field(label), text);
          await tester.pump();
          expect(
            tester
                .widget<EditableText>(
                  find.descendant(
                    of: field(label),
                    matching: find.byType(EditableText),
                  ),
                )
                .controller
                .text,
            text,
          );
        }

        Future<void> branch(String label) async {
          await h.tap(find.byType(DropdownMenu<String>));
          await h.tap(find.widgetWithText(MenuItemButton, label).last);
        }

        Future<List<Map<String, dynamic>>> rows({bool archived = true}) =>
            crm.listSubscriptionPackages(includeArchived: archived);
        String? id;
        Future<Map<String, dynamic>> row() async {
          final value = (await rows()).singleWhere((r) => r['id'] == id);
          h.facts.add({'step': h.currentStep, 'package': value});
          return value;
        }

        Future<void> submit(String label) async {
          await h.tap(find.widgetWithText(ElevatedButton, label));
          await h.quiet();
          expect(field('Название'), findsNothing);
        }

        await h.check(
          'OPEN',
          'Открыть каталог в системных настройках',
          () async {
            await h.mount(
              const SystemSettingsRouteScreen(initialArea: 'sales'),
            );
            await h.waitFor(
              () => find.text('Продажи и оплаты').evaluate().isNotEmpty,
              'Sales catalog rendered',
            );
            await h.quiet();
          },
        );
        if (role == 'manager') {
          await h.check(
            'READONLY',
            'Управляющий видит каталог, но не может изменять пакеты',
            () async {
              final item = (await rows(
                archived: false,
              )).singleWhere((r) => r['name'] == 'CATALOG-UPDATED');
              expect(find.text('CATALOG-UPDATED'), findsOneWidget);
              expect(find.text('Новый абонемент'), findsNothing);
              expect(
                find.byKey(
                  const ValueKey('subscription-packages-archive-filter'),
                ),
                findsNothing,
              );
              expect(
                find.byKey(
                  ValueKey('archive-subscription-package-${item['id']}'),
                ),
                findsNothing,
              );
              final tile = tester.widget<ListTile>(
                find.widgetWithText(ListTile, 'CATALOG-UPDATED'),
              );
              expect(tile.onTap, isNull);
            },
          );
          await h.finish();
          return;
        }
        await h.check(
          'CREATE-CANCEL',
          'Отмена заполненного редактора не создаёт пакет',
          () async {
            await h.tap(find.widgetWithText(FilledButton, 'Новый абонемент'));
            await edit('Название', 'CATALOG-CANCELLED');
            await h.tap(find.widgetWithText(OutlinedButton, 'Отмена'));
            await h.quiet();
            expect(
              (await rows()).where((r) => r['name'] == 'CATALOG-CANCELLED'),
              isEmpty,
            );
          },
        );
        await h.check(
          'VALIDATION',
          'Невалидные название, часы, цена и срок блокируют отправку',
          () async {
            await h.tap(find.widgetWithText(FilledButton, 'Новый абонемент'));
            await edit('Количество часов', '0');
            await edit('Цена, ₽', '-1');
            await edit('Срок действия, дней', '0');
            final before = h.requests.length;
            await h.tap(find.widgetWithText(ElevatedButton, 'Создать'));
            expect(find.text('Укажите название'), findsOneWidget);
            expect(find.text('Должно быть больше 0'), findsNWidgets(2));
            expect(find.text('Не может быть отрицательной'), findsOneWidget);
            expect(
              h.requests.skip(before).where((r) => r['method'] != 'GET'),
              isEmpty,
            );
          },
        );
        await h.check(
          'CREATE',
          'Создать пакет с часами, стоимостью, сроком и филиалом',
          () async {
            await edit('Название', 'CATALOG-CREATED');
            await edit('Количество часов', '8');
            await edit('Цена, ₽', '8000');
            await edit('Срок действия, дней', '90');
            await branch('HTTP test');
            await submit('Создать');
            final created = (await rows()).singleWhere(
              (r) => r['name'] == 'CATALOG-CREATED',
            );
            id = created['id'] as String;
            final saved = await row();
            expect(num.parse(saved['unitCount'].toString()), 8);
            expect(saved['basePriceMinor'].toString(), '800000');
            expect(saved['validityDays'], 90);
            expect(saved['branchId'], h.fixture['branchId']);
            expect(find.text('CATALOG-CREATED'), findsOneWidget);
          },
        );
        if (id == null) {
          h.blocked(
            'LIFECYCLE',
            'Дальнейшее редактирование пакета',
            'No created package ID',
          );
          await h.finish();
          return;
        }
        await h.check(
          'EDIT',
          'Открыть и изменить название, часы, цену с копейками и срок',
          () async {
            await h.tap(find.text('CATALOG-CREATED'));
            await edit('Название', 'CATALOG-UPDATED');
            await edit('Количество часов', '12');
            await edit('Цена, ₽', '12000,50');
            await edit('Срок действия, дней', '30');
            await submit('Сохранить');
            final saved = await row();
            expect(saved['name'], 'CATALOG-UPDATED');
            expect(num.parse(saved['unitCount'].toString()), 12);
            expect(saved['basePriceMinor'].toString(), '1200050');
            expect(saved['validityDays'], 30);
            expect(find.text('Часов: 12'), findsOneWidget);
          },
        );
        await h.check(
          'STALE',
          'Конфликт версии сохраняет черновик и блокирует повторную отправку',
          () async {
            await h.tap(find.text('CATALOG-UPDATED'));
            final before = await row();
            await crm.updateSubscriptionPackage(id!, {
              'name': 'CATALOG-SERVER',
            }, expectedVersion: (before['version'] as num).toInt());
            await edit('Название', 'CATALOG-DRAFT');
            await h.tap(find.widgetWithText(ElevatedButton, 'Сохранить'));
            await h.quiet();
            expect(
              find.byKey(const Key('subscription-package-stale-banner')),
              findsOneWidget,
            );
            expect(
              tester
                  .widget<ElevatedButton>(
                    find.widgetWithText(ElevatedButton, 'Сохранить'),
                  )
                  .onPressed,
              isNull,
            );
            expect((await row())['name'], 'CATALOG-SERVER');
            expect(
              tester
                  .widget<EditableText>(
                    find.descendant(
                      of: field('Название'),
                      matching: find.byType(EditableText),
                    ),
                  )
                  .controller
                  .text,
              'CATALOG-DRAFT',
            );
          },
          expectedHttpErrors: [
            (
              method: 'PATCH',
              path: '/api/crm/subscription-packages/$id',
              status: 409,
              maxCount: 1,
            ),
          ],
        );
        await h.check(
          'RELOAD',
          'Загрузить актуальную версию и сохранить новую правку',
          () async {
            await h.tap(
              find.byKey(const Key('subscription-package-reload-latest')),
            );
            await h.quiet();
            expect(
              find.byKey(const Key('subscription-package-stale-banner')),
              findsNothing,
            );
            expect(
              tester
                  .widget<EditableText>(
                    find.descendant(
                      of: field('Название'),
                      matching: find.byType(EditableText),
                    ),
                  )
                  .controller
                  .text,
              'CATALOG-SERVER',
            );
            await edit('Название', 'CATALOG-UPDATED');
            await submit('Сохранить');
            expect((await row())['name'], 'CATALOG-UPDATED');
          },
        );
        await h.check(
          'CLEAR-OPTIONAL',
          'Очистить срок действия и ограничение филиалом',
          () async {
            await h.tap(find.text('CATALOG-UPDATED'));
            await edit('Срок действия, дней', '');
            await branch('Вся школа');
            await submit('Сохранить');
            final saved = await row();
            expect(saved['validityDays'], isNull);
            expect(saved['branchId'], isNull);
          },
        );
        for (final confirm in [false, true]) {
          await h.check(
            confirm ? 'ARCHIVE' : 'ARCHIVE-CANCEL',
            confirm
                ? 'Подтвердить архивирование; активный каталог скрывает пакет'
                : 'Отказ от архивирования сохраняет активный пакет',
            () async {
              await h.tap(
                find.byKey(ValueKey('archive-subscription-package-$id')),
              );
              await h.tap(
                find.widgetWithText(
                  TextButton,
                  confirm ? 'Архивировать' : 'Отмена',
                ),
              );
              await h.quiet();
              expect(
                (await rows(archived: false)).any((r) => r['id'] == id),
                !confirm,
              );
              if (confirm) expect(find.text('CATALOG-UPDATED'), findsNothing);
            },
          );
        }
        await h.check(
          'SHOW-ARCHIVE',
          'Фильтр показывает сохранённый архивный пакет',
          () async {
            await h.tap(
              find.byKey(
                const ValueKey('subscription-packages-archive-filter'),
              ),
            );
            await h.quiet();
            expect(find.text('CATALOG-UPDATED'), findsOneWidget);
            expect(
              find.byKey(ValueKey('restore-subscription-package-$id')),
              findsOneWidget,
            );
            expect((await row())['archivedAt'], isNotNull);
          },
        );
        for (final confirm in [false, true]) {
          await h.check(
            confirm ? 'RESTORE' : 'RESTORE-CANCEL',
            confirm
                ? 'Восстановить пакет в активный каталог'
                : 'Отказ от восстановления сохраняет архив',
            () async {
              await h.tap(
                find.byKey(ValueKey('restore-subscription-package-$id')),
              );
              await h.tap(
                confirm
                    ? find.widgetWithText(FilledButton, 'Восстановить')
                    : find.widgetWithText(TextButton, 'Отмена'),
              );
              await h.quiet();
              expect(
                (await rows(archived: false)).any((r) => r['id'] == id),
                confirm,
              );
              if (confirm) {
                await h.tap(
                  find.byKey(
                    const ValueKey('subscription-packages-archive-filter'),
                  ),
                );
                await h.quiet();
                expect(find.text('CATALOG-UPDATED'), findsOneWidget);
                expect((await row())['archivedAt'], isNull);
              }
            },
          );
        }
        await h.finish();
      },
      timeout: const Timeout(Duration(minutes: 7)),
    );
  }
}
