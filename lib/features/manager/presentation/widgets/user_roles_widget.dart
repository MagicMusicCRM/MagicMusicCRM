import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:magic_music_crm/core/services/crm_realtime_provider.dart';
import 'package:magic_music_crm/core/services/magic_profile_admin_service.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/skeletons.dart';

class UserRolesWidget extends ConsumerStatefulWidget {
  final String currentRole;
  final String? initialSearch;

  const UserRolesWidget({
    super.key,
    required this.currentRole,
    this.initialSearch,
  });

  @override
  ConsumerState<UserRolesWidget> createState() => _UserRolesWidgetState();
}

class _UserRolesWidgetState extends ConsumerState<UserRolesWidget> {
  List<Map<String, dynamic>> _profiles = [];
  bool _isLoading = false;
  String _searchQuery = '';
  String _selectedRole = 'all';
  String? _linkingProfileId;
  final Set<String> _pendingRoleProfileIds = {};
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  Timer? _realtimeDebounce;

  static const _availableRoles = [
    'client',
    'teacher',
    'manager',
    'admin',
    'system_admin',
  ];
  static const _roleFilterValues = [
    'all',
    'client',
    'teacher',
    'manager',
    'admin',
    'system_admin',
  ];

  static const _roleLabels = {
    'all': 'Все',
    'client': 'Клиент',
    'teacher': 'Преподаватель',
    'manager': 'Управляющий',
    'admin': 'Администратор',
    'system_admin': 'Администратор системы',
  };

  static const _roleColors = {
    'client': Color(0xFF10B981),
    'teacher': Color(0xFF3B82F6),
    'manager': Color(0xFF8B5CF6),
    'admin': Color(0xFFF59E0B),
    'system_admin': Color(0xFFC5A059),
  };

  @override
  void initState() {
    super.initState();
    _applyInitialSearch(widget.initialSearch);
    _loadProfiles();
  }

