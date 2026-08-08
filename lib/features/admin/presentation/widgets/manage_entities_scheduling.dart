part of 'manage_entities_widget.dart';

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
              final students = _asInt(item['students_count']);

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
                    'Учеников: $students • Преп.: $teacherName • Фил.: $branchName',
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

// ─────────────────────────────────────────────────
// Employees List
// ─────────────────────────────────────────────────
class _EmployeesList extends ConsumerWidget {
  final String searchQuery;
  final String currentRole;
  const _EmployeesList({required this.searchQuery, required this.currentRole});

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
              final email = (e['email'] as String? ?? '').trim();
              final presentableEmail =
                  email.endsWith('@migration.invalid') ||
                      email.endsWith('@local.magicmusiccrm.invalid')
                  ? ''
                  : email;
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
                        if (presentableEmail.isNotEmpty)
                          Text(
                            presentableEmail,
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
                    final updated = await StaffDetailDialog.show(
                      context,
                      e,
                      currentRole: currentRole,
                    );
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
