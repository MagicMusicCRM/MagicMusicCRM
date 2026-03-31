import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';

class LessonAttendanceDialog extends StatefulWidget {
  final Map<String, dynamic> lesson;

  const LessonAttendanceDialog({super.key, required this.lesson});

  static Future<void> show(BuildContext context, Map<String, dynamic> lesson) {
    return showDialog(
      context: context,
      builder: (ctx) => LessonAttendanceDialog(lesson: lesson),
    );
  }

  @override
  State<LessonAttendanceDialog> createState() => _LessonAttendanceDialogState();
}

class _LessonAttendanceDialogState extends State<LessonAttendanceDialog> {
  final _supabase = Supabase.instance.client;
  bool _loading = true;
  bool _saving = false;
  List<Map<String, dynamic>> _participations = [];
  List<Map<String, dynamic>> _students = [];

  @override
  void initState() {
    super.initState();
    _loadAttendance();
  }

  Future<void> _loadAttendance() async {
    setState(() => _loading = true);
    try {
      final lessonId = widget.lesson['id'];
      final groupId = widget.lesson['group_id'];
      final studentId = widget.lesson['student_id'];

      // 1. Get students for this lesson
      if (groupId != null) {
        final res = await _supabase
            .from('group_students')
            .select('student_id, students(id, first_name, last_name, profiles(first_name, last_name))')
            .eq('group_id', groupId);
        _students = List<Map<String, dynamic>>.from(res).map((item) {
          final s = item['students'] as Map<String, dynamic>;
          final sfName = s['first_name']?.toString() ?? '';
          final slName = s['last_name']?.toString() ?? '';
          final p = s['profiles'] as Map<String, dynamic>?;
          var name = '$sfName $slName'.trim();
          if (name.isEmpty && p != null) {
            name = '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim();
          }
          return {
            'id': s['id'],
            'name': name.isEmpty ? 'Без имени' : name,
          };
        }).toList();
      } else if (studentId != null) {
        final s = widget.lesson['students'];
        final sfName = s?['first_name']?.toString() ?? '';
        final slName = s?['last_name']?.toString() ?? '';
        final p = s?['profiles'];
        var name = '$sfName $slName'.trim();
        if (name.isEmpty && p != null) {
          name = '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim();
        }
        _students = [{
          'id': studentId,
          'name': name.isEmpty ? 'Без имени' : name,
        }];
      }

      // 2. Get existing participation
      final participationRes = await _supabase
          .from('lesson_participation')
          .select('*')
          .eq('lesson_id', lessonId);
      
      _participations = List<Map<String, dynamic>>.from(participationRes);

      // Initialize missing participations in local state
      for (final student in _students) {
        final exists = _participations.any((p) => p['student_id'] == student['id']);
        if (!exists) {
          _participations.add({
            'lesson_id': lessonId,
            'student_id': student['id'],
            'is_present': true,
            'pass_reason': '',
          });
        }
      }

      setState(() => _loading = false);
    } catch (e) {
      print('Error loading attendance: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка загрузки: $e')));
        Navigator.pop(context);
      }
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final lessonId = widget.lesson['id'];
      
      // Upsert participations
      for (final p in _participations) {
        await _supabase.from('lesson_participation').upsert({
          'lesson_id': lessonId,
          'student_id': p['student_id'],
          'is_present': p['is_present'],
          'pass_reason': p['pass_reason'],
        }, onConflict: 'lesson_id,student_id');
      }

      // Update lesson status to completed
      await _supabase.from('lessons').update({'status': 'completed'}).eq('id', lessonId);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Посещаемость сохранена')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка сохранения: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Посещаемость'),
      content: _loading
          ? const SizedBox(height: 100, child: Center(child: CircularProgressIndicator(color: AppTheme.primaryPurple)))
          : SizedBox(
              width: double.maxFinite,
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _students.length,
                separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white12),
                itemBuilder: (ctx, i) {
                  final student = _students[i];
                  final participation = _participations.firstWhere((p) => p['student_id'] == student['id']);
                  
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(student['name'], style: const TextStyle(fontWeight: FontWeight.w600))),
                            Switch(
                              value: participation['is_present'],
                              onChanged: (val) => setState(() => participation['is_present'] = val),
                              activeColor: AppTheme.success,
                            ),
                            Text(participation['is_present'] ? 'Был' : 'Н/Б', 
                                style: TextStyle(
                                  fontSize: 12, 
                                  color: participation['is_present'] ? AppTheme.success : AppTheme.danger,
                                  fontWeight: FontWeight.bold
                                )),
                          ],
                        ),
                        if (!participation['is_present'])
                          TextField(
                            decoration: const InputDecoration(
                              hintText: 'Причина отсутствия...',
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(vertical: 8),
                            ),
                            style: const TextStyle(fontSize: 13),
                            onChanged: (val) => participation['pass_reason'] = val,
                            controller: TextEditingController(text: participation['pass_reason'])..selection = TextSelection.collapsed(offset: (participation['pass_reason'] ?? '').length),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Отмена', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Сохранить'),
        ),
      ],
    );
  }
}
