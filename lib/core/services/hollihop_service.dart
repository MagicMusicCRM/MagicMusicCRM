import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';

final hollihopServiceProvider = Provider<HolliHopService>((ref) {
  return HolliHopService(ref.watch(magicApiClientProvider));
});

class HolliHopService {
  final MagicApiClient _api;

  const HolliHopService(this._api);

  Future<List<String>> getDisciplines() async {
    final response = await _api.get<Map<String, dynamic>>(
      '/crm/hollihop/disciplines',
    );
    return _stringItems(response);
  }

  Future<List<String>> getLevels() async {
    final response = await _api.get<Map<String, dynamic>>(
      '/crm/hollihop/levels',
    );
    return _stringItems(response);
  }

  Future<List<String>> getCategories() async {
    final response = await _api.get<Map<String, dynamic>>(
      '/crm/hollihop/categories',
    );
    return _stringItems(response);
  }

  Future<List<Map<String, dynamic>>> getLeadStatuses() async {
    final response = await _api.get<Map<String, dynamic>>(
      '/crm/hollihop/lead-statuses',
    );
    final items = response['items'];
    if (items is! List) return const <Map<String, dynamic>>[];
    return items.whereType<Map<String, dynamic>>().toList();
  }

  List<String> _stringItems(Map<String, dynamic> response) {
    final items = response['items'];
    if (items is! List) return const <String>[];
    return items.whereType<String>().toList();
  }
}
