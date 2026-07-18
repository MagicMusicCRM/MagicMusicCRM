// Общий фейк MagicApiClient для виджет-тестов мессенджера.
//
// Фейкается именно MagicApiClient (НЕ MagicCrmService/MagicMessengerService —
// их методы лежат на extension'ах и не переопределяются). Все сервисы приложения
// строятся от magicApiClientProvider, поэтому одного override'а достаточно.
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';

typedef ApiCall = ({String method, String path, Object? data});

class RecordingFakeApiClient extends MagicApiClient {
  RecordingFakeApiClient({
    this.chats = const [],
    this.profileRole = 'client',
    this.contactByUser = const {},
    this.chatPageSize,
  }) : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  /// Ответ GET /messenger/chats (сырые camelCase-элементы, как с сервера).
  final List<Map<String, dynamic>> chats;
  final String profileRole;
  final int? chatPageSize;

  /// Ответ GET /crm/contacts/by-user/:id поверх дефолтного {null, null}.
  final Map<String, dynamic> contactByUser;

  final List<ApiCall> calls = [];
  final List<Map<String, dynamic>> chatQueries = [];

  Iterable<ApiCall> callsWhere(String method, String path) =>
      calls.where((c) => c.method == method && c.path == path);

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    calls.add((method: 'GET', path: path, data: null));
    if (path == '/messenger/chats') {
      final query = Map<String, dynamic>.from(queryParameters ?? const {});
      chatQueries.add(query);
      final wantsArchived = query['archived'] == true;
      final branchId = query['branchId']?.toString();
      final filtered = chats.where((chat) {
        if ((chat['archived'] == true) != wantsArchived) return false;
        if (branchId != null && chat['branchId']?.toString() != branchId) {
          return false;
        }
        return true;
      }).toList();
      final configuredPageSize = chatPageSize;
      if (configuredPageSize == null) return {'items': filtered} as T;

      final offset = int.tryParse(query['cursor']?.toString() ?? '') ?? 0;
      final end = (offset + configuredPageSize).clamp(0, filtered.length);
      final items = offset >= filtered.length
          ? <Map<String, dynamic>>[]
          : filtered.sublist(offset, end);
      return <String, dynamic>{
            'items': items,
            'nextCursor': end < filtered.length ? end.toString() : null,
          }
          as T;
    }
    if (path == '/messenger/channels') return {'items': <dynamic>[]} as T;
    if (path == '/profile/me') {
      return <String, dynamic>{
            'userId': 'user-me',
            'email': 'me@example.com',
            'role': profileRole,
            'firstName': 'Тест',
            'lastName': 'Сотрудник',
          }
          as T;
    }
    if (path == '/settings/admin-chat-avatar') {
      return <String, dynamic>{'value': null} as T;
    }
    if (path == '/admin/profiles') return {'items': <dynamic>[]} as T;
    if (path == '/crm/branches') return {'items': <dynamic>[]} as T;
    if (path == '/crm/sections/unseen') return <String, dynamic>{} as T;
    if (path.startsWith('/crm/contacts/by-user/')) {
      return <String, dynamic>{
            'leadId': null,
            'studentId': null,
            ...contactByUser,
          }
          as T;
    }
    if (path.endsWith('/messages') || path.endsWith('/posts')) {
      return {'items': <dynamic>[]} as T;
    }
    return <String, dynamic>{'items': <dynamic>[]} as T;
  }

  @override
  Future<T> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    calls.add((method: 'POST', path: path, data: data));
    if (path == '/messenger/chats/direct') {
      return <String, dynamic>{
            'id': 'admin-created-1',
            'type': 'administration',
            'unreadCount': 0,
          }
          as T;
    }
    return <String, dynamic>{'ok': true} as T;
  }

  @override
  Future<T> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    calls.add((method: 'PATCH', path: path, data: data));
    final archiveMatch = RegExp(r'^/chats/([^/]+)/archive$').firstMatch(path);
    if (archiveMatch != null && data is Map) {
      final id = archiveMatch.group(1);
      for (final chat in chats) {
        if (chat['id']?.toString() == id) {
          chat['archived'] = data['archived'] == true;
        }
      }
    }
    return <String, dynamic>{'ok': true} as T;
  }

  @override
  Future<T> put<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    calls.add((method: 'PUT', path: path, data: data));
    return <String, dynamic>{'ok': true} as T;
  }

  @override
  Future<T> delete<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    calls.add((method: 'DELETE', path: path, data: data));
    return <String, dynamic>{'ok': true} as T;
  }
}
