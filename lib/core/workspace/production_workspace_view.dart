import 'dart:async';

import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/navigation/app_back_policy.dart';
import 'package:magic_music_crm/core/navigation/entity_route_registry.dart';
import 'package:magic_music_crm/core/navigation/responsive_navigation_shell.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/workspace/desktop_workspace_shell.dart';
import 'package:magic_music_crm/core/workspace/magic_context_bar.dart';
import 'package:magic_music_crm/core/workspace/workspace_controller.dart';
import 'package:magic_music_crm/core/workspace/workspace_navigation_scope.dart';
import 'package:magic_music_crm/core/workspace/workspace_state.dart';

class ProductionWorkspaceNavigationData {
  const ProductionWorkspaceNavigationData({
    required this.sectionTabs,
    required this.destinations,
    required this.selectedIndex,
  });

  final List<int> sectionTabs;
  final List<ResponsiveNavDestination> destinations;
  final int selectedIndex;
}

typedef ProductionWorkspaceNavigationFor =
    ProductionWorkspaceNavigationData Function(
      WorkspaceTabState tab, {
      required bool isDesktop,
    });
typedef ProductionWorkspaceLocationFor =
    CanonicalAppLocation? Function(WorkspaceTabState tab);
typedef ProductionWorkspaceTabVisible =
    void Function(WorkspaceTabState tab, {required bool isDesktop});
typedef ProductionWorkspaceBack = Future<void> Function(WorkspaceTabState tab);
typedef ProductionWorkspaceNavigate =
    Future<void> Function(WorkspaceTabState tab, AppBreadcrumbNode node);

/// Pure responsive shell for a prepared workspace controller and callbacks.
class ProductionWorkspaceView extends StatelessWidget {
  const ProductionWorkspaceView({
    required this.controller,
    required this.tabBuilder,
    required this.navigationFor,
    required this.locationFor,
    required this.onLayoutModeChanged,
    required this.onTabVisible,
    required this.onSectionSelected,
    required this.onBack,
    required this.onNavigate,
    required this.onLimitReached,
    required this.resolveDirty,
    required this.saveDirty,
    required this.discardDirty,
    super.key,
  });

  final WorkspaceController controller;
  final WorkspaceTabBuilder tabBuilder;
  final ProductionWorkspaceNavigationFor navigationFor;
  final ProductionWorkspaceLocationFor locationFor;
  final ValueChanged<bool> onLayoutModeChanged;
  final ProductionWorkspaceTabVisible onTabVisible;
  final ValueChanged<int> onSectionSelected;
  final ProductionWorkspaceBack onBack;
  final ProductionWorkspaceNavigate onNavigate;
  final VoidCallback onLimitReached;
  final DirtyCloseResolver resolveDirty;
  final DirtyTabSaver saveDirty;
  final DirtyTabDiscarder discardDirty;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 840;
        onLayoutModeChanged(isDesktop);
        return WorkspaceNavigationScope(
          controller: controller,
          isDesktop: isDesktop,
          child: isDesktop ? Scaffold(body: _desktop()) : _mobile(),
        );
      },
    );
  }

  Widget _mobile() {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (controller.state.loggedOut) return const SizedBox.shrink();
        final tab = controller.state.activeTab;
        onTabVisible(tab, isDesktop: false);
        final navigation = navigationFor(tab, isDesktop: false);
        return AppBackScope(
          hasLocalHistory:
              tab.routeStack.length > 1 || navigation.selectedIndex != 0,
          onBack: () {
            if (tab.routeStack.length > 1) {
              unawaited(onBack(tab));
            } else {
              onSectionSelected(navigation.sectionTabs.first);
            }
          },
          child: Scaffold(
            body: SafeArea(child: tabBuilder(context, tab)),
            bottomNavigationBar: ResponsiveNavigationShell(
              isDesktop: false,
              destinations: navigation.destinations,
              selectedIndex: navigation.selectedIndex,
              onSelected: (index) =>
                  onSectionSelected(navigation.sectionTabs[index]),
            ),
          ),
        );
      },
    );
  }

  Widget _desktop() {
    return DesktopWorkspaceShell(
      controller: controller,
      tabBuilder: (context, tab) {
        if (tab.tabId == controller.state.activeTabId) {
          onTabVisible(tab, isDesktop: true);
        }
        final content = tabBuilder(context, tab);
        final navigation = navigationFor(tab, isDesktop: true);
        final shell = ResponsiveNavigationShell(
          isDesktop: true,
          destinations: navigation.destinations,
          selectedIndex: navigation.selectedIndex,
          onSelected: (index) =>
              onSectionSelected(navigation.sectionTabs[index]),
        );
        final location = locationFor(tab);
        final entityId = tab.currentRoute.link.entityId;
        final isWorkspaceRoot =
            tab.routeStack.length == 1 &&
            (entityId == '__section__' || entityId == 'home');
        final showContextBar = location != null && !isWorkspaceRoot;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(color: AppColor.sidebar, child: shell),
            Expanded(
              child: ColoredBox(
                color: AppColor.surfaceSoft,
                child: Column(
                  children: [
                    if (showContextBar)
                      MagicContextBar(
                        controller: controller,
                        tab: tab,
                        location: location,
                        currentTitle: tab.titleHint,
                        onBack: () => unawaited(onBack(tab)),
                        onNavigate: (node) => unawaited(onNavigate(tab, node)),
                      ),
                    Expanded(child: content),
                  ],
                ),
              ),
            ),
          ],
        );
      },
      onLimitReached: onLimitReached,
      resolveDirty: resolveDirty,
      saveDirty: saveDirty,
      discardDirty: discardDirty,
    );
  }
}
