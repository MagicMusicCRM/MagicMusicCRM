import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/entity_presentation_resolver.dart';
import 'package:magic_music_crm/core/workspace/desktop_workspace_shell.dart';
import 'package:magic_music_crm/core/workspace/workspace_controller.dart';
import 'package:magic_music_crm/core/workspace/workspace_state.dart';

void main() {
  EntityLink link(String id) =>
      EntityLink.typed(entityType: EntityLinkType.client, entityId: id);

  WorkspaceController controller() => WorkspaceController(
    accountId: 'account-1',
    initialLink: link('home'),
    titleResolver: const EntityPresentationResolver().pageTitle,
    sharedScope: WorkspaceSharedScope(
      session: Object(),
      cache: Object(),
      realtime: Object(),
    ),
  );

  test(
    'normal open focuses existing entity and explicit new duplicates it',
    () {
      final workspace = controller();
      final first = workspace.open(link('client-1'));
      final focused = workspace.open(link('client-1'));
      final duplicate = workspace.open(link('client-1'), explicitNew: true);

      expect(focused, first);
      expect(duplicate, isNot(first));
      expect(workspace.state.tabs, hasLength(3));
      expect(workspace.state.activeTabId, duplicate);
    },
  );

  test('route and form state remain isolated per tab', () {
    final workspace = controller();
    final first = workspace.open(link('client-1'));
    final second = workspace.open(link('client-2'));

    workspace.push(
      first,
      EntityLink.typed(entityType: EntityLinkType.lesson, entityId: 'lesson-1'),
      currentViewState: ContextViewState(
        filters: const {'status': 'lead'},
        scrollOffset: 120,
      ),
    );
    workspace.registerForm(first, 'client-form', expectedVersion: 4);
    workspace.updateForm(
      first,
      'client-form',
      dirty: true,
      draft: const {'name': 'Локальный ввод'},
    );

    expect(
      workspace.state.tabs.firstWhere((tab) => tab.tabId == first).routeStack,
      hasLength(2),
    );
    expect(
      workspace.state.tabs.firstWhere((tab) => tab.tabId == second).routeStack,
      hasLength(1),
    );
    expect(
      workspace.state.tabs.firstWhere((tab) => tab.tabId == first).forms,
      contains('client-form'),
    );
    expect(
      workspace.state.tabs.firstWhere((tab) => tab.tabId == second).forms,
      isEmpty,
    );
  });

  test('re-register preserves a dirty draft and rebinds its saver', () async {
    final workspace = controller();
    final tabId = workspace.state.activeTabId;
    var saved = false;
    workspace.registerForm(tabId, 'client-form', expectedVersion: 4);
    workspace.updateForm(
      tabId,
      'client-form',
      dirty: true,
      draft: const {'name': 'Локальный ввод'},
    );

    workspace.registerForm(
      tabId,
      'client-form',
      onSave: () async {
        saved = true;
        return true;
      },
    );

    final form = workspace.state.activeTab.forms['client-form']!;
    expect(form.dirty, isTrue);
    expect(form.expectedVersion, 4);
    expect(form.draft, const {'name': 'Локальный ввод'});
    await workspace.saveDirtyForms(workspace.state.activeTab);
    expect(saved, isTrue);
  });

  test(
    'tab title follows its current route and accepts a loaded entity name',
    () {
      final workspace = WorkspaceController(
        accountId: 'account-1',
        initialLink: link('home'),
        titleResolver: const EntityPresentationResolver().pageTitle,
        sharedScope: WorkspaceSharedScope(
          session: Object(),
          cache: Object(),
          realtime: Object(),
        ),
      );

      workspace.push('tab-1', link('client-1'));
      expect(workspace.state.activeTab.titleHint, 'Ученик');

      workspace.updateEntityPresentation(
        link('client-1'),
        const EntityPresentationReference(primary: 'Иванов Иван'),
      );
      expect(workspace.state.activeTab.titleHint, 'Ученик · Иванов Иван');
      expect(
        workspace.state.activeTab.currentRoute.link.presentation?.primary,
        'Иванов Иван',
      );

      workspace.back('tab-1');
      expect(workspace.state.activeTab.titleHint, 'Ученик');
    },
  );

  test('lateral section replacement becomes the Back source for drilldown', () {
    final workspace = controller();
    final schedule = EntityLink.typed(
      entityType: EntityLinkType.report,
      entityId: '__section__',
      variant: 'lesson_list',
      optionalFocus: EntityLinkFocus(focus: 'schedule'),
    );
    workspace.replaceCurrentLink(
      'tab-1',
      schedule,
      viewState: ContextViewState(
        filters: const {'branchId': 'branch-1', 'view': 'week'},
        date: DateTime(2026, 8, 4),
        scrollOffset: 320,
      ),
    );
    workspace.push(
      'tab-1',
      EntityLink.typed(
        entityType: EntityLinkType.client,
        entityId: 'student-1',
        variant: 'student',
      ),
      currentViewState: workspace.state.activeTab.currentRoute.viewState,
    );

    workspace.back('tab-1');
    final restored = workspace.state.activeTab.currentRoute;
    expect(restored.link, same(schedule));
    expect(restored.viewState.filters['view'], 'week');
    expect(restored.viewState.filters['branchId'], 'branch-1');
    expect(restored.viewState.date, DateTime(2026, 8, 4));
    expect(restored.viewState.scrollOffset, 320);
  });

  test('restore collapses legacy schedule reports into one Schedule tab', () {
    final workspace = controller();
    final legacySchedule = EntityLink.typed(
      entityType: EntityLinkType.report,
      entityId: '2026-08-12T00:00:00.000',
      variant: 'lesson_list',
      optionalFocus: EntityLinkFocus(
        focus: 'schedule',
        filter: const {'clientId': 'client-9'},
      ),
    );
    final canonicalSchedule = EntityLink.typed(
      entityType: EntityLinkType.report,
      entityId: '__section__',
      variant: 'lesson_list',
    );

    workspace.restore(
      WorkspaceState(
        accountId: 'account-1',
        activeTabId: 'tab-2',
        tabs: [
          WorkspaceTabState(
            tabId: 'tab-1',
            titleHint: 'Расписание',
            routeStack: [
              ContextRouteState(
                link: canonicalSchedule,
                viewState: ContextViewState(),
              ),
            ],
          ),
          WorkspaceTabState(
            tabId: 'tab-2',
            titleHint: 'Отчёт',
            routeStack: [
              ContextRouteState(
                link: legacySchedule,
                viewState: ContextViewState(
                  filters: const {'clientId': 'client-9'},
                  date: DateTime(2026, 8, 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    expect(workspace.state.tabs, hasLength(1));
    expect(workspace.state.activeTabId, 'tab-2');
    expect(workspace.state.activeTab.titleHint, 'Расписание');
    expect(workspace.state.activeTab.currentRoute.link.entityId, '__section__');
    expect(
      workspace.state.activeTab.currentRoute.link.optionalFocus?.filter,
      containsPair('clientId', 'client-9'),
    );
    expect(
      workspace.state.activeTab.currentRoute.viewState.date,
      DateTime(2026, 8, 12),
    );
  });

  testWidgets('top strip switches tabs without replacing shared scope', (
    tester,
  ) async {
    final workspace = controller();
    final shared = workspace.sharedScope;
    workspace.open(link('client-1'), titleHint: 'Клиент');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DesktopWorkspaceShell(
            controller: workspace,
            tabBuilder: (context, tab) => Text(
              '${tab.currentRoute.link.entityId}:'
              '${identical(shared, workspace.sharedScope)}',
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('workspace-new-tab')), findsOneWidget);

    expect(find.text('client-1:true'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('workspace-tab-tab-1')));
    await tester.pump();
    expect(find.text('home:true'), findsOneWidget);
    expect(workspace.sharedScope, same(shared));
  });

  test('workspace rejects an eleventh tab', () {
    final workspace = controller();
    for (var index = 1; index < WorkspaceController.maxTabs; index++) {
      workspace.open(link('client-$index'), explicitNew: true);
    }

    expect(
      () => workspace.open(link('client-11'), explicitNew: true),
      throwsA(isA<WorkspaceLimitReached>()),
    );
    expect(workspace.state.tabs, hasLength(10));
  });
}
