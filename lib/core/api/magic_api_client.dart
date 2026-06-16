import 'package:dio/dio.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/api/magic_api_tokens.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

class MagicApiClient {
  final Dio _dio;
  final MagicTokenStore _tokenStore;
  static Future<bool>? _sharedRefreshInFlight;

  MagicApiClient({
    required String baseUrl,
    required MagicTokenStore tokenStore,
    Dio? dio,
  }) : _tokenStore = tokenStore,
       _dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: _normalizeBaseUrl(baseUrl),
               connectTimeout: const Duration(seconds: 15),
               receiveTimeout: const Duration(seconds: 30),
               sendTimeout: const Duration(seconds: 30),
               contentType: Headers.jsonContentType,
               responseType: ResponseType.json,
             ),
           ) {
    _dio.options.baseUrl = _normalizeBaseUrl(baseUrl);
  }

  Dio get rawDio => _dio;

  Future<MagicApiTokens?> readTokens() => _tokenStore.read();

  Future<void> saveTokens(MagicApiTokens tokens) => _tokenStore.write(tokens);

  Future<void> clearTokens() => _tokenStore.clear();

  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) {
    return request<T>(
      'GET',
      path,
      queryParameters: queryParameters,
      authenticated: authenticated,
    );
  }

  Future<T> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) {
    return request<T>(
      'POST',
      path,
      data: data,
      queryParameters: queryParameters,
      authenticated: authenticated,
    );
  }

  Future<T> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) {
    return request<T>(
      'PATCH',
      path,
      data: data,
      queryParameters: queryParameters,
      authenticated: authenticated,
    );
  }

  Future<T> put<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) {
    return request<T>(
      'PUT',
      path,
      data: data,
      queryParameters: queryParameters,
      authenticated: authenticated,
    );
  }

  Future<T> delete<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) {
    return request<T>(
      'DELETE',
      path,
      data: data,
      queryParameters: queryParameters,
      authenticated: authenticated,
    );
  }

  Future<T> request<T>(
    String method,
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    _addApiBreadcrumb(method, path, authenticated: authenticated);
    try {
      return await _send<T>(
        method,
        path,
        data: data,
        queryParameters: queryParameters,
        authenticated: authenticated,
      );
    } on DioException catch (error) {
      if (!authenticated || error.response?.statusCode != 401) {
        await _captureApiException(error, method, path);
        throw MagicApiException.fromDio(error);
      }

      final refreshed = await _tryRefresh();
      if (!refreshed) {
        await _captureApiException(error, method, path);
        throw MagicApiException.fromDio(error);
      }

      try {
        return await _send<T>(
          method,
          path,
          data: data,
          queryParameters: queryParameters,
          authenticated: authenticated,
        );
      } on DioException catch (retryError) {
        await _captureApiException(retryError, method, path);
        throw MagicApiException.fromDio(retryError);
      }
    }
  }

  Future<T> _send<T>(
    String method,
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    required bool authenticated,
  }) async {
    final headers = <String, dynamic>{};
    if (authenticated) {
      final tokens = await _tokenStore.read();
      if (tokens?.accessToken.isNotEmpty == true) {
        headers['Authorization'] = '${tokens!.tokenType} ${tokens.accessToken}';
      }
    }

    final stopwatch = Stopwatch()..start();
    final response = await _dio.request<Object?>(
      _normalizePath(path),
      data: data,
      queryParameters: queryParameters,
      options: Options(method: method, headers: headers),
    );
    stopwatch.stop();
    _addApiResponseBreadcrumb(
      method,
      path,
      statusCode: response.statusCode,
      durationMs: stopwatch.elapsedMilliseconds,
    );
    return response.data as T;
  }

  Future<bool> _tryRefresh() async {
    final inFlight = _sharedRefreshInFlight;
    if (inFlight != null) return inFlight;

    final refresh = _refreshTokens();
    _sharedRefreshInFlight = refresh;
    try {
      return await refresh;
    } finally {
      if (identical(_sharedRefreshInFlight, refresh)) {
        _sharedRefreshInFlight = null;
      }
    }
  }

  Future<bool> _refreshTokens() async {
    final current = await _tokenStore.read();
    final refreshToken = current?.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) return false;

    try {
      final response = await _dio.post<Object?>(
        _normalizePath('/auth/refresh'),
        data: {'refreshToken': refreshToken},
        options: Options(headers: <String, dynamic>{}),
      );
      final data = response.data;
      if (data is! Map<String, dynamic>) return false;
      final session = data['session'];
      if (session is! Map<String, dynamic>) return false;
      await _tokenStore.write(MagicApiTokens.fromJson(session));
      return true;
    } on DioException {
      final latest = await _tokenStore.read();
      if (latest?.refreshToken != null &&
          latest!.refreshToken != refreshToken) {
        return true;
      }
      await _tokenStore.clear();
      return false;
    }
  }

  static String _normalizeBaseUrl(String baseUrl) {
    final trimmed = baseUrl.trim();
    return trimmed.endsWith('/') ? trimmed : '$trimmed/';
  }

  static String _normalizePath(String path) {
    return path.startsWith('/') ? path.substring(1) : path;
  }

  static void _addApiBreadcrumb(
    String method,
    String path, {
    required bool authenticated,
  }) {
    Sentry.addBreadcrumb(
      Breadcrumb(
        category: 'api.request',
        type: 'http',
        level: SentryLevel.info,
        data: {
          'method': method,
          'path': _safePath(path),
          'authenticated': authenticated,
        },
      ),
    );
  }

  static void _addApiResponseBreadcrumb(
    String method,
    String path, {
    required int? statusCode,
    required int durationMs,
  }) {
    Sentry.addBreadcrumb(
      Breadcrumb(
        category: 'api.response',
        type: 'http',
        level: SentryLevel.info,
        data: {
          'method': method,
          'path': _safePath(path),
          'statusCode': statusCode,
          'durationMs': durationMs,
        },
      ),
    );
  }

  static Future<void> _captureApiException(
    DioException error,
    String method,
    String path,
  ) {
    return Sentry.captureException(
      error,
      stackTrace: error.stackTrace,
      withScope: (scope) {
        scope.setTag('api.method', method);
        scope.setTag('api.path', _safePath(path));
        scope.setTag('api.error_type', error.type.name);
        final statusCode = error.response?.statusCode;
        if (statusCode != null) {
          scope.setTag('api.status_code', statusCode.toString());
        }
        scope.setContexts('api', {
          'baseUrlHost': error.requestOptions.uri.host,
          'path': _safePath(path),
          'method': method,
          'statusCode': statusCode,
          'errorType': error.type.name,
        });
      },
    );
  }

  static String _safePath(String path) {
    final normalized = path.startsWith('/') ? path : '/$path';
    final queryIndex = normalized.indexOf('?');
    return queryIndex == -1 ? normalized : normalized.substring(0, queryIndex);
  }
}
