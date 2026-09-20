import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/workspace/workspace_controller.dart';
import 'package:magic_music_crm/core/workspace/workspace_navigation_scope.dart';
import 'package:magic_music_crm/core/workspace/workspace_store.dart';
import 'package:magic_music_crm/features/crm/presentation/staff_workspace_screen.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/client_card.dart';
import 'live_audit_harness.dart';

// OS secure-storage boundary uses an isolated on-disk synthetic test store.
class AuditDiskWorkspaceStore implements WorkspaceKeyValueStore {
  AuditDiskWorkspaceStore(this.file);
  final File file;
  Map<String, dynamic> readAll() => file.existsSync()
      ? jsonDecode(file.readAsStringSync()) as Map<String, dynamic>
      : {};
  @override
  Future<String?> read(String key) async => readAll()[key] as String?;
  @override
  Future<void> write(String key, String value) async {
    final all = readAll();
    all[key] = value;
    file.writeAsStringSync(jsonEncode(all), flush: true);
  }

  @override
  Future<void> delete(String key) async {
    final all = readAll();
    all.remove(key);
    file.writeAsStringSync(jsonEncode(all), flush: true);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru'));
  final stage = Platform.environment['WORKSPACE_AUDIT_STAGE'] ?? 'first';
  testWidgets('director real workspace $stage', (tester) async {
    final storeFile = File(
      '${Platform.environment['EVIDENCE_SCREENSHOT_DIR']}/workspace-store.json',
    );
    final disk = AuditDiskWorkspaceStore(storeFile);
    final h = LiveAuditHarness(tester, 'director', 'workspace-$stage');
    await h.initialize(
      size: const Size(1500, 1150),
      workspaceStore: AccountWorkspaceStore(disk),
    );
    final students = (h.fixture['students'] as List).cast<String>();
    EntityLink link(int n) => EntityLink.typed(
      entityType: EntityLinkType.client,
      entityId: students[n],
      variant: 'student',
    );
    WorkspaceController controller() => WorkspaceNavigationScope.maybeOf(
      tester.element(find.byType(ClientCard).first),
    )!.controller;
    Finder name() => find.widgetWithText(TextFormField, 'Имя').first;
    Finder close(String tab) =>
        find.byKey(ValueKey('workspace-tab-close-$tab'));
    String visibleName() => tester
        .widget<EditableText>(
          find.descendant(of: name(), matching: find.byType(EditableText)),
        )
        .controller
        .text;
    Future<String> readName(int n) async {
      final data = await h.api.get<Map<String, dynamic>>(
        '/crm/students/${students[n]}',
      );
      return data['firstName'] as String;
    }

    var failSave = false;
    h.api.rawDio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, handler) {
          if (failSave &&
              o.method == 'PATCH' &&
              o.uri.path.endsWith('/crm/students/${students[0]}')) {
            h.trace(o, 503, error: 'auditOffline');
            handler.reject(
              DioException(
                requestOptions: o,
                response: Response(
                  requestOptions: o,
                  statusCode: 503,
                  data: {'message': 'Audit unavailable'},
                ),
                type: DioExceptionType.badResponse,
              ),
            );
            return;
          }
          handler.next(o);
        },
      ),
    );
    final expectedErrors = [
      (
        method: 'PATCH',
        path: '/api/crm/students/${students[0]}',
        status: 503,
        maxCount: 8,
      ),
    ];
    await h.check(
      'OPEN',
      stage == 'first'
          ? 'Открыть настоящую рабочую область по ссылке на ученика'
          : 'Новый процесс восстанавливает рабочую область из файла',
      () async {
        await h.mount(
          StaffWorkspaceScreen(initialLink: stage == 'first' ? link(0) : null),
        );
        await h.waitFor(
          () => find.byType(ClientCard).evaluate().isNotEmpty,
          'Actual routed card',
        );
        await h.quiet();
        if (stage != 'first') {
          expect(controller().state.tabs.length, 2);
          expect(
            controller().state.activeTab.currentRoute.link.entityId,
            students[0],
          );
        }
      },
    );
    if (stage == 'first') {
      final firstTab = controller().state.activeTabId;
      String? secondTab;
      await h.check(
        'NEW-TAB',
        'Вторая карточка в отдельной вкладке реального рабочего пространства',
        () async {
          secondTab = controller().open(link(1), explicitNew: true);
          await h.quiet();
          expect(controller().state.tabs.length, 2);
          expect(
            controller().state.activeTab.currentRoute.link.entityId,
            students[1],
          );
        },
      );
      await h.check(
        'SWITCH',
        'Кнопки вкладок переключают активную карточку',
        () async {
          await h.tap(find.byKey(ValueKey('workspace-tab-select-$firstTab')));
          await h.quiet();
          expect(controller().state.activeTabId, firstTab);
          await h.tap(find.byKey(ValueKey('workspace-tab-select-$secondTab')));
          expect(controller().state.activeTabId, secondTab);
          await h.tap(find.byKey(ValueKey('workspace-tab-select-$firstTab')));
        },
      );
      final original = await readName(0);
      await h.check(
        'DIRTY-STAY',
        'Закрытие несохранённой карточки: Остаться сохраняет черновик',
        () async {
          failSave = true;
          await tester.enterText(name(), 'AUDIT-WORKSPACE-DISCARD');
          await h.quiet();
          expect(controller().state.activeTab.hasDirtyForms, true);
          await h.tap(close(firstTab));
          await h.tap(find.text('Остаться'));
          expect(controller().state.activeTabId, firstTab);
          expect(visibleName(), 'AUDIT-WORKSPACE-DISCARD');
          expect(await readName(0), original);
        },
        expectedHttpErrors: expectedErrors,
      );
      await h.check(
        'DIRTY-DISCARD',
        'Не сохранять закрывает вкладку без изменения БД',
        () async {
          await h.tap(close(firstTab));
          await h.tap(find.text('Не сохранять'));
          await h.quiet();
          expect(
            controller().state.tabs.any((t) => t.tabId == firstTab),
            false,
          );
          expect(await readName(0), original);
          failSave = false;
        },
      );
      String? savedTab;
      await h.check(
        'DIRTY-SAVE',
        'Сохранить при закрытии повторяет неудачное автосохранение',
        () async {
          savedTab = controller().open(link(0), explicitNew: true);
          await h.quiet();
          failSave = true;
          await tester.enterText(name(), 'AUDIT-WORKSPACE-SAVED');
          await h.quiet();
          await h.tap(close(savedTab!));
          failSave = false;
          await h.tap(find.text('Сохранить'));
          await h.quiet();
          expect(
            controller().state.tabs.any((t) => t.tabId == savedTab),
            false,
          );
          expect(await readName(0), 'AUDIT-WORKSPACE-SAVED');
        },
        expectedHttpErrors: expectedErrors,
      );
      await h.check(
        'PERSIST-DRAFT',
        'Несохранённый черновик записывается на диск перед завершением процесса',
        () async {
          controller().open(link(0), explicitNew: true);
          await h.quiet();
          failSave = true;
          await tester.enterText(name(), 'AUDIT-WORKSPACE-RESTORED');
          await h.quiet();
          await h.waitFor(
            () =>
                storeFile.existsSync() &&
                storeFile.readAsStringSync().contains(
                  'AUDIT-WORKSPACE-RESTORED',
                ),
            'Draft persisted',
          );
          expect(await readName(0), 'AUDIT-WORKSPACE-SAVED');
          h.facts.add({
            'persistedTabs': controller().state.tabs.length,
            'draft': 'AUDIT-WORKSPACE-RESTORED',
            'storageBoundary': 'isolated on-disk adapter',
          });
        },
        expectedHttpErrors: expectedErrors,
      );
    } else {
      await h.check(
        'RESTORE-SAVE',
        'После настоящего перезапуска черновик автоматически сохраняется через HTTP',
        () async {
          await h.waitFor(
            () => visibleName() == 'AUDIT-WORKSPACE-RESTORED',
            'Draft visible',
          );
          await h.quiet();
          expect(await readName(0), 'AUDIT-WORKSPACE-RESTORED');
          expect(controller().state.activeTab.hasDirtyForms, false);
        },
      );
      await h.check(
        'CLEAN-CLOSE',
        'Закрыть сохранённую вкладку без запроса сохранения',
        () async {
          final tab = controller().state.activeTabId;
          await h.tap(close(tab));
          await h.quiet();
          expect(find.text('Сохранить изменения?'), findsNothing);
          expect(controller().state.tabs.length, 1);
        },
      );
      await h.check(
        'LOGOUT-CONTEXT',
        'Координатор выхода очищает контекст и сохранённые вкладки аккаунта',
        () async {
          await h.scope.read(workspaceLogoutCoordinatorProvider).logoutAll();
          await h.quiet();
          expect(disk.readAll(), isEmpty);
        },
      );
    }
    await h.finish();
  });
}
