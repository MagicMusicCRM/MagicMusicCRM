import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:magic_music_crm/core/theme/telegram_colors.dart';
import 'package:magic_music_crm/core/services/chat_attachment_service.dart';

/// A Telegram-style dialog for confirming file sending with an optional caption.
class SendFileDialog extends StatefulWidget {
  final String fileName;
  final int fileSize;
  final Uint8List? fileBytes; // For preview if it's an image
  final Function(String caption) onSend;

  const SendFileDialog({
    super.key,
    required this.fileName,
    required this.fileSize,
    this.fileBytes,
    required this.onSend,
  });

  @override
  State<SendFileDialog> createState() => _SendFileDialogState();
}

class _SendFileDialogState extends State<SendFileDialog> {
  final _captionController = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // Use a slight delay to ensure the dialog is fully settled before requesting focus
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _captionController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool _isImage(String name) {
    final ext = name.toLowerCase();
    return ext.endsWith('.jpg') ||
        ext.endsWith('.jpeg') ||
        ext.endsWith('.png') ||
        ext.endsWith('.gif') ||
        ext.endsWith('.webp');
  }

  IconData _getFileIcon(String name) {
    final nameParts = name.split('.');
    if (nameParts.length < 2) return Icons.insert_drive_file_rounded;
    final ext = nameParts.last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'doc':
      case 'docx':
        return Icons.description_rounded;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart_rounded;
      case 'mp3':
      case 'wav':
      case 'm4a':
        return Icons.audio_file_rounded;
      case 'mp4':
      case 'mov':
      case 'avi':
        return Icons.video_file_rounded;
      case 'zip':
      case 'rar':
      case '7z':
        return Icons.folder_zip_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isImage = _isImage(widget.fileName);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 450),
        decoration: BoxDecoration(
          color: isDark ? TelegramColors.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                    splashRadius: 20,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Отправить файл',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.more_vert_rounded),
                    onPressed: () {},
                    splashRadius: 20,
                  ),
                ],
              ),
            ),
            
            // File Preview / Info
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                children: [
                  // File Icon / Thumbnail
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: TelegramColors.accentBlue.withAlpha(isDark ? 50 : 30),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: isImage && widget.fileBytes != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.memory(
                              widget.fileBytes!,
                              fit: BoxFit.cover,
                            ),
                          )
                        : Icon(
                            _getFileIcon(widget.fileName),
                            size: 32,
                            color: TelegramColors.accentBlue,
                          ),
                  ),
                  const SizedBox(width: 16),
                  // Name and Size
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.fileName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          ChatAttachmentService.formatFileSize(widget.fileSize),
                          style: TextStyle(
                            color: isDark
                                ? TelegramColors.darkTextSecondary
                                : TelegramColors.lightTextSecondary,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Delete icon like in reference
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () => Navigator.pop(context),
                    color: isDark
                        ? TelegramColors.darkTextSecondary
                        : TelegramColors.lightTextSecondary,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Caption Field
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.sentiment_satisfied_alt_rounded),
                    onPressed: () {},
                    color: isDark
                        ? TelegramColors.darkTextSecondary
                        : TelegramColors.lightTextSecondary,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _captionController,
                      focusNode: _focusNode,
                      decoration: const InputDecoration(
                        hintText: 'Добавить подпись...',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 12),
                      ),
                      onSubmitted: (_) {
                        widget.onSend(_captionController.text.trim());
                        Navigator.pop(context);
                      },
                    ),
                  ),
                ],
              ),
            ),

            // Actions
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ElevatedButton(
                    onPressed: () {
                      widget.onSend(_captionController.text.trim());
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: TelegramColors.accentBlue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'ОТПРАВИТЬ',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
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
