import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/providers/realtime_providers.dart';
import 'package:magic_music_crm/core/widgets/skeletons.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_attendance_dialog.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';

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
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  List<Map<String, dynamic>> _rooms = [];
  List<Map<String, dynamic>> _teachers = [];
  List<Map<String, dynamic>> _students = [];

  @override
  void initState() {
    super.initState();
    // Pre-load metadata (can also be streams)
    _loadMetadata();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadMetadata() async {
    final supabase = ref.read(supabaseProvider);
    final results = await Future.wait([
      supabase.from('rooms').select('id, name').order('name'),
      supabase.from('teachers').select('id, first_name, last_name, profiles(first_name, last_name)').order('last_name', referencedTable: 'profiles'),
      supabase.from('students').select('id, first_name, last_name, profiles(first_name, last_name)').order('last_name', referencedTable: 'profiles'),
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
    final lessonsAsync = ref.watch(lessonsStreamProvider(_selectedDate));

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          _buildFilters(),
          Expanded(
            child: lessonsAsync.when(
              data: (lessons) {
                var filtered = lessons;
                if (_selectedRoomId != null) filtered = filtered.where((l) => l['room_id'].toString() == _selectedRoomId).toList();
                if (_selectedTeacherId != null) filtered = filtered.where((l) => l['teacher_id'].toString() == _selectedTeacherId).toList();
                if (_selectedStudentId != null) filtered = filtered.where((l) => l['student_id'].toString() == _selectedStudentId).toList();

                if (_searchQuery.isNotEmpty) {
                  final q = _searchQuery.toLowerCase();
                  filtered = filtered.where((l) {
                    final student = l['students'];
                    String studentName = 'Без ученика';
                    if (student != null) {
                      final sf = student['first_name'] ?? student['profiles']?['first_name'] ?? '';
                      final sl = student['last_name'] ?? student['profiles']?['last_name'] ?? '';
                      studentName = '$sf $sl'.trim();
                      if (studentName.isEmpty) studentName = 'Без имени';
                    }
                    final sName = studentName.toLowerCase();
                    
                    final teacher = l['teachers'];
                    String teacherName = 'Без преподавателя';
                    if (teacher != null) {
                      final tf = teacher['first_name'] ?? teacher['profiles']?['first_name'] ?? '';
                      final tl = teacher['last_name'] ?? teacher['profiles']?['last_name'] ?? '';
                      teacherName = '$tf $tl'.trim();
                      if (teacherName.isEmpty) teacherName = 'Без имени';
                    }
                    final tName = teacherName.toLowerCase();
                    
                    final gName = (l['groups']?['name'] as String? ?? '').toLowerCase();
                    
                    return sName.contains(q) || tName.contains(q) || gName.contains(q);
                  }).toList();
                }

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Нет занятий на эту дату', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
                  final roomId = l['room_id']?.toString() ?? 'unassigned';
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
                      return _KanbanColumn(
                        title: room['name'] ?? 'Без названия', 
                        lessons: roomLessons,
                        teachers: _teachers,
                        students: _students,
                        selectedDate: _selectedDate,
                      );
                    }),
                    if (grouped.containsKey('unassigned'))
                      _KanbanColumn(
                        title: 'Без аудитории', 
                        lessons: grouped['unassigned']!,
                        teachers: _teachers,
                        students: _students,
                        selectedDate: _selectedDate,
                      ),
                  ],
                );
              },
              loading: () => ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(12),
                children: List.generate(3, (i) => const _KanbanColumnSkeleton()),
              ),
              error: (e, _) => Center(child: Text('Ошибка: $e')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: TextField(
            controller: _searchController,
            onChanged: (val) => setState(() => _searchQuery = val),
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Поиск по ученику, учителю или группе...',
              hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
              prefixIcon: Icon(Icons.search_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 20),
              suffixIcon: _searchQuery.isNotEmpty 
                ? IconButton(
                    icon: Icon(Icons.close_rounded, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  )
                : null,
              filled: true,
              fillColor: Theme.of(context).colorScheme.surface,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
          children: [
            _FilterDropdown(
              label: 'Аудитория',
              value: _selectedRoomId,
              items: _rooms,
              onChanged: (v) => setState(() => _selectedRoomId = v),
            ),
            SizedBox(width: 8),
            _FilterDropdown(
              label: 'Преподаватель',
              value: _selectedTeacherId,
              items: _teachers.map((t) {
                final tfName = t['first_name']?.toString() ?? '';
                final tlName = t['last_name']?.toString() ?? '';
                final p = t['profiles'] as Map<String, dynamic>?;
                var name = '$tfName $tlName'.trim();
                if (name.isEmpty && p != null) {
                  name = '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim();
                }
                return {'id': t['id'], 'name': name.isEmpty ? 'Без имени' : name};
              }).toList(),
              onChanged: (v) => setState(() => _selectedTeacherId = v),
            ),
            SizedBox(width: 8),
            _FilterDropdown(
              label: 'Ученик',
              value: _selectedStudentId,
              items: _students.map((s) {
                final sfName = s['first_name']?.toString() ?? '';
                final slName = s['last_name']?.toString() ?? '';
                final p = s['profiles'] as Map<String, dynamic>?;
                var name = '$sfName $slName'.trim();
                if (name.isEmpty && p != null) {
                  name = '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim();
                }
                return {'id': s['id'], 'name': name.isEmpty ? 'Без имени' : name};
              }).toList(),
              onChanged: (v) => setState(() => _selectedStudentId = v),
            ),
            SizedBox(width: 8),
            ActionChip(
              backgroundColor: Theme.of(context).colorScheme.surface,
              avatar: Icon(Icons.calendar_today_rounded, size: 16, color: AppTheme.primaryPurple),
              label: Text(DateFormat('d MMM yyyy', 'ru').format(_selectedDate), style: const TextStyle(fontSize: 12, color: Colors.white)),
              onPressed: () => _selectDate(context),
            ),
            if (_selectedRoomId != null || _selectedTeacherId != null || _selectedStudentId != null)
              IconButton(
                icon: Icon(Icons.clear_rounded, color: AppTheme.danger),
                onPressed: () => setState(() {
                  _selectedRoomId = null;
                  _selectedTeacherId = null;
                  _selectedStudentId = null;
                }),
              ),
            ],
          ),
        ),
      ],
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
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: value != null ? AppTheme.primaryPurple : Colors.transparent),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          hint: Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          dropdownColor: Theme.of(context).colorScheme.surface,
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
  final List<Map<String, dynamic>> teachers;
  final List<Map<String, dynamic>> students;
  final DateTime selectedDate;

  const _KanbanColumn({
    required this.title, 
    required this.lessons,
    required this.teachers,
    required this.students,
    required this.selectedDate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withAlpha(50),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppTheme.primaryPurple, shape: BoxShape.circle)),
                SizedBox(width: 8),
                Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
                Text('${lessons.length}', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: lessons.length,
              itemBuilder: (ctx, i) => _LessonKanbanCard(
                lesson: lessons[i],
                teachers: teachers,
                students: students,
                selectedDate: selectedDate,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _KanbanColumnSkeleton extends StatelessWidget {
  const _KanbanColumnSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withAlpha(50),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Skeleton(width: 120, height: 20),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: 4,
              itemBuilder: (ctx, i) => const _LessonCardSkeleton(),
            ),
          ),
        ],
      ),
    );
  }
}

