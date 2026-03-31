import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/providers/realtime_providers.dart';
import 'package:magic_music_crm/core/widgets/skeletons.dart';

final subscriptionProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final studentIdAsync = ref.watch(currentStudentIdProvider);
  final studentId = studentIdAsync.asData?.value;
  
  if (studentId == null) return null;

  // Watch the stream to trigger re-fetches
  ref.watch(studentSubscriptionsStreamProvider(studentId));

  final supabase = ref.watch(supabaseProvider);
  final subRes = await supabase
      .from('subscriptions')
      .select()
      .eq('student_id', studentId)
      .order('valid_until', ascending: false)
      .limit(1)
      .maybeSingle();

  return subRes;
});

class SubscriptionStatusCard extends ConsumerWidget {
  const SubscriptionStatusCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subAsync = ref.watch(subscriptionProvider);

    return subAsync.when(
      data: (subscription) {
        if (subscription == null) {
          return Card(
            margin: const EdgeInsets.all(16.0),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 64, height: 64,
                    decoration: BoxDecoration(
                      color: AppTheme.warning.withAlpha(25),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.warning_rounded, size: 32, color: AppTheme.warning),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Нет активного абонемента',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Пожалуйста, свяжитесь с администратором для приобретения или продления абонемента.',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        final courseName = (subscription['type']?.toString() ?? 'Абонемент').toUpperCase();
        final lessonsTotal = subscription['lessons_total'] as int? ?? 0;
        final lessonsUsed = subscription['lessons_used'] as int? ?? 0;
        final remainingClasses = lessonsTotal - lessonsUsed;
        final endDateStr = subscription['valid_until'] as String?;
        if (endDateStr == null) return const SizedBox.shrink();
        final endDate = DateTime.parse(endDateStr).toLocal();
        final daysLeft = endDate.difference(DateTime.now()).inDays;

        bool isExpiringSoon = daysLeft <= 7 || remainingClasses <= 2;

        return Card(
          margin: const EdgeInsets.all(16.0),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        courseName,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isExpiringSoon ? AppTheme.danger.withAlpha(25) : AppTheme.success.withAlpha(25),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Осталось: $remainingClasses',
                        style: TextStyle(
                            color: isExpiringSoon ? AppTheme.danger : AppTheme.success,
                            fontWeight: FontWeight.w700,
                            fontSize: 13),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(Icons.calendar_month_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 18),
                    const SizedBox(width: 8),
                    Text('Действует до: ${DateFormat('d MMMM yyyy', 'ru').format(endDate)}',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  ],
                ),
                if (isExpiringSoon) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12.0),
                    decoration: BoxDecoration(
                      color: AppTheme.danger.withAlpha(20),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.danger.withAlpha(50)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded, color: AppTheme.danger),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            remainingClasses <= 0
                                ? 'Абонемент закончился. Пожалуйста, продлите его.'
                                : 'Абонемент скоро закончится! Не забудьте продлить.',
                            style: const TextStyle(color: AppTheme.danger, fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
      loading: () => const _SubscriptionSkeleton(),
      error: (err, _) => Center(child: Text('Ошибка: $err', style: const TextStyle(color: AppTheme.danger))),
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
    );
  }
}

class _SubscriptionSkeleton extends StatelessWidget {
  const _SubscriptionSkeleton();

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16.0),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Skeleton(width: 150, height: 24),
                Skeleton(width: 80, height: 24),
              ],
            ),
            const SizedBox(height: 16),
            const Skeleton(width: 200, height: 18),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                   Skeleton(width: 24, height: 24),
                   SizedBox(width: 12),
                   Skeleton(width: 180, height: 14),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
