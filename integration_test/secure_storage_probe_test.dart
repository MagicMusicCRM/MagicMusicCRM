// Verifies per-instance namespaced token stores are isolated on this platform,
// so two windows of the same binary can hold two different accounts and a logout
// in one does not break the other.
// Run on Windows:  flutter test integration_test/secure_storage_probe_test.dart -d windows
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:magic_music_crm/core/api/magic_api_tokens.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  MagicApiTokens t(String v) => MagicApiTokens(
    accessToken: 'access-$v',
    refreshToken: 'refresh-$v',
    tokenType: 'Bearer',
    expiresIn: 900,
  );

  test(
    'namespaced token stores are isolated; logout in one keeps the other',
    () async {
      final a = SecureMagicTokenStore(namespace: 'a');
      final b = SecureMagicTokenStore(namespace: 'b');
      await a.clear();
      await b.clear();

      await a.write(t('ACCOUNT-A'));
      await b.write(t('ACCOUNT-B'));

      final ra = await a.read();
      final rb = await b.read();
      // ignore: avoid_print
      print('PROBE a=${ra?.accessToken} b=${rb?.accessToken}');
      expect(ra?.accessToken, 'access-ACCOUNT-A');
      expect(rb?.accessToken, 'access-ACCOUNT-B');

      // Logout in window A must not touch window B.
      await a.clear();
      final raAfter = await a.read();
      final rbAfter = await b.read();
      // ignore: avoid_print
      print(
        'PROBE after a.clear() a=${raAfter?.accessToken} b=${rbAfter?.accessToken}',
      );
      expect(raAfter, isNull);
      expect(rbAfter?.accessToken, 'access-ACCOUNT-B');

      await b.clear();
    },
  );
}