class _LessonCardSkeleton extends StatelessWidget {
  const _LessonCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withAlpha(10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Skeleton(width: 60, height: 16),
              Skeleton(width: 20, height: 16),
            ],
          ),
          SizedBox(height: 12),
          Skeleton(width: 180, height: 14),
          SizedBox(height: 8),
          Skeleton(width: 140, height: 12),
          SizedBox(height: 4),
          Skeleton(width: 120, height: 12),
        ],
      ),
    );
  }
}

class _LessonKanbanCard extends ConsumerWidget {
  final Map<String, dynamic> lesson;
  final List<Map<String, dynamic>> teachers;
  final List<Map<String, dynamic>> students;
  final DateTime selectedDate;

  const _LessonKanbanCard({
    required this.lesson,
    required this.teachers,
    required this.students,
    required this.selectedDate,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dt = DateTime.tryParse(lesson['scheduled_at'] ?? '');
    final timeStr = dt != null ? DateFormat('HH:mm').format(dt.toLocal()) : '';
    final dateStr = dt != null ? DateFormat('d MMM').format(dt.toLocal()) : '';

    // Manual name resolution
    final studentId = lesson['student_id']?.toString();
    final teacherId = lesson['teacher_id']?.toString();

    String studentName = '—';
    if (studentId != null) {
      final s = students.firstWhere((e) => e['id'].toString() == studentId, orElse: () => {});
      if (s.isNotEmpty) {
        final sfName = s['first_name']?.toString() ?? '';
        final slName = s['last_name']?.toString() ?? '';
        final p = s['profiles'] as Map<String, dynamic>?;
        var name = '$sfName $slName'.trim();
        if (name.isEmpty && p != null) {
          name = '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim();
        }
        studentName = name.isEmpty ? 'Без имени' : name;
      }
    }

    String teacherName = '—';
    if (teacherId != null) {
      final t = teachers.firstWhere((e) => e['id'].toString() == teacherId, orElse: () => {});
      if (t.isNotEmpty) {
        final tfName = t['first_name']?.toString() ?? '';
        final tlName = t['last_name']?.toString() ?? '';
        final p = t['profiles'] as Map<String, dynamic>?;
        var name = '$tfName $tlName'.trim();
        if (name.isEmpty && p != null) {
          name = '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim();
        }
        teacherName = name.isEmpty ? 'Без имени' : name;
      }
    }
    
    final groupName = 'Индивидуально'; // Need group stream if joins are missing

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.white.withAlpha(10))),
      child: InkWell(
        onTap: () {
          LessonAttendanceDialog.show(context, lesson);
        },
        onLongPress: () {
          if (lesson['student_id'] != null) {
            GoRouter.of(context).push('/student/${lesson['student_id']}');
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
                  Row(
                    children: [
                      Text(timeStr, style: const TextStyle(color: AppTheme.primaryPurple, fontWeight: FontWeight.w800, fontSize: 14)),
                      SizedBox(width: 8),
                      Text(dateStr, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 11)),
                    ],
                  ),
                  Row(
                    children: [
                      if (lesson['status'] == 'completed')
                        Icon(Icons.check_circle_rounded, color: AppTheme.success, size: 16)
                      else
                        Icon(Icons.radio_button_unchecked_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 16),
                      
                      PopupMenuButton<String>(
                        icon: Icon(Icons.more_vert_rounded, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
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
                ],
              ),
              SizedBox(height: 8),
              Text(groupName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
              SizedBox(height: 4),
              _buildEntityRow(context, Icons.person_outline_rounded, 'Уч.: $studentName'),
              _buildEntityRow(context, Icons.school_outlined, 'Пр.: $teacherName'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEntityRow(BuildContext context, IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Icon(icon, size: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
          SizedBox(width: 4),
          Expanded(child: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  Future<void> _cancelLesson(BuildContext context, WidgetRef ref, String lessonId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Отменить занятие?'),
        content: Text('Статус занятия будет изменен на "Отменено".'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Назад')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Отменить', style: TextStyle(color: AppTheme.danger))),
        ],
      ),
    );

    if (confirm == true) {
      await Supabase.instance.client.from('lessons').update({'status': 'cancelled'}).eq('id', lessonId);
      ref.invalidate(lessonsFilteredProvider(selectedDate));
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
    ref.invalidate(lessonsFilteredProvider(selectedDate));
  }
}

final lessonsFilteredProvider = FutureProvider.family<List<Map<String, dynamic>>, DateTime>((ref, date) async {
  final supabase = Supabase.instance.client;
  final startOfDay = DateTime(date.year, date.month, date.day).toIso8601String();
  final endOfDay = DateTime(date.year, date.month, date.day).add(const Duration(days: 1)).toIso8601String();

  final res = await supabase
      .from('lessons')
      .select('*, students(first_name, last_name, profiles(first_name, last_name)), groups(name), teachers(first_name, last_name, profiles(first_name, last_name)), rooms(name), branches(name)')
      .gte('scheduled_at', startOfDay)
      .lt('scheduled_at', endOfDay)
      .order('scheduled_at');
  
  return List<Map<String, dynamic>>.from(res);
});
