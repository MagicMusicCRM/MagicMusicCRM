part of 'manage_entities_widget.dart';

class _GroupsList extends ConsumerWidget {
  final String searchQuery;
  final bool includeArchived;
  final bool canManageLifecycle;
  const _GroupsList({
    required this.searchQuery,
    required this.includeArchived,
    required this.canManageLifecycle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(
      entitiesProvider(includeArchived ? 'groups:all' : 'groups'),
    );
    return async.when(
      loading: () =>
          Padding(padding: EdgeInsets.all(12), child: ListSkeleton()),
      error: (_, _) => _EntityLoadError(
        title: 'Не удалось загрузить группы',
        onRetry: () => invalidateGroupCatalog(ref),
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
          onRefresh: () async => invalidateGroupCatalog(ref),
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: filtered.length,
            itemBuilder: (ctx, i) {
              final item = filtered[i];
              final name = item['name'] as String? ?? 'Без названия';
              final branchName =
                  item['branches']?['name'] as String? ?? 'Без филиала';
              final teacher = item['teachers'];
              final students = _asInt(item['students_count']);
              final archived = item['lifecycle_state'] == 'archived';

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
                    final Future<bool?> dialog;
                    if (archived && canManageLifecycle) {
                      dialog = showMagicDialog<bool>(
                        context: context,
                        builder: (_) => GroupLifecycleDialog(group: item),
                      );
                    } else {
                      dialog = GroupDetailDialog.show(
                        context,
                        item,
                        canWrite: canManageLifecycle,
                      );
                    }
                    final updated = await dialog;
                    if (updated == true) {
                      invalidateGroupCatalog(ref);
                    }
                  },
                  leading: CircleAvatar(
                    backgroundColor: archived
                        ? Theme.of(context).colorScheme.surfaceContainerHighest
                        : AppTheme.primaryGold.withAlpha(30),
                    child: Icon(
                      archived ? Icons.archive_outlined : Icons.group_rounded,
                      color: archived
                          ? Theme.of(context).colorScheme.onSurfaceVariant
                          : AppTheme.primaryGold,
                    ),
                  ),
                  title: Row(
                    children: [
                      Expanded(child: Text(name)),
                      if (archived)
                        const Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text('Завершена'),
                          ),
                        ),
                    ],
                  ),
                  subtitle: Text(
                    'Учеников: $students • Преп.: $teacherName • Фил.: $branchName',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                  trailing: canManageLifecycle
                      ? IconButton(
                          tooltip: archived
                              ? 'Восстановить группу'
                              : 'Завершить группу',
                          icon: Icon(
                            archived
                                ? Icons.restore_rounded
                                : Icons.archive_outlined,
                          ),
                          onPressed: () async {
                            final updated = await showMagicDialog<bool>(
                              context: context,
                              builder: (_) => GroupLifecycleDialog(group: item),
                            );
                            if (updated == true) invalidateGroupCatalog(ref);
                          },
                        )
                      : null,
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
  final String? branchId, status;
  final String currentRole;
  final String? selectedId;
  final ValueChanged<Map<String, dynamic>>? onSelected;
  const _EmployeesList({
    required this.searchQuery,
    this.branchId,
    this.status,
    required this.currentRole,
    this.selectedId,
    this.onSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = searchQuery.trim();
    final provider = branchId == null && status == null
        ? staffSearchProvider(query)
        : personnelDirectoryProvider((
            teachers: false,
            query: query,
            branchId: branchId,
            status: status,
          ));
    final all = ref.watch(provider);
    return all.when(
      loading: () =>
          const Padding(padding: EdgeInsets.all(12), child: ListSkeleton()),
      error: (_, _) => _EntityLoadError(
        title: 'Не удалось загрузить сотрудников',
        onRetry: () => ref.invalidate(provider),
      ),
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
          onRefresh: () async => ref.invalidate(provider),
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
              final status = e['status'] as String? ?? '';
              final position = e['position'] as String? ?? '';
              final roleLabel = _staffRoleLabel(role);
              const roleColor = AppColor.gold;
              final branches = _branchesText(e['branches']);
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                color: selectedId == e['id']?.toString()
                    ? AppColor.goldSoft
                    : null,
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
                  subtitle: Text(
                    [
                      position.trim().isEmpty ? roleLabel : position.trim(),
                      if (branches.isNotEmpty) branches,
                      _staffStatusLabel(status),
                    ].join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  onTap: () async {
                    if (onSelected != null) {
                      onSelected!(e);
                      return;
                    }
                    final updated = await StaffDetailDialog.show(
                      context,
                      e,
                      currentRole: currentRole,
                    );
                    if (updated == true) {
                      ref.invalidate(entitiesProvider('employees'));
                      ref.invalidate(provider);
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
