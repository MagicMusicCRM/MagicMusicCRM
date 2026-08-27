import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/entity_presentation_resolver.dart';
import 'package:magic_music_crm/core/navigation/responsive_navigation_shell.dart';
import 'package:magic_music_crm/core/workspace/desktop_workspace_shell.dart';
import 'package:magic_music_crm/core/workspace/production_workspace_view.dart';
import 'package:magic_music_crm/core/workspace/workspace_controller.dart';
import 'package:magic_music_crm/core/workspace/workspace_navigation_scope.dart';

void main() {
  testWidgets('view owns the exact 840 responsive scope boundary', (
    tester,
  ) async {
    final controller = WorkspaceController(
      accountId: 'account-1',
      initialLink: EntityLink.typed(
        entityType: EntityLinkType.chat,
        entityId: 'home',
      ),
      sharedScope: WorkspaceSharedScope(
        session: Object(),
        cache: Object(),
        realtime: Object(),
      ),
      titleResolver: const EntityPresentationResolver().pageTitle,
    );
    addTearDown(controller.dispose);

    Future<void> pump(double width) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 800);
      await tester.pumpWidget(
        MaterialApp(
          home: ProductionWorkspaceView(
            controller: controller,
            tabBuilder: (context, tab) => Text(
              'desktop:${WorkspaceNavigationScope.maybeOf(context)?.isDesktop}',
            ),
            navigationFor: (tab, {required isDesktop}) =>
                ProductionWorkspaceNavigationData(
                  sectionTabs: const [0],
                  destinations: const [
                    ResponsiveNavDestination(
                      icon: Icons.chat_bubble_outline,
                      selectedIcon: Icons.chat_bubble,
                      label: 'Чат',
                    ),
                  ],
                  selectedIndex: 0,
                ),
            locationFor: (_) => null,
            onLayoutModeChanged: (_) {},
            onTabVisible: (_, {required isDesktop}) {},
            onSectionSelected: (_) {},
            onBack: (_) async {},
            onNavigate: (_, _) async {},
            onLimitReached: () {},
            resolveDirty: (_) async => DirtyCloseDecision.cancel,
            saveDirty: (_) async {},
            discardDirty: (_) async {},
          ),
        ),
      );
      await tester.pump();
    }

    addTearDown(tester.view.reset);
    await pump(839);
    expect(find.byType(DesktopWorkspaceShell), findsNothing);
    expect(find.text('desktop:false'), findsOneWidget);

    await pump(840);
    expect(find.byType(DesktopWorkspaceShell), findsOneWidget);
    expect(find.text('desktop:true'), findsOneWidget);
  });

  test('runtime view and host keep the approved dependency ownership', () {
    const root = 'lib/core/workspace';
    final runtime = File('$root/production_workspace_runtime.dart');
    final view = File('$root/production_workspace_view.dart');
    final host = File('$root/production_workspace_host.dart');
    expect(runtime.existsSync(), isTrue);
    expect(view.existsSync(), isTrue);
    expect(host.existsSync(), isTrue);
    if (!runtime.existsSync() || !view.existsSync() || !host.existsSync()) {
      return;
    }

    final runtimeSource = runtime.readAsStringSync();
    final viewSource = view.readAsStringSync();
    final hostSource = host.readAsStringSync();
    for (final forbidden in const [
      'flutter_riverpod',
      'BuildContext',
      'Navigator.',
      'ScaffoldMessenger',
    ]) {
      expect(runtimeSource, isNot(contains(forbidden)), reason: forbidden);
    }
    for (final forbidden in const [
      'flutter_riverpod',
      'Provider',
      'production_workspace_host.dart',
      'production_workspace_runtime.dart',
      'magic_realtime_service.dart',
      'section_unseen_service.dart',
    ]) {
      expect(viewSource, isNot(contains(forbidden)), reason: forbidden);
    }
    expect(hostSource, isNot(contains('WorkspaceController(')));
    expect(hostSource, isNot(contains('WorkspacePersistenceBinding(')));
    expect(hostSource, isNot(contains('WorkspaceNavigationScope(')));
    expect(hostSource, isNot(contains('DesktopWorkspaceShell(')));
    expect(hostSource, isNot(contains('ResponsiveNavigationShell(')));
    expect(hostSource, isNot(contains('MediaQuery.sizeOf')));
    expect(hostSource, contains('ProductionWorkspaceRuntime('));
    expect(hostSource, contains('ProductionWorkspaceView('));
    expect(viewSource, contains('onLayoutModeChanged(isDesktop)'));
    expect(hostSource, contains('_token != token'));
    expect(hostSource, contains('showDirtyFormExitDialog('));
    expect(hostSource, contains('crmNavigationRequestProvider'));
  });
}
