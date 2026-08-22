import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/entity_link_state_view.dart';
import 'package:magic_music_crm/core/navigation/entity_presentation_resolver.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/reporting_presentation.dart';

class ReportingDrilldownView extends StatelessWidget {
  const ReportingDrilldownView({
    super.key,
    required this.loading,
    required this.error,
    required this.data,
    required this.lessonDrilldown,
    required this.onRetry,
    required this.onBack,
    required this.onOpenEntity,
  });

  final bool loading;
  final Object? error;
  final Map<String, dynamic>? data;
  final bool lessonDrilldown;
  final VoidCallback onRetry;
  final VoidCallback onBack;
  final ValueChanged<EntityLink> onOpenEntity;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error is EntityRouteState) {
      return EntityLinkStateView(state: error! as EntityRouteState);
    }
    if (error != null) {
      return _ReportingError(error: error!, onRetry: onRetry);
    }

    final items = reportingMapList(data?['items']);
    return ListView(
      key: const ValueKey('reporting-drilldown'),
      padding: const EdgeInsets.all(16),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back),
            label: const Text('К отчёту'),
          ),
        ),
        Text(
          '${lessonDrilldown ? 'Занятия' : 'Клиенты'}: '
          '${reportingInt(data?['total'])}',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 40),
            child: Center(child: Text('Список пуст')),
          ),
        ...items.map((item) {
          final parsed = EntityLink.fromJson(
            reportingStringMap(item['entityLink']),
          );
          final displayName = item['displayName']?.toString().trim() ?? '';
          final link = displayName.isEmpty
              ? parsed
              : parsed.withPresentation(
                  EntityPresentationReference(primary: displayName),
                );
          return ListTile(
            title: Text(item['displayName']?.toString() ?? 'Без имени'),
            subtitle: Text(
              (lessonDrilldown ? item['subtitle'] : item['statusLabel'])
                      ?.toString() ??
                  '',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => onOpenEntity(link),
          );
        }),
      ],
    );
  }
}

class _ReportingError extends StatelessWidget {
  const _ReportingError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const ValueKey('reporting-error'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 36),
          const SizedBox(height: 8),
          Text(
            userErrorMessage(error, fallback: 'Не удалось загрузить отчёт.'),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Повторить')),
        ],
      ),
    );
  }
}
