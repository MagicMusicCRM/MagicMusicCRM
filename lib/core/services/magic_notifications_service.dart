import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';

final magicNotificationsServiceProvider = Provider<MagicNotificationsService>((
  ref,
) {
  return MagicNotificationsService(ref.watch(magicApiClientProvider));
});

class MagicNotificationsService {
  final MagicApiClient _api;

  const MagicNotificationsService(this._api);

  Future<List<Map<String, dynamic>>> list({
    bool? unread,
    int limit = 50,
    String? cursor,
  }) async {
    final queryParameters = <String, dynamic>{'limit': limit};
    if (unread != null) queryParameters['unread'] = unread;
    if (cursor != null && cursor.trim().isNotEmpty) {
      queryParameters['cursor'] = cursor.trim();
    }

    final response = await _api.get<Map<String, dynamic>>(
      '/notifications',
      queryParameters: queryParameters,
    );
    final items = response['items'];
    if (items is! List) return const <Map<String, dynamic>>[];
    return items.whereType<Map<String, dynamic>>().map(_legacy).toList();
  }

  Future<void> markAllRead() async {
    await _api.post<Map<String, dynamic>>('/notifications/read-all');
  }

  Future<Map<String, dynamic>> markRead(String id) async {
    final response = await _api.post<Map<String, dynamic>>(
      '/notifications/$id/read',
    );
    return _legacy(response);
  }

  Future<Map<String, dynamic>> registerDevice({
    required String token,
    required String platform,
  }) async {
    final response = await _api.post<Map<String, dynamic>>(
      '/notifications/devices',
      data: {'token': token, 'platform': platform},
    );
    return {
      'id': response['id'],
      'user_id': response['userId'],
      'platform': response['platform'],
      'token_hash': response['tokenHash'],
      'enabled': response['enabled'],
      'last_seen_at': response['lastSeenAt'],
      'created_at': response['createdAt'],
      'updated_at': response['updatedAt'],
    };
  }

  Future<void> deleteDevice(String id) async {
    await _api.delete<Map<String, dynamic>>('/notifications/devices/$id');
  }

  Future<Map<String, dynamic>> adminSend({
    required String target,
    String? role,
    List<String>? userIds,
    required String title,
    required String body,
    List<String> channels = const ['in_app', 'push'],
    Map<String, dynamic> data = const {},
  }) {
    final payload = <String, dynamic>{
      'target': target,
      'title': title.trim(),
      'body': body.trim(),
      'channels': channels,
      'role': ?role,
      if (userIds != null && userIds.isNotEmpty) 'userIds': userIds,
      if (data.isNotEmpty) 'data': data,
    };
    return _api.post<Map<String, dynamic>>(
      '/admin/notifications',
      data: payload,
    );
  }

  Map<String, dynamic> _legacy(Map<String, dynamic> item) {
    return {
      'id': item['id'],
      'type': item['type'],
      'title': item['title'],
      'body': item['body'],
      'data': item['data'],
      'created_by': item['createdBy'],
      'created_at': item['createdAt'],
      'is_read': item['isRead'],
      'read_at': item['readAt'],
      'delivered_at': item['deliveredAt'],
    };
  }
}
