import 'dart:async';
import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:magic_music_crm/core/observability/app_performance.dart';

import 'package:dio/dio.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/api/magic_token_store_contract.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Caller-owned metadata for a command that may be retried after an ambiguous
/// network failure.
///
/// Most mutations can use [MagicApiClient]'s automatically generated headers.
/// Multi-step UI commands (subscription issue + optional payment) keep these
/// identities in widget state and pass them explicitly, so a user-initiated
/// retry cannot accidentally execute either step under a fresh key.
class MagicMutationIdentity {
  const MagicMutationIdentity({
    required this.idempotencyKey,
    required this.requestId,
  });

  final String idempotencyKey;
  final String requestId;

  static int _sequence = 0;

  factory MagicMutationIdentity.create(String operation) {
    final safeOperation = operation
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9._:-]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final sequence = _sequence++;
    final suffix = '$stamp-$sequence';
    final prefix = safeOperation.isEmpty ? 'command' : safeOperation;
    return MagicMutationIdentity(
      idempotencyKey: 'magiccrm-$prefix-$suffix',
      requestId: 'flutter-$prefix-$suffix',
    );
  }

  Map<String, dynamic> get headers => <String, dynamic>{
    'Idempotency-Key': idempotencyKey,
    'X-Request-Id': requestId,
  };
}

class MagicApiClient {
  final Dio _dio;
  final MagicTokenStore _tokenStore;
  static Future<bool>? _sharedRefreshInFlight;

  /// Called after an unrecoverable refresh failure has cleared local tokens.
  /// The auth layer uses this to leave the stale signed-in shell immediately.
  FutureOr<void> Function()? onSessionInvalidated;

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

  /// Returns a currently-valid access token, proactively refreshing the stored
  /// one when it is expired or near expiry. `null` when there is no session or
  /// the refresh failed.
  ///
  /// Needed by consumers that authenticate OUTSIDE the HTTP request path (the
  /// Socket.IO handshake): they cannot rely on the per-request 401-refresh
  /// here, and a token baked in at connect() time outlives the 15-minute
  /// access TTL, making every later reconnect loop with an expired JWT.
  Future<String?> readFreshAccessToken() async {
    var tokens = await _tokenStore.read();
    if (tokens != null && _isAccessTokenExpired(tokens.accessToken)) {
      await _tryRefresh();
      tokens = await _tokenStore.read();
    }
    final token = tokens?.accessToken;
    return (token == null || token.isEmpty) ? null : token;
  }

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

