import 'dart:async';

import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_tokens.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

class MagicAuthSession {
  final String accessToken;
  final String refreshToken;

  const MagicAuthSession({
    required this.accessToken,
    required this.refreshToken,
  });

  factory MagicAuthSession.fromTokens(MagicApiTokens tokens) {
    return MagicAuthSession(
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
    );
  }
}

class MagicAuthResponse {
  final MagicAuthUser? user;
  final MagicAuthSession? session;
  final bool emailVerificationRequired;
  final bool emailOtpRequired;

  const MagicAuthResponse({
    required this.user,
    required this.session,
    this.emailVerificationRequired = false,
    this.emailOtpRequired = false,
  });

  bool get hasSession => session != null;
}

class MagicAuthUser {
  final String id;
  final String email;
  final String role;
  final bool emailVerified;

  const MagicAuthUser({
    required this.id,
    required this.email,
    required this.role,
    required this.emailVerified,
  });

  factory MagicAuthUser.fromJson(Map<String, dynamic> json) {
    return MagicAuthUser(
      id: json['id']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      role: json['role']?.toString() ?? 'client',
      emailVerified: json['emailVerified'] == true,
    );
  }
}

class MagicAuthIdentity {
  final String provider;

  const MagicAuthIdentity({required this.provider});
}

class MagicAuthProfile {
  final String userId;
  final String email;
  final String role;
  final String? firstName;
  final String? lastName;
  final String? phone;
  final String? dob;
  final String? avatarFileId;
  final bool emailOtp2faEnabled;

  const MagicAuthProfile({
    required this.userId,
    required this.email,
    required this.role,
    required this.emailOtp2faEnabled,
    this.firstName,
    this.lastName,
    this.phone,
    this.dob,
    this.avatarFileId,
  });

  bool get isComplete {
    return (firstName?.trim().isNotEmpty ?? false) &&
        (lastName?.trim().isNotEmpty ?? false) &&
        (phone?.trim().isNotEmpty ?? false);
  }

  factory MagicAuthProfile.fromJson(Map<String, dynamic> json) {
    return MagicAuthProfile(
      userId: json['userId']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      role: json['role']?.toString() ?? 'client',
      firstName: json['firstName']?.toString(),
      lastName: json['lastName']?.toString(),
      phone: json['phone']?.toString(),
      dob: json['dob']?.toString(),
      avatarFileId: json['avatarFileId']?.toString(),
      emailOtp2faEnabled: json['emailOtp2faEnabled'] == true,
    );
  }
}

class MagicAuthService {
  final MagicApiClient _api;
  final _sessionController = StreamController<MagicAuthSession?>.broadcast();
  final FutureOr<void> Function()? _onBeforeSessionChange;
  final FutureOr<void> Function()? _onAfterSessionChange;

  MagicAuthService(
    this._api, {
    FutureOr<void> Function()? onBeforeSessionChange,
    FutureOr<void> Function()? onAfterSessionChange,
  }) : _onBeforeSessionChange = onBeforeSessionChange,
       _onAfterSessionChange = onAfterSessionChange {
    _api.onSessionInvalidated = _handleSessionInvalidated;
  }

  Stream<MagicAuthSession?> watchSession() async* {
    yield await currentSession();
    yield* _sessionController.stream;
  }

  Future<MagicAuthSession?> currentSession() async {
    final tokens = await _api.readTokens();
    return tokens == null ? null : MagicAuthSession.fromTokens(tokens);
  }

  Future<MagicAuthResponse> signInWithPassword({
    required String email,
    required String password,
  }) async {
    _addAuthBreadcrumb('password_login');
    try {
      final response = await _api.post<Map<String, dynamic>>(
        '/auth/login',
        data: {'email': email.trim(), 'password': password},
        authenticated: false,
      );
      final result = await _handleAuthResponse(response);
      // Do not publish a signed-out state before the server answers: doing so
      // rebuilds the router/login form and races a subsequent session event.
      // An OTP challenge is the only successful password response without a
      // session, and must still fail closed by removing any stale tokens.
      if (!result.hasSession) await _clearLocalSession();
      return result;
    } catch (error, stackTrace) {
      await _captureAuthException(error, stackTrace, 'password_login');
      rethrow;
    }
  }

  Future<MagicAuthResponse> signUpWithPassword({
    required String email,
    required String password,
    required String fullName,
    String? phone,
  }) async {
    await _clearLocalSession();
    _addAuthBreadcrumb('signup');
    try {
      final response = await _api.post<Map<String, dynamic>>(
        '/auth/signup',
        data: {
          'email': email.trim(),
          'password': password,
          'fullName': fullName.trim(),
          if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
        },
        authenticated: false,
      );
      return MagicAuthResponse(
        user: _parseUser(response['user']),
        session: null,
        emailVerificationRequired:
            response['emailVerificationRequired'] == true,
      );
    } catch (error, stackTrace) {
      await _captureAuthException(error, stackTrace, 'signup');
      rethrow;
    }
  }

  Future<void> signOut() async {
    await _beforeSessionChange();
    await _api.clearTokens();
    unawaited(
      Future.sync(() => Sentry.configureScope((scope) => scope.setUser(null))),
    );
    _sessionController.add(null);
    await _afterSessionChange();
  }

  Future<void> logoutAllDevices() async {
    await _api.post<Map<String, dynamic>>('/auth/logout-all');
    await signOut();
  }

  Future<void> sendEmailOtp({
    required String email,
    bool shouldCreateUser = false,
  }) {
    return _api.post<void>(
      '/auth/otp/request',
      data: {'email': email.trim()},
      authenticated: false,
    );
  }

