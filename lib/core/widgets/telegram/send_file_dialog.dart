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

    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.only(bottom: bottomPadding),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          decoration: BoxDecoration(
            color: isDark ? TelegramColors.darkSurface : Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(isDark ? 50 : 20),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
                child: Row(
                  children: [
                    const Text(
                      'Отправить файл',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context),
                      splashRadius: 20,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ],
                ),
              ),
              
              // File Preview / Info
              if (isImage && widget.fileBytes != null)
                // Larger Image Preview
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  height: 200,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: isDark ? Colors.black26 : Colors.black.withAlpha(5),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.memory(
                      widget.fileBytes!,
                      fit: BoxFit.contain,
                    ),
                  ),
                )
              else
                // Standard File Info
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: TelegramColors.accentBlue.withAlpha(isDark ? 30 : 15),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: TelegramColors.accentBlue.withAlpha(50),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            _getFileIcon(widget.fileName),
                            size: 24,
                            color: TelegramColors.accentBlue,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.fileName,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                ChatAttachmentService.formatFileSize(widget.fileSize),
                                style: TextStyle(
                                  color: isDark
                                      ? TelegramColors.darkTextSecondary
                                      : TelegramColors.lightTextSecondary,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 12),

              // Caption Field
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark ? TelegramColors.darkInputBg : TelegramColors.lightInputBg,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 12),
                      Icon(
                        Icons.sentiment_satisfied_alt_rounded,
                        color: isDark ? Colors.white54 : Colors.black45,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _captionController,
                          focusNode: _focusNode,
                          style: const TextStyle(fontSize: 16),
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
                      const SizedBox(width: 8),
                    ],
                  ),
                ),
              ),

              // Actions
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                child: ElevatedButton(
                  onPressed: () {
                    widget.onSend(_captionController.text.trim());
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: TelegramColors.accentBlue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    minimumSize: const Size(double.infinity, 54),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'ОТПРАВИТЬ',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
