import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/providers/realtime_providers.dart';
import 'package:magic_music_crm/core/widgets/skeletons.dart';

// Provider for the active tab (0: Upcoming, 1: History)

final upcomingLessonsRichProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final supabase = ref.watch(supabaseProvider);
  final user = supabase.auth.currentUser;
  if (user == null) return [];

  final studentRes = await supabase
      .from('students')
      .select('id')
      .eq('profile_id', user.id)
      .maybeSingle();
  if (studentRes == null) return [];

  // Watch for any changes in the real-time stream to trigger a re-fetch
  ref.watch(studentLessonsStreamProvider(studentRes['id']));

  final lessons = await supabase
      .from('v_student_lessons_all')
      .select('*')
      .eq('filter_student_id', studentRes['id'])
      .gte('scheduled_at', DateTime.now().toIso8601String())
      .order('scheduled_at', ascending: true)
      .limit(20);

  return List<Map<String, dynamic>>.from(lessons);
});

final pastLessonsRichProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final supabase = ref.watch(supabaseProvider);
  final user = supabase.auth.currentUser;
  if (user == null) return [];

  final studentRes = await supabase
      .from('students')
      .select('id')
      .eq('profile_id', user.id)
      .maybeSingle();
  if (studentRes == null) return [];

  final lessons = await supabase
      .from('v_student_lessons_all')
      .select('*')
      .eq('filter_student_id', studentRes['id'])
      .lt('scheduled_at', DateTime.now().toIso8601String())
      .order('scheduled_at', ascending: false)
      .limit(50);

  return List<Map<String, dynamic>>.from(lessons);
});

class UpcomingLessonsList extends ConsumerStatefulWidget {
  const UpcomingLessonsList({super.key});

  @override
  ConsumerState<UpcomingLessonsList> createState() => _UpcomingLessonsListState();
}

class _UpcomingLessonsListState extends ConsumerState<UpcomingLessonsList> {
  int _activeTab = 0; // 0: Upcoming, 1: History

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
  Widget build(BuildContext context) {
    final upcomingAsync = ref.watch(upcomingLessonsRichProvider);
    final pastAsync = ref.watch(pastLessonsRichProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.primaryPurple.withAlpha(30)),
            ),
            child: Row(
              children: [
                _TabButton(
                  label: 'Предстоящие',
                  isActive: _activeTab == 0,
                  onTap: () => setState(() => _activeTab = 0),
                ),
                _TabButton(
                  label: 'История',
                  isActive: _activeTab == 1,
                  onTap: () => setState(() => _activeTab = 1),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: (_activeTab == 0 ? upcomingAsync : pastAsync).when(
            loading: () => const Padding(
              padding: EdgeInsets.all(12),
              child: ListSkeleton(count: 5),
            ),
            error: (err, _) => Center(child: Text('Ошибка: $err', style: const TextStyle(color: AppTheme.danger))),
            data: (lessons) {
              if (lessons.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _activeTab == 0 ? Icons.calendar_today_rounded : Icons.history_rounded, 
                        size: 64, 
                        color: Theme.of(context).colorScheme.onSurfaceVariant.withAlpha(80)
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _activeTab == 0 ? 'Нет предстоящих занятий' : 'История занятий пуста', 
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 16)
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: () {
                          ref.invalidate(upcomingLessonsRichProvider);
                          ref.invalidate(pastLessonsRichProvider);
                        },
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Обновить'),
                      ),
                    ],
                  ),
                );
              }

              return RefreshIndicator(
                color: AppTheme.primaryPurple,
                onRefresh: () async {
                  ref.invalidate(upcomingLessonsRichProvider);
                  ref.invalidate(pastLessonsRichProvider);
                },
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: lessons.length,
                  itemBuilder: (context, index) {
                    final lesson = lessons[index];
                    final branchName = lesson['branch_name'] as String? ?? 'Без филиала';
                    
                    // Unified name resolution from flattened fields
                    var teacherFirst = lesson['teacher_first_name'] as String? ?? '';
                    var teacherLast = lesson['teacher_last_name'] as String? ?? '';
                    if (teacherFirst.isEmpty && teacherLast.isEmpty) {
                      teacherFirst = lesson['teacher_profile_first_name'] as String? ?? '';
                      teacherLast = lesson['teacher_profile_last_name'] as String? ?? '';
                    }
                    final teacherName = '$teacherFirst $teacherLast'.trim();
                    
                    final room = lesson['room_name'] as String? ?? '';
                    final status = lesson['status'] as String?;
                    final dt = DateTime.tryParse(lesson['scheduled_at'] as String? ?? '');
                    
                    final dateStr = dt != null
                        ? DateFormat('EEEE, d MMMM · HH:mm', 'ru').format(dt.toUtc().add(const Duration(hours: 3)))
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
                                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
                                  Row(children: [
                                    Text('Филиал: $branchName', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
                                    if (room.isNotEmpty) ...[
                                      Text(' · ', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
                                      Text(room, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
                                    ],
                                    Text(' · ', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
                                    Text('$duration мин', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
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
          ),
        ),
      ],
    );
  }
}

class _TabButton extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _TabButton({required this.label, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isActive ? AppTheme.primaryPurple : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isActive ? Colors.white : Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}
