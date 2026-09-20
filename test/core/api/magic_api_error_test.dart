import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';

void main() {
  for (final type in [
    DioExceptionType.connectionError,
    DioExceptionType.sendTimeout,
    DioExceptionType.receiveTimeout,
  ]) {
    test('login $type never claims a business action may have been saved', () {
      final error = MagicApiException.fromDio(
        DioException(
          requestOptions: RequestOptions(
            path: '/auth/login',
            baseUrl: 'http://127.0.0.1/api',
            method: 'POST',
          ),
          type: type,
        ),
      );
      expect(error.toUserMessage(), isNot(contains('могло сохраниться')));
    });
    test('business POST $type retains the uncertain-outcome warning', () {
      final error = MagicApiException.fromDio(
        DioException(
          requestOptions: RequestOptions(path: '/crm/lessons', method: 'POST'),
          type: type,
        ),
      );
      expect(error.toUserMessage(), contains('могло сохраниться'));
    });
  }
  group('userErrorMessage', () {
    test('keeps safe Russian email business errors visible', () {
      for (final message in const [
        'Пользователь с таким email уже существует.',
        'У ученика нет email для приглашения.',
      ]) {
        final error = MagicApiException(statusCode: 400, message: message);

        expect(
          error.toUserMessage(fallback: 'Не удалось сохранить карточку.'),
          message,
        );
      }
    });

    test('maps an English server failure to a Russian message', () {
      const error = MagicApiException(
        statusCode: 500,
        message: 'Internal Server Error',
      );

      expect(
        error.toUserMessage(),
        'Сервис временно недоступен. Попробуйте позже.',
      );
    });

    test('maps common authentication errors', () {
      const error = MagicApiException(message: 'Invalid login credentials');

      expect(error.toUserMessage(), 'Неверная почта или пароль.');
    });

    test('keeps a short Russian domain message and removes a long dash', () {
      const error = MagicApiException(
        message: 'Аудитория занята — выберите другое время',
      );

      expect(error.toUserMessage(), 'Аудитория занята: выберите другое время');
    });

    test('drops technical details after a Russian action prefix', () {
      expect(
        userErrorText('Не удалось сохранить: SocketException: timed out'),
        'Не удалось сохранить',
      );
    });

    test('uses the supplied fallback for an unknown technical error', () {
      expect(
        userErrorMessage(
          StateError('PostgreSQL constraint schedule_overlap'),
          fallback: 'Не удалось проверить расписание.',
        ),
        'Не удалось проверить расписание.',
      );
    });

    test('maps forbidden access without exposing a server response', () {
      const error = MagicApiException(statusCode: 403, message: 'Forbidden');

      expect(error.toUserMessage(), 'Недостаточно прав для этого действия.');
    });
  });
}
