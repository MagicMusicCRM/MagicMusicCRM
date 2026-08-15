import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http_parser/http_parser.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:mime/mime.dart';

final homeworkAttachmentServiceProvider = Provider<HomeworkAttachmentService>(
  (ref) => HomeworkAttachmentService(ref.watch(magicApiClientProvider)),
);

/// Uploads a private homework file and binds it to the canonical homework.
///
/// The file API must receive the homework id up front so its RBAC policy can
/// validate the owner. If the second request fails, the just-uploaded file is
/// soft-deleted to avoid leaving an inaccessible orphan in storage history.
class HomeworkAttachmentService {
  HomeworkAttachmentService(this._api);

  static const maxFileSizeBytes = 25 * 1024 * 1024;

  final MagicApiClient _api;

  Future<Map<String, dynamic>> uploadAndAttach({
    required String homeworkId,
    required Uint8List bytes,
    required String fileName,
    required String kind,
  }) async {
    if (homeworkId.trim().isEmpty) {
      throw const MagicApiException(message: 'Не найдено домашнее задание.');
    }
    if (bytes.isEmpty) {
      throw const MagicApiException(message: 'Выбранный файл пустой.');
    }
    if (bytes.length > maxFileSizeBytes) {
      throw const MagicApiException(
        message: 'Файл слишком большой (максимум 25 МБ).',
      );
    }
    if (kind != 'assignment' && kind != 'submission') {
      throw const MagicApiException(message: 'Некорректный тип вложения.');
    }

    final safeName = fileName.trim();
    if (safeName.isEmpty) {
      throw const MagicApiException(message: 'У файла отсутствует имя.');
    }
    final mimeType =
        lookupMimeType(safeName, headerBytes: bytes) ??
        'application/octet-stream';
    final formData = FormData.fromMap({
      'purpose': 'homework_attachment',
      'ownerType': 'homework',
      'ownerId': homeworkId,
      'file': MultipartFile.fromBytes(
        bytes,
        filename: safeName,
        contentType: MediaType.parse(mimeType),
      ),
    });

    final uploaded = await _api.post<Map<String, dynamic>>(
      '/files',
      data: formData,
    );
    final fileId = uploaded['id']?.toString();
    if (fileId == null || fileId.isEmpty) {
      throw const MagicApiException(
        message: 'Сервер не подтвердил загрузку файла.',
      );
    }

    try {
      final attachment = await _api.post<Map<String, dynamic>>(
        '/crm/homeworks/$homeworkId/attachments',
        data: {'fileId': fileId, 'kind': kind},
      );
      return {
        ...attachment,
        'fileId': fileId,
        'fileName': uploaded['originalName'] ?? safeName,
        'mimeType': uploaded['mimeType'] ?? mimeType,
        'sizeBytes': uploaded['sizeBytes'] ?? bytes.length,
        'kind': kind,
      };
    } catch (error) {
      try {
        await _api.delete<Map<String, dynamic>>('/files/$fileId');
      } catch (cleanupError) {
        debugPrint('Homework attachment cleanup failed: $cleanupError');
      }
      rethrow;
    }
  }
}
