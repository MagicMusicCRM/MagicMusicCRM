import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/services/homework_attachment_service.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/file_attachment_widget.dart';

class HomeworkPickedFile {
  const HomeworkPickedFile({
    required this.bytes,
    required this.name,
    required this.size,
  });

  final Uint8List bytes;
  final String name;
  final int size;
}

Future<HomeworkPickedFile?> pickHomeworkAttachment(BuildContext context) async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const [
      'png',
      'jpg',
      'jpeg',
      'webp',
      'pdf',
      'txt',
      'doc',
      'docx',
      'xls',
      'xlsx',
      'mp3',
      'm4a',
      'ogg',
      'webm',
      'wav',
      'mp4',
    ],
    allowMultiple: false,
    withData: false,
  );
  if (result == null || result.files.isEmpty) return null;

  final file = result.files.first;
  if (file.size > HomeworkAttachmentService.maxFileSizeBytes) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Файл слишком большой (макс. 25 МБ)')),
      );
    }
    return null;
  }

  final bytes = file.bytes ?? await _readPickedBytes(file);
  if (bytes == null || bytes.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось прочитать файл')),
      );
    }
    return null;
  }
  return HomeworkPickedFile(bytes: bytes, name: file.name, size: file.size);
}

Future<Uint8List?> _readPickedBytes(PlatformFile file) async {
  final path = file.path;
  if (path == null || path.isEmpty) return null;
  return File(path).readAsBytes();
}

List<Map<String, dynamic>> homeworkAttachments(Object? value) {
  if (value is! List) return const [];
  return [
    for (final item in value)
      if (item is Map)
        item.map((key, value) => MapEntry(key.toString(), value)),
  ];
}

class HomeworkAttachmentList extends StatelessWidget {
  const HomeworkAttachmentList({
    super.key,
    required this.attachments,
    this.compact = false,
  });

  final List<Map<String, dynamic>> attachments;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final attachment in attachments) ...[
          if (!compact || attachment != attachments.first)
            const SizedBox(height: AppSpace.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!compact) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    attachment['kind']?.toString() == 'submission'
                        ? 'Решение'
                        : 'Задание',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
              ],
              Expanded(
                child: FileAttachmentWidget(
                  fileName:
                      (attachment['fileName'] ?? attachment['originalName'])
                          ?.toString(),
                  fileUrl: (attachment['fileId'] ?? attachment['file_id'])
                      ?.toString(),
                  fileSize: _asInt(
                    attachment['sizeBytes'] ?? attachment['size_bytes'],
                  ),
                  mimeType: (attachment['mimeType'] ?? attachment['mime_type'])
                      ?.toString(),
                  isMe: false,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

int? _asInt(Object? value) {
  if (value == null) return null;
  return value is num ? value.toInt() : int.tryParse(value.toString());
}
