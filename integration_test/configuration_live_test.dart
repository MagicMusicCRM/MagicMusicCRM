import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/features/crm/presentation/client_forms/client_forms_api.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/manage_entities_widget.dart';
import 'package:magic_music_crm/features/crm/presentation/client_forms/crm_configuration_workspace.dart';
import 'live_audit_harness.dart';
import 'evidence_screenshot.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru'));
  testWidgets(
    'director configuration draft publish archive rollback',
    (tester) async {
      final h = LiveAuditHarness(tester, 'director', 'configuration');
      await h.initialize(size: const Size(1600, 1350));
      final api = h.scope.read(clientFormsApiProvider);
      int? firstVersion;
      Future<Map<String, dynamic>> draft() async {
        final r = await api.getConfigurationDraft();
        h.facts.add({'step': h.currentStep, 'draft': r});
        return r;
      }

      Map? field(Map r) => ((r['snapshot'] as Map)['fields'] as List)
          .cast<Map>()
          .where((f) => f['key'] == 'audit_free_text')
          .firstOrNull;
      Future<void> open() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await h.mount(
          SystemSettingsRouteScreen(key: UniqueKey(), initialArea: 'crm'),
        );
        await h.quiet();
      }

      Future<void> revealField(String label) async {
        final target = find.text(label);
        for (
          var attempt = 0;
          target.evaluate().isEmpty && attempt < 20;
          attempt++
        ) {
          await tester.dragFrom(const Offset(420, 1000), const Offset(0, -500));
          await tester.pump(const Duration(milliseconds: 200));
        }
        expect(target, findsWidgets);
      }

      Future<void> fill(String label, String value) async {
        final f = find.widgetWithText(TextField, label);
        await h.tap(f);
        await tester.enterText(f, value);
        await tester.pump();
      }

      Future<void> saveDraft() async {
        await h.tap(find.widgetWithText(OutlinedButton, 'Сохранить черновик'));
        await h.quiet();
      }

      Future<void> preview() async {
        await h.tap(find.byKey(const ValueKey('configuration-publish')));
        await h.quiet();
        expect(find.text('Предпросмотр публикации'), findsOneWidget);
      }

      Future<void> publish(String reason) async {
        await preview();
        await fill('Причина публикации *', reason);
        await h.tap(find.widgetWithText(FilledButton, 'Опубликовать'));
        await h.quiet();
      }

      Future<void> edit(String title) async {
        await revealField(title);
        await h.tap(find.widgetWithText(ListTile, title).first);
        await h.tap(find.text('Изменить').last);
        await h.quiet();
        expect(find.text('Настройка поля'), findsOneWidget);
      }

      await h.check(
        'OPEN',
        'Открыть конструктор и прочитать исходный черновик',
        () async {
          await open();
          expect(field(await draft()), isNull);
          final selected = tester
              .widgetList<ListTile>(
                find.descendant(
                  of: find.byType(CrmConfigurationWorkspace),
                  matching: find.byType(ListTile),
                ),
              )
              .where((tile) => tile.selected)
              .single;
          expect(find.text((selected.title! as Text).data!), findsWidgets);
          expect(find.text('Выберите элемент в списке слева'), findsNothing);
          expect(find.text('Структура и видимость полей'), findsNothing);
        },
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await h.check(
        'TABS-HOVER',
        'Наведение на выбранную вкладку без затемнения иконки',
        () async {
          final tab = find.widgetWithText(ChoiceChip, 'Поля карточек');
          expect(tester.widget<ChoiceChip>(tab).showCheckmark, false);
          await mouse.moveTo(tester.getCenter(tab));
          await tester.pumpAndSettle();
        },
      );
      await h.check(
        'CATEGORIES',
        'Категории открываются отдельно от списка полей',
        () async {
          await h.tap(find.widgetWithText(ChoiceChip, 'Категории'));
          final tab = find.widgetWithText(ChoiceChip, 'Категории');
          expect(tester.widget<ChoiceChip>(tab).showCheckmark, false);
          await mouse.moveTo(tester.getCenter(tab));
          expect(find.byTooltip('Добавить категорию'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('configuration-field-search')),
            findsNothing,
          );
        },
      );
      await mouse.moveTo(Offset.zero);
      await h.tap(find.widgetWithText(ChoiceChip, 'Поля карточек'));
      await h.check(
        'ADD-CANCEL',
        'Отмена нового поля не меняет черновик',
        () async {
          await h.tap(find.byTooltip('Добавить поле'));
          await fill('Название *', 'Отмена');
          await fill('Стабильный ключ *', 'audit_cancelled');
          await h.tap(find.widgetWithText(TextButton, 'Отмена'));
          expect(field(await draft()), isNull);
        },
      );
      await h.check(
        'ADD',
        'Добавить текстовое поле в локальный редактор',
        () async {
          await h.tap(find.byTooltip('Добавить поле'));
          await fill('Название *', 'AUDIT-FIELD');
          await fill('Стабильный ключ *', 'audit_free_text');
          await h.tap(find.byKey(const ValueKey('field-visible-lead')));
          await h.tap(find.widgetWithText(FilledButton, 'Сохранить'));
          await h.quiet();
          expect(find.text('AUDIT-FIELD'), findsWidgets);
          expect(field(await draft()), isNull);
        },
      );
      await h.check('DRAFT', 'Сохранить черновик с новым полем', () async {
        await saveDraft();
        expect(field(await draft())?['label'], 'AUDIT-FIELD');
      });
      await h.check(
        'DRAFT-REOPEN',
        'Открытие восстанавливает сохранённый черновик',
        () async {
          await open();
          await revealField('AUDIT-FIELD');
          expect(find.text('AUDIT-FIELD'), findsWidgets);
          expect(field(await draft())?['active'], true);
        },
      );
      await h.check(
        'SEARCH-FILTERS',
        'Поиск по ключу, фильтры карточки и категории, очистка поиска',
        () async {
          Future<void> choose(String key, String label) async {
            await h.tap(find.byKey(ValueKey(key)));
            await h.quiet();
            await h.tap(find.widgetWithText(MenuItemButton, label).last);
            await h.quiet();
          }

          final search = find.byKey(
            const ValueKey('configuration-field-search'),
          );
          await h.tap(search);
          await tester.enterText(search, 'AUDIT_FREE_TEXT');
          await h.quiet();
          expect(find.widgetWithText(ListTile, 'AUDIT-FIELD'), findsOneWidget);
          expect(find.textContaining('Поля · 1 из'), findsOneWidget);
          await choose('configuration-field-target', 'Лид');
          h.facts.add({
            'step': h.currentStep,
            'targetValue': tester
                .state<FormFieldState<String?>>(
                  find.byKey(const ValueKey('configuration-field-target')),
                )
                .value,
          });
          await captureEvidence(tester, 'configuration-filter-lead');
          expect(
            tester
                .state<FormFieldState<String?>>(
                  find.byKey(const ValueKey('configuration-field-target')),
                )
                .value,
            'lead',
          );
          expect(find.widgetWithText(ListTile, 'AUDIT-FIELD'), findsNothing);
          expect(find.textContaining('Поля не найдены'), findsOneWidget);
          await choose('configuration-field-target', 'Ученик');
          expect(find.widgetWithText(ListTile, 'AUDIT-FIELD'), findsOneWidget);
          final categories =
              ((await draft())['snapshot'] as Map)['categories'] as List;
          final label = (categories.first as Map)['label'] as String;
          await choose('configuration-field-category', label);
          expect(find.widgetWithText(ListTile, 'AUDIT-FIELD'), findsOneWidget);
          await choose('configuration-field-target', 'Все карточки');
          await choose('configuration-field-category', 'Все категории');
          await h.tap(search);
          await tester.enterText(search, 'НЕСУЩЕСТВУЮЩЕЕ ПОЛЕ');
          await h.quiet();
          expect(
            tester.widget<TextField>(search).controller!.text,
            'НЕСУЩЕСТВУЮЩЕЕ ПОЛЕ',
          );
          expect(find.textContaining('Поля не найдены'), findsOneWidget);
          await h.tap(find.byTooltip('Очистить поиск полей'));
          await h.quiet();
          expect(tester.widget<TextField>(search).controller!.text, isEmpty);
          expect(find.textContaining('Поля не найдены'), findsNothing);
        },
      );
      await h.check(
        'PUBLISH-CANCEL',
        'Предпросмотр и закрытие не создают ревизию',
        () async {
          final before = await api.listConfigurationRevisions();
          await preview();
          await h.tap(find.widgetWithText(TextButton, 'Закрыть'));
          expect(
            (await api.listConfigurationRevisions()).length,
            before.length,
          );
        },
      );
      await h.check(
        'PUBLISH-REASON',
        'Публикация требует непустую причину',
        () async {
          await preview();
          await h.tap(find.widgetWithText(FilledButton, 'Опубликовать'));
          expect(find.text('Предпросмотр публикации'), findsOneWidget);
          await h.tap(find.widgetWithText(TextButton, 'Закрыть'));
        },
      );
      await h.check('PUBLISH', 'Опубликовать поле с причиной', () async {
        await publish('AUDIT-CONFIG-CREATED');
        final r = await draft();
        firstVersion = r['baseVersion'] as int;
        expect(firstVersion, greaterThan(0));
        expect(field(r)?['label'], 'AUDIT-FIELD');
      });
      await h.check(
        'EDIT-CANCEL',
        'Отмена изменения сохраняет опубликованное название',
        () async {
          await edit('AUDIT-FIELD');
          await fill('Название *', 'CANCEL-RENAME');
          await h.tap(find.widgetWithText(TextButton, 'Отмена'));
          expect(field(await draft())?['label'], 'AUDIT-FIELD');
        },
      );
      await h.check(
        'EDIT',
        'Изменить название и опубликовать новую ревизию',
        () async {
          await edit('AUDIT-FIELD');
          await fill('Название *', 'AUDIT-FIELD-EDITED');
          await h.tap(find.widgetWithText(FilledButton, 'Сохранить'));
          await publish('AUDIT-CONFIG-EDITED');
          expect(field(await draft())?['label'], 'AUDIT-FIELD-EDITED');
        },
      );
      await h.check(
        'ARCHIVE',
        'Снять активность поля и опубликовать архив без удаления определения',
        () async {
          await edit('AUDIT-FIELD-EDITED');
          await h.tap(find.widgetWithText(CheckboxListTile, 'Активное'));
          await h.tap(find.widgetWithText(FilledButton, 'Сохранить'));
          await publish('AUDIT-CONFIG-ARCHIVED');
          expect(field(await draft())?['active'], false);
        },
      );
      await h.check(
        'HISTORY',
        'История хранит публикации с причинами',
        () async {
          await h.tap(find.text('История версий'));
          await h.quiet();
          final rows = await api.listConfigurationRevisions();
          h.facts.add({'step': h.currentStep, 'revisions': rows});
          expect(rows.any((r) => r['reason'] == 'AUDIT-CONFIG-CREATED'), true);
          expect(rows.any((r) => r['reason'] == 'AUDIT-CONFIG-ARCHIVED'), true);
        },
      );
      await h.check(
        'ROLLBACK',
        'Откат к первой публикации создаёт новую ревизию и восстанавливает поле',
        () async {
          final row = find.ancestor(
            of: find.text('Версия $firstVersion'),
            matching: find.byType(ListTile),
          );
          await h.tap(
            find.descendant(
              of: row,
              matching: find.byTooltip('Опубликовать откат к этой версии'),
            ),
          );
          await fill('Причина *', 'AUDIT-CONFIG-ROLLBACK');
          await h.tap(find.text('Продолжить'));
          await h.quiet();
          final r = await draft();
          expect(r['baseVersion'], greaterThan(firstVersion!));
          expect(field(r)?['label'], 'AUDIT-FIELD');
          expect(field(r)?['active'], true);
        },
      );
      await h.check(
        'FINAL',
        'Повторное открытие сохраняет результат отката и историю',
        () async {
          await open();
          final r = await draft();
          expect(field(r)?['label'], 'AUDIT-FIELD');
          expect(field(r)?['active'], true);
          expect(
            (await api.listConfigurationRevisions()).length,
            greaterThanOrEqualTo(4),
          );
        },
      );
      await h.check(
        'NARROW',
        'CRM на узком экране: выбор поля и возврат к списку',
        () async {
          tester.view.physicalSize = const Size(390, 844);
          await open();
          final target = find.widgetWithText(ListTile, 'AUDIT-FIELD');
          await tester.scrollUntilVisible(
            target,
            200,
            scrollable: find
                .descendant(
                  of: find.byType(CrmConfigurationWorkspace),
                  matching: find.byType(Scrollable),
                )
                .last,
          );
          await h.tap(target);
          await h.quiet();
          expect(find.text('К списку'), findsOneWidget);
          expect(find.text('Изменить'), findsOneWidget);
          await h.tap(find.text('К списку'));
          await h.quiet();
          expect(find.text('К списку'), findsNothing);
        },
      );
      await h.finish();
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
