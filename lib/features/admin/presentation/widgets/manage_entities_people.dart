part of 'manage_entities_widget.dart';

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
    'working' => 'Работает',
    'active' => 'Активен',
    'inactive' => 'Неактивен',
    'archived' => 'В архиве',
    _ => status.isEmpty ? 'Статус не указан' : status,
  };
}

class _TeachersList extends ConsumerWidget {
  final String searchQuery;
  final String? branchId, status;
  final String? selectedId;
  final ValueChanged<Map<String, dynamic>>? onSelected;
  const _TeachersList({
    required this.searchQuery,
    this.branchId,
    this.status,
    this.selectedId,
    this.onSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = searchQuery.trim();
    final provider = branchId == null && status == null
        ? teacherSearchProvider(query)
        : personnelDirectoryProvider((
            teachers: true,
            query: query,
            branchId: branchId,
            status: status,
          ));
    final async = ref.watch(provider);
    return async.when(
      loading: () =>
          Padding(padding: EdgeInsets.all(12), child: ListSkeleton()),
      error: (_, _) => _EntityLoadError(
        title: 'Не удалось загрузить преподавателей',
        onRetry: () => ref.invalidate(provider),
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
          onRefresh: () async => ref.invalidate(provider),
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
                color: selectedId == item['id']?.toString()
                    ? AppColor.goldSoft
                    : null,
                child: ListTile(
                  onTap: () async {
                    if (onSelected != null) {
                      onSelected!(item);
                      return;
                    }
                    final updated = await TeacherDetailDialog.show(
                      context,
                      item,
                    );
                    if (updated == true) {
                      ref.invalidate(entitiesProvider('teachers'));
                      ref.invalidate(provider);
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
    return Text(
      [
        spec,
        if (branches.isNotEmpty) branches,
        if (item['lifecycle_state'] == 'archived') 'В архиве',
      ].join(' · '),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontSize: 12,
      ),
    );
  }
}
