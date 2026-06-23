import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/constants/env.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

typedef MagicRealtimeHandler = void Function(Map<String, dynamic> payload);
typedef MagicRealtimeTransportFactory =
    MagicRealtimeTransport Function(
      String origin,
      Map<String, dynamic> options,
    );

final magicRealtimeServiceProvider = Provider<MagicRealtimeService>((ref) {
  return MagicRealtimeService(
    api: ref.watch(magicApiClientProvider),
    apiBaseUrl: Env.magicApiBaseUrl,
  );
});

abstract class MagicRealtimeTransport {
  void connect();
  void disconnect();
  void dispose();
  void emit(String event, Object? payload);
  void on(String event, void Function(Object? payload) handler);
  void off(String event);
}

class SocketIoMagicRealtimeTransport implements MagicRealtimeTransport {
  final io.Socket _socket;

  SocketIoMagicRealtimeTransport(String origin, Map<String, dynamic> options)
    : _socket = io.io(origin, options);

  @override
  void connect() => _socket.connect();

  @override
  void disconnect() => _socket.disconnect();

  @override
  void dispose() => _socket.dispose();

  @override
  void emit(String event, Object? payload) => _socket.emit(event, payload);

  @override
  void on(String event, void Function(Object? payload) handler) {
    _socket.on(event, handler);
  }

  @override
  void off(String event) => _socket.off(event);
}

class MagicRealtimeService {
  final MagicApiClient _api;
  final String _apiBaseUrl;
  final MagicRealtimeTransportFactory _transportFactory;

  const MagicRealtimeService({
    required MagicApiClient api,
    required String apiBaseUrl,
    MagicRealtimeTransportFactory transportFactory =
        _defaultRealtimeTransportFactory,
  }) : _api = api,
       _apiBaseUrl = apiBaseUrl,
       _transportFactory = transportFactory;

  Future<MagicRealtimeConnection> connect() async {
    final tokens = await _api.readTokens();
    final accessToken = tokens?.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      throw StateError('Realtime requires an authenticated v3 session.');
    }

    final origin = realtimeOriginFromApiBaseUrl(_apiBaseUrl);
    final transport = _transportFactory(
      origin,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setPath('/realtime')
          .setAuth({'token': accessToken})
          .disableAutoConnect()
          .build(),
    );

    final connection = MagicRealtimeConnection(transport);
    connection.connect();
    return connection;
  }
}

class MagicRealtimeConnection {
  final MagicRealtimeTransport _transport;

  const MagicRealtimeConnection(this._transport);

  void connect() => _transport.connect();

  void disconnect() => _transport.disconnect();

  void dispose() => _transport.dispose();

  void joinChat(String chatId) {
    _transport.emit('room.join', {'roomType': 'chat', 'roomId': chatId});
  }

  void joinUserRoom(String userId) {
    _transport.emit('room.join', {'roomType': 'user', 'roomId': userId});
  }

  void leaveRoom(String roomId) {
    _transport.emit('room.leave', {'roomId': roomId});
  }

  void startTyping(String chatId) {
    _transport.emit('typing.start', {'chatId': chatId});
  }

  void stopTyping(String chatId) {
    _transport.emit('typing.stop', {'chatId': chatId});
  }

  void updatePresence({String status = 'online'}) {
    _transport.emit('presence.update', {'status': status});
  }

  void onMessageCreated(MagicRealtimeHandler handler) {
    _onMap('message.created', handler);
  }

  void onMessageUpdated(MagicRealtimeHandler handler) {
    _onMap('message.updated', handler);
  }

  void onChatUpdated(MagicRealtimeHandler handler) {
    _onMap('chat.updated', handler);
  }

  void onChannelPostCreated(MagicRealtimeHandler handler) {
    _onMap('channel.post_created', handler);
  }

  void onTypingStart(MagicRealtimeHandler handler) {
    _onMap('typing.start', handler);
  }

  void onTypingStop(MagicRealtimeHandler handler) {
    _onMap('typing.stop', handler);
  }

  void onPresenceUpdated(MagicRealtimeHandler handler) {
    _onMap('presence.updated', handler);
  }

  /// CRM invalidation hint broadcast to staff (lessons/leads/etc. changed).
  void onCrmChanged(MagicRealtimeHandler handler) {
    _onMap('crm.changed', handler);
  }

  void off(String event) => _transport.off(event);

  void _onMap(String event, MagicRealtimeHandler handler) {
    _transport.on(event, (payload) {
      final map = _asStringMap(payload);
      if (map != null) handler(map);
    });
  }
}

String realtimeOriginFromApiBaseUrl(String apiBaseUrl) {
  final uri = Uri.parse(apiBaseUrl.trim());
  if (!uri.hasScheme || uri.host.isEmpty) {
    throw ArgumentError.value(apiBaseUrl, 'apiBaseUrl', 'Invalid API base URL');
  }
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
  ).toString();
}

MagicRealtimeTransport _defaultRealtimeTransportFactory(
  String origin,
  Map<String, dynamic> options,
) {
  return SocketIoMagicRealtimeTransport(origin, options);
}

Map<String, dynamic>? _asStringMap(Object? payload) {
  if (payload is! Map) return null;
  return payload.map((key, value) => MapEntry(key.toString(), value));
}
