import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/features/crm/presentation/staff_workspace_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/create_lesson_dialog.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/widgets/searchable_picker_field.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/client_card.dart';
import 'package:magic_music_crm/features/crm/presentation/client_forms/client_create_dialogs.dart';
import 'live_audit_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru'));
  for (final role in ['admin', 'manager', 'director']) {
    testWidgets('$role extended create and card fields', (tester) async {
      // Keep scripted input in one driver; native IME echoes can overwrite enterText.
      tester.testTextInput.register();
      addTearDown(tester.testTextInput.unregister);
      final h = LiveAuditHarness(tester, role, 'client-extended');
      await h.initialize(size: const Size(1600, 1800));
      final crm = h.scope.read(magicCrmServiceProvider),
          access = await h.scope.read(capabilitySnapshotProvider.future);
      Finder key(String k) => find.byKey(ValueKey(k));
      Future<void> fill(Finder f, String text) async {
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();
        await h.tap(f);
        await tester.enterText(f, text);
        await tester.pump();
      }

      Future<void> select(Finder f, String label) async {
        await h.tap(f);
        await h.tap(find.text(label));
        await h.quiet();
      }

      Finder picker(String label) => find.byWidgetPredicate(
        (w) => w is SearchablePickerField && w.label == label,
      );
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
          'Card autosave settled',
        );
      }

      await h.check(
        'POPULATED-VIEWPORT',
        'Заполненная карточка в рабочем пространстве: первый экран 1366×768/125%',
        () async {
          tester.view.physicalSize = const Size(1366, 768);
          tester.view.devicePixelRatio = 1.25;
          await h.mount(
            StaffWorkspaceScreen(
              initialLink: EntityLink.typed(
                entityType: EntityLinkType.client,
                entityId: h.fixture['populatedStudentId'] as String,
                variant: 'student',
              ),
            ),
          );
          await h.waitFor(
            () => find.byType(ClientCard).evaluate().isNotEmpty,
            'Routed client card opened',
          );
          await h.quiet();
          final items = find.byWidgetPredicate(
            (w) =>
                w.key is ValueKey<String> &&
                (w.key as ValueKey<String>).value.startsWith(
                  'student-timeline-',
                ) &&
                w is InkWell,
          );
          final viewport =
              Offset.zero &
              (tester.view.physicalSize / tester.view.devicePixelRatio);
          final visible = items
              .evaluate()
              .where(
                (e) => viewport.contains(
                  tester.getCenter(find.byWidget(e.widget)),
                ),
              )
              .toList();
          h.facts.add({
            'step': h.currentStep,
            'timelineRows': items.evaluate().length,
            'visibleRows': visible.length,
            'physicalSize': '1366x768',
            'devicePixelRatio': 1.25,
          });
          final nearest = (await crm.listLessons(
            studentId: h.fixture['populatedStudentId'],
            from: DateTime.now().toUtc().toIso8601String(),
            order: 'asc',
            limit: 1,
          )).single;
          final label =
              'Ближайшее: ${DateFormat('dd.MM HH:mm').format(DateTime.parse(nearest['scheduled_at']).toLocal())}';
          expect(
            find.text(label).hitTestable(),
            findsOneWidget,
            reason:
                'A real upcoming lesson and its time must be visible before scrolling',
          );
          final balance = (await crm.getStudentCommerceProjection(
            h.fixture['populatedStudentId'],
          )).student.lessonBalance;
          expect(balance.paid, greaterThan(0));
          expect(
            find
                .text(
                  'Оплачено: ${balance.paid} · Доступно: ${balance.available}',
                )
                .hitTestable(),
            findsOneWidget,
            reason:
                'The first screen must expose the subscription balance, not only its section title',
          );
          expect(tester.takeException(), isNull);
          await h.tap(find.text(label));
          await h.quiet();
          expect(find.byType(CreateLessonDialog), findsOneWidget);
          expect(
            tester
                .widget<CreateLessonDialog>(find.byType(CreateLessonDialog))
                .lesson!['id'],
            nearest['id'],
          );
          await h.tap(
            find.descendant(
              of: find.byType(CreateLessonDialog),
              matching: find.widgetWithText(TextButton, 'Отмена'),
            ),
          );
          h.facts.add({
            'step': h.currentStep,
            'nearestLessonId': nearest['id'],
            'scheduledAt': nearest['scheduled_at'],
          });
        },
      );
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.physicalSize = const Size(1600, 1800);
      tester.view.devicePixelRatio = 1;
      if (Platform.environment['CLIENT_AUDIT_VIEWPORT_ONLY'] == 'true') {
        await h.finish();
        return;
      }
      for (final entity in ['lead', 'student']) {
        Map<String, dynamic>? created;
        String? id;
        Future<Map<String, dynamic>> read() async {
          final card = entity == 'student'
              ? await crm.getStudentCard(id!)
              : await crm.getLeadCard(id!);
          return {
            ...Map<String, dynamic>.from(card[entity] as Map),
            'custom_field_values': card['custom_field_values'],
          };
        }

        Future<void> openCard() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await h.mount(
            Scaffold(
              body: ClientCard(
                lead: await read(),
                entityType: entity,
                routed: true,
                initialSection: 'overview',
                capabilitySnapshot: access,
              ),
            ),
          );
          await h.quiet();
        }

        Map<String, dynamic> custom(Map<String, dynamic> row) => {
          ...Map<String, dynamic>.from(row['custom_data'] as Map? ?? {}),
          ...Map<String, dynamic>.from(
            row['custom_field_values'] as Map? ?? {},
          ),
        };
        await h.check(
          '$entity-CREATE-DRAFT',
          'Новая карточка: заполнить текст, дату, список и флажок',
          () async {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump();
            await h.mount(
              Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () async {
                      created = await showDialog<Map<String, dynamic>>(
                        context: context,
                        builder: (_) => entity == 'lead'
                            ? const LeadCreateDialog()
                            : StudentCreateDialog(
                                initialBranchId: h.fixture['branchId'],
                              ),
                      );
                    },
                    child: const Text('Новый клиент'),
                  ),
                ),
              ),
            );
            await h.tap(find.text('Новый клиент'));
            await h.quiet();
            if (entity == 'lead') {
              expect(key('custom-field-birthday'), findsNothing);
              await h.tap(key('lead-additional-toggle'));
            }
            await fill(key('$entity-first-name'), 'AUDIT-EXTENDED');
            final firstFocus = FocusManager.instance.primaryFocus;
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            expect(FocusManager.instance.primaryFocus, isNot(same(firstFocus)));
            await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
            expect(FocusManager.instance.primaryFocus, same(firstFocus));
            await fill(key('$entity-last-name'), '$role-$entity');
            final phone = find.descendant(
              of: key('$entity-phone'),
              matching: find.byType(TextField),
            );
            await fill(phone, '9991234567');
            await select(key('$entity-branch'), 'HTTP test');
            final source = tester.widget<SearchablePickerField>(
              key('$entity-source'),
            );
            await select(key('$entity-source'), source.items.first.label);
            await fill(key('custom-field-learningGoal'), 'AUDIT-CREATE-GOAL');
            await fill(key('custom-field-birthday'), '2000-02-29');
            await select(key('custom-field-level'), 'Средний');
            if (entity == 'student') {
              await h.tap(key('custom-field-noEmail'));
            }
            expect(
              tester
                  .widget<TextField>(phone)
                  .controller!
                  .text
                  .replaceAll(RegExp(r'\D'), ''),
              '79991234567',
              reason: 'Phone input must survive editing the remaining fields',
            );
          },
        );
        if (entity == 'lead') {
          await h.check(
            'lead-COLLAPSE-ERROR',
            'Скрытое поле сохраняет ввод и раскрывается при ошибке сервера',
            () async {
              await h.tap(key('lead-additional-toggle'));
              expect(key('custom-field-birthday'), findsNothing);
              await h.tap(key('lead-additional-toggle'));
              expect(
                tester
                    .widget<TextFormField>(key('custom-field-birthday'))
                    .initialValue,
                '2000-02-29',
              );
              await fill(key('custom-field-birthday'), '2000-02-30');
              await h.tap(key('lead-additional-toggle'));
              await h.tap(key('lead-submit'));
              await h.quiet();
              expect(created, isNull);
              final birthday = find.descendant(
                of: key('custom-field-birthday'),
                matching: find.byType(InputDecorator),
              );
              expect(
                tester.widget<InputDecorator>(birthday).decoration.errorText,
                isNotNull,
              );
            },
            expectedHttpErrors: [
              (
                method: 'POST',
                path: '/api/crm/leads',
                status: 422,
                maxCount: 1,
              ),
            ],
          );
          await h.check(
            'lead-ERROR-RECOVER',
            'Исправить скрытое поле без потери остального ввода',
            () async {
              await fill(key('custom-field-birthday'), '2000-02-29');
            },
          );
        }
        await h.check(
          '$entity-CREATE-SAVE',
          'Сохранить дополнительные поля и независимо прочитать карточку',
          () async {
            await h.tap(key('$entity-submit'));
            await h.quiet();
            expect(created, isNotNull);
            id = created!['id'];
            final row = await read(), data = custom(row);
            expect(data['learningGoal'], 'AUDIT-CREATE-GOAL');
            expect(data['birthday'], '2000-02-29');
            expect(data['level'], 'Средний');
            if (entity == 'student') {
              expect(data['noEmail'], true);
            }
            h.facts.add({
              'step': h.currentStep,
              'id': id,
              'entity': entity,
              'row': row,
            });
          },
        );
        if (id == null) {
          continue;
        }
        await h.check(
          '$entity-BRANCH',
          'Сменить основной филиал и проверить после повторного открытия',
          () async {
            await openCard();
            await select(picker('Основной филиал'), 'AUDIT-SECOND-BRANCH');
            await settle();
            expect((await read())['branch_id'], h.fixture['secondBranchId']);
            await openCard();
            expect(
              tester
                  .widget<SearchablePickerField>(picker('Основной филиал'))
                  .selectedId,
              h.fixture['secondBranchId'],
            );
          },
        );
        await h.check(
          '$entity-BRANCH-RETURN',
          'Вернуть исходный филиал',
          () async {
            await select(picker('Основной филиал'), 'HTTP test');
            await settle();
            expect((await read())['branch_id'], h.fixture['branchId']);
          },
        );
        await h.check(
          '$entity-SOURCE',
          'Сменить рекламный источник и прочитать сохранённый ID',
          () async {
            final field = picker('Рекламный источник *'),
                w = tester.widget<SearchablePickerField>(field),
                option = w.items.firstWhere((i) => i.id != w.selectedId);
            await select(field, option.label);
            await settle();
            final row = await read();
            expect(row['source_id'], option.id);
            await openCard();
            expect(
              tester
                  .widget<SearchablePickerField>(picker('Рекламный источник *'))
                  .selectedId,
              option.id,
            );
            h.facts.add({'step': h.currentStep, 'id': id, 'row': row});
          },
        );
        await h.check(
          '$entity-DISCIPLINE',
          'Выбрать два направления и сохранить после переоткрытия',
          () async {
            final chips = find.byType(FilterChip);
            final candidates = tester
                .widgetList<FilterChip>(chips)
                .where((w) => w.label is Text)
                .map((w) => (w.label as Text).data)
                .whereType<String>()
                .where(
                  (s) =>
                      ['Вокал', 'Гитара', 'Фортепиано', 'Барабаны'].contains(s),
                )
                .toList();
            expect(candidates.length, greaterThanOrEqualTo(2));
            for (final label in candidates.take(2)) {
              final f = find.widgetWithText(FilterChip, label);
              if (!tester.widget<FilterChip>(f).selected) await h.tap(f);
            }
            await settle();
            await openCard();
            for (final label in candidates.take(2)) {
              expect(
                tester
                    .widget<FilterChip>(find.widgetWithText(FilterChip, label))
                    .selected,
                true,
              );
            }
            h.facts.add({'step': h.currentStep, 'id': id, 'row': await read()});
          },
        );
        await h.check(
          '$entity-DOB',
          'Изменить дату рождения через настоящий ввод даты и сохранить',
          () async {
            final layout = key('custom-field-layout-birthday');
            if (layout.evaluate().isEmpty) {
              await h.tap(find.text('Дополнительные поля').first);
              await h.quiet();
            }
            final dateField = find
                .descendant(of: layout, matching: find.byType(InkWell))
                .first;
            await h.tap(dateField);
            final dialog = find.byType(DatePickerDialog),
                loc = MaterialLocalizations.of(
                  tester.element(find.byType(DatePickerDialog)),
                );
            final input = find.descendant(
              of: dialog,
              matching: find.byType(TextFormField),
            );
            await fill(input, loc.formatCompactDate(DateTime(1996, 2, 29)));
            await h.tap(
              find.descendant(
                of: dialog,
                matching: find.text(loc.okButtonLabel),
              ),
            );
            await settle();
            expect(custom(await read())['birthday'], '1996-02-29');
            await openCard();
            if (key('custom-field-layout-birthday').evaluate().isEmpty) {
              await h.tap(find.text('Дополнительные поля').first);
              await h.quiet();
            }
            expect(find.text('29.02.1996'), findsOneWidget);
            h.facts.add({'step': h.currentStep, 'id': id, 'row': await read()});
          },
        );
        await h.check(
          '$entity-VIEWPORT',
          'Карточка на экране 1366×768 при масштабе 125%',
          () async {
            tester.view.physicalSize = const Size(1366, 768);
            tester.view.devicePixelRatio = 1.25;
            await openCard();
            expect(find.text('Действия'), findsOneWidget);
            expect(tester.takeException(), isNull);
            h.facts.add({
              'step': h.currentStep,
              'physicalSize': '1366x768',
              'devicePixelRatio': 1.25,
            });
          },
        );
        tester.view.physicalSize = const Size(1600, 1800);
        tester.view.devicePixelRatio = 1;
        await tester.pump();
      }
      await h.finish();
    });
  }
}
