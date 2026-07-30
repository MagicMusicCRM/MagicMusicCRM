import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/navigation/entity_route_registry.dart';

class EntityLinkStateView extends StatelessWidget {
  const EntityLinkStateView({
    super.key,
    required this.state,
    this.onBack,
  });

  final EntityRouteState state;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final (icon, title, message) = switch (state) {
      EntityRouteState.forbidden => (
        Icons.lock_outline,
        'Нет доступа',
        'Эта запись недоступна для текущего аккаунта.',
      ),
      EntityRouteState.archived => (
        Icons.inventory_2_outlined,
        'Запись в архиве',
        'Данные доступны только для просмотра.',
      ),
      EntityRouteState.deleted => (
        Icons.delete_outline,
        'Запись удалена',
        'Вернитесь в исходный раздел.',
      ),
      EntityRouteState.unknown => (
        Icons.link_off,
        'Ссылка не поддерживается',
        'Откройте запись из исходного раздела.',
      ),
      EntityRouteState.resolved => (
        Icons.open_in_new,
        'Запись доступна',
        'Переход готов.',
      ),
    };
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 36),
              const SizedBox(height: 12),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(message, textAlign: TextAlign.center),
              if (onBack != null) ...[
                const SizedBox(height: 20),
                FilledButton.tonal(
                  onPressed: onBack,
                  child: const Text('Назад'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
