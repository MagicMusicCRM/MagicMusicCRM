import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/v7/magic_shimmer.dart';

enum MagicPageStateKind { loading, empty, error, forbidden }

class MagicPageState extends StatelessWidget {
  const MagicPageState({
    required this.kind,
    this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  const MagicPageState.loading({super.key})
    : kind = MagicPageStateKind.loading,
      title = null,
      message = null,
      actionLabel = null,
      onAction = null;

  final MagicPageStateKind kind;
  final String? title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    if (kind == MagicPageStateKind.loading) {
      return const Padding(
        padding: EdgeInsets.all(AppSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SkeletonBox(height: 52, radius: AppRadius.control),
            SizedBox(height: AppSpace.sm),
            SkeletonBox(height: 52, radius: AppRadius.control),
            SizedBox(height: AppSpace.sm),
            SkeletonBox(height: 52, radius: AppRadius.control),
          ],
        ),
      );
    }
    final icon = switch (kind) {
      MagicPageStateKind.empty => Icons.inbox_outlined,
      MagicPageStateKind.error => Icons.error_outline_rounded,
      MagicPageStateKind.forbidden => Icons.lock_outline_rounded,
      MagicPageStateKind.loading => Icons.hourglass_empty_rounded,
    };
    final fallbackTitle = switch (kind) {
      MagicPageStateKind.empty => 'Здесь пока ничего нет',
      MagicPageStateKind.error => 'Не удалось загрузить данные',
      MagicPageStateKind.forbidden => 'Нет доступа',
      MagicPageStateKind.loading => '',
    };
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 36,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: AppSpace.sm),
              Text(
                title ?? fallbackTitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (message case final text? when text.isNotEmpty) ...[
                const SizedBox(height: AppSpace.xs),
                Text(
                  text,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (onAction != null && actionLabel != null) ...[
                const SizedBox(height: AppSpace.md),
                FilledButton.icon(
                  onPressed: onAction,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
