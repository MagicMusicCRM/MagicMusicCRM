import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:magic_music_crm/core/api/magic_api_tokens.dart';

abstract class MagicTokenStore {
  Future<MagicApiTokens?> read();
  Future<void> write(MagicApiTokens tokens);
  Future<void> clear();
}

class SecureMagicTokenStore implements MagicTokenStore {
  /// Optional per-instance namespace. Empty keeps the original shared keys
  /// (backward compatible); a non-empty value (e.g. from MAGIC_PROFILE) isolates
  /// the session so multiple windows of the same binary don't clobber each other.
  final String _namespace;
  final FlutterSecureStorage _storage;

  const SecureMagicTokenStore({
    String namespace = '',
    FlutterSecureStorage storage = const FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    ),
  })  : _namespace = namespace,
        _storage = storage;

  String get _prefix =>
      _namespace.isEmpty ? 'mmcrm.v3.' : 'mmcrm.v3.$_namespace.';
  String get _accessTokenKey => '${_prefix}access_token';
  String get _refreshTokenKey => '${_prefix}refresh_token';
  String get _tokenTypeKey => '${_prefix}token_type';
  String get _expiresInKey => '${_prefix}expires_in';
  String get _tokenBundleKey => '${_prefix}tokens';

  // IMPORTANT: every secure-storage call below is awaited sequentially, never via
  // Future.wait. The Windows backend (flutter_secure_storage_windows → Credential
  // Manager) is not safe under concurrent operations: parallel writes/deletes race
  // and silently drop some keys. A racy clear() left the legacy split-key tokens
  // behind while removing the bundle, so read()'s fallback resurrected a stale,
  // expired session → the backend returned 401 ("Требуется авторизация") on the
  // first authenticated request. Serializing the calls keeps the store consistent
  // on Windows; Android/iOS are unaffected.

  @override
  Future<MagicApiTokens?> read() async {
    final bundle = await _storage.read(key: _tokenBundleKey);
    if (bundle != null && bundle.isNotEmpty) {
      try {
        final decoded = jsonDecode(bundle);
        if (decoded is Map<String, dynamic>) {
          return MagicApiTokens.fromJson(decoded);
        }
      } catch (_) {
        // Fall back to legacy split keys below.
      }
    }

    final accessToken = await _storage.read(key: _accessTokenKey);
    final refreshToken = await _storage.read(key: _refreshTokenKey);
    // Treat empty strings as absent so a half-cleared key can never masquerade
    // as a valid session.
    if (accessToken == null ||
        accessToken.isEmpty ||
        refreshToken == null ||
        refreshToken.isEmpty) {
      return null;
    }

    final expiresInRaw = await _storage.read(key: _expiresInKey);
    final tokenType = await _storage.read(key: _tokenTypeKey);
    return MagicApiTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      tokenType: tokenType ?? 'Bearer',
      expiresIn: int.tryParse(expiresInRaw ?? '') ?? 0,
    );
  }

  @override
  Future<void> write(MagicApiTokens tokens) async {
    await _storage.write(
      key: _tokenBundleKey,
      value: jsonEncode(tokens.toJson()),
    );
    await _storage.write(key: _accessTokenKey, value: tokens.accessToken);
    await _storage.write(key: _refreshTokenKey, value: tokens.refreshToken);
    await _storage.write(key: _tokenTypeKey, value: tokens.tokenType);
    await _storage.write(key: _expiresInKey, value: tokens.expiresIn.toString());
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _tokenBundleKey);
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
    await _storage.delete(key: _tokenTypeKey);
    await _storage.delete(key: _expiresInKey);
  }
}

class MemoryMagicTokenStore implements MagicTokenStore {
  MagicApiTokens? _tokens;

  MemoryMagicTokenStore([this._tokens]);

  @override
  Future<MagicApiTokens?> read() async => _tokens;

  @override
  Future<void> write(MagicApiTokens tokens) async {
    _tokens = tokens;
  }

  @override
  Future<void> clear() async {
    _tokens = null;
  }
}
