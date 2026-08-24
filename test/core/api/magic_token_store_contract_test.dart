import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_token_store_contract.dart';

void main() {
  test(
    'dependency-free memory token store preserves the current session',
    () async {
      const tokens = MagicApiTokens(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        tokenType: 'Bearer',
        expiresIn: 900,
      );
      final MagicTokenStore store = MemoryMagicTokenStore();

      expect(await store.read(), isNull);

      await store.write(tokens);
      expect(await store.read(), same(tokens));

      await store.clear();
      expect(await store.read(), isNull);
    },
  );
}
