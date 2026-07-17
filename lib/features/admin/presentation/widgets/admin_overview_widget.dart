import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';

final statsProvider = FutureProvider<Map<String, dynamic>>((ref) {
  return ref.watch(magicCrmServiceProvider).getOverviewStats();
});

/// Tasks due within the next 24 hours, plus anything already overdue — the
/// dashboard's "актуальные задачи". Reuses /crm/tasks (its from/to filter due
/// dates and it already orders by them) rather than growing another endpoint.
final upcomingTasksProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final crm = ref.watch(magicCrmServiceProvider);
  final now = DateTime.now();
  final results = await Future.wait([
    crm.listTasks(
      status: 'open',
      from: now.toUtc().toIso8601String(),
      to: now.add(const Duration(hours: 24)).toUtc().toIso8601String(),
      limit: 20,
    ),
    // Overdue work does not stop being current just because its deadline
    // passed — it is the first thing an admin needs to see.
    crm.listTasks(
      status: 'open',
      to: now.toUtc().toIso8601String(),
      limit: 20,
    ),
  ]);
  final overdue = results[1];
  final upcoming = results[0];
  return [...overdue, ...upcoming];
});

class AdminOverviewWidget extends ConsumerWidget {
  final Function(int, int?)? onTabChange;
  const AdminOverviewWidget({super.key, this.onTabChange});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(statsProvider);

    return statsAsync.when(
      data: (stats) => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            // Keep the overview readable instead of stretching cards across the
            // whole desktop window.
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Обзор системы',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  'Статистика по всей школе',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                // Fixed-size cards that wrap: 4-up on wide, fewer on narrow,
                // never ballooning to half-screen-tall blocks.
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _StatCard(
                      title: 'Учеников',
                      value: '${stats['students'] ?? 0}',
                      icon: Icons.school_rounded,
                      color: AppTheme.primaryGold,
                      onTap: () => onTabChange?.call(1, 0),
                    ),
                    _StatCard(
                      title: 'Преподавателей',
                      value: '${stats['teachers'] ?? 0}',
                      icon: Icons.person_rounded,
                      color: AppTheme.secondaryGold,
                      onTap: () => onTabChange?.call(1, 1),
                    ),
                    _StatCard(
                      title: 'Филиалов',
                      value: '${stats['branches'] ?? 0}',
                      icon: Icons.business_rounded,
                      color: AppTheme.success,
                      onTap: () {
                        onTabChange?.call(1, 2);
                      },
                    ),
                    _StatCard(
                      title: 'Занятий сегодня',
                      value: '${stats['today_lessons'] ?? 0}',
                      icon: Icons.today_rounded,
                      color: AppTheme.warning,
                      onTap: () => onTabChange?.call(1, 3),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const _UpcomingTasksSection(),
              ],
            ),
          ),
        ),
      ),
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppTheme.primaryGold),
      ),
      error: (err, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: AppTheme.danger,
              size: 48,
            ),
            const SizedBox(height: 8),
            Text(
              'Ошибка загрузки: $err',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => ref.invalidate(statsProvider),
              child: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      height: 120,
      child: Card(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: color, size: 24),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      style: TextStyle(
                        color: color,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      title,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// «Актуальные задачи» — overdue first, then the next 24 hours. Overdue rows
/// burn red, matching the tasks screen.
class _UpcomingTasksSection extends ConsumerWidget {
  const _UpcomingTasksSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(upcomingTasksProvider);
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Актуальные задачи',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 8),
            Text(
              'на 24 часа',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Обновить',
              onPressed: () => ref.invalidate(upcomingTasksProvider),
              icon: const Icon(Icons.refresh_rounded, size: 18),
            ),
          ],
        ),
        const SizedBox(height: 8),
        tasksAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator(),
          ),
          error: (error, _) => Text(
            'Не удалось загрузить задачи: $error',
            style: TextStyle(color: cs.error, fontSize: 13),
          ),
          data: (tasks) => tasks.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Задач на ближайшие сутки нет',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                )
              : Column(
                  children: [
                    for (final task in tasks) _UpcomingTaskTile(task: task),
                  ],
                ),
        ),
      ],
    );
  }
}

class _UpcomingTaskTile extends StatelessWidget {
  final Map<String, dynamic> task;

  const _UpcomingTaskTile({required this.task});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dueAt = task['due_date'] != null
        ? DateTime.tryParse(task['due_date'].toString())?.toLocal()
        : null;
    final isOverdue = dueAt != null && dueAt.isBefore(DateTime.now());
    final due = dueAt == null
        ? '—'
        : DateFormat('d MMM, HH:mm', 'ru').format(dueAt);
    final assignee = task['assigned_name']?.toString();

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      elevation: 0,
      color: isOverdue
          ? Color.alphaBlend(AppTheme.danger.withValues(alpha: 0.06), cs.surface)
          : cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isOverdue ? AppTheme.danger : cs.outlineVariant,
          width: isOverdue ? 1.5 : 1,
        ),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(
          isOverdue ? Icons.warning_amber_rounded : Icons.task_alt_rounded,
          color: isOverdue ? AppTheme.danger : AppTheme.primaryGold,
          size: 20,
        ),
        title: Text(
          task['title']?.toString() ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        subtitle: Text(
          [
            isOverdue ? 'Просрочена: $due' : 'Срок: $due',
            if (assignee != null && assignee.trim().isNotEmpty) assignee,
          ].join(' • '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            color: isOverdue ? AppTheme.danger : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
