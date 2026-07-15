part of 'chat_info_dialog.dart';

/// Reuses the same profile-list loading + multi-select pattern as
/// [CreateGroupChatDialog], but excludes already-present members.
class _AddMembersDialog extends ConsumerStatefulWidget {
  final Set<String> existingMemberUserIds;

  const _AddMembersDialog({required this.existingMemberUserIds});

  @override
  ConsumerState<_AddMembersDialog> createState() => _AddMembersDialogState();
}

class _AddMembersDialogState extends ConsumerState<_AddMembersDialog> {
  final _searchController = TextEditingController();

  List<Map<String, dynamic>> _allUsers = [];
  List<Map<String, dynamic>> _filteredUsers = [];
  final Set<String> _selectedUserIds = {};
  bool _loading = true;
  bool _loadError = false;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    try {
      final res = await ref
          .read(magicProfileAdminServiceProvider)
          .listProfiles(limit: 100);
      if (mounted) {
        setState(() {
          _allUsers = res
              .where(
                (user) =>
                    user['user_id'] != null &&
                    !widget.existingMemberUserIds
                        .contains(user['user_id']?.toString()),
              )
              .map(
                (user) => {
                  ...user,
                  'id': user['user_id'],
                },
              )
              .toList();
          _filteredUsers = _allUsers;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; _loadError = true; });
    }
  }

  void _filterUsers(String query) {
    final q = query.toLowerCase();
    setState(() {
      _filteredUsers = _allUsers.where((u) {
        final name = '${u['first_name'] ?? ''} ${u['last_name'] ?? ''}'
            .toLowerCase();
        final email = (u['email'] ?? '').toString().toLowerCase();
        return name.contains(q) || email.contains(q);
      }).toList();
    });
  }

  String _getRoleLabel(String? role) {
    return switch (role) {
      'system_admin' => 'Администратор системы',
      'admin' => 'Администратор',
      'manager' => 'Управляющий',
      'director' => 'Директор',
      'teacher' => 'Преподаватель',
      _ => 'Клиент',
    };
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      child: Container(
        width: 480,
        height: 520,
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Добавить участников',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Поиск пользователей...',
                      prefixIcon: const Icon(Icons.search_rounded),
                      filled: true,
                      fillColor: isDark
                          ? TelegramColors.darkInputBg
                          : TelegramColors.lightInputBg,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: _filterUsers,
                  ),
                ],
              ),
            ),
            // Selected chips
            if (_selectedUserIds.isNotEmpty)
              Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: _selectedUserIds.map((uid) {
                    final user = _allUsers.firstWhere(
                      (u) => u['id'] == uid,
                      orElse: () => const {},
                    );
                    final name =
                        '${user['first_name'] ?? ''} ${user['last_name'] ?? ''}'
                            .trim();
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Chip(
                        avatar: TelegramAvatar(
                          name: name,
                          uniqueId: uid,
                          radius: 12,
                        ),
                        label: Text(
                          name,
                          style: const TextStyle(fontSize: 12),
                        ),
                        deleteIcon: const Icon(Icons.close, size: 16),
                        onDeleted: () =>
                            setState(() => _selectedUserIds.remove(uid)),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    );
                  }).toList(),
                ),
              ),
            const Divider(height: 1),
            // User list
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _loadError
                      ? const Center(
                          child: Text(
                            'Не удалось загрузить пользователей',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : _filteredUsers.isEmpty
                      ? Center(
                          child: Text(
                            'Нет пользователей для добавления',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _filteredUsers.length,
                          itemBuilder: (context, index) {
                            final user = _filteredUsers[index];
                            final uid = user['id']?.toString() ?? '';
                            final name =
                                '${user['first_name'] ?? ''} ${user['last_name'] ?? ''}'
                                    .trim();
                            final role = user['role']?.toString();
                            final isSelected = _selectedUserIds.contains(uid);

                            return ListTile(
                              leading: TelegramAvatar(
                                name: name,
                                uniqueId: uid,
                                radius: 20,
                              ),
                              title: Text(
                                name.isEmpty ? 'Без имени' : name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              subtitle: Text(
                                _getRoleLabel(role),
                                style: const TextStyle(fontSize: 12),
                              ),
                              trailing: isSelected
                                  ? const Icon(
                                      Icons.check_circle_rounded,
                                      color: TelegramColors.accent,
                                    )
                                  : Icon(
                                      Icons.circle_outlined,
                                      color: isDark
                                          ? TelegramColors.darkTextSecondary
                                          : TelegramColors.lightTextSecondary,
                                    ),
                              onTap: () {
                                setState(() {
                                  if (isSelected) {
                                    _selectedUserIds.remove(uid);
                                  } else {
                                    _selectedUserIds.add(uid);
                                  }
                                });
                              },
                            );
                          },
                        ),
            ),
            const Divider(height: 1),
            // Footer buttons
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Отмена'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _selectedUserIds.isEmpty
                        ? null
                        : () => Navigator.pop(context, _selectedUserIds),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: TelegramColors.accent,
                      foregroundColor: Colors.white,
                    ),
                    child: Text('Добавить (${_selectedUserIds.length})'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverAppBarDelegate(this._tabBar);

  final Widget _tabBar;

  @override
  double get minExtent => 48.0;
  @override
  double get maxExtent => 48.0;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return _tabBar;
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) {
    return false;
  }
}

class _ResolvedNetworkImage extends ConsumerStatefulWidget {
  final String url;
  final BoxFit fit;

  const _ResolvedNetworkImage({required this.url, required this.fit});

  @override
  ConsumerState<_ResolvedNetworkImage> createState() =>
      _ResolvedNetworkImageState();
}

class _ResolvedNetworkImageState extends ConsumerState<_ResolvedNetworkImage> {
  String? _resolvedUrl;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _resolveUrl();
  }

  @override
  void didUpdateWidget(covariant _ResolvedNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _resolveUrl();
    }
  }

  Future<void> _resolveUrl() async {
    setState(() {
      _isLoading = true;
      _resolvedUrl = null;
    });

    try {
      final resolved = await ref
          .read(chatAttachmentServiceProvider)
          .resolveUrl(widget.url);
      if (!mounted || widget.url.isEmpty) return;
      setState(() {
        _resolvedUrl = resolved;
        _isLoading = false;
      });
    } catch (error) {
      debugPrint('Media URL resolve error: $error');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_resolvedUrl == null) {
      return Container(
        color: Colors.grey.shade800,
        alignment: Alignment.center,
        child: const Icon(Icons.broken_image_rounded, color: Colors.white70),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final dpr = MediaQuery.of(context).devicePixelRatio;
        int? cacheDimension(double extent) {
          if (!extent.isFinite || extent <= 0) return null;
          return (extent * dpr).round();
        }

        return Image.network(
          _resolvedUrl!,
          fit: widget.fit,
          cacheWidth: cacheDimension(constraints.maxWidth),
          cacheHeight: cacheDimension(constraints.maxHeight),
        );
      },
    );
  }
}
