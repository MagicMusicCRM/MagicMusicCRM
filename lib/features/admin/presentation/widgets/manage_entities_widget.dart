import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/skeletons.dart';
import 'create_student_dialog.dart';
import 'create_teacher_dialog.dart';
import 'create_group_dialog.dart';
import 'student_detail_dialog.dart';
import 'teacher_detail_dialog.dart';
import 'group_detail_dialog.dart';
import 'create_room_dialog.dart';
import 'create_employee_dialog.dart';

final entitiesProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, table) async {
  final supabase = Supabase.instance.client;
  
  if (table == 'students') {
    final r = await supabase.from('students').select('*, profiles(first_name, last_name)');
    return List<Map<String, dynamic>>.from(r);
  } else if (table == 'teachers') {
    final r = await supabase.from('teachers').select('*, profiles(first_name, last_name)');
    return List<Map<String, dynamic>>.from(r);
  } else if (table == 'lessons') {
    final r = await supabase
        .from('lessons')
        .select('*, students(first_name, last_name, profiles(first_name, last_name)), groups(name), teachers(first_name, last_name, profiles(first_name, last_name)), rooms(name), branches(name)')
        .order('scheduled_at', ascending: false)
        .limit(50);
    return List<Map<String, dynamic>>.from(r);
  } else if (table == 'groups') {
    final r = await supabase
        .from('groups')
        .select('*, branches(name), teachers(first_name, last_name, profiles(first_name, last_name))')
        .order('name', ascending: true);
    return List<Map<String, dynamic>>.from(r);
  } else if (table == 'rooms') {
    final r = await supabase.from('rooms').select('*, branches(name)').order('name', ascending: true);
    return List<Map<String, dynamic>>.from(r);
  }
  
  final res = await supabase.from(table).select('*');
  return List<Map<String, dynamic>>.from(res);
});

class ManageEntitiesWidget extends ConsumerStatefulWidget {
  const ManageEntitiesWidget({super.key});

  @override
  ConsumerState<ManageEntitiesWidget> createState() => ManageEntitiesWidgetState();
}

class ManageEntitiesWidgetState extends ConsumerState<ManageEntitiesWidget> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
  }

  void setTab(int index) {
    if (index >= 0 && index < _tabController.length) {
      _tabController.animateTo(index);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(110),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                controller: _searchController,
                onChanged: (val) => setState(() => _searchQuery = val),
                decoration: InputDecoration(
                  hintText: 'Поиск...',
                  prefixIcon: Icon(Icons.search_rounded, color: Theme.of(context!).colorScheme.onSurfaceVariant),
                  suffixIcon: _searchQuery.isNotEmpty 
                    ? IconButton(
                        icon: Icon(Icons.close_rounded, size: 20),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                  filled: true,
                  fillColor: Theme.of(context!).colorScheme.surface,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelPadding: const EdgeInsets.symmetric(horizontal: 16),
              indicatorColor: AppTheme.primaryPurple,
              labelColor: AppTheme.primaryPurple,
              unselectedLabelColor: Theme.of(context!).colorScheme.onSurfaceVariant,
              tabs: [
                Tab(text: 'Ученики'),
                Tab(text: 'Преподаватели'),
                Tab(text: 'Группы'),
                Tab(text: 'Занятия'),
                Tab(text: 'Аудитории'),
                Tab(text: 'Сотрудники'),
              ],
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _StudentsList(searchQuery: _searchQuery),
          _TeachersList(searchQuery: _searchQuery),
          _GroupsList(searchQuery: _searchQuery),
          const _LessonsList(),
          _RoomsList(searchQuery: _searchQuery),
          _EmployeesList(searchQuery: _searchQuery),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _createNewEntity(context),
        backgroundColor: AppTheme.primaryPurple,
        child: Icon(Icons.add_rounded, color: Colors.white),
      ),
    );
  }

  void _createNewEntity(BuildContext context) async {
    Widget? dialog;
    switch (_tabController.index) {
      case 0:
        dialog = const CreateStudentDialog();
        break;
      case 1:
        dialog = const CreateTeacherDialog();
        break;
      case 2:
        dialog = const CreateGroupDialog();
        break;
      case 3:
        // No longer creating lessons from here, redirecting to Schedule
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Для создания занятия используйте раздел "Расписание"'))
        );
        return;
      case 4:
        dialog = const CreateRoomDialog();
        break;
      case 5:
        dialog = const CreateEmployeeDialog();
        break;
    }

    if (dialog != null) {
      final res = await showDialog(context: context, builder: (ctx) => dialog!);
      if (res == true) {
        // Invalidate appropriately based on tab index
        if (_tabController.index == 4) ref.invalidate(entitiesProvider('rooms'));
        if (_tabController.index == 2) ref.invalidate(entitiesProvider('groups'));
        if (_tabController.index == 1) ref.invalidate(entitiesProvider('teachers'));
        if (_tabController.index == 0) ref.invalidate(entitiesProvider('students'));
        if (_tabController.index == 5) ref.invalidate(entitiesProvider('employees'));
      }
    }
  }
}

