import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http_parser/http_parser.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:mime/mime.dart';

final chatAttachmentServiceProvider = Provider<ChatAttachmentService>((ref) {
  return ChatAttachmentService(ref.watch(magicApiClientProvider));
});

/// Service for private v3 file uploads and short-lived download URLs.
class ChatAttachmentService {
  static const String _chatBucketName = 'chat-attachments';
  static const String _storageReferencePrefix = 'storage://';
  static const int maxFileSizeBytes = 25 * 1024 * 1024; // 25 MB

  final MagicApiClient _api;
  final Map<String, Future<String?>> _inFlightResolveUrls = {};

  ChatAttachmentService(this._api);

  /// Upload a file to v3 private storage.
  /// Returns the backend file object id.
  Future<String> uploadFile({
    required Uint8List bytes,
    required String originalFileName,
    required String senderId,
    String? chatId,
  }) {
    _assertChatId(chatId);
    return _upload(
      bytes: bytes,
      fileName: originalFileName,
      purpose: 'chat_attachment',
      ownerType: 'chat',
      ownerId: chatId,
    );
  }

  /// Upload a voice recording to v3 private storage.
  /// Returns the backend file object id.
  Future<String> uploadVoice({
    required Uint8List bytes,
    required String senderId,
    String? chatId,
    String extension = '.m4a',
  }) {
    _assertChatId(chatId);
    final normalizedExtension = extension.startsWith('.')
        ? extension
        : '.$extension';
    return _upload(
      bytes: bytes,
      fileName:
          'voice_${DateTime.now().millisecondsSinceEpoch}$normalizedExtension',
      purpose: 'chat_voice',
      ownerType: 'chat',
      ownerId: chatId,
      explicitMimeType: _voiceMimeType(normalizedExtension),
    );
  }

  /// Upload an avatar image to v3 private storage.
  /// Returns the backend file object id.
  Future<String> uploadAvatar({
    required Uint8List bytes,
    required String fileName,
  }) {
    return _upload(bytes: bytes, fileName: fileName, purpose: 'profile_avatar');
  }

  /// Delete an avatar file object when it is already a v3 file id.
  /// Legacy Supabase storage references are ignored during v3 cutover.
  Future<void> deleteAvatar(String? value) async {
    if (!_looksLikeBackendFileId(value)) return;
    try {
      await _api.delete<Map<String, dynamic>>('/files/$value');
    } catch (e) {
      debugPrint('Avatar delete error: $e');
    }
  }

  /// Roll back a chat upload whose message was not committed.
  Future<void> deleteUploadedFile(String? value) async {
    if (!_looksLikeBackendFileId(value)) return;
    await _api.delete<Map<String, dynamic>>('/files/$value');
  }

  static bool isPrivateStorageReference(String? value) {
    return value != null &&
        value.startsWith('$_storageReferencePrefix$_chatBucketName/');
  }

  Future<String?> resolveUrl(String? value, {int expiresIn = 3600}) async {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;

    if (_looksLikeBackendFileId(trimmed)) {
      return _resolveBackendFileUrl(trimmed);
    }

    if (_parseStorageReference(trimmed) != null) return null;

    return trimmed;
  }

  Future<String?> _resolveBackendFileUrl(String fileId) {
    final cacheKey = '${_api.rawDio.options.baseUrl}|$fileId';
    final pending = _inFlightResolveUrls[cacheKey];
    if (pending != null) return pending;

    final future = _requestBackendFileUrl(fileId).whenComplete(() {
      _inFlightResolveUrls.remove(cacheKey);
    });
    _inFlightResolveUrls[cacheKey] = future;
    return future;
  }

  Future<String?> _requestBackendFileUrl(String fileId) async {
    final response = await _api.post<Map<String, dynamic>>(
      '/files/$fileId/download-token',
    );
    final token = response['token']?.toString();
    if (token == null || token.isEmpty) {
      throw const MagicApiException(message: 'Сервер не выдал ссылку на файл.');
    }
    return _downloadUrl(token);
  }