  @override
  void didUpdateWidget(covariant UserRolesWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSearch != widget.initialSearch) {
      _applyInitialSearch(widget.initialSearch);
    }
  }

  @override
  void dispose() {
    _realtimeDebounce?.cancel();
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _applyInitialSearch(String? value) {
    final query = value?.trim();
    if (query == null || query.isEmpty || query == _searchQuery) return;
    _searchQuery = query;
    _searchController.text = query;
  }

  Future<void> _loadProfiles() async {
    setState(() => _isLoading = true);
    try {
      final data = await ref
          .read(magicProfileAdminServiceProvider)
          .listProfiles(
            limit: 100,
            role: _selectedRole == 'all' ? null : _selectedRole,
            // Filter on the server so search reaches the whole dataset, not
            // just the first 100 loaded rows.
            q: _searchQuery.trim().isEmpty ? null : _searchQuery.trim(),
          );
      if (mounted) {
        setState(() {
          _profiles = data;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки: $e'),
            backgroundColor: AppColor.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _autoLinkProfile(Map<String, dynamic> profile) async {
    final profileId = profile['id']?.toString();
    if (profileId == null || profileId.isEmpty) return;
    setState(() => _linkingProfileId = profileId);
    try {
      final summary = await ref
          .read(magicProfileAdminServiceProvider)
          .autoLinkByPhone(profileId);
      _applyLinkSummary(profileId, summary);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Связь по телефону обновлена'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка связи: $e'),
            backgroundColor: AppColor.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _linkingProfileId = null);
    }
  }

  Future<void> _linkCrmEntity({
    required String profileId,
    required String entityType,
    required String entityId,
  }) async {
    setState(() => _linkingProfileId = profileId);
    try {
      final summary = await ref
          .read(magicProfileAdminServiceProvider)
          .linkCrmEntity(
            profileId: profileId,
            entityType: entityType,
            entityId: entityId,
          );
      _applyLinkSummary(profileId, summary);
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Связь добавлена'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка связи: $e'),
            backgroundColor: AppColor.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _linkingProfileId = null);
    }
  }

  void _applyLinkSummary(String profileId, Map<String, dynamic> summary) {
    setState(() {
      final idx = _profiles.indexWhere((p) => p['id'] == profileId);
      if (idx < 0) return;
      _profiles[idx] = {
        ..._profiles[idx],
        'linked_students': summary['linkedStudents'] ?? 0,
        'linked_leads': summary['linkedLeads'] ?? 0,
        'linked_teachers': summary['linkedTeachers'] ?? 0,
        'linked_staff': summary['linkedStaff'] ?? 0,
        'candidate_students': summary['candidateStudents'] ?? 0,
        'candidate_leads': summary['candidateLeads'] ?? 0,
        'candidate_teachers': summary['candidateTeachers'] ?? 0,
        'candidate_staff': summary['candidateStaff'] ?? 0,
      };
    });
  }

  Future<void> _updateRole(String profileId, String newRole) async {
    final index = _profiles.indexWhere((p) => p['id'] == profileId);
    if (index < 0 || _pendingRoleProfileIds.contains(profileId)) return;
    final previous = Map<String, dynamic>.from(_profiles[index]);
    setState(() {
      _profiles[index] = {..._profiles[index], 'role': newRole};
      _pendingRoleProfileIds.add(profileId);
    });
    try {
      final updated = await ref
          .read(magicProfileAdminServiceProvider)
          .updateRole(profileId: profileId, role: newRole);
      if (!mounted) return;
      setState(() {
        final idx = _profiles.indexWhere((p) => p['id'] == profileId);
        if (idx >= 0) _profiles[idx] = {..._profiles[idx], ...updated};
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Роль обновлена на «${_roleLabels[newRole]}»'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          final idx = _profiles.indexWhere((p) => p['id'] == profileId);
          if (idx >= 0) _profiles[idx] = previous;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Не удалось изменить роль: $e'),
            backgroundColor: AppColor.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _pendingRoleProfileIds.remove(profileId));
      }
    }
  }

  List<Map<String, dynamic>> get _filteredProfiles {
    if (_searchQuery.isEmpty) return _profiles;
    final q = _searchQuery.toLowerCase();
    return _profiles.where((p) {
      final name = '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'
          .toLowerCase();
      final email = (p['email'] ?? '').toString().toLowerCase();
      final phone = (p['phone'] ?? '').toString().toLowerCase();
      return name.contains(q) || email.contains(q) || phone.contains(q);
    }).toList();
  }

  String _fullName(Map<String, dynamic> p) {
    final first = p['first_name'] ?? '';
    final last = p['last_name'] ?? '';
    if (first.isEmpty && last.isEmpty) return 'Без имени';
    return '$last $first'.trim();
  }

  int _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<void> _openLinkDialog(Map<String, dynamic> profile) async {
    final profileId = profile['id']?.toString();
    if (profileId == null || profileId.isEmpty) return;
    setState(() => _linkingProfileId = profileId);
    Map<String, dynamic> candidates;
    try {
      candidates = await ref
          .read(magicProfileAdminServiceProvider)
          .listLinkCandidates(profileId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки связей: $e'),
            backgroundColor: AppColor.danger,
          ),
        );
      }
      return;
    } finally {
      if (mounted) setState(() => _linkingProfileId = null);
    }
    if (!mounted) return;

    final students = (candidates['students'] as List?) ?? const [];
    final leads = (candidates['leads'] as List?) ?? const [];
    final teachers = (candidates['teachers'] as List?) ?? const [];
    final staff = (candidates['staff'] as List?) ?? const [];
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        title: Text(
          'Связь по телефону',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _LinkSection(
                  title: 'Ученики',
                  emptyText: 'Ученики с таким телефоном не найдены',
                  items: students.whereType<Map<String, dynamic>>().toList(),
                  onTap: (id) => _linkCrmEntity(
                    profileId: profileId,
                    entityType: 'student',
                    entityId: id,
                  ),
                ),
                const SizedBox(height: 12),
                _LinkSection(
                  title: 'Преподаватели',
                  emptyText: 'Преподаватели с таким телефоном не найдены',
                  items: teachers.whereType<Map<String, dynamic>>().toList(),
                  onTap: (id) => _linkCrmEntity(
                    profileId: profileId,
                    entityType: 'teacher',
                    entityId: id,
                  ),
                ),
                const SizedBox(height: 12),
                _LinkSection(
                  title: 'Сотрудники',
                  emptyText: 'Сотрудники с таким телефоном не найдены',
                  items: staff.whereType<Map<String, dynamic>>().toList(),
                  onTap: (id) => _linkCrmEntity(
                    profileId: profileId,
                    entityType: 'staff',
                    entityId: id,
                  ),
                ),
                const SizedBox(height: 12),
                _LinkSection(
                  title: 'Лиды',
                  emptyText: 'Лиды с таким телефоном не найдены',
                  items: leads.whereType<Map<String, dynamic>>().toList(),
                  onTap: (id) => _linkCrmEntity(
                    profileId: profileId,
                    entityType: 'lead',
                    entityId: id,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Закрыть'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColor.gold,
              foregroundColor: AppColor.onGold,
            ),
            onPressed: () {
              Navigator.pop(context);
              _autoLinkProfile(profile);
            },
            icon: const Icon(Icons.auto_fix_high, size: 18),
            label: const Text('Автосвязь'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Realtime: refresh the user/roles list when another staff member changes a
    // user (role/profile). Skip while loading or while a role update is in
    // flight — those refetch/patch themselves on completion.
    ref.listen(crmRealtimeProvider, (prev, next) {
      final event = next.value;
      if (event == null || event.entity != 'user' || !mounted) return;
      if (_isLoading || _pendingRoleProfileIds.isNotEmpty) return;
      _realtimeDebounce?.cancel();
      _realtimeDebounce = Timer(const Duration(milliseconds: 350), () {
        if (!mounted || _isLoading || _pendingRoleProfileIds.isNotEmpty) return;
        _loadProfiles();
      });
    });
    final filtered = _filteredProfiles;
    // A1: role editing is Управляющий + Администратор системы only.
    // Администратор (`admin`) is intentionally excluded (manager > admin).
    final canUpdateRoles =
        widget.currentRole == 'manager' ||
        widget.currentRole == 'system_admin';
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (v) {
                      setState(() => _searchQuery = v);
                      _searchDebounce?.cancel();
                      _searchDebounce = Timer(
                        const Duration(milliseconds: 350),
                        _loadProfiles,
                      );
                    },
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Поиск по имени, почте, телефону...',
                      hintStyle: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      prefixIcon: Icon(
                        Icons.search,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.control),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                SizedBox(width: 10),
                IconButton(
                  icon: Icon(
                    Icons.refresh,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  tooltip: 'Обновить',
                  onPressed: _loadProfiles,
                ),
              ],
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemBuilder: (context, index) {
                final role = _roleFilterValues[index];
                final selected = _selectedRole == role;
                final color =
                    _roleColors[role] ?? Theme.of(context).colorScheme.primary;
                return ChoiceChip(
                  selected: selected,
                  label: Text(_roleLabels[role] ?? role),
                  labelStyle: TextStyle(
                    color: selected
                        ? Colors.white
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                  selectedColor: color,
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  side: BorderSide(
                    color: selected
                        ? color
                        : Theme.of(context).colorScheme.outlineVariant,
                  ),
                  onSelected: (_) {
                    setState(() => _selectedRole = role);
                    _loadProfiles();
                  },
                );
              },
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemCount: _roleFilterValues.length,
            ),
          ),
          if (_profiles.length >= 100)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Показаны первые 100 — уточните поиск, чтобы найти '
                      'остальных',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _isLoading
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: ListSkeleton(count: 7),
                  )
                : filtered.isEmpty
                ? Center(
                    child: Text(
                      'Пользователи не найдены',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 16,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final p = filtered[i];
                      final role = p['role'] as String? ?? 'client';
                      final isRolePending = _pendingRoleProfileIds.contains(
                        p['id']?.toString(),
                      );
                      final roleColor =
                          _roleColors[role] ??
                          Theme.of(context).colorScheme.onSurfaceVariant;
                      final avatar = CircleAvatar(
                        radius: 24,
                        backgroundColor: roleColor.withAlpha(40),
                        child: Text(
                          _fullName(p).isNotEmpty
                              ? _fullName(p)[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            color: roleColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      );
                      final identity = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _fullName(p),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          if ((p['email'] ?? '').isNotEmpty)
                            Text(
                              p['email'],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                                fontSize: 13,
                              ),
                            ),
                          if ((p['phone'] ?? '').isNotEmpty)
                            Text(
                              p['phone'],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                                fontSize: 13,
                              ),
                            ),
                        ],
                      );
                      final badges = Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _MiniBadge(
                            icon: Icons.school_outlined,
                            text: '${_intValue(p['linked_students'])} учен.',
                          ),
                          _MiniBadge(
                            icon: Icons.assignment_ind_outlined,
                            text: '${_intValue(p['linked_leads'])} лид.',
                          ),
                          _MiniBadge(
                            icon: Icons.person_pin_outlined,
                            text: '${_intValue(p['linked_teachers'])} преп.',
                          ),
                          _MiniBadge(
                            icon: Icons.badge_outlined,
                            text: '${_intValue(p['linked_staff'])} сотр.',
                          ),
                          if (_intValue(p['candidate_students']) +
                                  _intValue(p['candidate_leads']) +
                                  _intValue(p['candidate_teachers']) +
                                  _intValue(p['candidate_staff']) >
                              0)
                            _MiniBadge(
                              icon: Icons.link_outlined,
                              text:
                                  '${_intValue(p['candidate_students']) + _intValue(p['candidate_leads']) + _intValue(p['candidate_teachers']) + _intValue(p['candidate_staff'])} канд.',
                              accent: AppColor.gold,
                            ),
                        ],
                      );
                      final linkButton = IconButton(
                        tooltip: 'Связать по телефону',
                        onPressed:
                            (p['phone'] ?? '').toString().trim().isEmpty
                            ? null
                            : () => _openLinkDialog(p),
                        icon: _linkingProfileId == p['id']
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.link),
                        color: AppColor.gold,
                      );
                      final roleDropdown = Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: roleColor.withAlpha(30),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: roleColor.withAlpha(80)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: role,
                            onChanged: canUpdateRoles && !isRolePending
                                ? (newRole) {
                                    if (newRole != null && newRole != role) {
                                      _confirmRoleChange(
                                        p['id'],
                                        _fullName(p),
                                        role,
                                        newRole,
                                      );
                                    }
                                  }
                                : null,
                            dropdownColor: Theme.of(
                              context,
                            ).colorScheme.surface,
                            icon: Icon(
                              isRolePending
                                  ? Icons.sync_rounded
                                  : Icons.arrow_drop_down,
                              color: roleColor,
                              size: 18,
                            ),
                            isDense: true,
                            items: _rolesForCurrentActor(role).map((r) {
                              return DropdownMenuItem<String>(
                                value: r,
                                child: Text(
                                  _roleLabels[r] ?? r,
                                  style: TextStyle(
                                    color:
                                        _roleColors[r] ??
                                        Theme.of(
                                          context,
                                        ).colorScheme.onSurface,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      );

                      final profileId = p['id']?.toString();
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(AppRadius.card),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            // Открыть карточку пользователя (профиль/админ).
                            onTap:
                                (profileId == null || profileId.isEmpty)
                                ? null
                                : () =>
                                      context.push('/admin/profiles/$profileId'),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              // Narrow (phone) screens stack the role dropdown
                              // below the identity so a wide role label can't
                              // squeeze the name to a single vertical character
                              // per line.
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  if (constraints.maxWidth < 480) {
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            avatar,
                                            const SizedBox(width: 12),
                                            Expanded(child: identity),
                                            linkButton,
                                            const Icon(
                                              Icons.chevron_right_rounded,
                                              color: AppColor.text2,
                                              size: 20,
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        badges,
                                        const SizedBox(height: 10),
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: roleDropdown,
                                        ),
                                      ],
                                    );
                                  }
                                  return Row(
                                    children: [
                                      avatar,
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            identity,
                                            const SizedBox(height: 4),
                                            badges,
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      linkButton,
                                      const SizedBox(width: 8),
                                      roleDropdown,
                                      const SizedBox(width: 4),
                                      const Icon(
                                        Icons.chevron_right_rounded,
                                        color: AppColor.text2,
                                        size: 20,
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
          ),
        ),
      ),
    );
  }

  List<String> _rolesForCurrentActor(String currentUserRole) {
    // A1: Управляющий и Администратор системы получают полный набор ролей и
    // могут сменить роль в любой момент. Администратор (`admin`) — НЕ может
    // менять роли (бизнес-иерархия: Управляющий > Администратор).
    if (widget.currentRole == 'manager' ||
        widget.currentRole == 'system_admin') {
      return _availableRoles;
    }
    return [currentUserRole];
  }

  void _confirmRoleChange(
    String profileId,
    String name,
    String oldRole,
    String newRole,
  ) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        title: Text(
          'Изменить роль',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
        content: Text(
          'Вы уверены, что хотите изменить роль пользователя «$name» с «${_roleLabels[oldRole]}» на «${_roleLabels[newRole]}»?',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Отмена'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColor.gold,
              foregroundColor: AppColor.onGold,
            ),
            onPressed: () {
              Navigator.pop(context);
              _updateRole(profileId, newRole);
            },
            child: Text('Изменить'),
          ),
        ],
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? accent;

  const _MiniBadge({required this.icon, required this.text, this.accent});

  @override
  Widget build(BuildContext context) {
    final color = accent ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(24),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkSection extends StatelessWidget {
  final String title;
  final String emptyText;
  final List<Map<String, dynamic>> items;
  final ValueChanged<String> onTap;

  const _LinkSection({
    required this.title,
    required this.emptyText,
    required this.items,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        if (items.isEmpty)
          Text(
            emptyText,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
          )
        else
          ...items.map((item) {
            final first = item['first_name']?.toString() ?? '';
            final last = item['last_name']?.toString() ?? '';
            final name = '$last $first'.trim();
            final phone = item['phone']?.toString() ?? '';
            final status = item['status']?.toString() ?? '';
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                name.isEmpty ? 'Без имени' : name,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              subtitle: Text(
                [phone, status].where((v) => v.isNotEmpty).join(' · '),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              trailing: IconButton(
                tooltip: 'Связать',
                icon: const Icon(Icons.link, color: AppColor.gold),
                onPressed: () => onTap(item['id'].toString()),
              ),
            );
          }),
      ],
    );
  }
}
