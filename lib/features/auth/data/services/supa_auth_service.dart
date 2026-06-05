import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:magic_music_crm/core/constants/env.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupaAuthService {
  final SupabaseClient _client;

  const SupaAuthService(this._client);

  bool get _supportsNativeGoogle {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  bool get _isIos => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  GoogleSignIn _googleSignInClient() {
    return GoogleSignIn(
      scopes: const ['email', 'profile'],
      serverClientId: Env.googleWebClientId,
      clientId: _isIos && Env.googleIosClientId.isNotEmpty
          ? Env.googleIosClientId
          : null,
    );
  }

  Future<AuthResponse> signInWithPassword({
    required String email,
    required String password,
  }) {
    return _client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<bool> isEmailOtpMfaEnabledForCurrentUser() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;

    final profile = await _client
        .from('profiles')
        .select('email_otp_2fa_enabled')
        .eq('id', userId)
        .maybeSingle();

    return profile?['email_otp_2fa_enabled'] == true;
  }

  Future<void> setEmailOtpMfaEnabled(bool enabled) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw const AuthException('Пользователь не авторизован.');
    }

    await _client
        .from('profiles')
        .update({'email_otp_2fa_enabled': enabled})
        .eq('id', userId);
  }

  Future<void> beginEmailOtpMfaChallenge({required String email}) async {
    await _client.auth.signOut(scope: SignOutScope.local);
    await _client.auth.signInWithOtp(
      email: email.trim(),
      shouldCreateUser: false,
    );
  }

  Future<AuthResponse> signUpWithPassword({
    required String email,
    required String password,
    required String fullName,
  }) {
    return _client.auth.signUp(
      email: email.trim(),
      password: password,
      data: {'full_name': fullName.trim()},
    );
  }

  Future<void> signInWithGoogle() async {
    if (!_shouldUseNativeGoogle) {
      await _signInWithSupabaseGoogleOAuth();
      return;
    }

    try {
      final tokens = await _requestGoogleTokens();
      await _signInWithGoogleTokens(tokens);
    } on AuthException catch (error) {
      if (!_shouldFallbackToSupabaseOAuth(error.message)) rethrow;
      await _signInWithSupabaseGoogleOAuth();
    }
  }

  Future<void> linkGoogleIdentity() async {
    if (!_shouldUseNativeGoogle) {
      await _linkGoogleWithSupabaseOAuth();
      return;
    }

    try {
      final tokens = await _requestGoogleTokens();
      await _client.auth.linkIdentityWithIdToken(
        provider: OAuthProvider.google,
        idToken: tokens.idToken,
        accessToken: tokens.accessToken,
      );
    } on AuthException catch (error) {
      if (!_shouldFallbackToSupabaseOAuth(error.message)) rethrow;
      await _linkGoogleWithSupabaseOAuth();
    }
  }

  Future<void> sendEmailOtp({
    required String email,
    bool shouldCreateUser = false,
  }) {
    return _client.auth.signInWithOtp(
      email: email.trim(),
      shouldCreateUser: shouldCreateUser,
    );
  }

  Future<AuthResponse> verifyEmailOtp({
    required String email,
    required String token,
  }) {
    return _client.auth.verifyOTP(
      email: email.trim(),
      token: token.trim(),
      type: OtpType.email,
    );
  }

  Future<void> resendSignupOtp({required String email}) {
    return _client.auth.resend(email: email.trim(), type: OtpType.signup);
  }

  Future<AuthResponse> verifySignupOtp({
    required String email,
    required String token,
  }) {
    return _client.auth.verifyOTP(
      email: email.trim(),
      token: token.trim(),
      type: OtpType.signup,
    );
  }

  Future<UserResponse> setPassword(String password) {
    return _client.auth.updateUser(UserAttributes(password: password));
  }

  Future<List<UserIdentity>> getUserIdentities() {
    return _client.auth.getUserIdentities();
  }

  bool get _shouldUseNativeGoogle {
    if (!_supportsNativeGoogle) return false;
    if (Env.googleWebClientId.isEmpty) return false;
    if (_isIos && Env.googleIosClientId.isEmpty) return false;
    return true;
  }

  Future<void> _signInWithSupabaseGoogleOAuth() {
    return _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: Env.authRedirectUrl,
    );
  }

  Future<void> _linkGoogleWithSupabaseOAuth() {
    return _client.auth.linkIdentity(
      OAuthProvider.google,
      redirectTo: Env.authRedirectUrl,
    );
  }

  Future<_GoogleOAuthTokens> _requestGoogleTokens() async {
    if (Env.googleWebClientId.isEmpty) {
      throw const AuthException(
        'Google OAuth не настроен: соберите приложение с GOOGLE_WEB_CLIENT_ID.',
      );
    }
    if (_isIos && Env.googleIosClientId.isEmpty) {
      throw const AuthException(
        'Google OAuth для iOS не настроен: добавьте GOOGLE_IOS_CLIENT_ID.',
      );
    }

    final googleSignIn = _googleSignInClient();

    try {
      await googleSignIn.signOut();
      final account = await googleSignIn.signIn();
      if (account == null) {
        throw const AuthException('Вход через Google отменен.');
      }

      final authentication = await account.authentication;
      final idToken = authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw const AuthException('Google native sign-in не вернул ID token.');
      }

      return _GoogleOAuthTokens(
        idToken: idToken,
        accessToken: authentication.accessToken,
      );
    } on PlatformException catch (error) {
      throw AuthException(_mapGooglePlatformError(error));
    }
  }

  Future<void> _signInWithGoogleTokens(_GoogleOAuthTokens tokens) async {
    try {
      await _client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: tokens.idToken,
        accessToken: tokens.accessToken,
      );
    } on AuthException catch (error) {
      if (!_isRetryableAuthError(error.message)) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await _client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: tokens.idToken,
        accessToken: tokens.accessToken,
      );
    }
  }

  bool _isRetryableAuthError(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains('network') ||
        normalized.contains('timeout') ||
        normalized.contains('temporar') ||
        normalized.contains('token verification');
  }

  bool _shouldFallbackToSupabaseOAuth(String message) {
    final normalized = message.toLowerCase();
    if (normalized.contains('отменен')) return false;
    return normalized.contains('google_web_client_id') ||
        normalized.contains('google_ios_client_id') ||
        normalized.contains('id token') ||
        normalized.contains('oauth client id') ||
        normalized.contains('sha-1') ||
        normalized.contains('sign_in_failed');
  }

  String _mapGooglePlatformError(PlatformException error) {
    final code = error.code.toLowerCase();
    if (code.contains('sign_in_canceled')) return 'Вход через Google отменен.';
    if (code.contains('network')) {
      return 'Нет стабильного соединения для входа через Google.';
    }
    if (code.contains('sign_in_failed')) {
      return 'Google native sign_in_failed.';
    }
    return error.message ?? 'Не удалось выполнить вход через Google.';
  }
}

class _GoogleOAuthTokens {
  final String idToken;
  final String? accessToken;

  const _GoogleOAuthTokens({required this.idToken, required this.accessToken});
}
