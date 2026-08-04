import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/workspace/workspace_controller.dart';
import 'package:magic_music_crm/core/workspace/workspace_state.dart';
import 'package:magic_music_crm/core/widgets/v7/magic_desktop_scrollbar.dart';

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
              onCloseOthers: _closeOthers,
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

  Future<void> _closeOthers(String tabId) {
    return controller.closeOtherTabs(
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
    required this.onCloseOthers,
    required this.onLimitReached,
  });

  final WorkspaceState state;
  final WorkspaceController controller;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onClose;
  final ValueChanged<String> onCloseOthers;
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
        child: Row(
          children: [
            IconButton(
              tooltip: 'Прокрутить вкладки влево',
              onPressed: () => _scrollBy(-1),
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: MagicDesktopScrollbar(
                axis: Axis.horizontal,
                controller: _scrollController,
                builder: (context, controller) => ReorderableListView.builder(
                  scrollController: controller,
                  scrollDirection: Axis.horizontal,
                  buildDefaultDragHandles: true,
                  itemCount: widget.state.tabs.length,
                  onReorder: widget.controller.reorderTab,
                  itemBuilder: (context, index) {
                    final tab = widget.state.tabs[index];
                    return _WorkspaceTabButton(
                      key: ValueKey('workspace-tab-${tab.tabId}'),
                      tab: tab,
                      selected: tab.tabId == widget.state.activeTabId,
                      onPressed: () => widget.onSelect(tab.tabId),
                      onDuplicate: () {
                        try {
                          widget.controller.duplicateTab(tab.tabId);
                        } on WorkspaceLimitReached {
                          widget.onLimitReached?.call();
                        }
                      },
                      onClose: () => widget.onClose(tab.tabId),
                      onCloseOthers: () => widget.onCloseOthers(tab.tabId),
                    );
                  },
                ),
              ),
            ),
            IconButton(
              tooltip: 'Прокрутить вкладки вправо',
              onPressed: () => _scrollBy(1),
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _scrollBy(int direction) async {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final target =
        (_scrollController.offset +
                position.viewportDimension * 0.8 * direction)
            .clamp(position.minScrollExtent, position.maxScrollExtent);
    await _scrollController.animateTo(
      target,
      duration: AppMotion.effective(context, AppMotion.fast),
      curve: AppMotion.ease,
    );
  }
}

enum _WorkspaceTabAction { duplicate, close, closeOthers }

class _WorkspaceTabButton extends StatefulWidget {
  const _WorkspaceTabButton({
    super.key,
    required this.tab,
    required this.selected,
    required this.onPressed,
    required this.onDuplicate,
    required this.onClose,
    required this.onCloseOthers,
  });

  final WorkspaceTabState tab;
  final bool selected;
  final VoidCallback onPressed;
  final VoidCallback onDuplicate;
  final VoidCallback onClose;
  final VoidCallback onCloseOthers;

  @override
  State<_WorkspaceTabButton> createState() => _WorkspaceTabButtonState();
}

class _WorkspaceTabButtonState extends State<_WorkspaceTabButton> {
  var _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Semantics(
        selected: widget.selected,
        button: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              key: ValueKey('workspace-tab-select-${widget.tab.tabId}'),
              onPressed: widget.onPressed,
              child: Text(widget.tab.titleHint),
            ),
            AnimatedOpacity(
              opacity: _hovering ? 1 : 0,
              duration: const Duration(milliseconds: 100),
              child: IgnorePointer(
                ignoring: !_hovering,
                child: PopupMenuButton<_WorkspaceTabAction>(
                  key: ValueKey('workspace-tab-menu-${widget.tab.tabId}'),
                  tooltip: 'Действия вкладки',
                  icon: const Icon(Icons.more_horiz),
                  onSelected: (action) {
                    switch (action) {
                      case _WorkspaceTabAction.duplicate:
                        widget.onDuplicate();
                      case _WorkspaceTabAction.close:
                        widget.onClose();
                      case _WorkspaceTabAction.closeOthers:
                        widget.onCloseOthers();
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      key: ValueKey(
                        'workspace-tab-duplicate-${widget.tab.tabId}',
                      ),
                      value: _WorkspaceTabAction.duplicate,
                      child: const Text('Открыть в новой вкладке'),
                    ),
                    PopupMenuItem(
                      key: ValueKey('workspace-tab-close-${widget.tab.tabId}'),
                      value: _WorkspaceTabAction.close,
                      child: const Text('Закрыть'),
                    ),
                    PopupMenuItem(
                      key: ValueKey(
                        'workspace-tab-close-others-${widget.tab.tabId}',
                      ),
                      value: _WorkspaceTabAction.closeOthers,
                      child: const Text('Закрыть другие'),
                    ),
                  ],
                ),
              ),
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
