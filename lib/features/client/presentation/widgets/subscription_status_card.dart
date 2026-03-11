import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';

final subscriptionProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final supabase = Supabase.instance.client;
  final user = supabase.auth.currentUser;
  
  if (user == null) return null;

  final studentRes = await supabase
      .from('students')
      .select('id')
      .eq('profile_id', user.id)
      .maybeSingle();

  if (studentRes == null) return null;
  
  final studentId = studentRes['id'];

  final subRes = await supabase
      .from('subscriptions')
      .select('*, courses(name)')
      .eq('student_id', studentId)
      .eq('status', 'active')
      .order('end_date', ascending: false)
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
                  const Text(
                    'Пожалуйста, свяжитесь с администратором для приобретения или продления абонемента.',
                    style: TextStyle(color: AppTheme.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        final courseName = subscription['courses']?['name'] as String? ?? 'Неизвестный курс';
        final remainingClasses = subscription['remaining_classes'] as int? ?? 0;
        final endDateStr = subscription['end_date'] as String;
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
                    const Icon(Icons.calendar_month_rounded, color: AppTheme.textSecondary, size: 18),
                    const SizedBox(width: 8),
                    Text('Действует до: ${DateFormat('d MMMM yyyy', 'ru').format(endDate)}',
                        style: const TextStyle(color: AppTheme.textSecondary)),
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
      loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.primaryPurple)),
      error: (err, _) => Center(child: Text('Ошибка: $err', style: const TextStyle(color: AppTheme.danger))),
    );
  }
}
