import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:magic_music_crm/core/api/magic_api_tokens.dart';

abstract class MagicTokenStore {
  Future<MagicApiTokens?> read();
  Future<void> write(MagicApiTokens tokens);
  Future<void> clear();
}

class SecureMagicTokenStore implements MagicTokenStore {
  static const _accessTokenKey = 'mmcrm.v3.access_token';
  static const _refreshTokenKey = 'mmcrm.v3.refresh_token';
  static const _tokenTypeKey = 'mmcrm.v3.token_type';
  static const _expiresInKey = 'mmcrm.v3.expires_in';

  final FlutterSecureStorage _storage;

  const SecureMagicTokenStore([
    this._storage = const FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    ),
  ]);

  @override
  Future<MagicApiTokens?> read() async {
    final coreTokens = await Future.wait([
      _storage.read(key: _accessTokenKey),
      _storage.read(key: _refreshTokenKey),
    ]);
    final accessToken = coreTokens[0];
    final refreshToken = coreTokens[1];
    if (accessToken == null || refreshToken == null) return null;

    final metadata = await Future.wait([
      _storage.read(key: _expiresInKey),
      _storage.read(key: _tokenTypeKey),
    ]);
    final expiresInRaw = metadata[0];
    return MagicApiTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      tokenType: metadata[1] ?? 'Bearer',
      expiresIn: int.tryParse(expiresInRaw ?? '') ?? 0,
    );
  }

  @override
  Future<void> write(MagicApiTokens tokens) async {
    await Future.wait([
      _storage.write(key: _accessTokenKey, value: tokens.accessToken),
      _storage.write(key: _refreshTokenKey, value: tokens.refreshToken),
      _storage.write(key: _tokenTypeKey, value: tokens.tokenType),
      _storage.write(key: _expiresInKey, value: tokens.expiresIn.toString()),
    ]);
  }

  @override
  Future<void> clear() async {
    await Future.wait([
      _storage.delete(key: _accessTokenKey),
      _storage.delete(key: _refreshTokenKey),
      _storage.delete(key: _tokenTypeKey),
      _storage.delete(key: _expiresInKey),
    ]);
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
