import 'package:dio/dio.dart';

class MagicApiException implements Exception {
  final int? statusCode;
  final String message;
  final Object? details;

  const MagicApiException({
    required this.message,
    this.statusCode,
    this.details,
  });

  bool get isUnauthorized => statusCode == 401;

  factory MagicApiException.fromDio(DioException error) {
    final response = error.response;
    final data = response?.data;
    if (data is Map<String, dynamic>) {
      return MagicApiException(
        statusCode: response?.statusCode,
        message: _messageFromData(data) ?? 'Ошибка API Magic Music.',
        details: data,
      );
    }

    if (data is String && data.trim().isNotEmpty) {
      return MagicApiException(
        statusCode: response?.statusCode,
        message: data,
        details: data,
      );
    }

    return MagicApiException(
      statusCode: response?.statusCode,
      message: _messageFromDioType(error),
      details: data,
    );
  }

  static String _messageFromDioType(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Сервер не отвечает. Проверьте подключение и попробуйте снова.';
      case DioExceptionType.badCertificate:
        return 'Сервер вернул некорректный TLS-сертификат.';
      case DioExceptionType.connectionError:
        return 'Не удалось подключиться к серверу Magic Music.';
      case DioExceptionType.cancel:
        return 'Запрос был отменен.';
      case DioExceptionType.badResponse:
      case DioExceptionType.unknown:
        return error.message ?? 'Не удалось выполнить запрос.';
    }
  }

  static String? _messageFromData(Map<String, dynamic> data) {
    final message = data['message'];
    if (message is String) return message;
    if (message is List) return message.whereType<String>().join('\n');
    final error = data['error'];
    if (error is String) return error;
    return null;
  }

  @override
  String toString() => message;
}
