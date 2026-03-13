import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/create_lesson_dialog.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/teacher_detail_dialog.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lessons_kanban_widget.dart';

final entitiesProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, table) async {
  final supabase = Supabase.instance.client;
  
  bool isDisposed = false;
  final channelName = 'public:entities:$table';
  final channel = supabase.channel(channelName).onPostgresChanges(
    event: PostgresChangeEvent.all,
    schema: 'public',
    table: table,
    callback: (payload) {
      if (!isDisposed) ref.invalidateSelf();
    },
  ).subscribe();

  ref.onDispose(() {
    isDisposed = true;
    supabase.removeChannel(channel);
  });

  if (table == 'students') {
    final r = await supabase.from('students').select('*, profiles(first_name, last_name, phone)');
    return List<Map<String, dynamic>>.from(r);
  } else if (table == 'teachers') {
    final r = await supabase.from('teachers').select('*, profiles(first_name, last_name, phone)');
    return List<Map<String, dynamic>>.from(r);
  } else if (table == 'lessons') {
    final r = await supabase
        .from('lessons')
        .select('*, students(profiles(first_name, last_name)), groups(name), teachers(first_name, last_name, profiles(first_name, last_name)), rooms(name), branches(name)')
        .order('scheduled_at', ascending: false)
        .limit(50);
    return List<Map<String, dynamic>>.from(r);
  } else if (table == 'groups') {
    final r = await supabase
        .from('groups')
        .select('*, branches(name), teachers(first_name, last_name, profiles(first_name, last_name))')
        .order('name', ascending: true);
    return List<Map<String, dynamic>>.from(r);
  }
  return List<Map<String, dynamic>>.from(await supabase.from(table).select('*'));
});

class ManageEntitiesWidget extends ConsumerStatefulWidget {
  final int initialTabIndex;
  const ManageEntitiesWidget({super.key, this.initialTabIndex = 0});

  @override
  ConsumerState<ManageEntitiesWidget> createState() => ManageEntitiesWidgetState();
}

