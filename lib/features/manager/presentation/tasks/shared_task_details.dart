import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/entity_link_text.dart';
import 'package:magic_music_crm/core/navigation/entity_route_registry.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_tasks_view.dart';

class SharedTaskDetails extends StatelessWidget {
  const SharedTaskDetails({
    super.key,
    required this.task,
    required this.history,
    required this.onOpenEntity,
  });

  final Map<String, dynamic> task;
  final Future<List<Map<String, dynamic>>> history;
  final ValueChanged<EntityLink> onOpenEntity;

  @override
  Widget build(BuildContext context) {
    final start = DateTime.tryParse(
      task['startAt']?.toString() ?? '',
    )?.toLocal();
    final rawLinked = task['linkedEntity'];
    final linked = rawLinked is Map
        ? EntityLink.fromJson({
            'entityType': rawLinked['type'],
            'entityId': rawLinked['id'],
          })
        : null;
    return SingleChildScrollView(
      padding: AppSpace.sheetBody,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (task['body']?.toString().trim().isNotEmpty == true) ...[
            Text(task['body'].toString()),
            const SizedBox(height: AppSpace.lg),
          ],
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              SharedTaskMetaChip(
                icon: task['state'] == 'closed'
                    ? Icons.check_circle_outline
                    : Icons.pending_actions_outlined,
                label: task['state'] == 'closed' ? 'Закрыта' : 'Открыта',
              ),
              SharedTaskMetaChip(
                icon: Icons.schedule_outlined,
                label: start == null
                    ? 'Без даты'
                    : DateFormat('dd.MM.yyyy HH:mm').format(start),
              ),
            ],
          ),
          if (linked?.isSupported == true) ...[
            const SizedBox(height: AppSpace.lg),
            Row(
              children: [
                const Text('Связанная запись: '),
                Flexible(
                  child: EntityLinkText(
                    key: const Key('shared-task-linked-entity'),
                    text: const EntityPresentationResolver()
                        .resolve(linked!)
                        .primary,
                    onPressed: () => onOpenEntity(linked),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpace.xl),
          Text('История', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpace.sm),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: history,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const LinearProgressIndicator();
              }
              if (snapshot.hasError) {
                return const Text('Не удалось загрузить историю задачи.');
              }
              final items = snapshot.data ?? const [];
              if (items.isEmpty) return const Text('Изменений пока нет.');
              return Column(
                children: [
                  for (final item in items)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.history_rounded),
                      title: Text(sharedTaskHistoryAction(item['action'])),
                      subtitle: Text(
                        [
                          if (item['actorName']?.toString().trim().isNotEmpty ==
                              true)
                            item['actorName'].toString(),
                          if (DateTime.tryParse(
                                item['occurredAt']?.toString() ?? '',
                              )?.toLocal()
                              case final occurred?)
                            DateFormat('dd.MM.yyyy HH:mm').format(occurred),
                        ].join(' · '),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

String sharedTaskHistoryAction(Object? action) => switch (action?.toString()) {
  'workflow.shared_task_created' => 'Задача создана',
  'workflow.shared_task_updated' => 'Задача изменена',
  'workflow.shared_task_closed' => 'Задача закрыта',
  final String value when value.startsWith('workflow.shared_task_legacy_') =>
    'Историческое изменение',
  _ => 'Задача обновлена',
};
