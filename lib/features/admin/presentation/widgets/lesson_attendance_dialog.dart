import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';

class LessonAttendanceDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic> lesson;

  const LessonAttendanceDialog({super.key, required this.lesson});

  static Future<void> show(BuildContext context, Map<String, dynamic> lesson) {
    return showDialog(
      context: context,
      builder: (ctx) => LessonAttendanceDialog(lesson: lesson),
    );
  }

  @override
  ConsumerState<LessonAttendanceDialog> createState() =>
      _LessonAttendanceDialogState();
}

class _LessonAttendanceDialogState
    extends ConsumerState<LessonAttendanceDialog> {
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
      final attendance = await ref
          .read(magicCrmServiceProvider)
          .getLessonAttendance(lessonId);
      _students = List<Map<String, dynamic>>.from(attendance['students']);
      _participations = List<Map<String, dynamic>>.from(
        attendance['participations'],
      );

      setState(() => _loading = false);
    } catch (e) {
      debugPrint('Error loading attendance: $e');
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
      await ref
          .read(magicCrmServiceProvider)
          .saveLessonAttendance(lessonId, _participations);

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
          ? const SizedBox(height: 100, child: Center(child: CircularProgressIndicator(color: AppTheme.primaryGold)))
          : SizedBox(
              width: double.maxFinite,
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _students.length,
                separatorBuilder: (_, _) => const Divider(height: 1, color: Colors.white12),
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
                              activeThumbColor: AppTheme.success,
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
