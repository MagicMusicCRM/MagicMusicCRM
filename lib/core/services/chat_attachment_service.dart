import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:mime/mime.dart';

/// Service for uploading chat attachments (files, voice messages) to Supabase Storage.
class ChatAttachmentService {
  static const String _bucketName = 'chat-attachments';
  static const String _storageReferencePrefix = 'storage://';
  static const int maxFileSizeBytes = 25 * 1024 * 1024; // 25 MB

  static final _supabase = Supabase.instance.client;
  static const _uuid = Uuid();

  /// Upload a file (bytes) to Supabase Storage.
  /// Returns a storage reference. The UI resolves it to a short-lived signed URL.
  static Future<String> uploadFile({
    required Uint8List bytes,
    required String originalFileName,
    required String senderId,
  }) async {
    final extension = _getExtension(originalFileName);
    final storagePath = '$senderId/${_uuid.v4()}$extension';
    var mimeType = lookupMimeType(originalFileName);
    const blockedMimes = {
      'text/html',
      'text/xml',
      'application/xhtml+xml',
      'image/svg+xml',
      'application/javascript',
      'text/javascript',
    };

    if (mimeType != null && blockedMimes.contains(mimeType)) {
      mimeType = 'application/octet-stream';
    }
    mimeType ??= 'application/octet-stream';

    await _supabase.storage
        .from(_bucketName)
        .uploadBinary(
          storagePath,
          bytes,
          fileOptions: FileOptions(contentType: mimeType),
        );

    return _storageReference(_bucketName, storagePath);
  }

  /// Upload a voice recording (bytes) to Supabase Storage.
  /// Returns a storage reference. The UI resolves it to a short-lived signed URL.
  static Future<String> uploadVoice({
    required Uint8List bytes,
    required String senderId,
    String extension = '.m4a',
  }) async {
    final storagePath = '$senderId/voice_${_uuid.v4()}$extension';
    final mimeType = extension == '.webm'
        ? 'audio/webm'
        : extension == '.wav'
        ? 'audio/wav'
        : 'audio/mp4';

    await _supabase.storage
        .from(_bucketName)
        .uploadBinary(
          storagePath,
          bytes,
          fileOptions: FileOptions(contentType: mimeType),
        );

    return _storageReference(_bucketName, storagePath);
  }

  /// Upload an avatar image (bytes) to the avatars bucket.
  /// Returns the public URL of the uploaded image.
  static Future<String> uploadAvatar({
    required Uint8List bytes,
    required String fileName,
  }) async {
    const avatarBucket = 'avatars';
    final extension = _getExtension(fileName);
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Avatar upload requires an authenticated user.');
    }
    final storagePath = '$userId/avatar_${_uuid.v4()}$extension';
    final mimeType = lookupMimeType(fileName) ?? 'image/jpeg';

    await _supabase.storage
        .from(avatarBucket)
        .uploadBinary(
          storagePath,
          bytes,
          fileOptions: FileOptions(contentType: mimeType),
        );

    return _supabase.storage.from(avatarBucket).getPublicUrl(storagePath);
  }

  /// Delete an avatar from the avatars bucket.
  static Future<void> deleteAvatar(String? url) async {
    if (url == null || url.isEmpty) return;
    const avatarBucket = 'avatars';
    try {
      final path = storagePathFromUrl(url, avatarBucket);
      if (path != null) {
        await _supabase.storage.from(avatarBucket).remove([path]);
      }
    } catch (e) {
      debugPrint('Avatar delete error: $e');
    }
  }

  static bool isPrivateStorageReference(String? value) {
    return value != null &&
        value.startsWith('$_storageReferencePrefix$_bucketName/');
  }

  static Future<String?> resolveUrl(
    String? value, {
    int expiresIn = 3600,
  }) async {
    if (value == null || value.isEmpty) return null;

    final reference = _parseStorageReference(value);
    if (reference == null) return value;

    return _supabase.storage
        .from(reference.bucket)
        .createSignedUrl(reference.path, expiresIn);
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

  static String _storageReference(String bucket, String path) {
    return '$_storageReferencePrefix$bucket/$path';
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

  static String _getExtension(String fileName) {
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == fileName.length - 1) return '';
    return fileName.substring(dotIndex);
  }

  /// Format file size for display.
  static String formatFileSize(int? bytes) {
    if (bytes == null) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _StorageReference {
  final String bucket;
  final String path;

  const _StorageReference({required this.bucket, required this.path});
}
