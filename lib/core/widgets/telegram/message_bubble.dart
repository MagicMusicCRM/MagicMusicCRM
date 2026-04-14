import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/theme/telegram_colors.dart';
import 'package:magic_music_crm/core/widgets/voice_player_widget.dart';
import 'package:magic_music_crm/core/widgets/file_attachment_widget.dart';

/// Telegram-style message bubble.
class MessageBubble extends StatelessWidget {
  final Map<String, dynamic> message;
  final bool isMe;
  final String? senderName;
  final bool showSenderName;
  final bool isGroupChat;
  final Map<String, dynamic>? repliedMessage;
  final VoidCallback? onReply;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onForward;
  final VoidCallback? onPin;
  final Function(String)? onReact;
  final List<dynamic>? reactions;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.senderName,
    this.showSenderName = false,
    this.isGroupChat = false,
    this.repliedMessage,
    this.onReply,
    this.onEdit,
    this.onDelete,
    this.onForward,
    this.onPin,
    this.onReact,
    this.reactions,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDeleted = message['deleted_at'] != null;
    
    final messageType = message['message_type']?.toString() ?? 'text';
    final attachmentUrl = message['attachment_url']?.toString();
    final hasAttachment = attachmentUrl != null && attachmentUrl.isNotEmpty && !isDeleted;
    final isAttachmentType = (messageType == 'file' || messageType == 'image' || messageType == 'photo' || messageType == 'voice') && !isDeleted;
    
    final isImageFile = (messageType == 'file' || messageType == 'image' || messageType == 'photo') &&
        FileAttachmentWidget.isImage(message['attachment_name']?.toString());

    final outgoingColor = isDark
        ? TelegramColors.darkOutgoingBubble
        : TelegramColors.lightOutgoingBubble;
    final incomingColor = isDark
        ? TelegramColors.darkIncomingBubble
        : TelegramColors.lightIncomingBubble;

    final outgoingTextColor = isDark ? Colors.white : TelegramColors.lightTextPrimary;
    final incomingTextColor = isDark ? Colors.white : TelegramColors.lightTextPrimary;

    Color? senderColor;
    if (showSenderName && senderName != null && !isMe) {
      final gradientColors = TelegramColors.avatarGradientFor(
          message['sender_id']?.toString() ?? senderName!);
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
            duration: const Duration(milliseconds: 200),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            padding: isImageFile
                ? const EdgeInsets.all(3)
                : const EdgeInsets.fromLTRB(10, 6, 10, 4),
            decoration: BoxDecoration(
              color: isMe ? outgoingColor : incomingColor,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isMe ? 16 : 4),
                bottomRight: Radius.circular(isMe ? 4 : 16),
              ),
            ),
            child: IntrinsicWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Sender name
                  if (showSenderName && senderName != null && !isMe)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        senderName!,
                        style: TextStyle(
                          color: senderColor ?? TelegramColors.accentBlue,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  
                  // Reply Quote
                  if (repliedMessage != null && !isDeleted)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(isDark ? 30 : 10),
                          border: Border(
                            left: BorderSide(
                              color: isMe ? TelegramColors.primaryGold : TelegramColors.accentBlue,
                              width: 2,
                            ),
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Ответ',
                              style: TextStyle(
                                color: isMe ? TelegramColors.primaryGold : TelegramColors.accentBlue,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              repliedMessage!['content']?.toString() ?? 'Медиа',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isMe ? outgoingTextColor.withAlpha(200) : incomingTextColor.withAlpha(200),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Content
                  if (isDeleted)
                    Text(
                      'Сообщение удалено',
                      style: TextStyle(
                        color: (isMe ? outgoingTextColor : incomingTextColor).withAlpha(150),
                        fontSize: 15,
                        fontStyle: FontStyle.italic,
                      ),
                    )
                  else if (isAttachmentType || hasAttachment) ...[
                    if (messageType == 'voice')
                      SizedBox(
                        width: 220,
                        child: VoicePlayerWidget(
                          audioUrl: message['attachment_url'] ?? '',
                          durationMs: message['voice_duration_ms'] as int?,
                          isMe: isMe,
                        ),
                      )
                    else
                      FileAttachmentWidget(
                        fileName: message['attachment_name']?.toString(),
                        fileUrl: message['attachment_url']?.toString(),
                        fileSize: message['attachment_size'] as int?,
                        isMe: isMe,
                      ),
                    
                    if (message['content'] != null && 
                        message['content'].toString().isNotEmpty && 
                        !message['content'].toString().startsWith('📎'))
                      Padding(
                        padding: const EdgeInsets.only(top: 4, left: 2, right: 2),
                        child: Text(
                          message['content'].toString(),
                          style: TextStyle(
                            color: isMe ? outgoingTextColor : incomingTextColor,
                            fontSize: 15,
                            height: 1.35,
                          ),
                        ),
                      ),
                  ]
                  else
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
    // Group reactions by emoji
    final Map<String, int> counts = {};
    for (final r in reactions!) {
      final emoji = r['emoji'] as String;
      counts[emoji] = (counts[emoji] ?? 0) + 1;
    }

    return counts.entries.map((entry) {
      return GestureDetector(
        onTap: () => onReact?.call(entry.key),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withAlpha(20) : Colors.black.withAlpha(10),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDark ? Colors.white.withAlpha(20) : Colors.black.withAlpha(20),
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(entry.key, style: const TextStyle(fontSize: 12)),
              const SizedBox(width: 4),
              Text(
                entry.value.toString(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            ],
          ),
        ),
      );
    }).toList();
  }

  void _showContextMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
                    children: ['👍', '❤️', '🔥', '😂', '😮', '😢', '🙏', '💯'].map((emoji) {
                      return IconButton(
                        icon: Text(emoji, style: const TextStyle(fontSize: 24)),
                        onPressed: () {
                          Navigator.pop(context);
                          onReact?.call(emoji);
                        },
                      );
                    }).toList(),
                  ),
                ),
              ),
              const Divider(height: 1),
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
                  leading: const Icon(Icons.push_pin_rounded),
                  title: const Text('Закрепить'),
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
              if (onDelete != null)
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded, color: TelegramColors.danger),
                  title: const Text('Удалить', style: TextStyle(color: TelegramColors.danger)),
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
