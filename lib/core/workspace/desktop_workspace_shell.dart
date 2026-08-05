import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/workspace/workspace_controller.dart';
import 'package:magic_music_crm/core/workspace/workspace_state.dart';

typedef WorkspaceTabBuilder =
    Widget Function(BuildContext context, WorkspaceTabState tab);

class DesktopWorkspaceShell extends StatelessWidget {
  const DesktopWorkspaceShell({
    required this.controller,
    required this.tabBuilder,
    this.resolveDirty,
    this.saveDirty,
    this.discardDirty,
    this.onLimitReached,
    super.key,
  });

  final WorkspaceController controller;
  final WorkspaceTabBuilder tabBuilder;
  final DirtyCloseResolver? resolveDirty;
  final DirtyTabSaver? saveDirty;
  final DirtyTabDiscarder? discardDirty;
  final VoidCallback? onLimitReached;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final state = controller.state;
        if (state.loggedOut) return const SizedBox.shrink();
        return Column(
          children: [
            _WorkspaceTabStrip(
              state: state,
              controller: controller,
              onSelect: _select,
              onClose: _close,
              onLimitReached: onLimitReached,
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

  Future<void> _close(String tabId) {
    return controller.closeTab(
      tabId,
      resolveDirty: resolveDirty ?? _cancelDirtyClose,
      saveDirty: saveDirty ?? _noSave,
      discardDirty: discardDirty,
    );
  }

  Future<void> _select(String tabId) async {
    if (tabId == controller.state.activeTabId) return;
    final canLeave = await controller.resolveDirtyTab(
      controller.state.activeTabId,
      resolveDirty: resolveDirty ?? _cancelDirtyClose,
      saveDirty: saveDirty ?? _noSave,
      discardDirty: discardDirty,
    );
    if (canLeave) controller.selectTab(tabId);
  }

  static Future<DirtyCloseDecision> _cancelDirtyClose(
    WorkspaceTabState tab,
  ) async => DirtyCloseDecision.cancel;

  static Future<void> _noSave(WorkspaceTabState tab) async {}
}

class _WorkspaceTabStrip extends StatefulWidget {
  const _WorkspaceTabStrip({
    required this.state,
    required this.controller,
    required this.onSelect,
    required this.onClose,
    required this.onLimitReached,
  });

  final WorkspaceState state;
  final WorkspaceController controller;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onClose;
  final VoidCallback? onLimitReached;

  @override
  State<_WorkspaceTabStrip> createState() => _WorkspaceTabStripState();
}

class _WorkspaceTabStripState extends State<_WorkspaceTabStrip> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: SizedBox(
        height: 48,
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: ReorderableListView.builder(
            scrollController: _scrollController,
            scrollDirection: Axis.horizontal,
            buildDefaultDragHandles: false,
            itemCount: widget.state.tabs.length,
            onReorder: widget.controller.reorderTab,
            footer: IconButton(
              key: const ValueKey('workspace-new-tab'),
              tooltip: 'Новая вкладка',
              onPressed: () {
                try {
                  widget.controller.duplicateTab(widget.state.activeTabId);
                } on WorkspaceLimitReached {
                  widget.onLimitReached?.call();
                }
              },
              icon: const Icon(Icons.add_rounded),
            ),
            itemBuilder: (context, index) {
              final tab = widget.state.tabs[index];
              return _WorkspaceTabButton(
                key: ValueKey('workspace-tab-${tab.tabId}'),
                index: index,
                tab: tab,
                selected: tab.tabId == widget.state.activeTabId,
                onPressed: () => widget.onSelect(tab.tabId),
                onClose: () => widget.onClose(tab.tabId),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _WorkspaceTabButton extends StatelessWidget {
  const _WorkspaceTabButton({
    super.key,
    required this.index,
    required this.tab,
    required this.selected,
    required this.onPressed,
    required this.onClose,
  });

  final int index;
  final WorkspaceTabState tab;
  final bool selected;
  final VoidCallback onPressed;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: Container(
        color: selected
            ? AppColor.gold.withValues(alpha: 0.12)
            : Colors.transparent,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ReorderableDragStartListener(
              index: index,
              child: TextButton(
                key: ValueKey('workspace-tab-select-${tab.tabId}'),
                onPressed: onPressed,
                child: Text(tab.titleHint),
              ),
            ),
            IconButton(
              key: ValueKey('workspace-tab-close-${tab.tabId}'),
              tooltip: 'Закрыть вкладку',
              visualDensity: VisualDensity.compact,
              iconSize: 17,
              onPressed: onClose,
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class WorkspaceLinkedEntityButton extends StatelessWidget {
  const WorkspaceLinkedEntityButton({
    required this.controller,
    required this.link,
    required this.label,
    this.onLimitReached,
    super.key,
  });

  final WorkspaceController controller;
  final EntityLink link;
  final String label;
  final VoidCallback? onLimitReached;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(onPressed: () => controller.open(link), child: Text(label)),
        IconButton(
          key: ValueKey(
            'workspace-open-new-${link.rawEntityType}-${link.entityId}',
          ),
          tooltip: 'Открыть в новой вкладке',
          onPressed: () {
            try {
              controller.open(link, explicitNew: true);
            } on WorkspaceLimitReached {
              onLimitReached?.call();
            }
          },
          icon: const Icon(Icons.open_in_new),
        ),
      ],
    );
  }
}
