import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';

final lessonsStreamProvider = StreamProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  return Supabase.instance.client
      .from('lessons')
      .stream(primaryKey: ['id'])
      .order('scheduled_at')
      .map((data) => List<Map<String, dynamic>>.from(data));
});

class LessonsKanbanWidget extends ConsumerStatefulWidget {
  const LessonsKanbanWidget({super.key});

  @override
  ConsumerState<LessonsKanbanWidget> createState() => _LessonsKanbanWidgetState();
}

class _LessonsKanbanWidgetState extends ConsumerState<LessonsKanbanWidget> {
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
      supabase.from('rooms').select('id, name'),
      supabase.from('teachers').select('id, first_name, last_name, profiles(first_name, last_name)'),
      supabase.from('students').select('id, profiles(first_name, last_name)'),
    ]);

    if (mounted) {
      setState(() {
        _rooms = List<Map<String, dynamic>>.from(results[0]);
        _teachers = List<Map<String, dynamic>>.from(results[1]);
        _students = List<Map<String, dynamic>>.from(results[2]);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final lessonsAsync = ref.watch(lessonsStreamProvider);

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
                  return const Center(child: Text('Нет занятий по данным фильтрам', style: TextStyle(color: AppTheme.textSecondary)));
                }

                // Group by room for Kanban columns
                final grouped = <String, List<Map<String, dynamic>>>{};
                for (final l in filtered) {
                  final roomId = l['room_id'] ?? 'unassigned';
                  grouped.putIfAbsent(roomId, () => []).add(l);
                }

                return ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.all(12),
                  children: [
                    ..._rooms.where((r) => grouped.containsKey(r['id']) || _selectedRoomId == null).map((room) {
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
                final fn = t['first_name'] ?? '';
                final ln = t['last_name'] ?? '';
                final p = t['profiles'] as Map<String, dynamic>?;
                final name = '$fn $ln'.trim().isEmpty ? '${p?['first_name'] ?? ''} ${p?['last_name'] ?? ''}'.trim() : '$fn $ln'.trim();
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

class _LessonKanbanCard extends StatelessWidget {
  final Map<String, dynamic> lesson;
  const _LessonKanbanCard({required this.lesson});

  @override
  Widget build(BuildContext context) {
    final dt = DateTime.tryParse(lesson['scheduled_at'] ?? '');
    final timeStr = dt != null ? DateFormat('HH:mm').format(dt.toLocal()) : '';
    final dateStr = dt != null ? DateFormat('d MMM').format(dt.toLocal()) : '';
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: AppTheme.surfaceDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.white.withAlpha(10))),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(timeStr, style: const TextStyle(color: AppTheme.primaryPurple, fontWeight: FontWeight.w800, fontSize: 14)),
                Text(dateStr, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
              ],
            ),
            const SizedBox(height: 8),
            const Text('Занятие', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.person_outline_rounded, size: 12, color: AppTheme.textSecondary),
                const SizedBox(width: 4),
                Expanded(child: Text('ID: ${lesson['student_id']?.toString().substring(0, 8) ?? '—'}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12))),
              ],
            ),
            Row(
              children: [
                const Icon(Icons.school_outlined, size: 12, color: AppTheme.textSecondary),
                const SizedBox(width: 4),
                Expanded(child: Text('ID: ${lesson['teacher_id']?.toString().substring(0, 8) ?? '—'}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
