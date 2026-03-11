import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';

final statsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final supabase = Supabase.instance.client;

  final now = DateTime.now();
  final todayStart = DateTime(now.year, now.month, now.day).toIso8601String();
  final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59).toIso8601String();

  final studentsCount = await supabase.from('students').count();
  final teachersCount = await supabase.from('teachers').count();
  final branchesCount = await supabase.from('branches').count();
  final lessonsCount = await supabase.from('lessons')
        .select('id')
        .gte('scheduled_at', todayStart)
        .lte('scheduled_at', todayEnd)
        .count();

  return {
    'students': studentsCount,
    'teachers': teachersCount,
    'branches': branchesCount,
    'today_lessons': lessonsCount,
  };
});

class AdminOverviewWidget extends ConsumerWidget {
  const AdminOverviewWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(statsProvider);

    return statsAsync.when(
      data: (stats) => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Обзор системы', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Статистика по всей школе', style: TextStyle(color: AppTheme.textSecondary)),
            const SizedBox(height: 20),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.4,
              children: [
                _StatCard(
                  title: 'Учеников',
                  value: '${stats['students'] ?? 0}',
                  icon: Icons.school_rounded,
                  color: AppTheme.primaryPurple,
                ),
                _StatCard(
                  title: 'Преподавателей',
                  value: '${stats['teachers'] ?? 0}',
                  icon: Icons.person_rounded,
                  color: AppTheme.secondaryGold,
                ),
                _StatCard(
                  title: 'Филиалов',
                  value: '${stats['branches'] ?? 0}',
                  icon: Icons.business_rounded,
                  color: AppTheme.success,
                ),
                _StatCard(
                  title: 'Занятий сегодня',
                  value: '${stats['today_lessons'] ?? 0}',
                  icon: Icons.today_rounded,
                  color: AppTheme.warning,
                ),
              ],
            ),
          ],
        ),
      ),
      loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.primaryPurple)),
      error: (err, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: AppTheme.danger, size: 48),
            const SizedBox(height: 8),
            Text('Ошибка загрузки: $err', style: const TextStyle(color: AppTheme.textSecondary)),
            const SizedBox(height: 12),
            FilledButton(onPressed: () => ref.invalidate(statsProvider), child: const Text('Повторить')),
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

  const _StatCard({required this.title, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
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
                Text(value, style: TextStyle(color: color, fontSize: 28, fontWeight: FontWeight.w800)),
                Text(title, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
