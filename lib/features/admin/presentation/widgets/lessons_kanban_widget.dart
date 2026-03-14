import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_attendance_dialog.dart';

final lessonsFilteredProvider = FutureProvider.family<List<Map<String, dynamic>>, DateTime>((ref, date) async {
  final startOfDay = DateTime(date.year, date.month, date.day);
  final endOfDay = startOfDay.add(const Duration(days: 1));
  
  final supabase = Supabase.instance.client;
  final r = await supabase
      .from('lessons')
      .select('*, students(profiles(first_name, last_name)), teachers(profiles(first_name, last_name)), rooms(name), groups(name)')
      .gte('scheduled_at', startOfDay.toIso8601String())
      .lt('scheduled_at', endOfDay.toIso8601String())
      .order('scheduled_at');
  
  return List<Map<String, dynamic>>.from(r);
});

class LessonsKanbanWidget extends ConsumerStatefulWidget {
  const LessonsKanbanWidget({super.key});

  @override
  ConsumerState<LessonsKanbanWidget> createState() => _LessonsKanbanWidgetState();
}

class _LessonsKanbanWidgetState extends ConsumerState<LessonsKanbanWidget> {
  DateTime _selectedDate = DateTime.now();
  String? _selectedRoomId;
  String? _selectedTeacherId;
  String? _selectedStudentId;

  List<Map<String, dynamic>> _rooms = [];
  List<Map<String, dynamic>> _teachers = [];
  List<Map<String, dynamic>> _students = [];

  @override
  void initState() {
    super.initState();
    _loadMetadata();
  }

  Future<void> _loadMetadata() async {
    final supabase = Supabase.instance.client;
    final results = await Future.wait([
      supabase.from('rooms').select('id, name').order('name'),
      supabase.from('teachers').select('id, profiles(first_name, last_name)').order('last_name', referencedTable: 'profiles'),
      supabase.from('students').select('id, profiles(first_name, last_name)').order('last_name', referencedTable: 'profiles'),
    ]);

    if (mounted) {
      setState(() {
        _rooms = List<Map<String, dynamic>>.from(results[0]);
        _teachers = List<Map<String, dynamic>>.from(results[1]);
        _students = List<Map<String, dynamic>>.from(results[2]);
      });
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2023),
      lastDate: DateTime(2026),
      locale: const Locale('ru', 'RU'),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lessonsAsync = ref.watch(lessonsFilteredProvider(_selectedDate));

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          _buildFilters(),
          Expanded(
            child: lessonsAsync.when(
              data: (lessons) {
                var filtered = lessons;
                if (_selectedRoomId != null) filtered = filtered.where((l) => l['room_id'] == _selectedRoomId).toList();
                if (_selectedTeacherId != null) filtered = filtered.where((l) => l['teacher_id'] == _selectedTeacherId).toList();
                if (_selectedStudentId != null) filtered = filtered.where((l) => l['student_id'] == _selectedStudentId).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('Нет занятий на эту дату', style: TextStyle(color: AppTheme.textSecondary)),
                        TextButton(
                          onPressed: () => _selectDate(context),
                          child: Text('Выбрать другую дату (${DateFormat('d MMM').format(_selectedDate)})'),
                        ),
                      ],
                    ),
                  );
                }

                // Group by room
                final grouped = <String, List<Map<String, dynamic>>>{};
                for (final l in filtered) {
                  final roomId = l['room_id'] ?? 'unassigned';
                  grouped.putIfAbsent(roomId, () => []).add(l);
                }

                final sortedRooms = [..._rooms]..sort((a, b) => (a['name'] ?? '').compareTo(b['name'] ?? ''));

