import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';

final homeworkProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final supabase = Supabase.instance.client;
  final user = supabase.auth.currentUser;
  if (user == null) return [];

  final studentRes = await supabase
      .from('students')
      .select('id')
      .eq('profile_id', user.id)
      .maybeSingle();
  if (studentRes == null) return [];

  final tasks = await supabase
      .from('tasks')
      .select('*')
      .eq('student_id', studentRes['id'])
      .order('created_at', ascending: false);

  return List<Map<String, dynamic>>.from(tasks);
});

class HomeworkWidget extends ConsumerWidget {
  const HomeworkWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final homeworkAsync = ref.watch(homeworkProvider);

    return homeworkAsync.when(
      loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.primaryPurple)),
      error: (err, _) => Center(child: Text('Ошибка: $err', style: const TextStyle(color: AppTheme.danger))),
      data: (tasks) {
        if (tasks.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.assignment_turned_in_rounded, size: 64, color: AppTheme.textSecondary.withAlpha(80)),
                const SizedBox(height: 16),
                const Text('Нет текущих заданий', style: TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
              ],
            ),
          );
        }

        return RefreshIndicator(
          color: AppTheme.primaryPurple,
          onRefresh: () async => ref.invalidate(homeworkProvider),
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: tasks.length,
            itemBuilder: (context, index) {
              final task = tasks[index];
              final isDone = task['status'] == 'done';
              final dt = DateTime.tryParse(task['created_at'] ?? '');
              final dateStr = dt != null ? DateFormat('d MMM', 'ru').format(dt.toLocal()) : '';

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: CheckboxListTile(
                  value: isDone,
                  activeColor: AppTheme.success,
                  checkColor: Colors.white,
                  title: Text(
                    task['title'] ?? 'Задание',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      decoration: isDone ? TextDecoration.lineThrough : null,
                      color: isDone ? AppTheme.textSecondary : AppTheme.textPrimary,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (task['description'] != null && task['description'].toString().isNotEmpty)
                        Text(task['description'], style: const TextStyle(fontSize: 12)),
                      Text('Назначено: $dateStr', style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
                    ],
                  ),
                  onChanged: (val) async {
                    if (val == null) return;
                    await Supabase.instance.client
                        .from('tasks')
                        .update({'status': val ? 'done' : 'todo'})
                        .eq('id', task['id']);
                    ref.invalidate(homeworkProvider);
                  },
                ),
              );
            },
          ),
        );
      },
    );
  }
}
