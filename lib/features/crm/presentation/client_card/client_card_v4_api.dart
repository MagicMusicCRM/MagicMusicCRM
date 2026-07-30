import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';

final clientCardV4ApiProvider = Provider<ClientCardV4Api>((ref) {
  return ClientCardV4Api(ref.watch(magicApiClientProvider));
});

class ClientCardV4Api {
  const ClientCardV4Api(this._api);

  final MagicApiClient _api;

  Future<Map<String, dynamic>> loadCard({
    required String entityType,
    required String entityId,
  }) {
    return _api.get<Map<String, dynamic>>(
      '/crm/clients/$entityType/$entityId/card',
    );
  }

  Future<Map<String, dynamic>> previewArchive({
    required String entityType,
    required String entityId,
  }) {
    return _api.post<Map<String, dynamic>>(
      '/crm/clients/archive/preview',
      data: {'type': entityType, 'id': entityId},
    );
  }

  Future<Map<String, dynamic>> archive({
    required String entityType,
    required String entityId,
    required int expectedVersion,
    required String reason,
  }) {
    return _api.post<Map<String, dynamic>>(
      '/crm/clients/archive',
      data: {
        'type': entityType,
        'id': entityId,
        'expectedVersion': expectedVersion,
        'confirm': true,
        'reason': reason,
      },
    );
  }
}