class _StudentsList extends ConsumerWidget {
  final String searchQuery;
  const _StudentsList({required this.searchQuery});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(entitiesProvider('students'));
    return async.when(
      loading: () => Padding(padding: EdgeInsets.all(12), child: ListSkeleton()),
      error: (e, _) => Center(child: Text('Ошибка: $e', style: TextStyle(color: AppTheme.danger))),
      data: (items) {
        var filtered = items;
        if (searchQuery.isNotEmpty) {
          filtered = items.where((item) {
            final firstName = (item['first_name'] ?? item['profiles']?['first_name'] ?? '').toString().toLowerCase();
            final lastName = (item['last_name'] ?? item['profiles']?['last_name'] ?? '').toString().toLowerCase();
            return firstName.contains(searchQuery.toLowerCase()) || lastName.contains(searchQuery.toLowerCase());
          }).toList();
        }

        if (filtered.isEmpty) return Center(child: Text(searchQuery.isEmpty ? 'Нет учеников' : 'Ничего не найдено', style: TextStyle(color: Theme.of(context!).colorScheme.onSurfaceVariant)));

        return RefreshIndicator(
          color: AppTheme.primaryPurple,
          onRefresh: () async => ref.invalidate(entitiesProvider('students')),
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: filtered.length,
            itemBuilder: (ctx, i) {
              final item = filtered[i];
              final fName = item['first_name'] ?? item['profiles']?['first_name'] ?? '';
              final lName = item['last_name'] ?? item['profiles']?['last_name'] ?? '';
              final name = '$fName $lName'.trim();
              final phone = item['phone'] as String? ?? '';
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  onTap: () async {
                    final updated = await StudentDetailDialog.show(context, item);
                    if (updated == true) {
                      ref.invalidate(entitiesProvider('students'));
                    }
                  },
                  leading: CircleAvatar(
                    backgroundColor: AppTheme.primaryPurple.withAlpha(30),
                    child: Text(name.isNotEmpty ? name[0] : '?',
                        style: const TextStyle(color: AppTheme.primaryPurple, fontWeight: FontWeight.w700)),
                  ),
                  title: Text(name.isEmpty ? 'Без имени' : name),
                  subtitle: phone.isNotEmpty ? Text(phone, style: TextStyle(color: Theme.of(context!).colorScheme.onSurfaceVariant)) : null,
                  trailing: Icon(Icons.chevron_right_rounded, color: Theme.of(context!).colorScheme.onSurfaceVariant),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _TeachersList extends ConsumerWidget {
  final String searchQuery;
  const _TeachersList({required this.searchQuery});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(entitiesProvider('teachers'));
    return async.when(
      loading: () => Padding(padding: EdgeInsets.all(12), child: ListSkeleton()),
      error: (e, _) => Center(child: Text('Ошибка: $e', style: TextStyle(color: AppTheme.danger))),
      data: (items) {
        var filtered = items;
        if (searchQuery.isNotEmpty) {
          filtered = items.where((item) {
            final firstName = (item['first_name'] ?? item['profiles']?['first_name'] ?? '').toString().toLowerCase();
            final lastName = (item['last_name'] ?? item['profiles']?['last_name'] ?? '').toString().toLowerCase();
            return firstName.contains(searchQuery.toLowerCase()) || lastName.contains(searchQuery.toLowerCase());
          }).toList();
        }

        if (filtered.isEmpty) return Center(child: Text(searchQuery.isEmpty ? 'Нет преподавателей' : 'Ничего не найдено', style: TextStyle(color: Theme.of(context!).colorScheme.onSurfaceVariant)));

        return RefreshIndicator(
          color: AppTheme.primaryPurple,
          onRefresh: () async => ref.invalidate(entitiesProvider('teachers')),
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: filtered.length,
            itemBuilder: (ctx, i) {
              final item = filtered[i];
              final fName = item['first_name'] ?? item['profiles']?['first_name'] ?? '';
              final lName = item['last_name'] ?? item['profiles']?['last_name'] ?? '';
              final name = '$fName $lName'.trim();
              final dList = item['disciplines'] as List<dynamic>?;
              String spec = 'Не указана';
              if (dList != null && dList.isNotEmpty) {
                try {
                  spec = dList.map((d) {
                    if (d is Map) return d['Name']?.toString() ?? d['name']?.toString() ?? '';
                    return d.toString();
                  }).where((s) => s.isNotEmpty).join(', ');
                } catch (e) {
                  spec = 'Ошибка парсинга';
                }
              } else {
                spec = item['specialization'] as String? ?? 'Не указана';
              }
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  onTap: () async {
                    final updated = await TeacherDetailDialog.show(context, item);
                    if (updated == true) {
                      ref.invalidate(entitiesProvider('teachers'));
                    }
                  },
                  leading: CircleAvatar(
                    backgroundColor: AppTheme.secondaryGold.withAlpha(30),
                    child: Text(name.isNotEmpty ? name[0] : '?',
                        style: const TextStyle(color: AppTheme.secondaryGold, fontWeight: FontWeight.w700)),
                  ),
                  title: Text(name.isEmpty ? 'Без имени' : name),
                  subtitle: Text('Специализация: $spec', style: TextStyle(color: Theme.of(context!).colorScheme.onSurfaceVariant, fontSize: 12)),
                  trailing: Icon(Icons.chevron_right_rounded, color: Theme.of(context!).colorScheme.onSurfaceVariant),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _LessonsList extends ConsumerWidget {
  const _LessonsList();

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
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(entitiesProvider('lessons'));
    return async.when(
      loading: () => Padding(padding: EdgeInsets.all(12), child: ListSkeleton()),
      error: (e, _) => Center(child: Text('Ошибка: $e', style: TextStyle(color: AppTheme.danger))),
      data: (items) {
        if (items.isEmpty) return Center(child: Text('Нет занятий', style: TextStyle(color: Theme.of(context!).colorScheme.onSurfaceVariant)));
        return RefreshIndicator(
          color: AppTheme.primaryPurple,
          onRefresh: () async => ref.invalidate(entitiesProvider('lessons')),
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            itemBuilder: (ctx, i) {
              final l = items[i];
              final dt = DateTime.tryParse(l['scheduled_at'] ?? '');
              final dateStr = dt != null ? DateFormat('d MMM yyyy, HH:mm', 'ru').format(dt.toLocal()) : '—';
              
              final student = l['students'];
              String studentName = 'Без ученика';
              if (student != null) {
                final sf = student['first_name'] ?? student['profiles']?['first_name'] ?? '';
                final sl = student['last_name'] ?? student['profiles']?['last_name'] ?? '';
                studentName = '$sf $sl'.trim();
                if (studentName.isEmpty) studentName = 'Без имени';
              } else if (l['groups'] != null && l['groups']['name'] != null) {
                studentName = 'Группа: ${l['groups']['name']}';
              }
              
              final teacher = l['teachers'];
              String teacherName = 'Без преподавателя';
              if (teacher != null) {
                final tf = teacher['first_name'] ?? teacher['profiles']?['first_name'] ?? '';
                final tl = teacher['last_name'] ?? teacher['profiles']?['last_name'] ?? '';
                teacherName = '$tf $tl'.trim();
                if (teacherName.isEmpty) teacherName = 'Без имени';
              }
              
              final room = l['rooms']?['name'] as String? ?? '—';
              final status = l['status'] as String?;

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(dateStr, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            SizedBox(height: 2),
                            Text('Ученик: $studentName', style: TextStyle(color: Theme.of(context!).colorScheme.onSurfaceVariant, fontSize: 12)),
                            Text('Преп.: $teacherName', style: TextStyle(color: Theme.of(context!).colorScheme.onSurfaceVariant, fontSize: 12)),
                            Text('Кабинет: $room', style: TextStyle(color: Theme.of(context!).colorScheme.onSurfaceVariant, fontSize: 12)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _statusColor(status).withAlpha(25),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(_statusLabel(status), style: TextStyle(color: _statusColor(status), fontSize: 11, fontWeight: FontWeight.w600)),
                      ),
                      SizedBox(width: 4),
                      PopupMenuButton<String>(
                        icon: Icon(Icons.more_vert_rounded, size: 20, color: Theme.of(context!).colorScheme.onSurfaceVariant),
                        onSelected: (val) {
                          if (val == 'cancel') _cancelLesson(context, ref, l['id']);
                          if (val == 'reschedule') _rescheduleLesson(context, ref, l['id'], dt);
                        },
                        itemBuilder: (ctx) => [
                          const PopupMenuItem(value: 'cancel', child: Text('Отменить занятие')),
                          const PopupMenuItem(value: 'reschedule', child: Text('Перенести')),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
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
      ref.invalidate(entitiesProvider('lessons'));
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
    ref.invalidate(entitiesProvider('lessons'));
  }
}

class _GroupsList extends ConsumerWidget {
  final String searchQuery;
  const _GroupsList({required this.searchQuery});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(entitiesProvider('groups'));
    return async.when(
      loading: () => Padding(padding: EdgeInsets.all(12), child: ListSkeleton()),
      error: (e, _) => Center(child: Text('Ошибка: $e', style: TextStyle(color: AppTheme.danger))),
      data: (items) {
        var filtered = items;
        if (searchQuery.isNotEmpty) {
          filtered = items.where((item) {
            final name = (item['name'] as String? ?? '').toLowerCase();
            return name.contains(searchQuery.toLowerCase());
          }).toList();
        }

        if (filtered.isEmpty) return Center(child: Text(searchQuery.isEmpty ? 'Нет групп' : 'Ничего не найдено', style: TextStyle(color: Theme.of(context!).colorScheme.onSurfaceVariant)));

        return RefreshIndicator(
          color: AppTheme.primaryPurple,
          onRefresh: () async => ref.invalidate(entitiesProvider('groups')),
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: filtered.length,
            itemBuilder: (ctx, i) {
              final item = filtered[i];
              final name = item['name'] as String? ?? 'Без названия';
              final branchName = item['branches']?['name'] as String? ?? 'Без филиала';
              final teacher = item['teachers'];
              
              var teacherName = 'Без преподавателя';
              if (teacher != null) {
                final tf = teacher['first_name'] ?? teacher['profiles']?['first_name'] ?? '';
                final tl = teacher['last_name'] ?? teacher['profiles']?['last_name'] ?? '';
                teacherName = '$tf $tl'.trim();
                if (teacherName.isEmpty) teacherName = 'Без преподавателя';
              }

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  onTap: () async {
                    final updated = await GroupDetailDialog.show(context, item);
                    if (updated == true) {
                      ref.invalidate(entitiesProvider('groups'));
                    }
                  },
                  leading: CircleAvatar(
                    backgroundColor: AppTheme.primaryPurple.withAlpha(30),
                    child: Icon(Icons.group_rounded, color: AppTheme.primaryPurple),
                  ),
                  title: Text(name),
                  subtitle: Text('Преп.: $teacherName • Фил.: $branchName', style: TextStyle(color: Theme.of(context!).colorScheme.onSurfaceVariant, fontSize: 12)),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _RoomsList extends ConsumerWidget {
  final String searchQuery;
  const _RoomsList({required this.searchQuery});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(entitiesProvider('rooms'));
    return async.when(
      loading: () => Padding(padding: EdgeInsets.all(12), child: ListSkeleton()),
      error: (e, _) => Center(child: Text('Ошибка: $e', style: TextStyle(color: AppTheme.danger))),
      data: (items) {
        var filtered = items;
        if (searchQuery.isNotEmpty) {
          filtered = items.where((item) {
            final name = (item['name'] as String? ?? '').toLowerCase();
            return name.contains(searchQuery.toLowerCase());
          }).toList();
        }

        if (filtered.isEmpty) return Center(child: Text(searchQuery.isEmpty ? 'Нет аудиторий' : 'Ничего не найдено', style: TextStyle(color: Theme.of(context!).colorScheme.onSurfaceVariant)));

        return RefreshIndicator(
          color: AppTheme.primaryPurple,
          onRefresh: () async => ref.invalidate(entitiesProvider('rooms')),
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: filtered.length,
            itemBuilder: (ctx, i) {
              final item = filtered[i];
              final name = item['name'] as String? ?? 'Без названия';
              final branchName = item['branches']?['name'] as String? ?? 'Без филиала';
              final capacity = item['capacity']?.toString() ?? '1';

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  onTap: () async {
                    final res = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => CreateRoomDialog(room: item),
                    );
                    if (res == true) {
                      ref.invalidate(entitiesProvider('rooms'));
                    }
                  },
                  leading: CircleAvatar(
                    backgroundColor: AppTheme.primaryPurple.withAlpha(30),
                    child: Icon(Icons.meeting_room_rounded, color: AppTheme.primaryPurple),
                  ),
                  title: Text(name),
                  subtitle: Text('Вместимость: $capacity чел. • Фил.: $branchName', style: TextStyle(color: Theme.of(context!).colorScheme.onSurfaceVariant, fontSize: 12)),
                  trailing: Icon(Icons.edit_rounded, color: Theme.of(context!).colorScheme.onSurfaceVariant, size: 18),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────
// Employees List
// ─────────────────────────────────────────────────
class _EmployeesList extends ConsumerWidget {
  final String searchQuery;
  const _EmployeesList({required this.searchQuery});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(entitiesProvider('employees'));
    return all.when(
      loading: () => Center(child: CircularProgressIndicator(color: AppTheme.primaryPurple)),
      error: (e, _) => Center(child: Text('Ошибка: $e')),
      data: (items) {
        final q = searchQuery.toLowerCase();
        final filtered = items.where((e) {
          final name = '${e['first_name'] ?? ''} ${e['last_name'] ?? ''}'.toLowerCase();
          final email = (e['email'] ?? '').toString().toLowerCase();
          final phone = (e['phone'] ?? '').toString().toLowerCase();
          return q.isEmpty || name.contains(q) || email.contains(q) || phone.contains(q);
        }).toList();

        if (filtered.isEmpty) {
          return Center(child: Text('Нет сотрудников', style: TextStyle(color: Theme.of(context!).colorScheme.onSurfaceVariant)));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: filtered.length,
          itemBuilder: (_, i) {
            final e = filtered[i];
            final firstName = e['first_name'] as String? ?? '';
            final lastName = e['last_name'] as String? ?? '';
            final fullName = '$lastName $firstName'.trim().isEmpty ? 'Без имени' : '$lastName $firstName'.trim();
            final role = e['role'] as String? ?? 'admin';
            final roleLabel = role == 'manager' ? 'Управляющий' : 'Администратор';
            final roleColor = role == 'manager' ? const Color(0xFF8B5CF6) : const Color(0xFFF59E0B);
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: roleColor.withAlpha(40),
                  child: Text(
                    fullName.isNotEmpty ? fullName[0].toUpperCase() : '?',
                    style: TextStyle(color: roleColor, fontWeight: FontWeight.bold),
                  ),
                ),
                title: Text(fullName),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if ((e['email'] ?? '').isNotEmpty)
                      Text(e['email'], style: TextStyle(color: Theme.of(context!).colorScheme.onSurfaceVariant, fontSize: 12)),
                    if ((e['phone'] ?? '').isNotEmpty)
                      Text(e['phone'], style: TextStyle(color: Theme.of(context!).colorScheme.onSurfaceVariant, fontSize: 12)),
                  ],
                ),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: roleColor.withAlpha(30),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: roleColor.withAlpha(80)),
                  ),
                  child: Text(roleLabel, style: TextStyle(color: roleColor, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
