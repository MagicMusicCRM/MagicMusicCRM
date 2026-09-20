import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/branch_form_dialog.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/branch_lifecycle_dialog.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/room_lifecycle_dialog.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/manage_entities_widget.dart';

import 'live_audit_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Organization lifecycle uses real previews and durable history',
    (tester) async {
      final h = LiveAuditHarness(tester, 'director', 'organization-lifecycle');
      await h.initialize(size: const Size(1440, 1400));
      final crm = h.scope.read(magicCrmServiceProvider);
      final branchId = h.fixture['newBranchId'] as String;
      final roomId = h.fixture['newRoomId'] as String;
      const branchName = 'LIFECYCLE-BRANCH';
      const roomName = 'LIFECYCLE-ROOM';
      final branchModal = find.byType(BranchLifecycleDialog);
      final roomModal = find.byType(RoomLifecycleDialog);
      final branchForm = find.byType(BranchFormDialog);
      Future<void> catalog() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await h.mount(
          SystemSettingsRouteScreen(
            key: UniqueKey(),
            initialArea: 'organization',
          ),
        );
        await h.waitFor(
          () => find.text('HTTP test').evaluate().isNotEmpty,
          'Branch list loaded',
        );
        await h.quiet();
      }

      Finder tile(String name) => find
          .ancestor(of: find.text(name), matching: find.byType(ListTile))
          .first;
      Future<void> reason(Finder modal, String value) async {
        final field = find.descendant(
          of: modal,
          matching: find.byType(TextField),
        );
        await h.tap(field);
        await tester.enterText(field, value);
        await tester.pump();
      }

      Finder commit(Finder modal) =>
          find.descendant(of: modal, matching: find.byType(FilledButton));
      Future<void> cancel(Finder modal) =>
          h.tap(find.descendant(of: modal, matching: find.text('Отмена')));
      Future<void> openBranchLifecycle({bool archived = false}) async {
        await catalog();
        if (archived) {
          await h.tap(find.widgetWithText(FilterChip, 'Показать архив'));
          await h.quiet();
        }
        await h.tap(
          find.descendant(
            of: tile(branchName),
            matching: find.byTooltip(
              archived ? 'Восстановить филиал' : 'Проверить закрытие',
            ),
          ),
        );
        await h.quiet();
        expect(branchModal, findsOneWidget);
      }

      Future<void> openRoomLifecycle({
        bool archived = false,
        bool busy = false,
      }) async {
        await catalog();
        await h.tap(find.text(busy ? 'HTTP test' : branchName));
        await h.quiet();
        var name = roomName;
        if (busy) {
          final rooms = await crm.listRooms(
            branchId: h.fixture['busyBranchId'] as String,
          );
          name =
              rooms.singleWhere(
                    (r) => r['id'] == h.fixture['busyRoomId'],
                  )['name']
                  as String;
        }
        if (archived) {
          await h.tap(
            find.descendant(of: branchForm, matching: find.text('Архив')),
          );
          await h.quiet();
        }
        await h.tap(
          find.descendant(
            of: tile(name),
            matching: find.byTooltip(
              archived ? 'Восстановить' : 'Проверить связи и архивировать',
            ),
          ),
        );
        await h.quiet();
        expect(roomModal, findsOneWidget);
      }

      Future<Map<String, dynamic>> branch() async {
        final value = (await crm.listBranches(
          includeArchived: true,
        )).singleWhere((r) => r['id'] == branchId);
        h.facts.add({'step': h.currentStep, 'branch': value});
        return value;
      }

      Future<Map<String, dynamic>> room() async {
        final value = (await crm.listRooms(
          branchId: branchId,
          includeArchived: true,
        )).singleWhere((r) => r['id'] == roomId);
        h.facts.add({'step': h.currentStep, 'room': value});
        return value;
      }

      await h.check(
        'ROOM-BLOCKERS',
        'Аудитория с назначенными занятиями не архивируется',
        () async {
          await openRoomLifecycle(busy: true);
          expect(find.text('Сначала устраните блокеры'), findsOneWidget);
          expect(
            tester.widget<FilledButton>(commit(roomModal)).onPressed,
            isNull,
          );
          final preview = await crm.previewRoomArchive(
            h.fixture['busyRoomId'] as String,
          );
          h.facts.add({'step': h.currentStep, 'preview': preview});
          expect(preview['canArchive'], false);
          expect(preview['blockers'], isNotEmpty);
          await cancel(roomModal);
        },
      );
      await h.check(
        'BRANCH-BLOCKERS',
        'Активная аудитория блокирует закрытие филиала',
        () async {
          await openBranchLifecycle();
          expect(
            tester.widget<FilledButton>(commit(branchModal)).onPressed,
            isNull,
          );
          final preview = await crm.previewBranchClose(branchId);
          h.facts.add({'step': h.currentStep, 'preview': preview});
          expect(preview['canClose'], false);
          expect(
            (preview['blockers'] as List).any(
              (r) => r['code'] == 'ACTIVE_ROOMS',
            ),
            true,
          );
          await cancel(branchModal);
        },
      );
      await h.check(
        'ROOM-REASON-CANCEL',
        'Причина архива обязательна; отмена не меняет аудиторию',
        () async {
          await openRoomLifecycle();
          expect(
            tester.widget<FilledButton>(commit(roomModal)).onPressed,
            isNotNull,
          );
          await h.tap(commit(roomModal));
          expect(
            find.text('Укажите понятную причину (минимум 3 символа).'),
            findsOneWidget,
          );
          await reason(roomModal, 'ROOM-CANCELLED');
          await cancel(roomModal);
          expect((await room())['lifecycle_state'], 'active');
        },
      );
      await h.check(
        'ROOM-ARCHIVE',
        'Архивировать свободную аудиторию с причиной',
        () async {
          await openRoomLifecycle();
          await reason(roomModal, 'ROOM-ARCHIVE');
          await h.tap(commit(roomModal));
          await h.quiet();
          expect(roomModal, findsNothing);
          expect((await room())['lifecycle_state'], 'archived');
          expect(find.text(roomName), findsNothing);
        },
      );
      if ((await room())['lifecycle_state'] != 'archived') {
        h.blocked(
          'DEPENDENTS',
          'Закрытие филиала и восстановление',
          'Room archive failed',
        );
        await h.finish();
        return;
      }
      await h.check(
        'BRANCH-REASON-CANCEL',
        'После отвязки активных аудиторий филиал допускает закрытие; отмена сохраняет его',
        () async {
          await openBranchLifecycle();
          expect(
            tester.widget<FilledButton>(commit(branchModal)).onPressed,
            isNotNull,
          );
          await h.tap(commit(branchModal));
          expect(
            find.text('Укажите понятную причину (минимум 3 символа).'),
            findsOneWidget,
          );
          await reason(branchModal, 'BRANCH-CANCELLED');
          await cancel(branchModal);
          expect((await branch())['lifecycle_state'], 'active');
        },
      );
      await h.check(
        'BRANCH-CLOSE',
        'Закрытие сохраняет филиал в архиве и убирает из активного списка',
        () async {
          await openBranchLifecycle();
          await reason(branchModal, 'BRANCH-CLOSE');
          await h.tap(commit(branchModal));
          await h.quiet();
          expect(branchModal, findsNothing);
          expect((await branch())['lifecycle_state'], 'archived');
          expect(find.text(branchName), findsNothing);
        },
      );
      if ((await branch())['lifecycle_state'] != 'archived') {
        h.blocked(
          'BRANCH-RESTORE-DEPENDENT',
          'Восстановление филиала',
          'Branch close failed',
        );
        await h.finish();
        return;
      }
      await h.check(
        'BRANCH-RESTORE-CANCEL',
        'Отмена восстановления оставляет филиал в архиве',
        () async {
          await openBranchLifecycle(archived: true);
          await reason(branchModal, 'BRANCH-RESTORE-CANCELLED');
          await cancel(branchModal);
          expect((await branch())['lifecycle_state'], 'archived');
        },
      );
      await h.check(
        'BRANCH-RESTORE',
        'Восстановить филиал с причиной без потери аудитории',
        () async {
          await openBranchLifecycle(archived: true);
          await reason(branchModal, 'BRANCH-RESTORE');
          await h.tap(commit(branchModal));
          await h.quiet();
          expect(branchModal, findsNothing);
          expect((await branch())['lifecycle_state'], 'active');
          expect((await room())['lifecycle_state'], 'archived');
        },
      );
      if ((await branch())['lifecycle_state'] != 'active') {
        h.blocked(
          'ROOM-RESTORE-DEPENDENT',
          'Восстановление аудитории',
          'Branch remains archived',
        );
        await h.finish();
        return;
      }
      await h.check(
        'ROOM-RESTORE-CANCEL',
        'Отмена восстановления аудитории сохраняет архив',
        () async {
          await openRoomLifecycle(archived: true);
          await reason(roomModal, 'ROOM-RESTORE-CANCELLED');
          await cancel(roomModal);
          expect((await room())['lifecycle_state'], 'archived');
        },
      );
      await h.check(
        'ROOM-RESTORE',
        'Восстановить аудиторию внутри активного филиала',
        () async {
          await openRoomLifecycle(archived: true);
          await reason(roomModal, 'ROOM-RESTORE');
          await h.tap(commit(roomModal));
          await h.quiet();
          expect(roomModal, findsNothing);
          expect((await room())['lifecycle_state'], 'active');
          expect(find.text(roomName), findsOneWidget);
        },
      );
      await h.check(
        'HISTORY',
        'История филиала и аудитории содержит закрытие и восстановление',
        () async {
          final branchHistory = await crm.listBranchLifecycleHistory(branchId);
          final roomHistory = await crm.listRoomLifecycleHistory(roomId);
          h.facts.add({
            'step': h.currentStep,
            'branchHistory': branchHistory,
            'roomHistory': roomHistory,
          });
          for (final history in [branchHistory, roomHistory]) {
            expect(history.length, 2);
            expect(history.map((r) => r['toState']).toSet(), {
              'active',
              'archived',
            });
          }
          await openRoomLifecycle();
          await h.tap(find.text('История (2)'));
          expect(find.text('Аудитория архивирована'), findsOneWidget);
          expect(find.text('Аудитория восстановлена'), findsOneWidget);
          await cancel(roomModal);
          await openBranchLifecycle();
          await h.tap(find.text('История (2)'));
          expect(find.text('Филиал закрыт'), findsOneWidget);
          expect(find.text('Филиал восстановлен'), findsOneWidget);
        },
      );
      await h.finish();
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
