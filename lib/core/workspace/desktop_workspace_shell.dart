import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/entity_link_text.dart';
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
              child: _WorkspaceTabViewport(
                state: state,
                tabBuilder: tabBuilder,
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

  void _select(String tabId) {
    if (tabId == controller.state.activeTabId) return;
    controller.selectTab(tabId);
  }

  static Future<DirtyCloseDecision> _cancelDirtyClose(
    WorkspaceTabState tab,
  ) async => DirtyCloseDecision.cancel;

  static Future<void> _noSave(WorkspaceTabState tab) async {}
}

class _WorkspaceTabViewport extends StatefulWidget {
  const _WorkspaceTabViewport({required this.state, required this.tabBuilder});

  final WorkspaceState state;
  final WorkspaceTabBuilder tabBuilder;

  @override
  State<_WorkspaceTabViewport> createState() => _WorkspaceTabViewportState();
}

class _WorkspaceTabViewportState extends State<_WorkspaceTabViewport> {
  final Set<String> _mountedTabs = {};

  @override
  void initState() {
    super.initState();
    _mountedTabs.add(widget.state.activeTabId);
  }

  @override
  void didUpdateWidget(covariant _WorkspaceTabViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    final openTabs = widget.state.tabs.map((tab) => tab.tabId).toSet();
    _mountedTabs
      ..removeWhere((tabId) => !openTabs.contains(tabId))
      ..add(widget.state.activeTabId);
  }

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: widget.state.tabs.indexWhere(
        (tab) => tab.tabId == widget.state.activeTabId,
      ),
      children: [
        for (final tab in widget.state.tabs)
          KeyedSubtree(
            key: ValueKey(tab.tabId),
            child: TickerMode(
              enabled: tab.tabId == widget.state.activeTabId,
              child: _mountedTabs.contains(tab.tabId)
                  ? widget.tabBuilder(context, tab)
                  : const SizedBox.shrink(),
            ),
          ),
      ],
    );
  }
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
      key: const ValueKey('workspace-tab-strip'),
      color: AppColor.sidebar,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColor.divider)),
        ),
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: ReorderableListView.builder(
            scrollController: _scrollController,
            scrollDirection: Axis.horizontal,
            buildDefaultDragHandles: false,
            itemCount: widget.state.tabs.length,
            onReorder: widget.controller.reorderTab,
            footer: Padding(
              padding: const EdgeInsets.only(left: 4),
              child: IconButton(
                key: const ValueKey('workspace-new-tab'),
                tooltip: 'Новая вкладка',
                style: IconButton.styleFrom(
                  foregroundColor: AppColor.text2,
                  minimumSize: const Size.square(38),
                  maximumSize: const Size.square(38),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                ),
                onPressed: () {
                  try {
                    widget.controller.duplicateTab(widget.state.activeTabId);
                  } on WorkspaceLimitReached {
                    widget.onLimitReached?.call();
                  }
                },
                icon: const Icon(Icons.add_rounded),
              ),
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
        key: ValueKey('workspace-tab-surface-${tab.tabId}'),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: selected ? AppColor.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(
            color: selected ? AppColor.borderSoft : Colors.transparent,
          ),
          boxShadow: selected ? AppShadow.sh1 : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ReorderableDragStartListener(
              index: index,
              child: TextButton(
                key: ValueKey('workspace-tab-select-${tab.tabId}'),
                onPressed: onPressed,
                style: TextButton.styleFrom(
                  foregroundColor: selected ? AppColor.text : AppColor.text2,
                  minimumSize: const Size(0, 38),
                  padding: const EdgeInsets.fromLTRB(12, 0, 6, 0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                ),
                child: Text(tab.titleHint),
              ),
            ),
            IconButton(
              key: ValueKey('workspace-tab-close-${tab.tabId}'),
              tooltip: 'Закрыть вкладку',
              visualDensity: VisualDensity.compact,
              iconSize: 17,
              color: selected ? AppColor.text2 : AppColor.text3,
              style: IconButton.styleFrom(
                minimumSize: const Size.square(34),
                maximumSize: const Size.square(34),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.icon),
                ),
              ),
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
    return EntityLinkText(
      key: ValueKey('workspace-linked-${link.rawEntityType}-${link.entityId}'),
      text: label,
      onPressed: () {
        try {
          controller.open(link, explicitNew: true);
        } on WorkspaceLimitReached {
          onLimitReached?.call();
        }
      },
    );
  }
}