                return ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.all(12),
                  children: [
                    ...sortedRooms.where((r) => grouped.containsKey(r['id']) || _selectedRoomId == null).map((room) {
                      final roomLessons = grouped[room['id']] ?? [];
                      if (roomLessons.isEmpty && _selectedRoomId != null) return const SizedBox.shrink();
                      return _KanbanColumn(title: room['name'] ?? 'Аудитория', lessons: roomLessons);
                    }),
                    if (grouped.containsKey('unassigned'))
                      _KanbanColumn(title: 'Без аудитории', lessons: grouped['unassigned']!),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.primaryPurple)),
              error: (e, _) => Center(child: Text('Ошибка: $e')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.all(12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _FilterDropdown(
              label: 'Аудитория',
              value: _selectedRoomId,
              items: _rooms,
              onChanged: (v) => setState(() => _selectedRoomId = v),
            ),
            const SizedBox(width: 8),
            _FilterDropdown(
              label: 'Преподаватель',
              value: _selectedTeacherId,
              items: _teachers.map((t) {
                final p = t['profiles'] as Map<String, dynamic>?;
                final name = '${p?['first_name'] ?? ''} ${p?['last_name'] ?? ''}'.trim();
                return {'id': t['id'], 'name': name.isEmpty ? 'Без имени' : name};
              }).toList(),
              onChanged: (v) => setState(() => _selectedTeacherId = v),
            ),
            const SizedBox(width: 8),
            _FilterDropdown(
              label: 'Ученик',
              value: _selectedStudentId,
              items: _students.map((s) {
                final p = s['profiles'] as Map<String, dynamic>?;
                final name = '${p?['first_name'] ?? ''} ${p?['last_name'] ?? ''}'.trim();
                return {'id': s['id'], 'name': name.isEmpty ? 'Без имени' : name};
              }).toList(),
              onChanged: (v) => setState(() => _selectedStudentId = v),
            ),
            const SizedBox(width: 8),
            ActionChip(
              backgroundColor: AppTheme.cardDark,
              avatar: const Icon(Icons.calendar_today_rounded, size: 16, color: AppTheme.primaryPurple),
              label: Text(DateFormat('d MMM yyyy', 'ru').format(_selectedDate), style: const TextStyle(fontSize: 12, color: Colors.white)),
              onPressed: () => _selectDate(context),
            ),
            if (_selectedRoomId != null || _selectedTeacherId != null || _selectedStudentId != null)
              IconButton(
                icon: const Icon(Icons.clear_rounded, color: AppTheme.danger),
                onPressed: () => setState(() {
                  _selectedRoomId = null;
                  _selectedTeacherId = null;
                  _selectedStudentId = null;
                }),
              ),
          ],
        ),
      ),
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  final String label;
  final String? value;
  final List<dynamic> items;
  final Function(String?) onChanged;

  const _FilterDropdown({required this.label, required this.value, required this.items, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: value != null ? AppTheme.primaryPurple : Colors.transparent),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          hint: Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
          dropdownColor: AppTheme.cardDark,
          style: const TextStyle(fontSize: 12, color: Colors.white),
          items: [
            DropdownMenuItem(value: null, child: Text('Все $label')),
            ...items.map((i) => DropdownMenuItem(value: i['id'].toString(), child: Text(i['name'] ?? 'Неизвестно'))),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _KanbanColumn extends StatelessWidget {
  final String title;
  final List<Map<String, dynamic>> lessons;

  const _KanbanColumn({required this.title, required this.lessons});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        color: AppTheme.cardDark.withAlpha(50),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppTheme.primaryPurple, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
                Text('${lessons.length}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: lessons.length,
              itemBuilder: (ctx, i) => _LessonKanbanCard(lesson: lessons[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class _LessonKanbanCard extends ConsumerWidget {
  final Map<String, dynamic> lesson;
  const _LessonKanbanCard({required this.lesson});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dt = DateTime.tryParse(lesson['scheduled_at'] ?? '');
    final timeStr = dt != null ? DateFormat('HH:mm').format(dt.toLocal()) : '';
    
    final student = lesson['students']?['profiles'];
    final studentName = student != null ? '${student['first_name'] ?? ''} ${student['last_name'] ?? ''}'.trim() : '—';
    final teacher = lesson['teachers']?['profiles'];
    final teacherName = teacher != null ? '${teacher['first_name'] ?? ''} ${teacher['last_name'] ?? ''}'.trim() : '—';
    final groupName = lesson['groups']?['name'] ?? 'Индивидуально';
    

    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: AppTheme.surfaceDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.white.withAlpha(10))),
      child: InkWell(
        onTap: () {
          LessonAttendanceDialog.show(context, lesson);
        },
        onLongPress: () {
          if (lesson['student_id'] != null) {
            context.push('/student/${lesson['student_id']}');
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(timeStr, style: const TextStyle(color: AppTheme.primaryPurple, fontWeight: FontWeight.w800, fontSize: 14)),
                  if (lesson['status'] == 'completed')
                    const Icon(Icons.check_circle_rounded, color: AppTheme.success, size: 16)
                  else
                    const Icon(Icons.radio_button_unchecked_rounded, color: AppTheme.textSecondary, size: 16),
                  
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert_rounded, size: 16, color: AppTheme.textSecondary),
                    onSelected: (val) {
                      if (val == 'cancel') _cancelLesson(context, ref, lesson['id']);
                      if (val == 'reschedule') _rescheduleLesson(context, ref, lesson['id'], dt);
                    },
                    padding: EdgeInsets.zero,
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(value: 'cancel', textStyle: TextStyle(fontSize: 13, color: Colors.white), child: Text('Отменить')),
                      const PopupMenuItem(value: 'reschedule', textStyle: TextStyle(fontSize: 13, color: Colors.white), child: Text('Перенести')),
                    ],
                  ),


                ],
              ),
              const SizedBox(height: 8),
              Text(groupName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              _buildEntityRow(Icons.person_outline_rounded, 'Уч.: $studentName'),
              _buildEntityRow(Icons.school_outlined, 'Пр.: $teacherName'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEntityRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Icon(icon, size: 12, color: AppTheme.textSecondary),
          const SizedBox(width: 4),
          Expanded(child: Text(text, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  Future<void> _cancelLesson(BuildContext context, WidgetRef ref, String lessonId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Отменить занятие?'),
        content: const Text('Статус занятия будет изменен на "Отменено".'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Назад')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Отменить', style: TextStyle(color: AppTheme.danger))),
        ],
      ),
    );

    if (confirm == true) {
      await Supabase.instance.client.from('lessons').update({'status': 'cancelled'}).eq('id', lessonId);
      ref.invalidate(lessonsFilteredProvider);
    }
  }

  Future<void> _rescheduleLesson(BuildContext context, WidgetRef ref, String lessonId, DateTime? current) async {
    final date = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !context.mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current ?? DateTime.now()),
    );
    if (time == null || !context.mounted) return;

    final newDateTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    
    await Supabase.instance.client.from('lessons').update({
      'scheduled_at': newDateTime.toIso8601String(),
    }).eq('id', lessonId);
    ref.invalidate(lessonsFilteredProvider);
  }
}
