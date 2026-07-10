import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/show_client_card.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/widgets/skeletons.dart';
import '../../../../core/widgets/v7/v7.dart';
import 'create_student_dialog.dart';
import 'create_teacher_dialog.dart';
import 'create_group_dialog.dart';
import 'teacher_detail_dialog.dart';
import 'staff_detail_dialog.dart';
import 'group_detail_dialog.dart';
import 'create_room_dialog.dart';
import 'create_employee_dialog.dart';
import 'branch_form_dialog.dart';
import 'data_quality_widget.dart';
import 'deletion_requests_widget.dart';

final entitiesProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((
      ref,
      table,
    ) async {
      final crm = ref.watch(magicCrmServiceProvider);

      if (table == 'students') {
        final response = await crm.searchStudents(limit: 100);
        return _studentSearchItems(response);
      } else if (table == 'teachers') {
        return crm.listTeachers(limit: 100);
      } else if (table == 'lessons') {
        return crm.listLessons(limit: 50);
      } else if (table == 'groups') {
        return crm.listGroups(limit: 100);
      } else if (table == 'rooms') {
        return crm.listRooms(limit: 100);
      } else if (table == 'employees') {
        return crm.listStaff(limit: 100);
      } else if (table == 'branches') {
        return crm.listBranches(limit: 100);
      } else if (table == 'subscription_packages') {
        return crm.listSubscriptionPackages(limit: 100);
      }

      return const <Map<String, dynamic>>[];
    });

final studentSearchProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((
      ref,
      query,
    ) async {
      final response = await ref
          .watch(magicCrmServiceProvider)
          .searchStudents(q: query, limit: 100);
      return _studentSearchItems(response);
    });

List<Map<String, dynamic>> _studentSearchItems(Map<String, dynamic> response) {
  final items = response['items'];
  if (items is! List) return const <Map<String, dynamic>>[];
  return items.whereType<Map<String, dynamic>>().toList();
}

final teacherSearchProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((
      ref,
      query,
    ) async {
      return ref
          .watch(magicCrmServiceProvider)
          .listTeachers(q: query, limit: 100);
    });

final staffSearchProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((
      ref,
      query,
    ) async {
      return ref.watch(magicCrmServiceProvider).listStaff(q: query, limit: 100);
    });

class ManageEntitiesWidget extends ConsumerStatefulWidget {
  const ManageEntitiesWidget({super.key});

  @override
  ConsumerState<ManageEntitiesWidget> createState() =>
      ManageEntitiesWidgetState();
}

class ManageEntitiesWidgetState extends ConsumerState<ManageEntitiesWidget>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 10, vsync: this);
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
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
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
                  fillColor: Theme.of(context).colorScheme.surface,
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
              indicatorColor: AppTheme.primaryGold,
              labelColor: AppTheme.primaryGold,
              unselectedLabelColor: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant,
              tabs: [
                Tab(text: 'Ученики'),
                Tab(text: 'Преподаватели'),
                Tab(text: 'Группы'),
                Tab(text: 'Занятия'),
                Tab(text: 'Аудитории'),
                Tab(text: 'Сотрудники'),
                Tab(text: 'Филиалы'),
                Tab(text: 'Каталог абонементов'),
                Tab(text: 'Качество данных'),
                Tab(text: 'Запросы на удаление'),
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
          _BranchesList(searchQuery: _searchQuery),
          _PackagesList(searchQuery: _searchQuery),
          const DataQualityWidget(),
          const DeletionRequestsWidget(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _createNewEntity(context),
        backgroundColor: AppTheme.primaryGold,
        child: Icon(Icons.add_rounded, color: Colors.white),
      ),
    );
  }

  void _createNewEntity(BuildContext context) async {
    // Subscription packages (Каталог) use a v7 sheet, not a Material dialog.
    if (_tabController.index == 7) {
      final saved = await showPackageSheet(context, ref);
      if (saved == true) {
        ref.invalidate(entitiesProvider('subscription_packages'));
      }
      return;
    }

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
          const SnackBar(
            content: Text(
              'Для создания занятия используйте раздел "Расписание"',
            ),
          ),
        );
        return;
      case 4:
        dialog = const CreateRoomDialog();
        break;
      case 5:
        dialog = const CreateEmployeeDialog();
        break;
      case 6:
        dialog = const BranchFormDialog();
        break;
    }

    if (dialog != null) {
      final res = await showDialog(context: context, builder: (ctx) => dialog!);
      if (res == true) {
        // Invalidate appropriately based on tab index
        if (_tabController.index == 4) {
          ref.invalidate(entitiesProvider('rooms'));
        }
        if (_tabController.index == 2) {
          ref.invalidate(entitiesProvider('groups'));
        }
        if (_tabController.index == 1) {
          ref.invalidate(entitiesProvider('teachers'));
          ref.invalidate(teacherSearchProvider(_searchQuery.trim()));
        }
        if (_tabController.index == 0) {
          ref.invalidate(entitiesProvider('students'));
          ref.invalidate(studentSearchProvider(_searchQuery.trim()));
        }
        if (_tabController.index == 5) {
          ref.invalidate(entitiesProvider('employees'));
          ref.invalidate(staffSearchProvider(_searchQuery.trim()));
        }
        if (_tabController.index == 6) {
          ref.invalidate(entitiesProvider('branches'));
        }
      }
    }
  }
}

