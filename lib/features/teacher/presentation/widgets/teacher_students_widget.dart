import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';

class TeacherStudentsWidget extends StatefulWidget {
  const TeacherStudentsWidget({super.key});

  @override
  State<TeacherStudentsWidget> createState() => _TeacherStudentsWidgetState();
}

class _TeacherStudentsWidgetState extends State<TeacherStudentsWidget> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _students = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadStudents();
  }

  Future<void> _loadStudents() async {
    setState(() => _loading = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      final teacher = await _supabase
          .from('teachers')
          .select('id')
          .eq('profile_id', userId)
          .maybeSingle();

      if (teacher == null) {
        setState(() => _loading = false);
        return;
      }

      final lessons = await _supabase
          .from('lessons')
          .select('student_id, students(id, custom_data, first_name, last_name, phone)')
          .eq('teacher_id', teacher['id']);

      // Deduplicate by student_id
      final seen = <String>{};
      final students = <Map<String, dynamic>>[];
      for (final l in lessons) {
        final sid = l['student_id'] as String?;
        if (sid != null && seen.add(sid)) {
          students.add(l['students'] as Map<String, dynamic>);
        }
      }

      // Count lessons per student
      final counts = <String, int>{};
      for (final l in lessons) {
        final sid = l['student_id'] as String?;
        if (sid != null) counts[sid] = (counts[sid] ?? 0) + 1;
      }

      setState(() {
        _students = students.map((s) {
          return {...s, '_lesson_count': counts[s['id'] as String? ?? ''] ?? 0};
        }).toList();
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

    if (_students.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_rounded, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant.withAlpha(80)),
            const SizedBox(height: 16),
            Text('Нет прикреплённых учеников', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 16)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: AppTheme.primaryPurple,
      onRefresh: _loadStudents,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _students.length,
        itemBuilder: (context, i) => _StudentCard(student: _students[i]),
      ),
    );
  }
}

class _StudentCard extends StatefulWidget {
  final Map<String, dynamic> student;
  const _StudentCard({required this.student});

  @override
  State<_StudentCard> createState() => _StudentCardState();
}

class _StudentCardState extends State<_StudentCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final student = widget.student;
    final firstName = student['first_name'] ?? '';
    final lastName = student['last_name'] ?? '';
    final fullName = '$firstName $lastName'.trim().isEmpty ? 'Без имени' : '$firstName $lastName'.trim();
    final phone = student['phone'] ?? '—';
    final lessonCount = widget.student['_lesson_count'] as int;
    final customData = widget.student['custom_data'] as Map<String, dynamic>? ?? {};
    final notes = customData['notes'] as String? ?? '';
    final level = customData['level'] as String? ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: AppTheme.primaryPurple.withAlpha(30),
                    child: Text(
                      fullName.isNotEmpty ? fullName[0].toUpperCase() : '?',
                      style: const TextStyle(color: AppTheme.primaryPurple, fontWeight: FontWeight.w700, fontSize: 18),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(fullName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                        if (level.isNotEmpty)
                          Text(level, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryPurple.withAlpha(25),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$lessonCount занятий',
                      style: const TextStyle(color: AppTheme.primaryPurple, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(_expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ],
              ),
              if (_expanded) ...[
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 8),
                _InfoRow(icon: Icons.phone_rounded, label: 'Телефон', value: phone),
                if (notes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _InfoRow(icon: Icons.notes_rounded, label: 'Заметки', value: notes),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Text('$label: ', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
      ],
    );
  }
}
