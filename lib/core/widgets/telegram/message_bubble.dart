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

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.senderName,
    this.showSenderName = false,
    this.isGroupChat = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dt = DateTime.tryParse(message['created_at'] ?? '');
    final timeStr = dt != null ? DateFormat('HH:mm', 'ru').format(dt.toLocal()) : '';
    final messageType = message['message_type']?.toString() ?? 'text';
    final attachmentUrl = message['attachment_url']?.toString();
    final hasAttachment = attachmentUrl != null && attachmentUrl.isNotEmpty;
    final isAttachmentType = messageType == 'file' || messageType == 'image' || messageType == 'photo' || messageType == 'voice';
    
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

    final timeColor = isMe
        ? (isDark ? Colors.white.withAlpha(140) : Colors.black.withAlpha(100))
        : (isDark ? TelegramColors.darkTextSecondary : TelegramColors.lightTextSecondary);

    // Determine sender name color for group chats
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
              topLeft: const Radius.circular(12),
              topRight: const Radius.circular(12),
              bottomLeft: Radius.circular(isMe ? 12 : 2),
              bottomRight: Radius.circular(isMe ? 2 : 12),
            ),
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withAlpha(8),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
          ),
          child: IntrinsicWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Sender name (for group chats)
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
                // Content
                if (isAttachmentType || hasAttachment) ...[
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
                // Time + read status
                const SizedBox(height: 2),
                Align(
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        timeStr,
                        style: TextStyle(
                          color: timeColor,
                          fontSize: 11,
                        ),
                      ),
                      if (isMe) ...[
                        const SizedBox(width: 3),
                        Icon(
                          message['is_read'] == true ? Icons.done_all : Icons.done,
                          size: 14,
                          color: message['is_read'] == true
                              ? TelegramColors.success
                              : timeColor,
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
    );
  }
}
