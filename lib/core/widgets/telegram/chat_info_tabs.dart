import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/services/chat_attachment_service.dart';
import 'package:magic_music_crm/core/theme/telegram_colors.dart';
import 'package:magic_music_crm/core/widgets/telegram/chat_info_member_dialogs.dart';
import 'package:magic_music_crm/core/widgets/telegram/chat_info_models.dart';
import 'package:url_launcher/url_launcher.dart';

class ChatInfoTabBar extends StatelessWidget {
  const ChatInfoTabBar({
    super.key,
    required this.tabController,
    required this.isDark,
    required this.hasNotes,
  });

  final TabController tabController;
  final bool isDark;
  final bool hasNotes;

  @override
  Widget build(BuildContext context) => Container(
    color: isDark ? TelegramColors.darkSurface : TelegramColors.lightBg,
    child: TabBar(
      controller: tabController,
      indicatorColor: TelegramColors.accent,
      labelColor: TelegramColors.accent,
      unselectedLabelColor: isDark
          ? TelegramColors.darkTextSecondary
          : TelegramColors.lightTextSecondary,
      tabs: [
        const Tab(text: 'Медиа'),
        const Tab(text: 'Файлы'),
        const Tab(text: 'Ссылки'),
        if (hasNotes) const Tab(text: 'Заметки'),
      ],
    ),
  );
}

class ChatInfoTabBody extends StatelessWidget {
  const ChatInfoTabBody({
    super.key,
    required this.model,
    required this.tabController,
    required this.actions,
  });

  final ChatInfoViewModel model;
  final TabController tabController;
  final ChatInfoActions actions;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TabBarView(
      controller: tabController,
      children: [
        ChatInfoMediaGrid(messages: model.snapshot.history.media),
        ChatInfoFilesList(
          messages: model.snapshot.history.files,
          isDark: isDark,
        ),
        ChatInfoLinksList(links: model.snapshot.history.links, isDark: isDark),
        if (model.access.hasNotes)
          ChatInfoNotesList(
            notes: model.snapshot.notes,
            isDark: isDark,
            onAdd: actions.addNote,
          ),
      ],
    );
  }
}

class ChatInfoMediaGrid extends StatelessWidget {
  const ChatInfoMediaGrid({super.key, required this.messages});

  final List<Map<String, dynamic>> messages;

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) {
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
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        final url =
            message['attachment_url']?.toString() ??
            message['attachment_file_id']?.toString();
        if (url == null) return Container(color: Colors.grey.shade800);
        return GestureDetector(
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) => Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: EdgeInsets.zero,
              child: InteractiveViewer(
                child: ResolvedChatAttachmentImage(
                  url: url,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          child: ResolvedChatAttachmentImage(url: url, fit: BoxFit.cover),
        );
      },
    );
  }
}

class ChatInfoFilesList extends ConsumerWidget {
  const ChatInfoFilesList({
    super.key,
    required this.messages,
    required this.isDark,
  });

  final List<Map<String, dynamic>> messages;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (messages.isEmpty) {
      return const Center(
        child: Text('Нет файлов', style: TextStyle(color: Colors.grey)),
      );
    }
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: messages.length,
      separatorBuilder: (_, _) =>
          Divider(height: 1, color: isDark ? Colors.white10 : Colors.black12),
      itemBuilder: (context, index) {
        final message = messages[index];
        final name = message['attachment_name']?.toString() ?? 'Файл';
        return ListTile(
          leading: _AccentIcon(icon: Icons.insert_drive_file),
          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            ChatAttachmentService.formatFileSize(
              message['attachment_size'] as int?,
            ),
          ),
          onTap: () async {
            final url =
                message['attachment_url']?.toString() ??
                message['attachment_file_id']?.toString();
            final resolved = await ref
                .read(chatAttachmentServiceProvider)
                .resolveUrl(url);
            if (resolved != null) await launchUrl(Uri.parse(resolved));
          },
        );
      },
    );
  }
}

class ChatInfoLinksList extends StatelessWidget {
  const ChatInfoLinksList({
    super.key,
    required this.links,
    required this.isDark,
  });

  final List<Map<String, dynamic>> links;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    if (links.isEmpty) {
      return const Center(
        child: Text('Нет ссылок', style: TextStyle(color: Colors.grey)),
      );
    }
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: links.length,
      separatorBuilder: (_, _) =>
          Divider(height: 1, color: isDark ? Colors.white10 : Colors.black12),
      itemBuilder: (context, index) {
        final link = links[index]['link'] as String;
        return ListTile(
          leading: _AccentIcon(icon: Icons.link, circular: true),
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
}

class ChatInfoNotesList extends StatelessWidget {
  const ChatInfoNotesList({
    super.key,
    required this.notes,
    required this.isDark,
    required this.onAdd,
  });

  final List<Map<String, dynamic>> notes;
  final bool isDark;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    if (notes.isEmpty) {
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
              onPressed: onAdd,
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
        onPressed: onAdd,
        tooltip: 'Добавить заметку',
        backgroundColor: TelegramColors.accent,
        child: const Icon(Icons.add_comment_rounded, color: Colors.white),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: notes.length,
        itemBuilder: (_, index) =>
            _NoteCard(note: notes[index], isDark: isDark),
      ),
    );
  }
}

class ChatInfoTabHeaderDelegate extends SliverPersistentHeaderDelegate {
  ChatInfoTabHeaderDelegate(this.tabBar);

  final Widget tabBar;

  @override
  double get minExtent => 48;
  @override
  double get maxExtent => 48;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => tabBar;
  @override
  bool shouldRebuild(ChatInfoTabHeaderDelegate oldDelegate) => false;
}

class ChatInfoActionButton extends StatelessWidget {
  const ChatInfoActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.isDark,
    this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final bool isDark;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
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
}

class _AccentIcon extends StatelessWidget {
  const _AccentIcon({required this.icon, this.circular = false});

  final IconData icon;
  final bool circular;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: TelegramColors.accent.withValues(alpha: 40 / 255),
      shape: circular ? BoxShape.circle : BoxShape.rectangle,
      borderRadius: circular ? null : BorderRadius.circular(8),
    ),
    child: Icon(icon, color: TelegramColors.accent),
  );
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note, required this.isDark});

  final Map<String, dynamic> note;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final author = note['author'];
    final authorName = author != null
        ? '${author['first_name'] ?? ''} ${author['last_name'] ?? ''}'.trim()
        : 'Админ';
    final createdAt = note['created_at'];
    final time = createdAt == null
        ? 'Без даты'
        : DateFormat(
            'dd.MM.yy HH:mm',
            'ru',
          ).format(createdAt is String ? DateTime.parse(createdAt) : createdAt);
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
          Text(note['content'] ?? '', style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }
}
