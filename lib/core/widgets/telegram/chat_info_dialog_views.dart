part of 'chat_info_dialog.dart';

/// Presentation builders for [ChatInfoDialog] — tab bar, media/files/links
/// grids, action buttons, members preview, notes list. Split out to keep the
/// dialog State focused on data loading + the build scaffold.
extension _ChatInfoViews on _ChatInfoDialogState {
  Widget _buildTabBar(bool isDark) {
    return Container(
      color: isDark ? TelegramColors.darkSurface : TelegramColors.lightBg,
      child: TabBar(
        controller: _tabController,
        indicatorColor: TelegramColors.accent,
        labelColor: TelegramColors.accent,
        unselectedLabelColor: isDark
            ? TelegramColors.darkTextSecondary
            : TelegramColors.lightTextSecondary,
        tabs: [
          const Tab(text: 'Медиа'),
          const Tab(text: 'Файлы'),
          const Tab(text: 'Ссылки'),
          if (_hasNotesTab) const Tab(text: 'Заметки'),
        ],
      ),
    );
  }

  Widget _buildMediaGrid() {
    if (_mediaMessages.isEmpty) {
      return const Center(
        child: Text('Нет медиа', style: TextStyle(color: Colors.grey)),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: _mediaMessages.length,
      itemBuilder: (context, index) {
        final m = _mediaMessages[index];
        final url =
            m['attachment_url']?.toString() ??
            m['attachment_file_id']?.toString();
        if (url == null) return Container(color: Colors.grey.shade800);
        return GestureDetector(
          onTap: () {
            showDialog(
              context: context,
              builder: (c) => Dialog(
                backgroundColor: Colors.transparent,
                insetPadding: EdgeInsets.zero,
                child: InteractiveViewer(
                  child: _ResolvedNetworkImage(url: url, fit: BoxFit.contain),
                ),
              ),
            );
          },
          child: _ResolvedNetworkImage(url: url, fit: BoxFit.cover),
        );
      },
    );
  }

  Widget _buildFilesList(bool isDark) {
    if (_fileMessages.isEmpty) {
      return const Center(
        child: Text('Нет файлов', style: TextStyle(color: Colors.grey)),
      );
    }
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: _fileMessages.length,
      separatorBuilder: (c, i) =>
          Divider(height: 1, color: isDark ? Colors.white10 : Colors.black12),
      itemBuilder: (context, index) {
        final m = _fileMessages[index];
        final name = m['attachment_name']?.toString() ?? 'Файл';
        final size = ChatAttachmentService.formatFileSize(
          m['attachment_size'] as int?,
        );
        return ListTile(
          leading: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: TelegramColors.accent.withValues(alpha: 40 / 255),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.insert_drive_file, color: TelegramColors.accent),
          ),
          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(size),
          onTap: () async {
            final url =
                m['attachment_url']?.toString() ??
                m['attachment_file_id']?.toString();
            final resolved = await ref
                .read(chatAttachmentServiceProvider)
                .resolveUrl(url);
            if (resolved != null) launchUrl(Uri.parse(resolved));
          },
        );
      },
    );
  }

  Widget _buildLinksList(bool isDark) {
    if (_linkMessages.isEmpty) {
      return const Center(
        child: Text('Нет ссылок', style: TextStyle(color: Colors.grey)),
      );
    }
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: _linkMessages.length,
      separatorBuilder: (c, i) =>
          Divider(height: 1, color: isDark ? Colors.white10 : Colors.black12),
      itemBuilder: (context, index) {
        final linkData = _linkMessages[index];
        final link = linkData['link'] as String;
        return ListTile(
          leading: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: TelegramColors.accent.withValues(alpha: 40 / 255),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.link, color: TelegramColors.accent),
          ),
          title: Text(
            link,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: TelegramColors.accent),
          ),
          onTap: () => launchUrl(Uri.parse(link)),
        );
      },
    );
  }

  Widget _buildActionButton(
    IconData icon,
    String label,
    bool isDark, {
    VoidCallback? onTap,
    Color? color,
  }) {
    final iconColor = color ?? (isDark ? Colors.white : Colors.black);
    final labelColor =
        color ??
        (isDark
            ? TelegramColors.darkTextSecondary
            : TelegramColors.lightTextSecondary);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: isDark
                    ? TelegramColors.darkSurface
                    : TelegramColors.lightSurface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: iconColor),
            ),
            const SizedBox(height: 8),
            Text(label, style: TextStyle(fontSize: 12, color: labelColor)),
          ],
        ),
      ),
    );
  }

  String _roleLabel(String role) {
    return switch (role) {
      'system_admin' => 'Администратор системы',
      'admin' => 'Администратор',
      'manager' => 'Управляющий',
      'director' => 'Директор',
      'teacher' => 'Преподаватель',
      _ => 'Клиент',
    };
  }

  Widget _buildMembersPreview(bool isDark) {
    final previewMembers = _members.take(6).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Участники',
              style: TextStyle(
                fontSize: 13,
                color: isDark
                    ? TelegramColors.darkTextSecondary
                    : TelegramColors.lightTextSecondary,
              ),
            ),
            if (_canManageGroup)
              GestureDetector(
                onTap: _addMembers,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.person_add_rounded,
                      size: 16,
                      color: TelegramColors.accent,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Добавить',
                      style: TextStyle(
                        fontSize: 13,
                        color: TelegramColors.accent,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        ...previewMembers.map((member) {
          final name = member['_display_name']?.toString() ?? 'Участник';
          final role = member['role']?.toString() == 'admin'
              ? 'Администратор группы'
              : _roleLabel(member['user_role']?.toString() ?? 'client');
          final memberUserId = member['user_id']?.toString();
          // Admins and up can tap a member to open a 1:1 chat with them —
          // teachers and clients just see the roster. (Owner rule: «переход с
          // участника на профиль/чат только для админов и всех кто старше».)
          final canOpen =
              _isManagerOrAdminRole &&
              memberUserId != null &&
              memberUserId.isNotEmpty;
          final canRemove =
              _canManageGroup && member['is_current_user'] != true;
          final row = Row(
            children: [
              TelegramAvatar(
                name: name,
                avatarUrl: null,
                uniqueId: memberUserId ?? name,
                radius: 16,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      role,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? TelegramColors.darkTextSecondary
                            : TelegramColors.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (canOpen)
                IconButton(
                  tooltip: 'Открыть чат',
                  onPressed: () => _startChatWithMember(memberUserId),
                  icon: Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 18,
                    color: TelegramColors.accent,
                  ),
                ),
              if (canRemove)
                IconButton(
                  tooltip: 'Удалить из группы',
                  onPressed: () => _removeMember(member),
                  icon: const Icon(
                    Icons.person_remove_outlined,
                    size: 18,
                    color: Colors.redAccent,
                  ),
                ),
            ],
          );
          return Padding(padding: const EdgeInsets.only(bottom: 8), child: row);
        }),
        if (_members.length > previewMembers.length)
          TextButton(
            onPressed: _showAllMembers,
            child: Text('Показать всех (${_members.length})'),
          ),
      ],
    );
  }

  Widget _buildNotesList(bool isDark) {
    if (_notes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Заметок пока нет',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: _addNote,
              icon: const Icon(Icons.add_comment_outlined),
              label: const Text('Добавить первую'),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.small(
        onPressed: _addNote,
        tooltip: 'Добавить заметку',
        backgroundColor: TelegramColors.accent,
        child: const Icon(Icons.add_comment_rounded, color: Colors.white),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _notes.length,
        itemBuilder: (context, index) {
          final note = _notes[index];
          final author = note['author'];
          final authorName = author != null
              ? '${author['first_name'] ?? ''} ${author['last_name'] ?? ''}'
                    .trim()
              : 'Админ';
          // Fix for potential string/datetime issues
          final createdAt = note['created_at'];
          final time = createdAt != null
              ? (createdAt is String
                    ? DateFormat(
                        'dd.MM.yy HH:mm',
                        'ru',
                      ).format(DateTime.parse(createdAt))
                    : DateFormat('dd.MM.yy HH:mm', 'ru').format(createdAt))
              : 'Без даты';

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.black.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      authorName,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: TelegramColors.accent,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      time,
                      style: const TextStyle(color: Colors.grey, fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  note['content'] ?? '',
                  style: const TextStyle(fontSize: 14),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