  /// POST with caller-owned command identity.
  ///
  /// Use this only when the caller must preserve the same identity across
  /// separate user-initiated retries. Connection and 401 retries already keep
  /// the identity stable inside [request].
  Future<T> postIdempotent<T>(
    String path, {
    required MagicMutationIdentity identity,
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
      mutationIdentity: identity,
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

  /// Authenticated binary GET returning the raw response bytes. Widgets that
  /// need to download a file (e.g. report exports) go through this instead of
  /// assembling their own authorized Dio request — token injection, proactive
  /// refresh, single-flight 401 refresh and retry all stay centralized here.
  Future<List<int>> downloadBytes(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) {
    return request<List<int>>(
      'GET',
      path,
      queryParameters: queryParameters,
      responseType: ResponseType.bytes,
    );
  }

  Future<T> patchIdempotent<T>(
    String path, {
    required MagicMutationIdentity identity,
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
      mutationIdentity: identity,
    );
  }

  Future<List<int>> postBytes(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
  }) {
    return request<List<int>>(
      'POST',
      path,
      data: data,
      queryParameters: queryParameters,
      responseType: ResponseType.bytes,
    );
  }

  Future<T> request<T>(
    String method,
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
    ResponseType? responseType,
    MagicMutationIdentity? mutationIdentity,
  }) => AppPerformance.measure<T>(
    AppPerformance.operationFor(method, path),
    () async {
      _addApiBreadcrumb(method, path, authenticated: authenticated);
      final requestHeaders =
          mutationIdentity?.headers ??
          _mutationHeaders(method) ??
          {'X-Request-Id': const Uuid().v4()};
      try {
        return await _sendWithRetry<T>(
          method,
          path,
          data: data,
          queryParameters: queryParameters,
          authenticated: authenticated,
          responseType: responseType,
          requestHeaders: requestHeaders,
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
            responseType: responseType,
            requestHeaders: requestHeaders,
          );
        } on DioException catch (retryError) {
          await _captureApiException(retryError, method, path);
          throw MagicApiException.fromDio(retryError);
        }
      }
    },
  );

  /// Retries once when no connection was established, or for safe reads.
  /// A connectionError can also mean a lost response after the server committed.
  /// Merely sending an Idempotency-Key does not prove that a route honors it;
  /// ambiguous writes must return to the caller without a transport replay.
  Future<T> _sendWithRetry<T>(
    String method,
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    required bool authenticated,
    ResponseType? responseType,
    Map<String, dynamic>? requestHeaders,
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
          responseType: responseType,
          requestHeaders: requestHeaders,
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
        return true;
      case DioExceptionType.connectionError:
      case DioExceptionType.receiveTimeout:
        return const {'GET', 'HEAD', 'OPTIONS'}.contains(method.toUpperCase());
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
    ResponseType? responseType,
    Map<String, dynamic>? requestHeaders,
  }) async {
    final headers = <String, dynamic>{...?requestHeaders};
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

    final response = await _requestTimed(
      method,
      path,
      data: data,
      queryParameters: queryParameters,
      headers: headers,
      responseType: responseType,
    );
    return response.data as T;
  }

  Future<Response<Object?>> _requestTimed(
    String method,
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    required Map<String, dynamic> headers,
    ResponseType? responseType,
  }) async {
    final timer = Stopwatch()..start();
    final operation = AppPerformance.current;
    Response<Object?>? response;
    String? failure;
    try {
      response = await _dio.request<Object?>(
        _normalizePath(path),
        data: data,
        queryParameters: queryParameters,
        options: Options(
          method: method,
          headers: {
            ...headers,
            if (operation != null) 'X-Operation-Id': operation.id,
          },
          responseType: responseType,
        ),
      );
      return response;
    } on DioException catch (error) {
      response = error.response;
      failure = error.type.name;
      rethrow;
    } finally {
      final timings = <String, double>{};
      for (final token
          in (response?.headers['server-timing']?.join(',') ?? '').split(',')) {
        final match = RegExp(
          r'^\s*(app|db|pool);dur=([0-9]+(?:\.[0-9]+)?)\s*$',
        ).firstMatch(token);
        if (match != null) {
          final value = double.tryParse(match[2]!);
          if (value != null && value.isFinite) timings[match[1]!] = value;
        }
      }
      AppPerformance.record({
        'kind': 'http',
        'operation': operation?.name.name ?? 'api',
        'operationId': operation?.id,
        'requestId': headers['X-Request-Id'],
        'method': method,
        'statusCode': response?.statusCode,
        'durationMs': timer.elapsedMicroseconds / 1000,
        'errorType': failure,
        if (timings['app'] != null) 'serverMs': timings['app'],
        if (timings['db'] != null) 'dbQueryMs': timings['db'],
        if (timings['pool'] != null) 'dbAcquireMs': timings['pool'],
      });
    }
  }

  static int _mutationSequence = 0;

  /// Every mutating request carries stable metadata for the full retry cycle.
  ///
  /// The v4 command boundary requires both headers. They are generated once in
  /// [request], then reused for connection and 401 retries, so a retry cannot
  /// accidentally execute the same command under a different idempotency key.
  static Map<String, dynamic>? _mutationHeaders(String method) {
    if (method == 'GET' || method == 'HEAD' || method == 'OPTIONS') return null;
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final sequence = _mutationSequence++;
    final suffix = '$stamp-$sequence';
    return {
      'Idempotency-Key': 'magiccrm-$suffix',
      'X-Request-Id': 'flutter-$suffix',
    };
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
      final response = await _requestTimed(
        'POST',
        '/auth/refresh',
        data: {'refreshToken': refreshToken},
        headers: {'X-Request-Id': const Uuid().v4()},
      );
      final data = response.data;
      if (data is! Map<String, dynamic>) return false;
      final session = data['session'];
      if (session is! Map<String, dynamic>) return false;
      await _tokenStore.write(MagicApiTokens.fromJson(session));
      return true;
    } on DioException catch (error) {
      final latest = await _tokenStore.read();
      if (latest?.refreshToken != null &&
          latest!.refreshToken != refreshToken) {
        return true;
      }
      // Only an explicit authentication rejection invalidates the session.
      // Network failures and temporary server errors retain retryable tokens.
      if (error.response?.statusCode != 401) {
        throw MagicApiException.fromDio(error);
      }
      await _tokenStore.clear();
      await onSessionInvalidated?.call();
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
