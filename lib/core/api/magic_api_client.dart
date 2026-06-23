import 'dart:convert';

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
      return await _sendWithRetry<T>(
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
        return await _sendWithRetry<T>(
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

  /// Wraps [_send] with a single retry for connection-phase failures. The first
  /// request after the app/network has been idle can be slow or dropped (cold
  /// DNS resolution, a dropped first SYN behind a rate-limiter); an immediate
  /// retry then succeeds because the route/DNS cache is warm. Connection-phase
  /// failures mean the request never reached the server, so retrying is safe for
  /// any method; a slow response (receiveTimeout) is only retried for reads.
  Future<T> _sendWithRetry<T>(
    String method,
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    required bool authenticated,
  }) async {
    const maxAttempts = 2;
    var attempt = 0;
    while (true) {
      attempt++;
      try {
        return await _send<T>(
          method,
          path,
          data: data,
          queryParameters: queryParameters,
          authenticated: authenticated,
        );
      } on DioException catch (e) {
        if (attempt >= maxAttempts || !_isRetriableConnectionError(e, method)) {
          rethrow;
        }
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    }
  }

  bool _isRetriableConnectionError(DioException e, String method) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.connectionError:
        return true;
      case DioExceptionType.receiveTimeout:
        return method == 'GET';
      default:
        return false;
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
      var tokens = await _tokenStore.read();
      // Proactively refresh an already-expired (or near-expiry) access token
      // BEFORE sending, so a burst of parallel requests does not each hit a 401
      // and pile up concurrent refreshes (the session-refresh race). The
      // refresh itself is single-flighted via [_tryRefresh].
      if (tokens != null && _isAccessTokenExpired(tokens.accessToken)) {
        await _tryRefresh();
        tokens = await _tokenStore.read();
      }
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

  /// Returns true when the JWT access token is expired or within
  /// [leewaySeconds] of expiry. On any parse failure returns false, so the
  /// normal 401-driven refresh path stays as a fallback.
  bool _isAccessTokenExpired(String token, {int leewaySeconds = 30}) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return false;
      var payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
      switch (payload.length % 4) {
        case 2:
          payload += '==';
          break;
        case 3:
          payload += '=';
          break;
      }
      final claims = jsonDecode(utf8.decode(base64.decode(payload)));
      final exp = claims is Map ? claims['exp'] : null;
      if (exp is! int) return false;
      final expiry = DateTime.fromMillisecondsSinceEpoch(
        exp * 1000,
        isUtc: true,
      );
      return DateTime.now().toUtc().isAfter(
        expiry.subtract(Duration(seconds: leewaySeconds)),
      );
    } catch (_) {
      return false;
    }
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
