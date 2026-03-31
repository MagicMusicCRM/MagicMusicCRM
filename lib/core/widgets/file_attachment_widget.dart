import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/services/chat_attachment_service.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

/// Widget for displaying a file attachment inside a message bubble.
/// Images are displayed inline; other files show as downloadable cards.
class FileAttachmentWidget extends StatefulWidget {
  final String? fileName;
  final String? fileUrl;
  final int? fileSize;
  final bool isMe;

  const FileAttachmentWidget({
    super.key,
    this.fileName,
    this.fileUrl,
    this.fileSize,
    required this.isMe,
  });

  /// Check if a filename is an image.
  static bool isImage(String? name) {
    if (name == null) return false;
    final lower = name.toLowerCase();
    return lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.png') ||
        lower.endsWith('.gif') || lower.endsWith('.webp');
  }

  @override
  State<FileAttachmentWidget> createState() => _FileAttachmentWidgetState();
}

class _FileAttachmentWidgetState extends State<FileAttachmentWidget> {
  bool _downloading = false;

  IconData _iconForFile(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.pdf')) return Icons.picture_as_pdf_rounded;
    if (lower.endsWith('.doc') || lower.endsWith('.docx')) return Icons.description_rounded;
    if (lower.endsWith('.xls') || lower.endsWith('.xlsx')) return Icons.table_chart_rounded;
    if (lower.endsWith('.mp4') || lower.endsWith('.webm') || lower.endsWith('.avi')) return Icons.video_file_rounded;
    if (lower.endsWith('.mp3') || lower.endsWith('.wav') || lower.endsWith('.ogg')) return Icons.audio_file_rounded;
    return Icons.attach_file_rounded;
  }

  static bool isImage(String? name) {
    if (name == null) return false;
    final lower = name.toLowerCase();
    return lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.png') ||
        lower.endsWith('.gif') || lower.endsWith('.webp');
  }

  Future<void> _downloadAndOpen() async {
    if (_downloading || widget.fileUrl == null) return;
    setState(() => _downloading = true);

    try {
      final dir = await getTemporaryDirectory();
      final savePath = '${dir.path}/${widget.fileName ?? 'download'}';
      
      await Dio().download(widget.fileUrl!, savePath);
      await OpenFilex.open(savePath);
    } catch (e) {
      debugPrint('Download error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка скачивания: $e', style: const TextStyle(color: Colors.white)),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  void _showFullScreenImage(BuildContext context) {
    if (widget.fileUrl == null) return;
    
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        barrierDismissible: true,
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: animation,
            child: _FullScreenImageViewer(
              imageUrl: widget.fileUrl!,
              fileName: widget.fileName,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.fileName ?? 'Файл';

    // ── Image: show inline like Telegram ──
    if (isImage(name) && widget.fileUrl != null) {
      return GestureDetector(
        onTap: () => _showFullScreenImage(context),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 250, maxWidth: 280),
            child: Image.network(
              widget.fileUrl!,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return Container(
                  height: 120,
                  width: 200,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: (widget.isMe ? Colors.white : AppTheme.primaryPurple).withAlpha(15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: CircularProgressIndicator(
                    value: progress.expectedTotalBytes != null
                        ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                        : null,
                    strokeWidth: 2,
                    color: widget.isMe ? Colors.white : AppTheme.primaryPurple,
                  ),
                );
              },
              errorBuilder: (_, __, error) => Container(
                height: 60,
                width: 200,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: (widget.isMe ? Colors.white : AppTheme.primaryPurple).withAlpha(15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.broken_image_rounded, 
                      color: widget.isMe ? Colors.white70 : Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(height: 4),
                    Text('Не удалось загрузить', 
                      style: TextStyle(fontSize: 11, 
                        color: widget.isMe ? Colors.white70 : Theme.of(context).colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    // ── Non-image file: show as downloadable card ──
    final sizeStr = ChatAttachmentService.formatFileSize(widget.fileSize);
    final iconColor = widget.isMe ? Colors.white : AppTheme.primaryPurple;
    final textCol = widget.isMe ? Colors.white : Theme.of(context).colorScheme.onSurface;
    final subtitleCol = widget.isMe ? Colors.white.withAlpha(180) : Theme.of(context).colorScheme.onSurfaceVariant;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: _downloadAndOpen,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: (widget.isMe ? Colors.white : AppTheme.primaryPurple).withAlpha(15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withAlpha(25),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(_iconForFile(name), color: iconColor, size: 20),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      color: textCol,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (sizeStr.isNotEmpty)
                    Text(
                      sizeStr,
                      style: TextStyle(color: subtitleCol, fontSize: 11),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _downloading
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: iconColor,
                    ),
                  )
                : Icon(Icons.download_rounded, size: 18, color: iconColor.withAlpha(150)),
          ],
        ),
      ),
    );
  }
}

/// Full-screen image viewer with zoom and close button (like Telegram).
class _FullScreenImageViewer extends StatelessWidget {
  final String imageUrl;
  final String? fileName;

  const _FullScreenImageViewer({required this.imageUrl, this.fileName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black87,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          fileName ?? 'Фото',
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: Image.network(
            imageUrl,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return Center(
                child: CircularProgressIndicator(
                  value: progress.expectedTotalBytes != null
                      ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                      : null,
                  color: Colors.white,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
