import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/group_lifecycle_dialog.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/group_detail_dialog.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/manage_entities_widget.dart';
import 'live_audit_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final role in ['director', 'manager']) {
    testWidgets(
      '$role archives and restores a group without losing membership',
      (tester) async {
        final h = LiveAuditHarness(tester, role, 'group-lifecycle');
        await h.initialize(size: const Size(1440, 1500));
        final crm = h.scope.read(magicCrmServiceProvider);
        final id = h.fixture['groups'][role] as String;
        final studentId = h.fixture['studentId'] as String;
        final name = 'LIFECYCLE-GROUP-$role';
        final modal = find.byType(GroupLifecycleDialog);
        Finder commit() =>
            find.descendant(of: modal, matching: find.byType(FilledButton));
        Future<void> cancel() =>
            h.tap(find.descendant(of: modal, matching: find.text('Отмена')));
        Future<void> reason(String text) async {
          final field = find.descendant(
            of: modal,
            matching: find.byType(TextField),
          );
          await h.tap(field);
          await tester.enterText(field, text);
          await tester.pump();
        }

        Future<void> catalog({bool archived = false}) async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await h.mount(
            SystemSettingsRouteScreen(
              key: UniqueKey(),
              initialArea: 'schedule',
            ),
          );
          await h.quiet();
          await h.tap(find.text('Группы'));
          await h.quiet();
          if (archived) {
            await h.tap(find.text('Показывать завершённые'));
            await h.quiet();
          }
        }

        Future<void> open({bool archived = false}) async {
          await catalog(archived: archived);
          final tile = find
              .ancestor(of: find.text(name), matching: find.byType(ListTile))
              .first;
          await h.tap(
            find.descendant(
              of: tile,
              matching: find.byTooltip(
                archived ? 'Восстановить группу' : 'Завершить группу',
              ),
            ),
          );
          await h.quiet();
          expect(modal, findsOneWidget);
        }

        Future<Map<String, dynamic>> current() async {
          final row = (await crm.listGroups(
            includeArchived: true,
          )).singleWhere((r) => r['id'] == id);
          h.facts.add({'step': h.currentStep, 'group': row});
          return row;
        }

        await h.check(
          'PREVIEW',
          'Участник сохранён в preview и не блокирует завершение группы без занятий',
          () async {
            await open();
            final preview = await crm.previewGroupArchive(id);
            h.facts.add({'step': h.currentStep, 'preview': preview});
            expect(preview['canArchive'], true);
            expect(preview['impact']['operational']['activeMembers'], 1);
            expect(tester.widget<FilledButton>(commit()).onPressed, isNotNull);
            await cancel();
          },
        );
        await h.check(
          'ARCHIVE-CANCEL',
          'Причина обязательна; отмена заполненного завершения не меняет группу',
          () async {
            await open();
            await h.tap(commit());
            expect(
              find.text('Укажите понятную причину (минимум 3 символа).'),
              findsOneWidget,
            );
            await reason('CANCEL-ARCHIVE');
            await cancel();
            expect((await current())['lifecycle_state'], 'active');
            expect(
              (await crm.listGroupStudents(id)).map((r) => r['id']).toList(),
              [studentId],
            );
          },
        );
        await h.check(
          'ARCHIVE',
          'Завершение группы сохраняется и убирает её из рабочего списка',
          () async {
            await open();
            await reason('GROUP-ARCHIVE-$role');
            await h.tap(commit());
            await h.quiet();
            expect(modal, findsNothing);
            expect((await current())['lifecycle_state'], 'archived');
            expect(find.text(name), findsNothing);
          },
        );
        if ((await current())['lifecycle_state'] != 'archived') {
          h.blocked(
            'RESTORE-DEPENDENTS',
            'Восстановление и история',
            'Group did not archive',
          );
          await h.finish();
          return;
        }
        await h.check(
          'ARCHIVE-FILTER',
          'Фильтр завершённых показывает группу; повторное открытие предлагает восстановление',
          () async {
            await open(archived: true);
            expect(find.text('Восстановить группу'), findsWidgets);
            expect(tester.widget<FilledButton>(commit()).onPressed, isNotNull);
            await cancel();
          },
        );
        await h.check(
          'RESTORE-CANCEL',
          'Восстановление требует причину; отмена оставляет архив',
          () async {
            await open(archived: true);
            await h.tap(commit());
            expect(
              find.text('Укажите понятную причину (минимум 3 символа).'),
              findsOneWidget,
            );
            await reason('CANCEL-RESTORE');
            await cancel();
            expect((await current())['lifecycle_state'], 'archived');
          },
        );
        await h.check(
          'RESTORE',
          'Восстановление возвращает группу в рабочий список',
          () async {
            await open(archived: true);
            await reason('GROUP-RESTORE-$role');
            await h.tap(commit());
            await h.quiet();
            expect(modal, findsNothing);
            expect((await current())['lifecycle_state'], 'active');
            await catalog();
            expect(find.text(name), findsOneWidget);
          },
        );
        if ((await current())['lifecycle_state'] != 'active') {
          h.blocked(
            'MEMBERS-DEPENDENT',
            'Состав после восстановления',
            'Group remains archived',
          );
          await h.finish();
          return;
        }
        await h.check(
          'MEMBERS',
          'После восстановления сохранён исходный участник в API и реальной карточке',
          () async {
            expect(
              (await crm.listGroupStudents(id)).map((r) => r['id']).toList(),
              [studentId],
            );
            await catalog();
            await h.tap(find.text(name));
            await h.quiet();
            expect(find.byType(GroupDetailDialog), findsOneWidget);
            expect(find.byIcon(Icons.remove_circle_outline), findsOneWidget);
          },
        );
        await h.check(
          'HISTORY',
          'История показывает обе операции, причины и возрастающие версии',
          () async {
            final history = await crm.listGroupLifecycleHistory(id);
            h.facts.add({'step': h.currentStep, 'history': history});
            expect(history.length, 2);
            expect(history.map((r) => r['toState']).toSet(), {
              'active',
              'archived',
            });
            await open();
            await h.tap(find.text('История (2)'));
            expect(find.text('Группа завершена'), findsOneWidget);
            expect(find.text('Группа восстановлена'), findsOneWidget);
            await cancel();
          },
        );
        await h.finish();
      },
      timeout: const Timeout(Duration(minutes: 8)),
    );
  }
}
