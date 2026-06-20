import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';

final statsProvider = FutureProvider<Map<String, dynamic>>((ref) {
  return ref.watch(magicCrmServiceProvider).getOverviewStats();
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
                      color: AppTheme.primaryPurple,
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
              ],
            ),
          ),
        ),
      ),
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppTheme.primaryPurple),
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
