import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/constants/env.dart';

final magicTokenStoreProvider = Provider<MagicTokenStore>((ref) {
  return const SecureMagicTokenStore();
});

final magicApiClientProvider = Provider<MagicApiClient>((ref) {
  return MagicApiClient(
    baseUrl: Env.magicApiBaseUrl,
    tokenStore: ref.watch(magicTokenStoreProvider),
  );
});
