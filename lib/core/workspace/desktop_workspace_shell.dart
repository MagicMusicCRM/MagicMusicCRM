import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/workspace/workspace_controller.dart';
import 'package:magic_music_crm/core/workspace/workspace_state.dart';

typedef WorkspaceTabBuilder =
    Widget Function(BuildContext context, WorkspaceTabState tab);

class DesktopWorkspaceShell extends StatelessWidget {
  const DesktopWorkspaceShell({
    required this.controller,
    required this.tabBuilder,
    super.key,
  });

  final WorkspaceController controller;
  final WorkspaceTabBuilder tabBuilder;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final state = controller.state;
        if (state.loggedOut) return const SizedBox.shrink();
        return Column(
          children: [
            Material(
              color: Theme.of(context).colorScheme.surfaceContainer,
              child: SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final tab in state.tabs)
                      _WorkspaceTabButton(
                        tab: tab,
                        selected: tab.tabId == state.activeTabId,
                        onPressed: () => controller.selectTab(tab.tabId),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: KeyedSubtree(
                key: ValueKey(state.activeTabId),
                child: tabBuilder(context, state.activeTab),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _WorkspaceTabButton extends StatelessWidget {
  const _WorkspaceTabButton({
    required this.tab,
    required this.selected,
    required this.onPressed,
  });

  final WorkspaceTabState tab;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: TextButton(
        key: ValueKey('workspace-tab-${tab.tabId}'),
        onPressed: onPressed,
        child: Text(tab.titleHint),
      ),
    );
  }
}
