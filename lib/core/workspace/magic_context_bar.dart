import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/navigation/entity_route_registry.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/workspace/workspace_controller.dart';
import 'package:magic_music_crm/core/workspace/workspace_state.dart';

class MagicContextAction {
  const MagicContextAction({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
}

class MagicContextBar extends StatelessWidget {
  const MagicContextBar({
    required this.controller,
    required this.tab,
    required this.location,
    this.actions = const [],
    super.key,
  });

  final WorkspaceController controller;
  final WorkspaceTabState tab;
  final CanonicalAppLocation location;
  final List<MagicContextAction> actions;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColor.surface,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColor.divider)),
        ),
        child: Row(
          children: [
            _HistoryButton(
              key: const ValueKey('context-back'),
              tooltip: 'Назад',
              icon: Icons.arrow_back,
              enabled: tab.routeStack.length > 1,
              onPressed: () => controller.back(tab.tabId),
            ),
            _HistoryButton(
              key: const ValueKey('context-forward'),
              tooltip: 'Вперёд',
              icon: Icons.arrow_forward,
              enabled: tab.forwardStack.isNotEmpty,
              onPressed: () => controller.forward(tab.tabId),
            ),
            const SizedBox(width: AppSpace.xs),
            const VerticalDivider(width: 1, color: AppColor.divider),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => _BreadcrumbTrail(
                  location: location,
                  availableWidth: constraints.maxWidth,
                  onNavigate: (node) => controller.push(tab.tabId, node.link),
                ),
              ),
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(width: AppSpace.sm),
              _ContextActions(actions: actions),
            ],
          ],
        ),
      ),
    );
  }
}

class _HistoryButton extends StatelessWidget {
  const _HistoryButton({
    required super.key,
    required this.tooltip,
    required this.icon,
    required this.enabled,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      iconSize: 19,
      visualDensity: VisualDensity.compact,
      onPressed: enabled ? onPressed : null,
      icon: Icon(icon),
    );
  }
}

class _BreadcrumbTrail extends StatelessWidget {
  const _BreadcrumbTrail({
    required this.location,
    required this.availableWidth,
    required this.onNavigate,
  });

  final CanonicalAppLocation location;
  final double availableWidth;
  final ValueChanged<AppBreadcrumbNode> onNavigate;

  @override
  Widget build(BuildContext context) {
    final ancestors = location.ancestors;
    final visibleLimit = availableWidth >= 1050
        ? 3
        : availableWidth >= 760
        ? 2
        : 1;
    final hiddenCount = (ancestors.length - visibleLimit).clamp(
      0,
      ancestors.length,
    );
    final hidden = ancestors.take(hiddenCount).toList(growable: false);
    final visible = ancestors.skip(hiddenCount).toList(growable: false);

    return Row(
      children: [
        if (hidden.isNotEmpty) ...[
          PopupMenuButton<AppBreadcrumbNode>(
            key: const ValueKey('context-path-menu'),
            tooltip: 'Весь путь',
            icon: const Icon(Icons.more_horiz, size: 19),
            onSelected: onNavigate,
            itemBuilder: (context) => [
              for (final node in hidden)
                PopupMenuItem(value: node, child: Text(node.title)),
            ],
          ),
          const _BreadcrumbSeparator(),
        ],
        for (final node in visible) ...[
          Flexible(
            child: TextButton(
              key: ValueKey('context-ancestor-${node.routeName}'),
              onPressed: () => onNavigate(node),
              style: TextButton.styleFrom(
                foregroundColor: AppColor.text2,
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
                minimumSize: const Size(0, 36),
              ),
              child: Text(
                node.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const _BreadcrumbSeparator(),
        ],
        Expanded(
          child: Semantics(
            header: true,
            label: 'Текущая страница: ${location.title}',
            child: Text(
              location.title,
              key: const ValueKey('context-current'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColor.text,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BreadcrumbSeparator extends StatelessWidget {
  const _BreadcrumbSeparator();

  @override
  Widget build(BuildContext context) {
    return const ExcludeSemantics(
      child: Icon(Icons.chevron_right, size: 17, color: AppColor.text2),
    );
  }
}

class _ContextActions extends StatelessWidget {
  const _ContextActions({required this.actions});

  final List<MagicContextAction> actions;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      key: const ValueKey('context-actions-menu'),
      tooltip: 'Действия страницы',
      icon: const Icon(Icons.more_vert, size: 19),
      onSelected: (index) => actions[index].onPressed(),
      itemBuilder: (context) => [
        for (var index = 0; index < actions.length; index++)
          PopupMenuItem(
            value: index,
            child: Row(
              children: [
                Icon(actions[index].icon, size: 18),
                const SizedBox(width: AppSpace.sm),
                Text(actions[index].label),
              ],
            ),
          ),
      ],
    );
  }
}
