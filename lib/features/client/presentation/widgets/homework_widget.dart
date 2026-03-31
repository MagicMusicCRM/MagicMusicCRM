import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/providers/realtime_providers.dart';
import 'package:magic_music_crm/core/widgets/skeletons.dart';

final homeworkProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final studentIdAsync = ref.watch(currentStudentIdProvider);
  final studentId = studentIdAsync.asData?.value;
  
  if (studentId == null) return [];

  // Watch the stream to trigger re-fetches
  ref.watch(studentTasksStreamProvider(studentId));

  final supabase = ref.watch(supabaseProvider);
  final tasks = await supabase
      .from('tasks')
      .select('*')
      .eq('student_id', studentId)
      .order('created_at', ascending: false);

  return List<Map<String, dynamic>>.from(tasks);
});

class HomeworkWidget extends ConsumerWidget {
  const HomeworkWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final homeworkAsync = ref.watch(homeworkProvider);

    return homeworkAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(12),
        child: ListSkeleton(count: 5),
      ),
      error: (err, _) => Center(child: Text('Ошибка: $err', style: TextStyle(color: AppTheme.danger))),
      data: (tasks) {
        if (tasks.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.assignment_turned_in_rounded, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant.withAlpha(80)),
                const SizedBox(height: 16),
                Text('Нет текущих заданий', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 16)),
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
                      color: isDone ? Theme.of(context).colorScheme.onSurfaceVariant : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (task['description'] != null && task['description'].toString().isNotEmpty)
                        Text(task['description'], style: const TextStyle(fontSize: 12)),
                      Text('Назначено: $dateStr', style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
