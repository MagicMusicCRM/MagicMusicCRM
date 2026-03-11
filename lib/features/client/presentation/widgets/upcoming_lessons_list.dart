import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';

final upcomingLessonsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final supabase = Supabase.instance.client;
  final user = supabase.auth.currentUser;
  if (user == null) return [];

  final studentRes = await supabase
      .from('students')
      .select('id')
      .eq('profile_id', user.id)
      .maybeSingle();
  if (studentRes == null) return [];

  final lessons = await supabase
      .from('lessons')
      .select('*, branches(name), teachers(profiles(first_name, last_name)), rooms(name)')
      .eq('student_id', studentRes['id'])
      .gte('scheduled_at', DateTime.now().toIso8601String())
      .order('scheduled_at', ascending: true)
      .limit(20);

  return List<Map<String, dynamic>>.from(lessons);
});

class UpcomingLessonsList extends ConsumerWidget {
  const UpcomingLessonsList({super.key});

  String _statusLabel(String? s) {
    switch (s) {
      case 'completed': return 'Завершено';
      case 'cancelled': return 'Отменено';
      default: return 'Запланировано';
    }
  }

  Color _statusColor(String? s) {
    switch (s) {
      case 'completed': return AppTheme.success;
      case 'cancelled': return AppTheme.danger;
      default: return AppTheme.primaryPurple;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lessonsAsync = ref.watch(upcomingLessonsProvider);

    return lessonsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.primaryPurple)),
      error: (err, _) => Center(child: Text('Ошибка: $err', style: const TextStyle(color: AppTheme.danger))),
      data: (lessons) {
        if (lessons.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.calendar_today_rounded, size: 64, color: AppTheme.textSecondary.withAlpha(80)),
                const SizedBox(height: 16),
                const Text('Нет предстоящих занятий', style: TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => ref.invalidate(upcomingLessonsProvider),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Обновить'),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          color: AppTheme.primaryPurple,
          onRefresh: () async => ref.invalidate(upcomingLessonsProvider),
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: lessons.length,
            itemBuilder: (context, index) {
              final lesson = lessons[index];
              final branchName = lesson['branches']?['name'] as String? ?? 'Без филиала';
              final teacherFirst = lesson['teachers']?['profiles']?['first_name'] as String? ?? '';
              final teacherLast = lesson['teachers']?['profiles']?['last_name'] as String? ?? '';
              final teacherName = '$teacherFirst $teacherLast'.trim();
              final room = lesson['rooms']?['name'] as String? ?? '';
              final status = lesson['status'] as String?;
              final dt = DateTime.tryParse(lesson['scheduled_at'] as String? ?? '');
              final dateStr = dt != null
                  ? DateFormat('EEEE, d MMMM · HH:mm', 'ru').format(dt.toLocal())
                  : '—';
              final duration = lesson['duration_minutes'] as int? ?? 60;

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryPurple.withAlpha(25),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.music_note_rounded, color: AppTheme.primaryPurple),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(dateStr, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            const SizedBox(height: 2),
                            Text('Преподаватель: ${teacherName.isEmpty ? 'Не назначен' : teacherName}',
                                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                            Row(children: [
                              Text('Филиал: $branchName', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                              if (room.isNotEmpty) ...[
                                const Text(' · ', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                                Text(room, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                              ],
                              const Text(' · ', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                              Text('${duration}мин', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                            ]),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _statusColor(status).withAlpha(25),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(_statusLabel(status),
                            style: TextStyle(color: _statusColor(status), fontSize: 10, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