class _StudentsList extends ConsumerWidget {
  final String searchQuery;
  const _StudentsList({required this.searchQuery});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = searchQuery.trim();
    final async = ref.watch(studentSearchProvider(query));
    return async.when(
      loading: () =>
          Padding(padding: EdgeInsets.all(12), child: ListSkeleton()),
      error: (e, _) => Center(
        child: Text('Ошибка: $e', style: TextStyle(color: AppTheme.danger)),
      ),
      data: (items) {
        if (items.isEmpty) {
          return Center(
            child: Text(
              query.isEmpty ? 'Нет учеников' : 'Ничего не найдено',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }

        return RefreshIndicator(
          color: AppTheme.primaryGold,
          onRefresh: () async => ref.invalidate(studentSearchProvider(query)),
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            itemBuilder: (ctx, i) {
              final item = items[i];
              final fName =
                  item['first_name'] ?? item['profiles']?['first_name'] ?? '';
              final lName =
                  item['last_name'] ?? item['profiles']?['last_name'] ?? '';
              final name = '$fName $lName'.trim();
              final phone = item['phone'] as String? ?? '';
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  onTap: () async {
                    final id = item['id']?.toString();
                    if (id == null || id.isEmpty) return;
                    await showClientCard(
                      context,
                      entityType: 'student',
                      entityId: id,
                      seed: item,
                    );
                    // Refresh on return — the screen may have changed the
                    // student (edits, payments, etc.).
                    ref.invalidate(entitiesProvider('students'));
                    ref.invalidate(studentSearchProvider(query));
                  },
                  leading: CircleAvatar(
                    backgroundColor: AppTheme.primaryGold.withAlpha(30),
                    child: Text(
                      name.isNotEmpty ? name[0] : '?',
                      style: const TextStyle(
                        color: AppTheme.primaryGold,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  title: Text(name.isEmpty ? 'Без имени' : name),
                  subtitle: _StudentSearchSummary(item: item, phone: phone),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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

class _StudentSearchSummary extends StatelessWidget {
  final Map<String, dynamic> item;
  final String phone;

  const _StudentSearchSummary({required this.item, required this.phone});

  @override
  Widget build(BuildContext context) {
    final branch = item['branch_name']?.toString().trim() ?? '';
    final groups = _asInt(item['groups_count']);
    final tasks = _asInt(item['open_tasks_count']);
    final lessons = _asInt(item['lessons_count']);
    final payments = _asNum(item['payments_total']);
    final linkedEmail = item['linked_user_email']?.toString().trim() ?? '';
    final hasAppAccount =
        item['linked_user_id'] != null || item['is_app_account'] == true;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (phone.isNotEmpty)
            Text(
              phone,
              style: TextStyle(color: muted, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (branch.isNotEmpty)
                _StudentMetricChip(
                  icon: Icons.location_on_outlined,
                  label: branch,
                  color: AppTheme.primaryGold,
                ),
              _StudentMetricChip(
                icon: Icons.groups_rounded,
                label: 'Группы: $groups',
                color: AppTheme.primaryGold,
              ),
              _StudentMetricChip(
                icon: Icons.event_available_rounded,
                label: 'Занятия: $lessons',
                color: AppTheme.success,
              ),
              _StudentMetricChip(
                icon: Icons.task_alt_rounded,
                label: 'Задачи: $tasks',
                color: tasks > 0 ? AppTheme.warning : muted,
              ),
              if (payments > 0)
                _StudentMetricChip(
                  icon: Icons.payments_rounded,
                  label: '${_formatMoney(payments)} ₽',
                  color: AppTheme.secondaryGold,
                ),
              _StudentMetricChip(
                icon: hasAppAccount
                    ? Icons.verified_user_rounded
                    : Icons.person_off_rounded,
                label: hasAppAccount
                    ? (linkedEmail.isEmpty ? 'Аккаунт' : linkedEmail)
                    : 'Без аккаунта',
                color: hasAppAccount ? AppTheme.success : muted,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StudentMetricChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StudentMetricChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(24),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(54)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 170),
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

num _asNum(dynamic value) {
  if (value is num) return value;
  return num.tryParse(value?.toString() ?? '') ?? 0;
}

String _formatMoney(num value) {
  return NumberFormat.decimalPattern('ru').format(value);
}

String _branchesText(dynamic value) {
  if (value is! List) return '';
  return value
      .map((branch) {
        if (branch is Map) {
          return (branch['name'] ?? branch['branch_name'] ?? '').toString();
        }
        return branch.toString();
      })
      .where((name) => name.trim().isNotEmpty)
      .join(', ');
}

String _staffRoleLabel(String role) {
  return switch (role) {
    'admin' => 'Администратор',
    'manager' => 'Управляющий',
    'director' => 'Директор',
    'teacher' => 'Преподаватель',
    'system_admin' => 'Администратор системы',
    _ => role.isEmpty ? 'Сотрудник' : role,
  };
}

String _staffStatusLabel(String status) {
  return switch (status) {
    'active' => 'Активен',
    'inactive' => 'Неактивен',
    'archived' => 'В архиве',
    _ => status.isEmpty ? 'Статус не указан' : status,
  };
}

class _TeachersList extends ConsumerWidget {
  final String searchQuery;
  const _TeachersList({required this.searchQuery});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = searchQuery.trim();
    final async = ref.watch(teacherSearchProvider(query));
    return async.when(
      loading: () =>
          Padding(padding: EdgeInsets.all(12), child: ListSkeleton()),
      error: (e, _) => Center(
        child: Text('Ошибка: $e', style: TextStyle(color: AppTheme.danger)),
      ),
      data: (items) {
        if (items.isEmpty) {
          return Center(
            child: Text(
              query.isEmpty ? 'Нет преподавателей' : 'Ничего не найдено',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }

        return RefreshIndicator(
          color: AppTheme.primaryGold,
          onRefresh: () async => ref.invalidate(teacherSearchProvider(query)),
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            itemBuilder: (ctx, i) {
              final item = items[i];
              final fName =
                  item['first_name'] ?? item['profiles']?['first_name'] ?? '';
              final lName =
                  item['last_name'] ?? item['profiles']?['last_name'] ?? '';
              final name = '$fName $lName'.trim();
              final dList = item['disciplines'] as List<dynamic>?;
              String spec = 'Не указана';
              if (dList != null && dList.isNotEmpty) {
                try {
                  spec = dList
                      .map((d) {
                        if (d is Map) {
                          return d['Name']?.toString() ??
                              d['name']?.toString() ??
                              '';
                        }
                        return d.toString();
                      })
                      .where((s) => s.isNotEmpty)
                      .join(', ');
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
                    final updated = await TeacherDetailDialog.show(
                      context,
                      item,
                    );
                    if (updated == true) {
                      ref.invalidate(entitiesProvider('teachers'));
                      ref.invalidate(teacherSearchProvider(query));
                    }
                  },
                  leading: CircleAvatar(
                    backgroundColor: AppTheme.secondaryGold.withAlpha(30),
                    child: Text(
                      name.isNotEmpty ? name[0] : '?',
                      style: const TextStyle(
                        color: AppTheme.secondaryGold,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  title: Text(name.isEmpty ? 'Без имени' : name),
                  subtitle: _TeacherSearchSummary(item: item, spec: spec),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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

class _TeacherSearchSummary extends StatelessWidget {
  final Map<String, dynamic> item;
  final String spec;

  const _TeacherSearchSummary({required this.item, required this.spec});

  @override
  Widget build(BuildContext context) {
    final branches = _branchesText(item['branches']);
    final students = _asInt(item['students_count']);
    final lessons = _asInt(item['lessons_count']);
    final rating = _asNum(item['rating']);
    final isAppAccount = item['is_app_account'] == true;
    final appRole = item['app_role']?.toString() ?? '';
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Специализация: $spec',
            style: TextStyle(color: muted, fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (branches.isNotEmpty)
                _StudentMetricChip(
                  icon: Icons.location_on_outlined,
                  label: branches,
                  color: AppTheme.primaryGold,
                ),
              _StudentMetricChip(
                icon: Icons.school_rounded,
                label: 'Ученики: $students',
                color: AppTheme.primaryGold,
              ),
              _StudentMetricChip(
                icon: Icons.event_available_rounded,
                label: 'Занятия: $lessons',
                color: AppTheme.success,
              ),
              if (rating > 0)
                _StudentMetricChip(
                  icon: Icons.star_rounded,
                  label: rating.toStringAsFixed(1),
                  color: AppTheme.secondaryGold,
                ),
              _StudentMetricChip(
                icon: isAppAccount
                    ? Icons.verified_user_rounded
                    : Icons.person_off_rounded,
                label: isAppAccount ? _staffRoleLabel(appRole) : 'Без аккаунта',
                color: isAppAccount ? AppTheme.success : muted,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LessonsList extends ConsumerWidget {
  const _LessonsList();

  String _statusLabel(String? s) {
    switch (s) {
      case 'completed':
        return 'Завершено';
      case 'cancelled':
        return 'Отменено';
      default:
        return 'Запланировано';
    }
  }

  Color _statusColor(String? s) {
    switch (s) {
      case 'completed':
        return AppTheme.success;
      case 'cancelled':
        return AppTheme.danger;
      default:
        return AppTheme.primaryGold;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(entitiesProvider('lessons'));
    return async.when(
      loading: () =>
          Padding(padding: EdgeInsets.all(12), child: ListSkeleton()),
      error: (e, _) => Center(
        child: Text('Ошибка: $e', style: TextStyle(color: AppTheme.danger)),
      ),
      data: (items) {
        if (items.isEmpty) {
          return Center(
            child: Text(
              'Нет занятий',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }
        return RefreshIndicator(
          color: AppTheme.primaryGold,
          onRefresh: () async => ref.invalidate(entitiesProvider('lessons')),
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            itemBuilder: (ctx, i) {
              final l = items[i];
              final dt = DateTime.tryParse(l['scheduled_at'] ?? '');
              final dateStr = dt != null
                  ? DateFormat('d MMM yyyy, HH:mm', 'ru').format(dt.toLocal())
                  : '—';

              String studentName = l['student_name'] as String? ?? '';
              if (studentName.trim().isEmpty) {
                final student = l['students'];
                if (student != null) {
                  final sf =
                      student['first_name'] ??
                      student['profiles']?['first_name'] ??
                      '';
                  final sl =
                      student['last_name'] ??
                      student['profiles']?['last_name'] ??
                      '';
                  studentName = '$sf $sl'.trim();
                }
              }
              if (studentName.trim().isEmpty &&
                  l['groups'] != null &&
                  l['groups']['name'] != null) {
                studentName = 'Группа: ${l['groups']['name']}';
              } else if (studentName.trim().isEmpty) {
                studentName = 'Без ученика';
              }

              String teacherName = l['teacher_name'] as String? ?? '';
              if (teacherName.trim().isEmpty) {
                final teacher = l['teachers'];
                if (teacher != null) {
                  final tf =
                      teacher['first_name'] ??
                      teacher['profiles']?['first_name'] ??
                      '';
                  final tl =
                      teacher['last_name'] ??
                      teacher['profiles']?['last_name'] ??
                      '';
                  teacherName = '$tf $tl'.trim();
                }
              }
              if (teacherName.trim().isEmpty) teacherName = 'Без преподавателя';

              final room =
                  l['room_name'] as String? ??
                  l['rooms']?['name'] as String? ??
                  '—';
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
                            Text(
                              dateStr,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Ученик: $studentName',
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              'Преп.: $teacherName',
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              'Кабинет: $room',
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _statusColor(status).withAlpha(25),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _statusLabel(status),
                          style: TextStyle(
                            color: _statusColor(status),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      SizedBox(width: 4),
                      PopupMenuButton<String>(
                        icon: Icon(
                          Icons.more_vert_rounded,
                          size: 20,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        onSelected: (val) {
                          if (val == 'cancel') {
                            _cancelLesson(context, ref, l['id']);
                          }
                          if (val == 'reschedule') {
                            _rescheduleLesson(context, ref, l['id'], dt);
                          }
                        },
                        itemBuilder: (ctx) => [
                          const PopupMenuItem(
                            value: 'cancel',
                            child: Text('Отменить занятие'),
                          ),
                          const PopupMenuItem(
                            value: 'reschedule',
                            child: Text('Перенести'),
                          ),
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

  Future<void> _cancelLesson(
    BuildContext context,
    WidgetRef ref,
    String lessonId,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Отменить занятие?'),
        content: Text('Статус занятия будет изменен на "Отменено".'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Назад'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Отменить', style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ref
          .read(magicCrmServiceProvider)
          .updateLesson(lessonId, status: 'cancelled');
      ref.invalidate(entitiesProvider('lessons'));
    }
  }

  Future<void> _rescheduleLesson(
    BuildContext context,
    WidgetRef ref,
    String lessonId,
    DateTime? current,
  ) async {
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

    final newDateTime = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    await ref
        .read(magicCrmServiceProvider)
        .updateLesson(lessonId, scheduledAt: newDateTime.toIso8601String());
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
      loading: () =>
          Padding(padding: EdgeInsets.all(12), child: ListSkeleton()),
      error: (e, _) => Center(
        child: Text('Ошибка: $e', style: TextStyle(color: AppTheme.danger)),
      ),
      data: (items) {
        var filtered = items;
        if (searchQuery.isNotEmpty) {
          filtered = items.where((item) {
            final name = (item['name'] as String? ?? '').toLowerCase();
            return name.contains(searchQuery.toLowerCase());
          }).toList();
        }

        if (filtered.isEmpty) {
          return Center(
            child: Text(
              searchQuery.isEmpty ? 'Нет групп' : 'Ничего не найдено',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }

        return RefreshIndicator(
          color: AppTheme.primaryGold,
          onRefresh: () async => ref.invalidate(entitiesProvider('groups')),
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: filtered.length,
            itemBuilder: (ctx, i) {
              final item = filtered[i];
              final name = item['name'] as String? ?? 'Без названия';
              final branchName =
                  item['branches']?['name'] as String? ?? 'Без филиала';
              final teacher = item['teachers'];

              var teacherName = 'Без преподавателя';
              if (teacher != null) {
                final tf =
                    teacher['first_name'] ??
                    teacher['profiles']?['first_name'] ??
                    '';
                final tl =
                    teacher['last_name'] ??
                    teacher['profiles']?['last_name'] ??
                    '';
                teacherName = '$tf $tl'.trim();
                if (teacherName.isEmpty) {
                  teacherName = teacher['name'] as String? ?? '';
                }
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
                    backgroundColor: AppTheme.primaryGold.withAlpha(30),
                    child: Icon(
                      Icons.group_rounded,
                      color: AppTheme.primaryGold,
                    ),
                  ),
                  title: Text(name),
                  subtitle: Text(
                    'Преп.: $teacherName • Фил.: $branchName',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
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

class _RoomsList extends ConsumerWidget {
  final String searchQuery;
  const _RoomsList({required this.searchQuery});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(entitiesProvider('rooms'));
    return async.when(
      loading: () =>
          Padding(padding: EdgeInsets.all(12), child: ListSkeleton()),
      error: (e, _) => Center(
        child: Text('Ошибка: $e', style: TextStyle(color: AppTheme.danger)),
      ),
      data: (items) {
        var filtered = items;
        if (searchQuery.isNotEmpty) {
          filtered = items.where((item) {
            final name = (item['name'] as String? ?? '').toLowerCase();
            return name.contains(searchQuery.toLowerCase());
          }).toList();
        }

        if (filtered.isEmpty) {
          return Center(
            child: Text(
              searchQuery.isEmpty ? 'Нет аудиторий' : 'Ничего не найдено',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }

        return RefreshIndicator(
          color: AppTheme.primaryGold,
          onRefresh: () async => ref.invalidate(entitiesProvider('rooms')),
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: filtered.length,
            itemBuilder: (ctx, i) {
              final item = filtered[i];
              final name = item['name'] as String? ?? 'Без названия';
              final branchName =
                  item['branches']?['name'] as String? ?? 'Без филиала';
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
                    backgroundColor: AppTheme.primaryGold.withAlpha(30),
                    child: Icon(
                      Icons.meeting_room_rounded,
                      color: AppTheme.primaryGold,
                    ),
                  ),
                  title: Text(name),
                  subtitle: Text(
                    'Вместимость: $capacity чел. • Фил.: $branchName',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                  trailing: Icon(
                    Icons.edit_rounded,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    size: 18,
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

// ─────────────────────────────────────────────────
// Employees List
// ─────────────────────────────────────────────────
class _EmployeesList extends ConsumerWidget {
  final String searchQuery;
  const _EmployeesList({required this.searchQuery});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = searchQuery.trim();
    final all = ref.watch(staffSearchProvider(query));
    return all.when(
      loading: () =>
          const Padding(padding: EdgeInsets.all(12), child: ListSkeleton()),
      error: (e, _) => Center(child: Text('Ошибка: $e')),
      data: (items) {
        if (items.isEmpty) {
          return Center(
            child: Text(
              query.isEmpty ? 'Нет сотрудников' : 'Ничего не найдено',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }

        return RefreshIndicator(
          color: AppTheme.primaryGold,
          onRefresh: () async => ref.invalidate(staffSearchProvider(query)),
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            itemBuilder: (_, i) {
              final e = items[i];
              final firstName = e['first_name'] as String? ?? '';
              final lastName = e['last_name'] as String? ?? '';
              final fullName = '$lastName $firstName'.trim().isEmpty
                  ? 'Без имени'
                  : '$lastName $firstName'.trim();
              final role = e['role'] as String? ?? '';
              final appRole = e['app_role'] as String? ?? '';
              final status = e['status'] as String? ?? '';
              final position = e['position'] as String? ?? '';
              final roleLabel = _staffRoleLabel(role);
              final roleColor = role == 'manager'
                  ? const Color(0xFF8B5CF6)
                  : role == 'director'
                  ? const Color(0xFFEF4444)
                  : role == 'teacher'
                  ? const Color(0xFF3B82F6)
                  : AppTheme.primaryGold;
              final branches = _branchesText(e['branches']);
              final isAppAccount = e['is_app_account'] == true;
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: roleColor.withAlpha(40),
                    child: Text(
                      fullName.isNotEmpty ? fullName[0].toUpperCase() : '?',
                      style: TextStyle(
                        color: roleColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(fullName),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if ((e['email'] ?? '').isNotEmpty)
                          Text(
                            e['email'],
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        if ((e['phone'] ?? '').isNotEmpty)
                          Text(
                            e['phone'],
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _StudentMetricChip(
                              icon: Icons.badge_outlined,
                              label: roleLabel,
                              color: roleColor,
                            ),
                            if (position.trim().isNotEmpty)
                              _StudentMetricChip(
                                icon: Icons.work_outline_rounded,
                                label: position.trim(),
                                color: AppTheme.secondaryGold,
                              ),
                            _StudentMetricChip(
                              icon: Icons.circle_outlined,
                              label: _staffStatusLabel(status),
                              color: status == 'active'
                                  ? AppTheme.success
                                  : Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                            ),
                            if (branches.isNotEmpty)
                              _StudentMetricChip(
                                icon: Icons.location_on_outlined,
                                label: branches,
                                color: AppTheme.primaryGold,
                              ),
                            _StudentMetricChip(
                              icon: isAppAccount
                                  ? Icons.verified_user_rounded
                                  : Icons.person_off_rounded,
                              label: isAppAccount
                                  ? _staffRoleLabel(appRole)
                                  : 'Без аккаунта',
                              color: isAppAccount
                                  ? AppTheme.success
                                  : Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  onTap: () async {
                    final updated = await StaffDetailDialog.show(context, e);
                    if (updated == true) {
                      ref.invalidate(entitiesProvider('employees'));
                      ref.invalidate(staffSearchProvider(query));
                    }
                  },
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
// Branches List
// ─────────────────────────────────────────────────
class _BranchesList extends ConsumerWidget {
  final String searchQuery;
  const _BranchesList({required this.searchQuery});

  String _offsetLabel(int minutes) {
    final sign = minutes >= 0 ? '+' : '-';
    final abs = minutes.abs();
    final h = abs ~/ 60;
    final m = abs % 60;
    final timeStr = m == 0
        ? 'UTC$sign$h'
        : 'UTC$sign$h:${m.toString().padLeft(2, '0')}';
    return switch (minutes) {
      180 => 'МСК ($timeStr)',
      120 => 'EET ($timeStr)',
      60 => 'CET ($timeStr)',
      0 => 'UTC',
      _ => timeStr,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(entitiesProvider('branches'));
    return async.when(
      loading: () =>
          const Padding(padding: EdgeInsets.all(12), child: ListSkeleton()),
      error: (e, _) => Center(
        child: Text('Ошибка: $e', style: TextStyle(color: AppTheme.danger)),
      ),
      data: (items) {
        var filtered = items;
        if (searchQuery.isNotEmpty) {
          filtered = items.where((item) {
            final name = (item['name'] as String? ?? '').toLowerCase();
            final address = (item['address'] as String? ?? '').toLowerCase();
            final q = searchQuery.toLowerCase();
            return name.contains(q) || address.contains(q);
          }).toList();
        }

        if (filtered.isEmpty) {
          return Center(
            child: Text(
              searchQuery.isEmpty ? 'Нет филиалов' : 'Ничего не найдено',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }

        return RefreshIndicator(
          color: AppTheme.primaryGold,
          onRefresh: () async => ref.invalidate(entitiesProvider('branches')),
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: filtered.length,
            itemBuilder: (ctx, i) {
              final item = filtered[i];
              final name = item['name'] as String? ?? 'Без названия';
              final address = item['address'] as String? ?? '';
              final offsetMinutes =
                  (item['utc_offset_minutes'] as num?)?.toInt() ?? 180;

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  onTap: () async {
                    final res = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => BranchFormDialog(branch: item),
                    );
                    if (res == true) {
                      ref.invalidate(entitiesProvider('branches'));
                    }
                  },
                  leading: CircleAvatar(
                    backgroundColor: AppTheme.primaryGold.withAlpha(30),
                    child: Icon(
                      Icons.location_city_rounded,
                      color: AppTheme.primaryGold,
                    ),
                  ),
                  title: Text(name),
                  subtitle: Text(
                    [
                      if (address.isNotEmpty) address,
                      _offsetLabel(offsetMinutes),
                    ].join(' • '),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                  trailing: Icon(
                    Icons.edit_rounded,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    size: 18,
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

// ─────────────────────────────────────────────────
// Subscription Packages (Каталог абонементов) — P5b-5
// ─────────────────────────────────────────────────
class _PackagesList extends ConsumerWidget {
  final String searchQuery;
  const _PackagesList({required this.searchQuery});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(entitiesProvider('subscription_packages'));
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(12),
        child: _PackagesSkeleton(),
      ),
      error: (e, _) => Center(
        child: Text('Ошибка: $e', style: TextStyle(color: AppTheme.danger)),
      ),
      data: (items) {
        var filtered = items;
        if (searchQuery.isNotEmpty) {
          final q = searchQuery.toLowerCase();
          filtered = items.where((item) {
            final name = (item['name'] as String? ?? '').toLowerCase();
            return name.contains(q);
          }).toList();
        }

        if (filtered.isEmpty) {
          return Center(
            child: Text(
              searchQuery.isEmpty ? 'Нет абонементов' : 'Ничего не найдено',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }

        return RefreshIndicator(
          color: AppColor.gold,
          onRefresh: () async =>
              ref.invalidate(entitiesProvider('subscription_packages')),
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: filtered.length,
            itemBuilder: (ctx, i) {
              final item = filtered[i];
              return _PackageCard(item: item);
            },
          ),
        );
      },
    );
  }
}

class _PackageCard extends ConsumerWidget {
  final Map<String, dynamic> item;
  const _PackageCard({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final name = item['name'] as String? ?? 'Без названия';
    final hoursNum = _asNum(item['lessons_total'] ?? item['lessonsTotal']);
    final hours = hoursNum % 1 == 0 ? hoursNum.toInt() : hoursNum;
    final price = _asNum(item['price']);
    final validity = item['validity_days'] ?? item['validityDays'];
    final validityDays = validity == null ? null : _asInt(validity);
    final branchName =
        (item['branches']?['name'] ?? item['branch_name'])?.toString() ?? '';
    final isActive =
        item['is_active'] == true ||
        item['isActive'] == true ||
        (item['is_active'] == null && item['isActive'] == null);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () async {
          final saved = await showPackageSheet(context, ref, existing: item);
          if (saved == true) {
            ref.invalidate(entitiesProvider('subscription_packages'));
          }
        },
        leading: CircleAvatar(
          backgroundColor: AppColor.goldSoft,
          child: const Icon(
            Icons.card_membership_rounded,
            color: AppColor.gold,
          ),
        ),
        title: Text(name),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _StudentMetricChip(
                icon: Icons.event_available_rounded,
                label: 'Часов: $hours',
                color: AppColor.gold,
              ),
              _StudentMetricChip(
                icon: Icons.payments_rounded,
                label: '${_formatMoney(price)} ₽',
                color: AppTheme.secondaryGold,
              ),
              if (validityDays != null)
                _StudentMetricChip(
                  icon: Icons.schedule_rounded,
                  label: 'Срок: $validityDays дн.',
                  color: AppTheme.success,
                ),
              if (branchName.trim().isNotEmpty)
                _StudentMetricChip(
                  icon: Icons.location_on_outlined,
                  label: branchName.trim(),
                  color: AppColor.gold,
                ),
              _StudentMetricChip(
                icon: isActive
                    ? Icons.check_circle_outline_rounded
                    : Icons.pause_circle_outline_rounded,
                label: isActive ? 'Активен' : 'Неактивен',
                color: isActive ? AppTheme.success : cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
        trailing: IconButton(
          icon: Icon(Icons.delete_outline_rounded, color: AppColor.danger),
          tooltip: 'Удалить',
          onPressed: () => _confirmDeletePackage(context, ref, item),
        ),
      ),
    );
  }
}

class _PackagesSkeleton extends StatelessWidget {
  const _PackagesSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        6,
        (_) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              const SkeletonBox(width: 40, height: 40, radius: AppRadius.pill),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    SkeletonLine(width: 160),
                    SizedBox(height: 8),
                    SkeletonLine(width: 220),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _confirmDeletePackage(
  BuildContext context,
  WidgetRef ref,
  Map<String, dynamic> item,
) async {
  final id = item['id']?.toString();
  if (id == null || id.isEmpty) return;
  final name = item['name'] as String? ?? 'абонемент';

  final confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Удалить абонемент?'),
      content: Text('«$name» будет удалён из каталога. Действие необратимо.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Отмена'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text('Удалить', style: TextStyle(color: AppColor.danger)),
        ),
      ],
    ),
  );
  if (confirm != true || !context.mounted) return;

  try {
    await ref.read(magicCrmServiceProvider).deleteSubscriptionPackage(id);
    ref.invalidate(entitiesProvider('subscription_packages'));
    if (context.mounted) {
      MagicToast.show(
        context,
        'Абонемент удалён',
        type: MagicToastType.success,
      );
    }
  } catch (e) {
    if (context.mounted) {
      MagicToast.show(
        context,
        'Не удалось удалить',
        detail: '$e',
        type: MagicToastType.danger,
      );
    }
  }
}

/// Opens the v7 create/edit sheet for a subscription package. Returns `true`
/// when a package was created or updated, so the caller can invalidate the list.
Future<bool?> showPackageSheet(
  BuildContext context,
  WidgetRef ref, {
  Map<String, dynamic>? existing,
}) {
  final isEdit = existing != null;
  return showMagicSheet<bool>(
    context,
    title: isEdit ? 'Редактировать абонемент' : 'Новый абонемент',
    subtitle: 'Каталог абонементов',
    icon: Icons.card_membership_rounded,
    builder: (ctx) => _PackageForm(ref: ref, existing: existing),
  );
}

class _PackageForm extends StatefulWidget {
  final WidgetRef ref;
  final Map<String, dynamic>? existing;
  const _PackageForm({required this.ref, this.existing});

  @override
  State<_PackageForm> createState() => _PackageFormState();
}

class _PackageFormState extends State<_PackageForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _lessons;
  late final TextEditingController _price;
  late final TextEditingController _validity;
  late final TextEditingController _branchId;
  late bool _isActive;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?['name']?.toString() ?? '');
    _lessons = TextEditingController(
      text: (e?['lessons_total'] ?? e?['lessonsTotal'])?.toString() ?? '',
    );
    _price = TextEditingController(text: e?['price']?.toString() ?? '');
    _validity = TextEditingController(
      text: (e?['validity_days'] ?? e?['validityDays'])?.toString() ?? '',
    );
    _branchId = TextEditingController(
      text: (e?['branch_id'] ?? e?['branchId'])?.toString() ?? '',
    );
    final active = e?['is_active'] ?? e?['isActive'];
    _isActive = active is bool ? active : true;
  }

  @override
  void dispose() {
    _name.dispose();
    _lessons.dispose();
    _price.dispose();
    _validity.dispose();
    _branchId.dispose();
    super.dispose();
  }

  InputDecoration _dec(String label, {String? hint}) {
    final cs = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: cs.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: const BorderSide(color: AppColor.goldLine),
      ),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final name = _name.text.trim();
    final lessonsTotal = num.parse(_lessons.text.trim().replaceAll(',', '.'));
    final price = num.parse(_price.text.trim().replaceAll(',', '.'));
    final validityText = _validity.text.trim();
    final validityDays = validityText.isEmpty ? null : int.parse(validityText);
    final branchText = _branchId.text.trim();
    final branchId = branchText.isEmpty ? null : branchText;

    setState(() => _saving = true);
    final crm = widget.ref.read(magicCrmServiceProvider);
    try {
      if (_isEdit) {
        final id = widget.existing!['id'].toString();
        await crm.updateSubscriptionPackage(id, {
          'name': name,
          'lessonsTotal': lessonsTotal,
          'price': price,
          'validityDays': validityDays,
          'branchId': branchId,
          'isActive': _isActive,
        });
      } else {
        await crm.createSubscriptionPackage(
          name: name,
          lessonsTotal: lessonsTotal,
          price: price,
          validityDays: validityDays,
          branchId: branchId,
          isActive: _isActive,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
      MagicToast.show(
        context,
        _isEdit ? 'Абонемент обновлён' : 'Абонемент создан',
        type: MagicToastType.success,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      MagicToast.show(
        context,
        'Не удалось сохранить',
        detail: '$e',
        type: MagicToastType.danger,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _name,
            decoration: _dec('Название', hint: 'Напр. «16 часов»'),
            textInputAction: TextInputAction.next,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Укажите название' : null,
          ),
          const SizedBox(height: AppSpace.md),
          TextFormField(
            controller: _lessons,
            decoration: _dec('Количество часов'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.next,
            validator: (v) {
              final n = num.tryParse((v ?? '').trim().replaceAll(',', '.'));
              if (n == null) return 'Введите число';
              if (n <= 0) return 'Должно быть больше 0';
              return null;
            },
          ),
          const SizedBox(height: AppSpace.md),
          TextFormField(
            controller: _price,
            decoration: _dec('Цена, ₽'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.next,
            validator: (v) {
              final n = num.tryParse((v ?? '').trim().replaceAll(',', '.'));
              if (n == null) return 'Введите число';
              if (n < 0) return 'Не может быть отрицательной';
              return null;
            },
          ),
          const SizedBox(height: AppSpace.md),
          TextFormField(
            controller: _validity,
            decoration: _dec('Срок действия, дней', hint: 'Необязательно'),
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            validator: (v) {
              final t = (v ?? '').trim();
              if (t.isEmpty) return null;
              final n = int.tryParse(t);
              if (n == null) return 'Введите целое число';
              if (n <= 0) return 'Должно быть больше 0';
              return null;
            },
          ),
          const SizedBox(height: AppSpace.md),
          TextFormField(
            controller: _branchId,
            decoration: _dec('ID филиала', hint: 'Необязательно'),
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: AppSpace.md),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Активен',
                    style: TextStyle(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Switch(
                  value: _isActive,
                  activeThumbColor: AppColor.gold,
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _isActive = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cs.onSurface,
                    side: BorderSide(color: cs.outlineVariant),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.control),
                    ),
                  ),
                  child: const Text('Отмена'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColor.gold,
                    foregroundColor: AppColor.onGold,
                    disabledBackgroundColor: AppColor.gold.withValues(
                      alpha: 0.5,
                    ),
                    disabledForegroundColor: AppColor.onGold,
                    elevation: 0,
                    shadowColor: Colors.transparent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.control),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColor.onGold,
                          ),
                        )
                      : Text(_isEdit ? 'Сохранить' : 'Создать'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
