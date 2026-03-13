import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:intl/intl.dart';

class CreateLessonDialog extends StatefulWidget {
  const CreateLessonDialog({super.key});

  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => const CreateLessonDialog(),
    );
  }

  @override
  State<CreateLessonDialog> createState() => _CreateLessonDialogState();
}

class _CreateLessonDialogState extends State<CreateLessonDialog> {
  final _supabase = Supabase.instance.client;
  bool _loading = false;
  bool _saving = false;

  List<Map<String, dynamic>> _teachers = [];
  List<Map<String, dynamic>> _groups = [];
  List<Map<String, dynamic>> _students = [];
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _rooms = [];

  String? _selectedTeacherId;
  String? _selectedGroupId;
  String? _selectedStudentId;
  String? _selectedBranchId;
  String? _selectedRoomId;
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _supabase.from('teachers').select('id, first_name, last_name, profiles(first_name, last_name)'),
        _supabase.from('groups').select('id, name'),
        _supabase.from('students').select('id, profiles(first_name, last_name)'),
        _supabase.from('branches').select('id, name'),
      ]);

      setState(() {
        _teachers = List<Map<String, dynamic>>.from(results[0]);
        _groups = List<Map<String, dynamic>>.from(results[1]);
        _students = List<Map<String, dynamic>>.from(results[2]);
        _branches = List<Map<String, dynamic>>.from(results[3]);
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка загрузки данных: $e')));
        Navigator.pop(context);
      }
    }
  }

  Future<void> _loadRooms(String branchId) async {
    try {
      final r = await _supabase.from('rooms').select('id, name').eq('branch_id', branchId);
      setState(() {
        _rooms = List<Map<String, dynamic>>.from(r);
        _selectedRoomId = null;
      });
    } catch (e) {
      print('Error loading rooms: $e');
    }
  }

  Future<void> _save() async {
    if (_selectedTeacherId == null || (_selectedGroupId == null && _selectedStudentId == null) || _selectedBranchId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Заполните обязательные поля')));
      return;
    }

    setState(() => _saving = true);
    try {
      final scheduledAt = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _selectedTime.hour,
        _selectedTime.minute,
      ).toIso8601String();

      await _supabase.from('lessons').insert({
        'teacher_id': _selectedTeacherId,
        'group_id': _selectedGroupId,
        'student_id': _selectedStudentId,
        'branch_id': _selectedBranchId,
        'room_id': _selectedRoomId, // Can be null
        'scheduled_at': scheduledAt,
        'status': 'scheduled',
      });

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Занятие создано')));
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
    if (_loading) {
      return const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppTheme.primaryPurple),
            SizedBox(height: 16),
            Text('Загрузка данных...'),
          ],
        ),
      );
    }

    return AlertDialog(
      title: const Text('Новое занятие'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              value: _selectedTeacherId,
              decoration: const InputDecoration(labelText: 'Преподаватель *'),
              items: _teachers.map((t) {
                final fn = t['first_name']?.toString() ?? '';
                final ln = t['last_name']?.toString() ?? '';
                final p = t['profiles'] as Map<String, dynamic>?;
                final name = '$fn $ln'.trim().isEmpty ? '${p?['first_name'] ?? ''} ${p?['last_name'] ?? ''}'.trim() : '$fn $ln'.trim();
                return DropdownMenuItem(value: t['id'].toString(), child: Text(name.isEmpty ? 'Без имени' : name));
              }).toList(),
              onChanged: (val) => setState(() => _selectedTeacherId = val),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedGroupId,
              decoration: const InputDecoration(labelText: 'Группа (если есть)'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Индивидуально')),
                ..._groups.map((g) => DropdownMenuItem(value: g['id'].toString(), child: Text(g['name']?.toString() ?? 'Без названия'))),
              ],
              onChanged: (val) => setState(() {
                _selectedGroupId = val;
                if (val != null) _selectedStudentId = null;
              }),
            ),
            if (_selectedGroupId == null) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _selectedStudentId,
                decoration: const InputDecoration(labelText: 'Ученик *'),
                items: _students.map((s) {
                  final p = s['profiles'] as Map<String, dynamic>?;
                  final name = '${p?['first_name'] ?? ''} ${p?['last_name'] ?? ''}'.trim();
                  return DropdownMenuItem(value: s['id'].toString(), child: Text(name.isEmpty ? 'Без имени' : name));
                }).toList(),
                onChanged: (val) => setState(() => _selectedStudentId = val),
              ),
            ],
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedBranchId,
              decoration: const InputDecoration(labelText: 'Филиал *'),
              items: _branches.map((b) => DropdownMenuItem(value: b['id'].toString(), child: Text(b['name']?.toString() ?? ''))).toList(),
              onChanged: (val) {
                setState(() => _selectedBranchId = val);
                if (val != null) _loadRooms(val);
              },
            ),
            if (_selectedBranchId != null) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _selectedRoomId,
                decoration: const InputDecoration(labelText: 'Аудитория'),
                items: _rooms.map((r) => DropdownMenuItem(value: r['id'].toString(), child: Text(r['name']?.toString() ?? ''))).toList(),
                onChanged: (val) => setState(() => _selectedRoomId = val),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _selectedDate,
                        firstDate: DateTime.now().subtract(const Duration(days: 30)),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (d != null) setState(() => _selectedDate = d);
                    },
                    icon: const Icon(Icons.calendar_today_rounded, size: 18),
                    label: Text(DateFormat('dd.MM.yyyy').format(_selectedDate)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final t = await showTimePicker(context: context, initialTime: _selectedTime);
                      if (t != null) setState(() => _selectedTime = t);
                    },
                    icon: const Icon(Icons.access_time_rounded, size: 18),
                    label: Text(_selectedTime.format(context)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена', style: TextStyle(color: AppTheme.textSecondary)),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Создать'),
        ),
      ],
    );
  }
}
