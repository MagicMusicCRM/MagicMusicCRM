import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:mime/mime.dart';

/// Service for uploading chat attachments (files, voice messages) to Supabase Storage.
class ChatAttachmentService {
  static const String _bucketName = 'chat-attachments';
  static const int maxFileSizeBytes = 25 * 1024 * 1024; // 25 MB

  static final _supabase = Supabase.instance.client;
  static const _uuid = Uuid();

  /// Upload a file (bytes) to Supabase Storage.
  /// Returns the public URL of the uploaded file.
  static Future<String> uploadFile({
    required Uint8List bytes,
    required String originalFileName,
    required String senderId,
  }) async {
    final extension = _getExtension(originalFileName);
    final storagePath = '$senderId/${_uuid.v4()}$extension';
    final mimeType = lookupMimeType(originalFileName) ?? 'application/octet-stream';

    await _supabase.storage.from(_bucketName).uploadBinary(
      storagePath,
      bytes,
      fileOptions: FileOptions(contentType: mimeType),
    );

    return _supabase.storage.from(_bucketName).getPublicUrl(storagePath);
  }

  /// Upload a voice recording (bytes) to Supabase Storage.
  /// Returns the public URL of the uploaded voice file.
  static Future<String> uploadVoice({
    required Uint8List bytes,
    required String senderId,
    String extension = '.m4a',
  }) async {
    final storagePath = '$senderId/voice_${_uuid.v4()}$extension';
    final mimeType = extension == '.webm' ? 'audio/webm'
        : extension == '.wav' ? 'audio/wav'
        : 'audio/mp4';

    await _supabase.storage.from(_bucketName).uploadBinary(
      storagePath,
      bytes,
      fileOptions: FileOptions(contentType: mimeType),
    );

    return _supabase.storage.from(_bucketName).getPublicUrl(storagePath);
  }

  /// Upload an avatar image (bytes) to the avatars bucket.
  /// Returns the public URL of the uploaded image.
  static Future<String> uploadAvatar({
    required Uint8List bytes,
    required String fileName,
  }) async {
    const avatarBucket = 'avatars';
    final extension = _getExtension(fileName);
    final storagePath = 'avatars_${_uuid.v4()}$extension';
    final mimeType = lookupMimeType(fileName) ?? 'image/jpeg';

    await _supabase.storage.from(avatarBucket).uploadBinary(
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
      final parts = url.split('/$avatarBucket/');
      if (parts.length == 2) {
        final path = parts.last;
        await _supabase.storage.from(avatarBucket).remove([path]);
      }
    } catch (e) {
      debugPrint('Avatar delete error: $e');
    }
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
