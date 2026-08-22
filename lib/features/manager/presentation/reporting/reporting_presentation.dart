import 'package:flutter/material.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/reporting_models.dart';

List<Map<String, dynamic>> reportingMapList(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => item.map((key, value) => MapEntry(key.toString(), value)))
      .toList(growable: false);
}

Map<String, dynamic> reportingStringMap(Object? value) {
  if (value is! Map) return const {};
  return value.map((key, item) => MapEntry(key.toString(), item));
}

int reportingInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

class ReportingLinkStateView extends StatelessWidget {
  const ReportingLinkStateView({super.key, required this.state, this.onBack});

  final ReportingLinkState state;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final (icon, title, message) = switch (state) {
      ReportingLinkState.forbidden => (
        Icons.lock_outline,
        'Нет доступа',
        'Эта запись недоступна для текущего аккаунта.',
      ),
      ReportingLinkState.archived => (
        Icons.inventory_2_outlined,
        'Запись в архиве',
        'Данные доступны только для просмотра.',
      ),
      ReportingLinkState.deleted => (
        Icons.delete_outline,
        'Запись удалена',
        'Вернитесь в исходный раздел.',
      ),
      ReportingLinkState.unknown => (
        Icons.link_off,
        'Ссылка не поддерживается',
        'Откройте запись из исходного раздела.',
      ),
      ReportingLinkState.resolved => (
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
