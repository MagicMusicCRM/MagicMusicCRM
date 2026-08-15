import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/services/crm_realtime_provider.dart';
import 'package:magic_music_crm/core/services/magic_profile_admin_service.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/skeletons.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/access_editor_sheet.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/notification_preferences_dialog.dart';

part 'user_roles_actions.dart';
part 'user_roles_widgets.dart';

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
  bool _isRefreshing = false;
  int _profileLoadSequence = 0;
  String _searchQuery = '';
  String _selectedRole = 'all';
  String? _linkingProfileId;
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  Timer? _realtimeDebounce;

  static const _roleFilterValues = [
    'all',
    'client',
    'teacher',
    'manager',
    'admin',
    'director',
    'system_admin',
  ];

  static const _roleLabels = {
    'all': 'Все',
    'client': 'Клиент',
    'teacher': 'Преподаватель',
    'manager': 'Управляющий',
    'admin': 'Администратор',
    'director': 'Директор',
    'system_admin': 'Администратор системы',
  };

  static const _roleColors = {
    'client': Color(0xFF10B981),
    'teacher': Color(0xFF3B82F6),
    'manager': Color(0xFF8B5CF6),
    'admin': Color(0xFFF59E0B),
    'director': Color(0xFFEF4444),
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

  void _emitState(void Function() fn) {
    if (mounted) setState(fn);
  }

  @override
  Widget build(BuildContext context) {
    // Realtime: refresh the user/roles list when another staff member changes a
    // user (role/profile). Skip while loading or while a role update is in
    // flight — those refetch/patch themselves on completion.
    ref.listen(crmRealtimeProvider, (prev, next) {
      final event = next.value;
      if (event == null || event.entity != 'user' || !mounted) return;
      if (_isLoading) return;
      _realtimeDebounce?.cancel();
      _realtimeDebounce = Timer(const Duration(milliseconds: 350), () {
        if (!mounted || _isLoading) return;
        _loadProfiles();
      });
    });
    final filtered = _filteredProfiles;
    final canManageAccess =
        widget.currentRole == 'director' ||
        widget.currentRole == 'system_admin';
    final roleFilters = widget.currentRole == 'system_admin'
        ? _roleFilterValues
        : _roleFilterValues.where((role) => role != 'system_admin').toList();
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
                          _emitState(() => _searchQuery = v);
                          _searchDebounce?.cancel();
                          _searchDebounce = Timer(
                            const Duration(milliseconds: 350),
                            () => _loadProfiles(preserveContent: true),
                          );
                        },
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Поиск по имени, почте, телефону...',
                          hintStyle: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                          prefixIcon: Icon(
                            Icons.search,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                          filled: true,
                          fillColor: Theme.of(context).colorScheme.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              AppRadius.control,
                            ),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 10),
                    // Notification routing is per-role, so it belongs with the
                    // roles rather than behind a settings screen the app does not
                    // have.
                    IconButton(
                      icon: Icon(
                        Icons.notifications_active_outlined,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      tooltip: 'Настройки уведомлений',
                      onPressed: () =>
                          NotificationPreferencesDialog.show(context),
                    ),
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
                    final role = roleFilters[index];
                    final selected = _selectedRole == role;
                    final color =
                        _roleColors[role] ??
                        Theme.of(context).colorScheme.primary;
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
                        _emitState(() => _selectedRole = role);
                        _loadProfiles(preserveContent: true);
                      },
                    );
                  },
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 8),
                  itemCount: roleFilters.length,
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
                          'Показаны первые 100. Уточните поиск для остальных.',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              SizedBox(
                height: 2,
                child: _isRefreshing
                    ? const LinearProgressIndicator(minHeight: 2)
                    : null,
              ),
              Expanded(
                child: _isLoading
                    ? const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: ListSkeleton(count: 7),
                      )
                    : filtered.isEmpty
                    ? Center(
                        child: Text(
                          'Пользователи не найдены',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
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
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
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
                                text:
                                    '${_intValue(p['linked_students'])} учен.',
                              ),
                              _MiniBadge(
                                icon: Icons.assignment_ind_outlined,
                                text: '${_intValue(p['linked_leads'])} лид.',
                              ),
                              _MiniBadge(
                                icon: Icons.person_pin_outlined,
                                text:
                                    '${_intValue(p['linked_teachers'])} преп.',
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
                          final accessUserId = p['user_id']?.toString();
                          final roleDropdown = Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 7,
                                ),
                                decoration: BoxDecoration(
                                  color: roleColor.withAlpha(30),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: roleColor.withAlpha(80),
                                  ),
                                ),
                                child: Text(
                                  _roleLabels[role] ?? role,
                                  style: TextStyle(
                                    color: roleColor,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (canManageAccess &&
                                  accessUserId != null &&
                                  accessUserId.isNotEmpty) ...[
                                const SizedBox(width: 4),
                                IconButton(
                                  key: Key('access-editor-$accessUserId'),
                                  tooltip: 'Настроить доступ',
                                  onPressed: () => AccessEditorSheet.show(
                                    context,
                                    actorRole: widget.currentRole,
                                    userId: accessUserId,
                                    userLabel: _fullName(p),
                                    onChanged: () =>
                                        _loadProfiles(preserveContent: true),
                                  ),
                                  icon: const Icon(Icons.admin_panel_settings),
                                  color: AppColor.gold,
                                ),
                              ],
                            ],
                          );

                          final profileId = p['id']?.toString();
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(
                                AppRadius.card,
                              ),
                              border: Border.all(
                                color: Theme.of(
                                  context,
                                ).colorScheme.outlineVariant,
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                // Открыть карточку пользователя (профиль/админ).
                                onTap: (profileId == null || profileId.isEmpty)
                                    ? null
                                    : () => context.push(
                                        '/admin/profiles/$profileId',
                                      ),
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
}
