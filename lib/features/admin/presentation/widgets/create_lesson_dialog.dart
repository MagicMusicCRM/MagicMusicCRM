import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/widgets/searchable_select.dart';
import 'package:intl/intl.dart';

class CreateLessonDialog extends StatefulWidget {
  final DateTime? initialDate;
  final String? initialRoomId;
  final String? initialBranchId;

  const CreateLessonDialog({super.key, this.initialDate, this.initialRoomId, this.initialBranchId});

  static Future<bool?> show(BuildContext context, {DateTime? initialDate, String? initialRoomId, String? initialBranchId}) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => CreateLessonDialog(initialDate: initialDate, initialRoomId: initialRoomId, initialBranchId: initialBranchId),
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
    if (widget.initialDate != null) {
      _selectedDate = widget.initialDate!;
      _selectedTime = TimeOfDay.fromDateTime(widget.initialDate!);
    }
    if (widget.initialRoomId != null) {
      _selectedRoomId = widget.initialRoomId;
    }
    if (widget.initialBranchId != null) {
      _selectedBranchId = widget.initialBranchId;
      _loadRooms(widget.initialBranchId!);
    }
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _supabase.from('teachers').select('id, first_name, last_name, profiles(first_name, last_name)'),
        _supabase.from('groups').select('id, name'),
        _supabase.from('students').select('id, first_name, last_name, profiles(first_name, last_name)'),
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
      final r = await _supabase
          .from('rooms')
          .select('id, name')
          .eq('branch_id', branchId);
      setState(() {
        _rooms = List<Map<String, dynamic>>.from(r);
        if (_selectedRoomId != null && !_rooms.any((room) => room['id'].toString() == _selectedRoomId)) {
          _selectedRoomId = null;
        }
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
      final localTime = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _selectedTime.hour,
        _selectedTime.minute,
      );
      
      // We want to save this as a timestamp with the correct offset (+03:00)
      // or convert to UTC. Given the user wants UTC+3, let's treat selected time as Moscow time.
      // If we use DateTime.toIso8601String() on a local time, it's missing the offset.
      // Let's create a UTC time that represents the same instant.
      final moscowTime = DateTime.utc(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _selectedTime.hour - 3, // Subtract 3 to get UTC
        _selectedTime.minute,
      );
      
      final scheduledAt = moscowTime.toIso8601String();

      await _supabase.from('lessons').insert({
        'teacher_id': _selectedTeacherId,
        'group_id': _selectedGroupId,
        'student_id': _selectedStudentId,
        'branch_id': _selectedBranchId,
        'room_id': _selectedRoomId, // Can be null
        'scheduled_at': scheduledAt,
        'status': 'planned',
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
            // Teacher Selection
            _buildSelectionField(
              label: 'Преподаватель *',
              value: _getTeacherName(_selectedTeacherId),
              onTap: () {
                final items = _teachers.map((t) {
                  final name = _getTeacherNameFromData(t);
                  return SearchableSelectItem(id: t['id'].toString(), label: name);
                }).toList();
                
                SearchableSelect.show(
                  context: context,
                  title: 'Выберите преподавателя',
                  hintText: 'Поиск по имени...',
                  items: items,
                  selectedId: _selectedTeacherId,
                  isNullable: false,
                  onSelected: (item) => setState(() => _selectedTeacherId = item?.id),
                );
              },
            ),
            const SizedBox(height: 16),

            // Group Selection
            DropdownButtonFormField<String>(
              value: _selectedGroupId,
              isExpanded: true,
              dropdownColor: Theme.of(context).colorScheme.surface,
              decoration: const InputDecoration(
                labelText: 'Группа',
                prefixIcon: Icon(Icons.group_rounded),
              ),
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
              const SizedBox(height: 16),
              // Student Selection
              _buildSelectionField(
                label: 'Ученик *',
                value: _getStudentName(_selectedStudentId),
                onTap: () {
                  final items = _students.map((s) {
                    final name = _getStudentNameFromData(s);
                    return SearchableSelectItem(id: s['id'].toString(), label: name);
                  }).toList();
                  
                  SearchableSelect.show(
                    context: context,
                    title: 'Выберите ученика',
                    hintText: 'Поиск по ФИО...',
                    items: items,
                    selectedId: _selectedStudentId,
                    isNullable: false,
                    onSelected: (item) => setState(() => _selectedStudentId = item?.id),
                  );
                },
              ),
            ],
            const SizedBox(height: 16),

            // Branch & Room
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedBranchId,
                    isExpanded: true,
                    dropdownColor: Theme.of(context).colorScheme.surface,
                    decoration: const InputDecoration(labelText: 'Филиал *'),
                    items: _branches.map((b) => DropdownMenuItem(value: b['id'].toString(), child: Text(b['name']?.toString() ?? ''))).toList(),
                    onChanged: (val) {
                      setState(() {
                        _selectedBranchId = val;
                        _selectedRoomId = null;
                        _rooms = [];
                      });
                      if (val != null) _loadRooms(val);
                    },
                  ),
                ),
                if (_selectedBranchId != null) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _selectedRoomId,
                      isExpanded: true,
                      dropdownColor: Theme.of(context).colorScheme.surface,
                      decoration: const InputDecoration(labelText: 'Аудитория'),
                      items: _rooms.isEmpty 
                        ? [const DropdownMenuItem(value: null, child: Text('Нет доступных'))]
                        : _rooms.map((r) => DropdownMenuItem(value: r['id'].toString(), child: Text(r['name']?.toString() ?? ''))).toList(),
                      onChanged: (val) => setState(() => _selectedRoomId = val),
                    ),
                  ),
                ],
              ],
            ),
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
                      final t = await showTimePicker(
                        context: context, 
                        initialTime: _selectedTime,
                        builder: (BuildContext context, Widget? child) {
                          return MediaQuery(
                            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
                            child: child!,
                          );
                        },
                      );
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
          child: Text('Отмена', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Создать'),
        ),
      ],
    );
  }

  String _getTeacherName(String? id) {
    if (id == null) return 'Не выбран';
    final t = _teachers.firstWhere((element) => element['id'].toString() == id, orElse: () => {});
    if (t.isEmpty) return 'Не выбран';
    return _getTeacherNameFromData(t);
  }

  String _getTeacherNameFromData(Map<String, dynamic> t) {
    final fn = t['first_name']?.toString() ?? '';
    final ln = t['last_name']?.toString() ?? '';
    final p = t['profiles'] as Map<String, dynamic>?;
    
    var name = '$fn $ln'.trim();
    if (name.isEmpty && p != null) {
      name = '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim();
    }
    return name.isEmpty ? 'Без имени' : name;
  }

  String _getStudentName(String? id) {
    if (id == null) return 'Не выбран';
    final s = _students.firstWhere((element) => element['id'].toString() == id, orElse: () => {});
    if (s.isEmpty) return 'Не выбран';
    return _getStudentNameFromData(s);
  }

  String _getStudentNameFromData(Map<String, dynamic> s) {
    final fn = s['first_name']?.toString() ?? '';
    final ln = s['last_name']?.toString() ?? '';
    final p = s['profiles'] as Map<String, dynamic>?;
    
    var name = '$fn $ln'.trim();
    if (name.isEmpty && p != null) {
      name = '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim();
    }
    return name.isEmpty ? 'Без имени' : name;
  }

  Widget _buildSelectionField({
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.transparent),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: TextStyle(
                      color: value == 'Не выбран' ? Theme.of(context).colorScheme.onSurfaceVariant : Theme.of(context).colorScheme.onSurface,
                      fontSize: 15,
                    ),
                  ),
                ),
                Icon(Icons.arrow_drop_down, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
