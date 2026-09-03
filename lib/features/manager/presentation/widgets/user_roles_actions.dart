part of 'user_roles_widget.dart';

extension _UserRolesActions on _UserRolesWidgetState {
  void _applyInitialSearch(String? value) {
    final query = value?.trim();
    if (query == null || query.isEmpty || query == _searchQuery) return;
    _searchQuery = query;
    _searchController.text = query;
  }

  Future<void> _loadProfiles({bool preserveContent = false}) async {
    final sequence = ++_profileLoadSequence;
    _emitState(() {
      if (preserveContent && _profiles.isNotEmpty) {
        _isRefreshing = true;
      } else {
        _isLoading = true;
      }
    });
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
      if (mounted && sequence == _profileLoadSequence) {
        _emitState(() {
          _profiles = data;
        });
      }
    } catch (e) {
      if (mounted && sequence == _profileLoadSequence) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userErrorMessage(e, fallback: 'Не удалось загрузить профили.'),
            ),
            backgroundColor: AppColor.danger,
          ),
        );
      }
    } finally {
      if (mounted && sequence == _profileLoadSequence) {
        _emitState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    }
  }

  Future<void> _autoLinkProfile(Map<String, dynamic> profile) async {
    final profileId = profile['id']?.toString();
    if (profileId == null || profileId.isEmpty) return;
    _emitState(() => _linkingProfileId = profileId);
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
            content: Text(
              userErrorMessage(e, fallback: 'Не удалось изменить связь.'),
            ),
            backgroundColor: AppColor.danger,
          ),
        );
      }
    } finally {
      if (mounted) _emitState(() => _linkingProfileId = null);
    }
  }

  Future<void> _linkCrmEntity({
    required String profileId,
    required String entityType,
    required String entityId,
  }) async {
    _emitState(() => _linkingProfileId = profileId);
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
            content: Text(
              userErrorMessage(e, fallback: 'Не удалось изменить связь.'),
            ),
            backgroundColor: AppColor.danger,
          ),
        );
      }
    } finally {
      if (mounted) _emitState(() => _linkingProfileId = null);
    }
  }

  void _applyLinkSummary(String profileId, Map<String, dynamic> summary) {
    _emitState(() {
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
    _emitState(() => _linkingProfileId = profileId);
    Map<String, dynamic> candidates;
    try {
      candidates = await ref
          .read(magicProfileAdminServiceProvider)
          .listLinkCandidates(profileId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userErrorMessage(e, fallback: 'Не удалось загрузить связи.'),
            ),
            backgroundColor: AppColor.danger,
          ),
        );
      }
      return;
    } finally {
      if (mounted) _emitState(() => _linkingProfileId = null);
    }
    if (!mounted) return;

    final students = (candidates['students'] as List?) ?? const [];
    final leads = (candidates['leads'] as List?) ?? const [];
    final teachers = (candidates['teachers'] as List?) ?? const [];
    final staff = (candidates['staff'] as List?) ?? const [];
    showMagicDialog(
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
}
