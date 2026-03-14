import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';

class TeacherScheduleWidget extends StatefulWidget {
  const TeacherScheduleWidget({super.key});

  @override
  State<TeacherScheduleWidget> createState() => _TeacherScheduleWidgetState();
}

class _TeacherScheduleWidgetState extends State<TeacherScheduleWidget> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _lessons = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadLessons();
  }

  Future<void> _loadLessons() async {
    setState(() => _loading = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      // Get teacher record
      final teacher = await _supabase
          .from('teachers')
          .select('id')
          .eq('profile_id', userId)
          .maybeSingle();

      if (teacher == null) {
        setState(() => _loading = false);
        return;
      }

      final now = DateTime.now();
      final weekStart = now.subtract(Duration(days: now.weekday - 1));

      final data = await _supabase
          .from('lessons')
          .select('''
            id, scheduled_at, status, duration_minutes, lesson_plan,
            students(profiles(first_name, last_name)),
            rooms(name),
            branches(name)
          ''')
          .eq('teacher_id', teacher['id'])
          .gte('scheduled_at', weekStart.toIso8601String())
          .order('scheduled_at');

      setState(() {
        _lessons = List<Map<String, dynamic>>.from(data);
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primaryPurple));
    }

    if (_lessons.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today_rounded, size: 64, color: AppTheme.textSecondary.withAlpha(80)),
            const SizedBox(height: 16),
            const Text('Нет занятий на этой неделе', style: TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _loadLessons,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Обновить'),
            )
          ],
        ),
      );
    }

    // Group by date
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final lesson in _lessons) {
      final dt = DateTime.tryParse(lesson['scheduled_at'] ?? '') ?? DateTime.now();
      final key = DateFormat('EEEE, d MMMM', 'ru').format(dt);
      grouped.putIfAbsent(key, () => []).add(lesson);
    }

    return RefreshIndicator(
      color: AppTheme.primaryPurple,
      onRefresh: _loadLessons,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: grouped.entries.map((entry) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  entry.key,
                  style: const TextStyle(
                    color: AppTheme.primaryPurple,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              ...entry.value.map((lesson) => _LessonCard(lesson: lesson, onRefresh: _loadLessons)),
              const SizedBox(height: 8),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _LessonCard extends StatelessWidget {
  final Map<String, dynamic> lesson;
  final VoidCallback onRefresh;
  const _LessonCard({required this.lesson, required this.onRefresh});

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

  Future<void> _markCompleted(BuildContext context) async {
    try {
      await Supabase.instance.client
          .from('lessons')
          .update({'status': 'completed'})
          .eq('id', lesson['id']);
      onRefresh();
    } catch (_) {}
  }

  Future<void> _editLessonPlan(BuildContext context) async {
    final controller = TextEditingController(text: lesson['lesson_plan'] ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('План занятия'),
        content: TextField(
          controller: controller,
          maxLines: 5,
          decoration: const InputDecoration(hintText: 'Что планируете делать на уроке?'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Сохранить')),
        ],
      ),
    );

    if (result != null) {
      await Supabase.instance.client
          .from('lessons')
          .update({'lesson_plan': result.trim()})
          .eq('id', lesson['id']);
      onRefresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final dt = DateTime.tryParse(lesson['scheduled_at'] ?? '');
    final time = dt != null ? DateFormat('HH:mm').format(dt) : '--:--';
    final duration = lesson['duration_minutes'] ?? 60;
    final status = lesson['status'] as String?;
    final student = lesson['students']?['profiles'];
    final studentName = student != null
        ? '${student['first_name'] ?? ''} ${student['last_name'] ?? ''}'.trim()
        : 'Неизвестен';
    final roomName = lesson['rooms']?['name'] ?? '—';

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
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(time, style: const TextStyle(color: AppTheme.primaryPurple, fontWeight: FontWeight.w700, fontSize: 15)),
                  Text('$duration мин', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(studentName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(Icons.meeting_room_rounded, size: 13, color: AppTheme.textSecondary),
                      const SizedBox(width: 4),
                      Text(roomName, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                    ],
                  ),
                  if (lesson['lesson_plan'] != null && (lesson['lesson_plan'] as String).isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      'План: ${lesson['lesson_plan']}',
                      style: const TextStyle(color: AppTheme.primaryPurple, fontSize: 11, fontStyle: FontStyle.italic),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_horiz_rounded, size: 18, color: AppTheme.textSecondary),
                  color: AppTheme.cardDark,
                  onSelected: (v) {
                    if (v == 'plan') _editLessonPlan(context);
                    if (v == 'complete') _markCompleted(context);
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'plan', child: Text('План урока')),
                    if (status == 'planned')
                      const PopupMenuItem(value: 'complete', child: Text('Завершить')),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _statusColor(status).withAlpha(25),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _statusLabel(status),
                    style: TextStyle(color: _statusColor(status), fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
                if (status == 'planned') ...[
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: () => _markCompleted(context),
                    child: const Text(
                      'Завершить',
                      style: TextStyle(color: AppTheme.primaryPurple, fontSize: 11, decoration: TextDecoration.underline),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
