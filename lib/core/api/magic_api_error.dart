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

  /// Short, Russian and safe for direct display in the interface.
  ///
  /// [message] stays unchanged for domain parsers and diagnostics. The UI must
  /// use this value (or [userErrorMessage]) so backend codes and transport
  /// details never leak to a person.
  String toUserMessage({String fallback = 'Не удалось выполнить действие.'}) {
    return _userMessage(message, statusCode: statusCode, fallback: fallback);
  }

  factory MagicApiException.fromDio(DioException error) {
    final response = error.response;
    final data = response?.data;
    if (data is Map<String, dynamic>) {
      return MagicApiException(
        statusCode: response?.statusCode,
        message: _messageFromData(data) ?? 'Не удалось выполнить запрос.',
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
    final isRead = const {
      'GET',
      'HEAD',
      'OPTIONS',
    }.contains(error.requestOptions.method.toUpperCase());
    if (!isRead &&
        const {
          DioExceptionType.connectionError,
          DioExceptionType.sendTimeout,
          DioExceptionType.receiveTimeout,
        }.contains(error.type)) {
      return 'Не удалось получить подтверждение. Действие могло сохраниться. '
          'Обновите данные и проверьте результат перед повтором.';
    }
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Сервер не отвечает. Проверьте подключение и попробуйте снова.';
      case DioExceptionType.badCertificate:
        return 'Не удалось установить безопасное соединение.';
      case DioExceptionType.connectionError:
        return 'Не удалось подключиться к серверу.';
      case DioExceptionType.cancel:
        return 'Запрос был отменён.';
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
  String toString() => toUserMessage();
}

/// Converts any caught error into a concise message suitable for the UI.
String userErrorMessage(
  Object? error, {
  String fallback = 'Не удалось выполнить действие.',
}) {
  if (error == null) return fallback;
  if (error is MagicApiException) {
    return error.toUserMessage(fallback: fallback);
  }
  if (error is DioException) {
    return MagicApiException.fromDio(error).toUserMessage(fallback: fallback);
  }
  return _userMessage(error.toString(), fallback: fallback);
}

/// Sanitizes an already composed error string before a shared UI component
/// displays it.
String userErrorText(
  String message, {
  String fallback = 'Не удалось выполнить действие.',
}) {
  return _userMessage(message, fallback: fallback);
}

String _userMessage(String raw, {int? statusCode, required String fallback}) {
  final normalized = raw
      .replaceFirst(RegExp(r'^(Exception|FormatException|StateError):\s*'), '')
      .replaceAll(RegExp(r'\s*[—–]\s*'), ': ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final lower = normalized.toLowerCase();

  if (lower.contains('invalid login credentials')) {
    return 'Неверная почта или пароль.';
  }
  if (lower.contains('email not confirmed')) {
    return 'Подтвердите почту перед входом.';
  }
  if (lower.contains('token has expired')) {
    return 'Код истёк. Запросите новый.';
  }
  if (lower.contains('invalid token')) return 'Неверный код.';
  if (lower.contains('too many requests')) {
    return 'Слишком много попыток. Попробуйте позже.';
  }

  final statusMessage = switch (statusCode) {
    401 => 'Сеанс завершён. Войдите снова.',
    403 => 'Недостаточно прав для этого действия.',
    404 => 'Запись не найдена.',
    409 => 'Данные изменились или уже заняты. Обновите их и повторите.',
    422 => 'Проверьте заполненные поля.',
    429 => 'Слишком много запросов. Попробуйте позже.',
    final code? when code >= 500 =>
      'Сервис временно недоступен. Попробуйте позже.',
    _ => null,
  };

  final hasRussian = RegExp(r'[А-Яа-яЁё]').hasMatch(normalized);
  // `email` is normal product language in otherwise Russian business errors.
  // Treating that one word as technical text hid useful 400 responses behind
  // a generic fallback (including duplicate-email and invite validation).
  final textWithoutUserFacingLatin = normalized.replaceAll(
    RegExp(r'\bemail\b', caseSensitive: false),
    '',
  );
  final hasUnsafeLatin = RegExp(
    r'[A-Za-z]',
  ).hasMatch(textWithoutUserFacingLatin);
  final hasTechnicalText = RegExp(
    r'\b(exception|stack|trace|sql|http|statuscode|constraint|undefined|null)\b',
    caseSensitive: false,
  ).hasMatch(normalized);
  if (hasRussian && hasUnsafeLatin) {
    final separator = normalized.indexOf(':');
    if (separator > 0) {
      final prefix = normalized.substring(0, separator).trim();
      if (RegExp(r'[А-Яа-яЁё]').hasMatch(prefix) &&
          !RegExp(r'[A-Za-z]').hasMatch(prefix) &&
          prefix.length <= 120) {
        return prefix;
      }
    }
    return statusMessage ?? fallback;
  }
  if (hasRussian && !hasTechnicalText && normalized.length <= 180) {
    return normalized;
  }
  return statusMessage ?? fallback;
}
