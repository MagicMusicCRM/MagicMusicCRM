import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/theme/telegram_colors.dart';
import 'package:magic_music_crm/core/widgets/voice_player_widget.dart';
import 'package:magic_music_crm/core/widgets/file_attachment_widget.dart';
import 'package:magic_music_crm/core/widgets/telegram/avatar_widget.dart';

/// Telegram-style message bubble.
class MessageBubble extends StatelessWidget {
  final Map<String, dynamic> message;
  final bool isMe;
  final String? senderName;
  final String? senderRole;
  final String? senderAvatarUrl;
  final bool showSenderName;
  final bool isGroupChat;
  final Map<String, dynamic>? repliedMessage;
  final VoidCallback? onReply;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onForward;
  final VoidCallback? onPin;
  final bool isHighlighted;
  final bool canDeleteOthers;
  final Function(String)? onReact;
  final List<dynamic>? reactions;
  final VoidCallback? onJumpToReplied;
  final String? forwardedFromName;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.senderName,
    this.senderRole,
    this.senderAvatarUrl,
    this.showSenderName = false,
    this.isGroupChat = false,
    this.repliedMessage,
    this.onReply,
    this.onEdit,
    this.onDelete,
    this.onForward,
    this.onPin,
    this.isHighlighted = false,
    this.canDeleteOthers = false,
    this.onReact,
    this.reactions,
    this.onJumpToReplied,
    this.forwardedFromName,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDeleted = message['deleted_at'] != null;
    final isPending = message['_pending'] == true;
    final maxBubbleWidth = MediaQuery.of(context).size.width * 0.75;
    final senderLabelMaxWidth = (maxBubbleWidth - 48).clamp(120.0, 360.0);

    final messageType = message['message_type']?.toString() ?? 'text';
    final attachmentUrl =
        message['attachment_url']?.toString() ??
        message['attachment_file_id']?.toString();
    final attachmentName = message['attachment_name']?.toString();
    final attachmentMimeType = message['attachment_mime_type']?.toString();
    final hasAttachment =
        attachmentUrl != null && attachmentUrl.isNotEmpty && !isDeleted;
    final isAttachmentType =
        (messageType == 'file' ||
            messageType == 'image' ||
            messageType == 'photo' ||
            messageType == 'voice') &&
        !isDeleted;

    final isImageFile =
        (messageType == 'file' ||
            messageType == 'image' ||
            messageType == 'photo') &&
        FileAttachmentWidget.isImage(
          attachmentName,
          mimeType: attachmentMimeType,
        );

    // Outgoing bubbles stay brand gold; incoming use the neutral surface.
    final outgoingColor = AppColor.gold;
    final incomingColor = isDark
        ? TelegramColors.darkIncomingBubble
        : TelegramColors.lightIncomingBubble;

    // Highlight color (brand gold with low alpha)
    final highlightColor = AppColor.gold.withAlpha(isDark ? 80 : 100);

    // Outgoing bubbles are always brand gold, so text/time/ticks use the dark
    // on-gold token for WCAG-AA contrast (KVA-228) instead of low-contrast white.
    final outgoingTextColor = AppColor.onGold;
    final incomingTextColor = isDark
        ? Colors.white
        : TelegramColors.lightTextPrimary;

    Color? senderColor;
    if (showSenderName && senderName != null && !isMe) {
      final gradientColors = TelegramColors.avatarGradientFor(
        message['sender_id']?.toString() ?? senderName!,
      );
      senderColor = gradientColors.first;
    }

