import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/widgets/searchable_picker_field.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/client_card.dart';
import 'package:magic_music_crm/features/crm/presentation/client_forms/client_forms_api.dart';

import 'live_audit_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru'));
  for (final role in ['admin', 'manager', 'director']) {
    testWidgets(
      '$role dynamic fields and status persistence',
      (tester) async {
        final h = LiveAuditHarness(tester, role, 'dynamic');
        await h.initialize(size: const Size(1440, 1100));
        final access = await h.scope.read(capabilitySnapshotProvider.future);
        final crm = h.scope.read(magicCrmServiceProvider);
        final forms = h.scope.read(clientFormsApiProvider);
        final source = (await forms.listSources()).first;
        for (final entity in ['lead', 'student']) {
          final branch = h.fixture['branchId'] as String;
          final pipeline = await crm.getClientPipeline(
            clientType: entity,
            branchId: branch,
          );
          final created = entity == 'lead'
              ? await forms.createLead(
                  identity: MagicMutationIdentity.create('audit.fixture.lead'),
                  firstName: 'Параметры',
                  lastName: 'DYNAMIC-$role',
                  phone: '+79995554433',
                  sourceId: source['id'] as String,
                  branchId: branch,
                  status: pipeline.activeStages.first.key,
                  customFields: [],
                )
              : await forms.createStudent(
                  identity: MagicMutationIdentity.create(
                    'audit.fixture.student',
                  ),
                  firstName: 'Параметры',
                  lastName: 'DYNAMIC-$role',
                  phone: '+79995554433',
                  sourceId: source['id'] as String,
                  branchId: branch,
                  status: pipeline.activeStages.first.key,
                  customFields: [],
                );
          final id = created['id'] as String;
          Future<Map<String, dynamic>> card() =>
              entity == 'lead' ? crm.getLeadCard(id) : crm.getStudentCard(id);
          Future<Map<String, dynamic>> row() async => entity == 'lead'
              ? Map<String, dynamic>.from((await card())['lead'] as Map)
              : crm.getStudent(id);
          Finder textField(String label) =>
              find.widgetWithText(TextFormField, label);
          String visibleText(Finder finder) => tester
              .widget<EditableText>(
                find.descendant(
                  of: finder,
                  matching: find.byType(EditableText),
                ),
              )
              .controller
              .text;
          Future<void> open() async {
            await h.mount(
              Scaffold(
                body: ClientCard(
                  key: UniqueKey(),
                  lead: await row(),
                  entityType: entity,
                  routed: true,
                  initialSection: 'overview',
                  capabilitySnapshot: access,
                ),
              ),
            );
            await h.waitFor(
              () => textField('Цель обучения').evaluate().isNotEmpty,
              'Dynamic schema rendered',
            );
            await h.quiet();
          }

          Future<void> settle() async {
            await tester.pump(const Duration(seconds: 2));
            await h.quiet();
            await h.waitFor(
              () => find
                  .byWidgetPredicate(
                    (w) =>
                        w is Semantics &&
                        w.properties.label == 'Изменения сохранены',
                  )
                  .evaluate()
                  .isNotEmpty,
              'Autosave completed',
            );
          }

          Future<void> edit(String label, String value) async {
            final field = textField(label);
            await h.tap(field);
            await tester.enterText(field, value);
            await tester.pump();
            expect(
              visibleText(field),
              value,
              reason: 'Input reached the real editor',
            );
            await settle();
          }

          Future<void> assertCustom(String key, Object? expected) async {
            final data = await card();
            final base = data[entity] as Map;
            final legacy = Map<String, dynamic>.from(
              base['custom_data'] as Map? ?? {},
            );
            final typed = Map<String, dynamic>.from(
              data['custom_field_values'] as Map? ?? {},
            );
            final actual = {...legacy, ...typed}[key];
            h.facts.add({
              'step': h.currentStep,
              'entity': entity,
              'id': id,
              'field': key,
              'expected': expected,
              'actual': actual,
              'legacy': legacy,
              'typed': typed,
            });
            expect(actual, expected);
          }

          await h.check(
            '$entity-OPEN',
            'Открыть реальные дополнительные поля карточки',
            open,
          );
          Finder selectField(String label) => find.byWidgetPredicate(
            (w) => w is SearchablePickerField && w.label == label,
          );
          Future<void> select(String label, String value) async {
            final field = find.descendant(
              of: selectField(label),
              matching: find.byType(TextField),
            );
            await h.tap(field);
            await tester.enterText(field, value);
            await tester.pump(const Duration(milliseconds: 500));
            await h.tap(find.text(value).last);
            await settle();
          }

          String? selected(String label) => tester
              .widget<SearchablePickerField>(selectField(label))
              .selectedId;
          await h.check(
            '$entity-learningGoal-SET',
            'Цель обучения: ввод → API → повторное открытие',
            () async {
              await open();
              await edit('Цель обучения', 'Играть джаз');
              await assertCustom('learningGoal', 'Играть джаз');
              await open();
              expect(visibleText(textField('Цель обучения')), 'Играть джаз');
            },
          );
          await h.check(
            '$entity-category-SET',
            'Категория обучения: выбор → API → повторное открытие',
            () async {
              await open();
              await select('Категория обучения', 'Взрослые');
              await assertCustom('category', 'Взрослые');
              await open();
              expect(selected('Категория обучения'), 'Взрослые');
            },
          );
          await h.check(
            '$entity-TEXT-CLEAR',
            'Очистить цель обучения, сохранив категорию',
            () async {
              await open();
              await edit('Цель обучения', 'Временная цель');
              await assertCustom('learningGoal', 'Временная цель');
              await edit('Цель обучения', '');
              await assertCustom('learningGoal', null);
              await assertCustom('category', 'Взрослые');
              await open();
              expect(visibleText(textField('Цель обучения')), '');
              expect(selected('Категория обучения'), 'Взрослые');
            },
          );
          Finder level() => find.byWidgetPredicate(
            (w) => w is SearchablePickerField && w.label == 'Уровень',
          );
          for (final value in ['Средний', 'Начальный']) {
            await h.check(
              '$entity-LEVEL-$value',
              'Уровень: выбрать «$value» → API → повторное открытие',
              () async {
                await open();
                final field = find.descendant(
                  of: level(),
                  matching: find.byType(TextField),
                );
                await h.tap(field);
                await tester.enterText(field, value);
                await tester.pump(const Duration(milliseconds: 500));
                await h.tap(find.text(value).last);
                await settle();
                await assertCustom('level', value);
                await open();
                expect(
                  tester.widget<SearchablePickerField>(level()).selectedId,
                  value,
                );
              },
            );
          }
          await h.check(
            '$entity-UNRELATED-EDIT',
            'Изменение имени сохраняет категорию и уровень',
            () async {
              await open();
              await edit('Имя', 'Сохранённые параметры');
              expect((await row())['first_name'], 'Сохранённые параметры');
              await assertCustom('category', 'Взрослые');
              await assertCustom('level', 'Начальный');
              await open();
              expect(selected('Категория обучения'), 'Взрослые');
              expect(
                tester.widget<SearchablePickerField>(level()).selectedId,
                'Начальный',
              );
            },
          );
          if (entity == 'lead' && pipeline.activeStages.length < 2) {
            h.blocked(
              '$entity-STATUS-CHANGE',
              'Выбрать другой доступный статус',
              'Only one lead stage exists; use --audit-statuses for configured transitions',
            );
            continue;
          }
          await h.check(
            '$entity-STATUS-CHANGE',
            'Выбрать другой доступный статус → API → повторное открытие',
            () async {
              await open();
              final statusLabel = entity == 'lead' ? 'Статус' : 'Этап воронки';
              final picker = find.byWidgetPredicate(
                (w) =>
                    w is DropdownButtonFormField<String> &&
                    w.decoration.labelText == statusLabel,
              );
              final dropdown = tester.widget<DropdownButton<String>>(
                find.descendant(
                  of: picker,
                  matching: find.byType(DropdownButton<String>),
                ),
              );
              final next = dropdown.items!.firstWhere(
                (item) => item.enabled && item.value != dropdown.value,
              );
              final label = find.descendant(
                of: find.byWidget(next.child),
                matching: find.byType(Text),
              );
              // Menu rows are initially offstage; their immutable widgets expose the
              // configured label. The actual transition is made by tapping the menu.
              String labelText(Widget widget) {
                if (widget is Text) return widget.data!;
                if (widget is Row) {
                  return widget.children.whereType<Text>().single.data!;
                }
                throw StateError(
                  'Unsupported status label ${widget.runtimeType}',
                );
              }

              final targetLabel = labelText(next.child);
              h.facts.add({
                'step': h.currentStep,
                'id': id,
                'beforeStatus': dropdown.value,
                'targetStatus': next.value,
                'targetLabel': targetLabel,
                'mountedLabelCount': label.evaluate().length,
              });
              await h.tap(picker);
              await h.tap(find.text(targetLabel).last);
              await settle();
              final saved = await row();
              h.facts.add({
                'step': h.currentStep,
                'id': id,
                'savedStatus': saved['status'],
                'savedStatusId': saved['status_id'],
              });
              expect(
                entity == 'lead' ? saved['status_id'] : saved['status'],
                next.value,
              );
              await open();
              final reopened = tester.widget<DropdownButton<String>>(
                find.descendant(
                  of: picker,
                  matching: find.byType(DropdownButton<String>),
                ),
              );
              expect(reopened.value, next.value);
              await assertCustom('category', 'Взрослые');
            },
          );
        }
        await h.finish();
      },
      timeout: const Timeout(Duration(minutes: 10)),
    );
  }
}