class ManageEntitiesWidgetState extends ConsumerState<ManageEntitiesWidget> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  void setTab(int index) {
    if (index >= 0 && index < _tabController.length) {
      _tabController.animateTo(index);
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this, initialIndex: widget.initialTabIndex);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          TabBar(
            controller: _tabController,
            labelColor: AppTheme.primaryPurple,
            unselectedLabelColor: AppTheme.textSecondary,
            indicatorColor: AppTheme.primaryPurple,
            tabs: const [
              Tab(text: 'Ученики'),
              Tab(text: 'Преподаватели'),
              Tab(text: 'Группы'),
              Tab(text: 'Занятия'),
              Tab(text: 'Канбан'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                _StudentsList(),
                _TeachersList(),
                _GroupsList(),
                _LessonsList(),
                LessonsKanbanWidget(),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _tabController.index == 3
          ? FloatingActionButton.extended(
              onPressed: () async {
                final created = await CreateLessonDialog.show(context);
                if (created == true) {
                  ref.invalidate(entitiesProvider('lessons'));
                }
              },
              backgroundColor: AppTheme.primaryPurple,
              icon: const Icon(Icons.add_rounded, color: Colors.white),
              label: const Text('Создать занятие', style: TextStyle(color: Colors.white)),
            )
          : null,
    );
  }
}

class _StudentsList extends ConsumerWidget {
  const _StudentsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(entitiesProvider('students'));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.primaryPurple)),
      error: (e, _) => Center(child: Text('РћС€РёР±РєР°: $e', style: const TextStyle(color: AppTheme.danger))),
      data: (items) {
        if (items.isEmpty) return const Center(child: Text('Нет учеников', style: TextStyle(color: AppTheme.textSecondary)));
        return RefreshIndicator(
          color: AppTheme.primaryPurple,
          onRefresh: () async => ref.invalidate(entitiesProvider('students')),
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            itemBuilder: (ctx, i) {
              final item = items[i];
              final p = item['profiles'] as Map<String, dynamic>?;
              final name = '${p?['first_name'] ?? ''} ${p?['last_name'] ?? ''}'.trim();
              final phone = p?['phone'] as String? ?? '';
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppTheme.primaryPurple.withAlpha(30),
                    child: Text(name.isNotEmpty ? name[0] : '?',
                        style: const TextStyle(color: AppTheme.primaryPurple, fontWeight: FontWeight.w700)),
                  ),
                  title: Text(name.isEmpty ? 'Без имени' : name),
                  subtitle: phone.isNotEmpty ? Text(phone, style: const TextStyle(color: AppTheme.textSecondary)) : null,
                  trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.textSecondary),
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
  const _TeachersList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(entitiesProvider('teachers'));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.primaryPurple)),
      error: (e, _) => Center(child: Text('РћС€РёР±РєР°: $e', style: const TextStyle(color: AppTheme.danger))),
      data: (items) {
        if (items.isEmpty) return const Center(child: Text('Нет преподавателей', style: TextStyle(color: AppTheme.textSecondary)));
        return RefreshIndicator(
          color: AppTheme.primaryPurple,
          onRefresh: () async => ref.invalidate(entitiesProvider('teachers')),
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            itemBuilder: (ctx, i) {
              final item = items[i];
              final tf = item['first_name'] as String? ?? '';
              final tl = item['last_name'] as String? ?? '';
              var name = '$tf $tl'.trim();
              if (name.isEmpty) {
                final p = item['profiles'] as Map<String, dynamic>?;
                name = '${p?['first_name'] ?? ''} ${p?['last_name'] ?? ''}'.trim();
              }
              final dList = item['disciplines'] as List<dynamic>?;
              String spec = 'Не указана';
              if (dList != null && dList.isNotEmpty) {
                try {
                  if (dList is List) {
                    spec = dList.map((d) {
                      if (d is Map) return d['Name']?.toString() ?? d['name']?.toString() ?? '';
                      return d.toString();
                    }).where((s) => s.isNotEmpty).join(', ');
                  } else {
                    spec = dList.toString();
                  }
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
                  subtitle: Text('Специализация: $spec', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                  trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.textSecondary),
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
      loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.primaryPurple)),
      error: (e, _) => Center(child: Text('РћС€РёР±РєР°: $e', style: const TextStyle(color: AppTheme.danger))),
      data: (items) {
        if (items.isEmpty) return const Center(child: Text('Нет занятий', style: TextStyle(color: AppTheme.textSecondary)));
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
              final student = l['students']?['profiles'];
              final teacher = l['teachers'];
              
              String studentName = 'Без ученика';
              if (student != null) {
                studentName = '${student['first_name'] ?? ''} ${student['last_name'] ?? ''}'.trim();
              } else if (l['groups'] != null && l['groups']['name'] != null) {
                studentName = 'Группа: ${l['groups']['name']}';
              }
              
              var teacherName = 'Без преподавателя';
              if (teacher != null) {
                final tf = teacher['first_name'] as String? ?? '';
                final tl = teacher['last_name'] as String? ?? '';
                teacherName = '$tf $tl'.trim();
                if (teacherName.isEmpty) {
                  final tp = teacher['profiles'];
                  if (tp != null) {
                    teacherName = '${tp['first_name'] ?? ''} ${tp['last_name'] ?? ''}'.trim();
                  }
                }
                if (teacherName.isEmpty) teacherName = 'Без преподавателя';
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
                            const SizedBox(height: 2),
                            Text('Ученик: $studentName', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                            Text('Преп.: $teacherName', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                            Text('Кабинет: $room', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
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
}

class _GroupsList extends ConsumerWidget {
  const _GroupsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(entitiesProvider('groups'));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.primaryPurple)),
      error: (e, _) => Center(child: Text('Ошибка: $e', style: const TextStyle(color: AppTheme.danger))),
      data: (items) {
        if (items.isEmpty) return const Center(child: Text('Нет групп', style: TextStyle(color: AppTheme.textSecondary)));
        return RefreshIndicator(
          color: AppTheme.primaryPurple,
          onRefresh: () async => ref.invalidate(entitiesProvider('groups')),
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            itemBuilder: (ctx, i) {
              final item = items[i];
              final name = item['name'] as String? ?? 'Без названия';
              final branchName = item['branches']?['name'] as String? ?? 'Без филиала';
              final teacher = item['teachers'];
              
              var teacherName = 'Без преподавателя';
              if (teacher != null) {
                final tf = teacher['first_name'] as String? ?? '';
                final tl = teacher['last_name'] as String? ?? '';
                teacherName = '$tf $tl'.trim();
                if (teacherName.isEmpty) {
                  final tp = teacher['profiles'];
                  if (tp != null) {
                    teacherName = '${tp['first_name'] ?? ''} ${tp['last_name'] ?? ''}'.trim();
                  }
                }
                if (teacherName.isEmpty) teacherName = 'Без преподавателя';
              }

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppTheme.primaryPurple.withAlpha(30),
                    child: const Icon(Icons.group_rounded, color: AppTheme.primaryPurple),
                  ),
                  title: Text(name),
                  subtitle: Text('Преп.: $teacherName • Фил.: $branchName', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