    return Padding(
      padding: EdgeInsets.only(
        left: isMe ? 60 : 10,
        right: isMe ? 10 : 60,
        top: 1,
        bottom: 1,
      ),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: GestureDetector(
          onLongPress: isDeleted ? null : () => _showContextMenu(context),
          onSecondaryTap: isDeleted ? null : () => _showContextMenu(context),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOut,
            constraints: BoxConstraints(maxWidth: maxBubbleWidth),
            padding: isImageFile
                ? const EdgeInsets.all(3)
                : const EdgeInsets.fromLTRB(10, 6, 10, 4),
            decoration: BoxDecoration(
              color: isHighlighted
                  ? highlightColor
                  : (isMe ? outgoingColor : incomingColor),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(AppRadius.card),
                topRight: const Radius.circular(AppRadius.card),
                bottomLeft: Radius.circular(isMe ? AppRadius.card : 4),
                bottomRight: Radius.circular(isMe ? 4 : AppRadius.card),
              ),
              // Flat Magic: highlight via a flat gold border, not a glow shadow.
              border: isHighlighted
                  ? Border.all(color: AppColor.gold, width: 1.5)
                  : null,
            ),
            child: IntrinsicWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Sender identity
                  if (showSenderName && senderName != null && !isMe)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TelegramAvatar(
                            name: senderName,
                            avatarUrl: senderAvatarUrl,
                            uniqueId:
                                message['sender_id']?.toString() ?? senderName!,
                            radius: 11,
                          ),
                          const SizedBox(width: 6),
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: senderLabelMaxWidth,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  senderName!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: senderColor ?? AppColor.gold,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (_roleLabel(senderRole) != null)
                                  Text(
                                    _roleLabel(senderRole)!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color:
                                          (isMe
                                                  ? outgoingTextColor
                                                  : incomingTextColor)
                                              .withAlpha(150),
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Forwarded from
                  if (forwardedFromName != null && !isDeleted)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4, left: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.forward_rounded,
                            size: 14,
                            color:
                                (isMe ? outgoingTextColor : incomingTextColor)
                                    .withAlpha(180),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Переслано от: $forwardedFromName',
                            style: TextStyle(
                              color:
                                  (isMe ? outgoingTextColor : incomingTextColor)
                                      .withAlpha(180),
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Reply Quote
                  if (repliedMessage != null && !isDeleted)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: GestureDetector(
                        onTap: onJumpToReplied,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withAlpha(isDark ? 30 : 10),
                            border: Border(
                              left: BorderSide(
                                color: isMe ? AppColor.onGold : AppColor.gold,
                                width: 2,
                              ),
                            ),
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Ответ',
                                style: TextStyle(
                                  color: isMe ? AppColor.onGold : AppColor.gold,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                repliedMessage!['content']?.toString() ??
                                    'Медиа',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: isMe
                                      ? outgoingTextColor.withAlpha(200)
                                      : incomingTextColor.withAlpha(200),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // Content
                  if (isDeleted)
                    Text(
                      'Сообщение удалено',
                      style: TextStyle(
                        color: (isMe ? outgoingTextColor : incomingTextColor)
                            .withAlpha(150),
                        fontSize: 15,
                        fontStyle: FontStyle.italic,
                      ),
                    )
                  else if (isAttachmentType || hasAttachment) ...[
                    if (messageType == 'voice')
                      SizedBox(
                        width: 220,
                        child: VoicePlayerWidget(
                          audioUrl: attachmentUrl ?? '',
                          durationMs: message['voice_duration_ms'] as int?,
                          isMe: isMe,
                        ),
                      )
                    else
                      FileAttachmentWidget(
                        fileName: attachmentName,
                        fileUrl: attachmentUrl,
                        fileSize: message['attachment_size'] as int?,
                        mimeType: attachmentMimeType,
                        isMe: isMe,
                      ),

                    if (message['content'] != null &&
                        message['content'].toString().isNotEmpty &&
                        !message['content'].toString().startsWith('📎'))
                      Padding(
                        padding: const EdgeInsets.only(
                          top: 4,
                          left: 2,
                          right: 2,
                        ),
                        child: Text(
                          message['content'].toString(),
                          style: TextStyle(
                            color: isMe ? outgoingTextColor : incomingTextColor,
                            fontSize: 15,
                            height: 1.35,
                          ),
                        ),
                      ),
                  ] else
                    Text(
                      message['content'] ?? '',
                      style: TextStyle(
                        color: isMe ? outgoingTextColor : incomingTextColor,
                        fontSize: 15,
                        height: 1.35,
                      ),
                    ),

                  // Reactions
                  if (reactions != null && reactions!.isNotEmpty && !isDeleted)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: _buildReactionWidgets(context, isDark),
                      ),
                    ),

                  // Time and Edited indicator
                  if (!isDeleted)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (message['is_edited'] == true)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Text(
                                'изменено',
                                style: TextStyle(
                                  fontSize: 10,
                                  color:
                                      (isMe
                                              ? outgoingTextColor
                                              : incomingTextColor)
                                          .withAlpha(150),
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          Text(
                            isPending
                                ? 'отправка'
                                : DateFormat('HH:mm').format(
                                    DateTime.tryParse(
                                          message['created_at'] ?? '',
                                        )?.toLocal() ??
                                        DateTime.now(),
                                  ),
                            style: TextStyle(
                              fontSize: 10.5,
                              color:
                                  (isMe ? outgoingTextColor : incomingTextColor)
                                      .withAlpha(150),
                            ),
                          ),
                          if (isMe && !isPending) ...[
                            const SizedBox(width: 4),
                            Icon(
                              message['is_read'] == true
                                  ? Icons.done_all_rounded
                                  : Icons.done_rounded,
                              size: 14,
                              color:
                                  (isMe ? outgoingTextColor : incomingTextColor)
                                      .withAlpha(150),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildReactionWidgets(BuildContext context, bool isDark) {
    if (reactions == null) return [];
    // Aggregated shape [{emoji, count, reactedByMe}] from the backend; tolerate
    // a legacy per-user [{emoji, user_id}] list by counting occurrences.
    final Map<String, int> counts = {};
    final Map<String, bool> mine = {};
    final List<String> order = [];
    for (final r in reactions!) {
      if (r is! Map) continue;
      final emoji = r['emoji']?.toString();
      if (emoji == null) continue;
      if (!counts.containsKey(emoji)) {
        counts[emoji] = 0;
        order.add(emoji);
      }
      counts[emoji] = counts[emoji]! + ((r['count'] as num?)?.toInt() ?? 1);
      if (r['reactedByMe'] == true) mine[emoji] = true;
    }

    final accent = Theme.of(context).colorScheme.primary;
    return order.map((emoji) {
      final isMine = mine[emoji] == true;
      return GestureDetector(
        onTap: () => onReact?.call(emoji),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: isMine
                ? accent.withAlpha(38)
                : (isDark
                    ? Colors.white.withAlpha(20)
                    : Colors.black.withAlpha(10)),
            borderRadius: BorderRadius.circular(AppRadius.chip),
            border: Border.all(
              color: isMine
                  ? accent.withAlpha(160)
                  : (isDark
                      ? Colors.white.withAlpha(20)
                      : Colors.black.withAlpha(20)),
              width: isMine ? 1 : 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 12)),
              const SizedBox(width: 4),
              Text(
                (counts[emoji] ?? 0).toString(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isMine
                      ? accent
                      : (isDark ? Colors.white70 : Colors.black87),
                ),
              ),
            ],
          ),
        ),
      );
    }).toList();
  }

  String? _roleLabel(String? role) {
    return switch (role) {
      'client' => 'Клиент',
      'teacher' => 'Преподаватель',
      'admin' => 'Администратор',
      'manager' => 'Управляющий',
      'director' => 'Директор',
      'system_admin' => 'Администратор системы',
      _ => null,
    };
  }

  void _showContextMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppRadius.sheet),
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Emoji Picker Row
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: ['👍', '❤️', '🔥', '😂', '😮', '😢', '🙏', '💯']
                        .map((emoji) {
                          return IconButton(
                            tooltip: 'Реакция $emoji',
                            icon: Text(
                              emoji,
                              style: const TextStyle(fontSize: 24),
                            ),
                            onPressed: () {
                              Navigator.pop(context);
                              onReact?.call(emoji);
                            },
                          );
                        })
                        .toList(),
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: const Text('Копировать'),
                onTap: () {
                  Navigator.pop(context);
                  Clipboard.setData(
                    ClipboardData(text: message['content'] ?? ''),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Скопировано в буфер обмена'),
                      duration: Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
              if (onReply != null)
                ListTile(
                  leading: const Icon(Icons.reply_rounded),
                  title: const Text('Ответить'),
                  onTap: () {
                    Navigator.pop(context);
                    onReply!();
                  },
                ),
              if (isMe && onEdit != null && message['message_type'] == 'text')
                ListTile(
                  leading: const Icon(Icons.edit_rounded),
                  title: const Text('Изменить'),
                  onTap: () {
                    Navigator.pop(context);
                    onEdit!();
                  },
                ),
              if (onPin != null)
                ListTile(
                  leading: Icon(
                    message['pinned_at'] != null
                        ? Icons.push_pin_outlined
                        : Icons.push_pin_rounded,
                  ),
                  title: Text(
                    message['pinned_at'] != null ? 'Открепить' : 'Закрепить',
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    onPin!();
                  },
                ),
              if (onForward != null)
                ListTile(
                  leading: const Icon(Icons.forward_rounded),
                  title: const Text('Переслать'),
                  onTap: () {
                    Navigator.pop(context);
                    onForward!();
                  },
                ),
              if (onDelete != null && (isMe || canDeleteOthers))
                ListTile(
                  leading: const Icon(
                    Icons.delete_outline_rounded,
                    color: AppColor.danger,
                  ),
                  title: const Text(
                    'Удалить',
                    style: TextStyle(color: AppColor.danger),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    onDelete!();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
