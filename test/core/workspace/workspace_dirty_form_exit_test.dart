import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/forms/dirty_form_exit.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/entity_presentation_resolver.dart';
import 'package:magic_music_crm/core/workspace/workspace_controller.dart';
import 'package:magic_music_crm/core/workspace/workspace_dirty_form_exit.dart';
import 'package:magic_music_crm/core/workspace/workspace_navigation_scope.dart';

void main() {
  testWidgets('cancelled workspace dirty exit does not log out', (
    tester,
  ) async {
    final workspace = _workspaceController();
    final tabId = workspace.state.activeTabId;
    workspace.registerForm(tabId, 'editor', draft: const {'name': 'Анна'});
    workspace.updateForm(tabId, 'editor', dirty: true);
    bool? canLogout;
    await tester.pumpWidget(
      MaterialApp(
        home: WorkspaceNavigationScope(
          controller: workspace,
          isDesktop: false,
          child: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                canLogout = await requestWorkspaceDirtyExit(
                  context,
                  reason: DirtyFormExitReason.logout,
                );
              },
              child: const Text('Выйти'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Выйти'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Остаться'));
    await tester.pumpAndSettle();
    expect(canLogout, isFalse);
    expect(workspace.state.loggedOut, isFalse);
    expect(workspace.state.activeTab.forms['editor']!.dirty, isTrue);

    await tester.tap(find.text('Выйти'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Не сохранять'));
    await tester.pumpAndSettle();
    expect(canLogout, isTrue);
    expect(workspace.state.activeTab.forms['editor']!.draft, isEmpty);
  });

  testWidgets('one logout decision saves dirty forms in every tab', (
    tester,
  ) async {
    final workspace = _workspaceController();
    final firstTabId = workspace.state.activeTabId;
    final secondTabId = workspace.open(
      EntityLink.typed(
        entityType: EntityLinkType.client,
        entityId: 'student-2',
      ),
      explicitNew: true,
    );
    final saved = <String>[];
    for (final tabId in [firstTabId, secondTabId]) {
      workspace.registerForm(
        tabId,
        'editor',
        draft: {'tabId': tabId},
        onSave: () async {
          saved.add(tabId);
          return true;
        },
      );
      workspace.updateForm(tabId, 'editor', dirty: true);
    }
    bool? canLogout;
    await tester.pumpWidget(
      MaterialApp(
        home: WorkspaceNavigationScope(
          controller: workspace,
          isDesktop: true,
          child: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                canLogout = await requestWorkspaceDirtyExit(
                  context,
                  reason: DirtyFormExitReason.logout,
                );
              },
              child: const Text('Выйти'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Выйти'));
    await tester.pumpAndSettle();
    expect(find.text('Сохранить изменения?'), findsOneWidget);
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();

    expect(canLogout, isTrue);
    expect(saved, [firstTabId, secondTabId]);
    expect(workspace.state.tabs.any((tab) => tab.hasDirtyForms), isFalse);
  });
}

WorkspaceController _workspaceController() => WorkspaceController(
  accountId: 'account-1',
  initialLink: EntityLink.typed(
    entityType: EntityLinkType.chat,
    entityId: 'home',
  ),
  titleResolver: const EntityPresentationResolver().pageTitle,
  sharedScope: WorkspaceSharedScope(
    session: Object(),
    cache: Object(),
    realtime: Object(),
  ),
);
