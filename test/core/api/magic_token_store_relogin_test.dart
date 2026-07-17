import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_tokens.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';

/// Regression for «вошёл → вышел → теми же верными данными не пускает».
///
/// On a logout→login cycle the store does delete() then write(). The Windows
/// Credential Manager can serve a STALE read right after — so the first
/// authenticated request after re-login went out with the wrong/no token, got
/// a 401, and the router signed the user back out. The in-process cache must
/// make read() return exactly what was last written/cleared, whatever the
/// laggy backend reports.
void main() {
  const tokensA = MagicApiTokens(
    accessToken: 'access-A',
    refreshToken: 'refresh-A',
    tokenType: 'Bearer',
    expiresIn: 900,
  );
  const tokensB = MagicApiTokens(
    accessToken: 'access-B',
    refreshToken: 'refresh-B',
    tokenType: 'Bearer',
    expiresIn: 900,
  );

  test('read() returns the freshly re-logged-in session despite a stale backend',
      () async {
    final storage = _LaggyStorage();
    final store = SecureMagicTokenStore(storage: storage);

    // First login.
    await store.write(tokensA);
    expect((await store.read())?.accessToken, 'access-A');

    // Logout — backend keeps lagging, still reporting tokensA on read.
    storage.frozenReadValue = _bundleFor(tokensA);
    await store.clear();
    expect(await store.read(), isNull, reason: 'logout must clear the session');

    // Re-login with the same account. The laggy backend still serves the OLD
    // bundle on read; without the cache read() would resurrect tokensA and the
    // gate request would 401 → auto-signout → stuck on /login.
    storage.frozenReadValue = _bundleFor(tokensA);
    await store.write(tokensB);
    expect(
      (await store.read())?.accessToken,
      'access-B',
      reason: 're-login must surface the NEW session, not a stale backend read',
    );
  });
}

String _bundleFor(MagicApiTokens t) =>
    '{"accessToken":"${t.accessToken}","refreshToken":"${t.refreshToken}",'
    '"tokenType":"${t.tokenType}","expiresIn":${t.expiresIn}}';

/// Fake secure storage whose reads lag behind writes/deletes — reproducing the
/// Windows Credential Manager behaviour the cache defends against. When
/// [frozenReadValue] is set, every bundle read returns it regardless of the
/// last write/delete.
class _LaggyStorage extends FlutterSecureStorage {
  final Map<String, String> _data = {};
  String? frozenReadValue;

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (frozenReadValue != null && key.endsWith('tokens')) {
      return frozenReadValue;
    }
    return _data[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value != null) _data[key] = value;
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _data.remove(key);
  }
}