  static String? storagePathFromUrl(String value, String bucket) {
    final reference = _parseStorageReference(value);
    if (reference != null && reference.bucket == bucket) return reference.path;

    final marker = '/storage/v1/object/public/$bucket/';
    final markerIndex = value.indexOf(marker);
    if (markerIndex == -1) return null;

    final rawPath = value
        .substring(markerIndex + marker.length)
        .split('?')
        .first;
    return Uri.decodeFull(rawPath);
  }

  Future<String> _upload({
    required Uint8List bytes,
    required String fileName,
    required String purpose,
    String? ownerType,
    String? ownerId,
    String? explicitMimeType,
  }) async {
    final mimeType =
        explicitMimeType ??
        lookupMimeType(fileName, headerBytes: bytes) ??
        'application/octet-stream';
    final formData = FormData.fromMap({
      'purpose': purpose,
      'ownerType': ?ownerType,
      'ownerId': ?ownerId,
      'file': MultipartFile.fromBytes(
        bytes,
        filename: fileName,
        contentType: MediaType.parse(mimeType),
      ),
    });

    final response = await _api.post<Map<String, dynamic>>(
      '/files',
      data: formData,
    );
    final id = response['id']?.toString();
    if (id == null || id.isEmpty) {
      throw const MagicApiException(message: 'Сервер не вернул id файла.');
    }
    return id;
  }

  static _StorageReference? _parseStorageReference(String value) {
    if (value.startsWith(_storageReferencePrefix)) {
      final body = value.substring(_storageReferencePrefix.length);
      final slashIndex = body.indexOf('/');
      if (slashIndex <= 0 || slashIndex == body.length - 1) return null;

      return _StorageReference(
        bucket: body.substring(0, slashIndex),
        path: body.substring(slashIndex + 1),
      );
    }

    const publicMarker = '/storage/v1/object/public/';
    final publicIndex = value.indexOf(publicMarker);
    if (publicIndex != -1) {
      final body = value
          .substring(publicIndex + publicMarker.length)
          .split('?')
          .first;
      final slashIndex = body.indexOf('/');
      if (slashIndex <= 0 || slashIndex == body.length - 1) return null;

      return _StorageReference(
        bucket: body.substring(0, slashIndex),
        path: Uri.decodeFull(body.substring(slashIndex + 1)),
      );
    }

    return null;
  }

  static bool _looksLikeBackendFileId(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return false;
    if (trimmed.startsWith(_storageReferencePrefix)) return false;
    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.hasScheme) return false;
    return !trimmed.contains('/');
  }

  String _downloadUrl(String token) {
    final baseUrl = _api.rawDio.options.baseUrl;
    final normalized = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    return Uri.parse(normalized).resolve('files/download/$token').toString();
  }

  static String _voiceMimeType(String extension) {
    return switch (extension.toLowerCase()) {
      '.webm' => 'audio/webm',
      '.wav' => 'audio/wav',
      '.ogg' => 'audio/ogg',
      '.mp3' => 'audio/mpeg',
      _ => 'audio/mp4',
    };
  }

  static void _assertChatId(String? chatId) {
    if (chatId?.trim().isNotEmpty == true) return;
    throw const MagicApiException(
      message: 'Сначала откройте чат, затем добавьте вложение.',
    );
  }

  /// Format file size for display.
  static String formatFileSize(int? bytes) {
    if (bytes == null) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static String safeDownloadFileName(String? value) {
    final fallback = 'download';
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return fallback;

    final withoutPath = trimmed.split(RegExp(r'[\\/]')).last.trim();
    final sanitized = withoutPath
        .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '')
        .replaceAll(RegExp(r'[<>:"|?*]'), '_')
        .trim();

    if (sanitized.isEmpty || sanitized == '.' || sanitized == '..') {
      return fallback;
    }
    return sanitized.length > 120 ? sanitized.substring(0, 120) : sanitized;
  }
}

class _StorageReference {
  final String bucket;
  final String path;

  const _StorageReference({required this.bucket, required this.path});
}