  Future<MagicAuthResponse> verifyEmailOtp({
    required String email,
    required String token,
  }) async {
    final response = await _api.post<Map<String, dynamic>>(
      '/auth/otp/verify',
      data: {'email': email.trim(), 'code': token.trim()},
      authenticated: false,
    );
    return _handleAuthResponse(response);
  }

  Future<void> resendSignupOtp({required String email}) {
    return sendEmailOtp(email: email, shouldCreateUser: false);
  }

  Future<MagicAuthResponse> verifySignupOtp({
    required String email,
    required String token,
  }) async {
    await _clearLocalSession();
    final response = await verifyEmailOtp(email: email, token: token);
    if (!response.hasSession) {
      await _clearLocalSession();
    }
    return response;
  }

  Future<void> requestPasswordReset({required String email}) {
    return _api.post<void>(
      '/auth/password-reset/request',
      data: {'email': email.trim()},
      authenticated: false,
    );
  }

  Future<void> resetPassword({
    required String token,
    required String password,
  }) {
    return _api.post<void>(
      '/auth/password-reset/confirm',
      data: {'token': token.trim(), 'password': password},
      authenticated: false,
    );
  }

  Future<void> setPassword(String password) {
    return _api.post<void>('/auth/password', data: {'password': password});
  }

  Future<void> changeEmail({
    required String email,
    required String currentPassword,
  }) async {
    await _api.post<void>(
      '/auth/email',
      data: {'email': email.trim(), 'currentPassword': currentPassword},
    );
    // The server revokes every session after changing the login identifier.
    // Clear local tokens immediately and require a fresh login with new email.
    await signOut();
  }

  Future<List<MagicAuthIdentity>> getUserIdentities() async {
    final response = await _api.get<Map<String, dynamic>>('/auth/identities');
    final items = response['items'];
    if (items is! List) return const <MagicAuthIdentity>[];
    return items
        .whereType<Map<String, dynamic>>()
        .map(
          (item) =>
              MagicAuthIdentity(provider: item['provider']?.toString() ?? ''),
        )
        .where((identity) => identity.provider.isNotEmpty)
        .toList();
  }

  Future<bool> isEmailOtpMfaEnabledForCurrentUser() async {
    return (await currentProfile()).emailOtp2faEnabled;
  }

  Future<void> setEmailOtpMfaEnabled(bool enabled) async {
    await _api.patch<Map<String, dynamic>>(
      '/profile/me',
      data: {'emailOtp2faEnabled': enabled},
    );
  }

  Future<void> beginEmailOtpMfaChallenge({required String email}) {
    return sendEmailOtp(email: email, shouldCreateUser: false);
  }

  Future<MagicAuthProfile> currentProfile() async {
    final response = await _api.get<Map<String, dynamic>>('/profile/me');
    return MagicAuthProfile.fromJson(response);
  }

  Future<MagicAuthProfile> updateCurrentProfile({
    String? firstName,
    String? lastName,
    String? phone,
    String? dob,
    String? avatarFileId,
  }) async {
    final response = await _api.patch<Map<String, dynamic>>(
      '/profile/me',
      data: {
        'firstName': firstName,
        'lastName': lastName,
        'phone': phone,
        'dob': dob,
        'avatarFileId': avatarFileId,
      },
    );
    return MagicAuthProfile.fromJson(response);
  }

  Future<MagicAuthResponse> _handleAuthResponse(
    Map<String, dynamic> response,
  ) async {
    final sessionJson = response['session'];
    MagicAuthSession? session;
    if (sessionJson is Map<String, dynamic>) {
      final tokens = MagicApiTokens.fromJson(sessionJson);
      await _beforeSessionChange();
      await _api.saveTokens(tokens);
      session = MagicAuthSession.fromTokens(tokens);
      _sessionController.add(session);
      await _afterSessionChange();
    }
    final user = _parseUser(response['user']);
    await _setSentryUser(user);
    return MagicAuthResponse(
      user: user,
      session: session,
      emailOtpRequired: response['emailOtpRequired'] == true,
    );
  }

  MagicAuthUser? _parseUser(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    return MagicAuthUser.fromJson(value);
  }

  void _addAuthBreadcrumb(String flow) {
    unawaited(
      Sentry.addBreadcrumb(
        Breadcrumb(
          category: 'auth',
          message: flow,
          level: SentryLevel.info,
          data: {'flow': flow},
        ),
      ),
    );
  }

  Future<void> _captureAuthException(
    Object error,
    StackTrace stackTrace,
    String flow,
  ) {
    return Sentry.captureException(
      error,
      stackTrace: stackTrace,
      withScope: (scope) {
        scope.setTag('auth.flow', flow);
      },
    );
  }

  Future<void> _setSentryUser(MagicAuthUser? user) async {
    await Sentry.configureScope((scope) {
      if (user == null) {
        scope.setUser(null);
        return;
      }
      scope.setUser(SentryUser(id: user.id, data: {'role': user.role}));
    });
  }

  Future<void> _clearLocalSession() async {
    await _beforeSessionChange();
    await _api.clearTokens();
    _sessionController.add(null);
    await _afterSessionChange();
  }

  Future<void> _handleSessionInvalidated() async {
    await _beforeSessionChange();
    _sessionController.add(null);
    await _afterSessionChange();
  }

  Future<void> _beforeSessionChange() async {
    await _onBeforeSessionChange?.call();
  }

  Future<void> _afterSessionChange() async {
    await _onAfterSessionChange?.call();
  }
}
