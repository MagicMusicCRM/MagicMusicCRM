part of 'manage_entities_widget.dart';

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
      try {
        await ref
            .read(magicCrmServiceProvider)
            .updateLesson(lessonId, status: 'cancelled');
        ref.invalidate(entitiesProvider('lessons'));
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Не удалось отменить занятие: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
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

    try {
      await ref
          .read(magicCrmServiceProvider)
          .updateLesson(lessonId, scheduledAt: newDateTime.toIso8601String());
      ref.invalidate(entitiesProvider('lessons'));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Не удалось перенести занятие: $e'),
          backgroundColor: AppTheme.danger,
        ),
      );
    }
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
