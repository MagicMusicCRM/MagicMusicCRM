import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:magic_music_crm/core/api/magic_token_store_contract.dart';

export 'package:magic_music_crm/core/api/magic_token_store_contract.dart'
    show MagicTokenStore, MemoryMagicTokenStore;

class SecureMagicTokenStore implements MagicTokenStore {
  /// Optional per-instance namespace. Empty keeps the original shared keys
  /// (backward compatible); a non-empty value (e.g. from MAGIC_PROFILE) isolates
  /// the session so multiple windows of the same binary don't clobber each other.
  final String _namespace;
  final FlutterSecureStorage _storage;

  // In-process authoritative cache of the current session.
  //
  // WHY: on a logout→login cycle the store does delete() (logout) then write()
  // (login). The Windows backend (Credential Manager) can serve a STALE or
  // empty read immediately after that delete+write — so the first authenticated
  // request after re-login went out with no/old token, the backend answered 401,
  // and the router's gate-error handler signed the user straight back out. The
  // symptom: «вошёл, вышел, теми же верными данными не пускает» — and only ever
  // on the *second* login, because a first-ever login never precedes it with a
  // delete. Once this process has written or cleared, `read()` trusts what we
  // just persisted instead of re-reading the flaky backend. A cold start (cache
  // not yet primed) still reads from the platform store.
  MagicApiTokens? _cached;
  bool _cachePrimed = false;

  SecureMagicTokenStore({
    String namespace = '',
    FlutterSecureStorage storage = const FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    ),
  }) : _namespace = namespace,
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
    // Once we've written/cleared in this process, the in-memory value is the
    // source of truth — never let a lagging platform read override it.
    if (_cachePrimed) return _cached;
    final tokens = await _readFromStorage();
    _cached = tokens;
    _cachePrimed = true;
    return tokens;
  }

  Future<MagicApiTokens?> _readFromStorage() async {
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
    // Prime the cache BEFORE the (slow, possibly-lagging) platform write so a
    // concurrent read in the same tick already sees the fresh session.
    _cached = tokens;
    _cachePrimed = true;
    await _storage.write(
      key: _tokenBundleKey,
      value: jsonEncode(tokens.toJson()),
    );
    await _storage.write(key: _accessTokenKey, value: tokens.accessToken);
    await _storage.write(key: _refreshTokenKey, value: tokens.refreshToken);
    await _storage.write(key: _tokenTypeKey, value: tokens.tokenType);
    await _storage.write(
      key: _expiresInKey,
      value: tokens.expiresIn.toString(),
    );
  }

  @override
  Future<void> clear() async {
    // Mark "definitely logged out" in-process immediately; a lagging backend
    // that still returns the old keys must not resurrect the session.
    _cached = null;
    _cachePrimed = true;
    await _storage.delete(key: _tokenBundleKey);
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
    await _storage.delete(key: _tokenTypeKey);
    await _storage.delete(key: _expiresInKey);
  }
}
