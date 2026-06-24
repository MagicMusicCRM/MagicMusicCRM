import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_tokens.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/services/magic_realtime_service.dart';

void main() {
  group('MagicRealtimeService', () {
    test('derives realtime origin from API base URL', () {
      expect(
        realtimeOriginFromApiBaseUrl('https://api.phantom-net.ru/api'),
        'https://api.phantom-net.ru',
      );
      expect(
        realtimeOriginFromApiBaseUrl('http://localhost:3000/api/'),
        'http://localhost:3000',
      );
    });

    test(
      'connects socket.io transport with v3 bearer token and realtime path',
      () async {
        final tokenStore = MemoryMagicTokenStore();
        await tokenStore.write(
          const MagicApiTokens(
            accessToken: 'access-token-a',
            refreshToken: 'refresh-token-a',
            tokenType: 'Bearer',
            expiresIn: 900,
          ),
        );
        final fakeFactory = _FakeTransportFactory();
        final service = MagicRealtimeService(
          api: _client(tokenStore),
          apiBaseUrl: 'https://api.phantom-net.ru/api',
          transportFactory: fakeFactory.call,
        );

        final connection = await service.connect();

        expect(fakeFactory.origin, 'https://api.phantom-net.ru');
        expect(fakeFactory.options['path'], '/realtime');
        expect(fakeFactory.options['autoConnect'], false);
        expect(fakeFactory.options['auth']['token'], 'access-token-a');
        expect(fakeFactory.transport.connected, true);
        connection.dispose();
        expect(fakeFactory.transport.disposed, true);
      },
    );

    test('emits room, typing and presence events', () {
      final transport = _FakeTransport();
      final connection = MagicRealtimeConnection(transport);

      connection.joinChat('chat-a');
      connection.joinUserRoom('user-a');
      connection.leaveRoom('chat:chat-a');
      connection.startTyping('chat-a');
      connection.stopTyping('chat-a');
      connection.updatePresence(status: 'away');

      expect(transport.emits[0], {
        'event': 'room.join',
        'payload': {'roomType': 'chat', 'roomId': 'chat-a'},
      });
      expect(transport.emits[1], {
        'event': 'room.join',
        'payload': {'roomType': 'user', 'roomId': 'user-a'},
      });
      expect(transport.emits[2], {
        'event': 'room.leave',
        'payload': {'roomId': 'chat:chat-a'},
      });
      expect(transport.emits[3], {
        'event': 'typing.start',
        'payload': {'chatId': 'chat-a'},
      });
      expect(transport.emits[4], {
        'event': 'typing.stop',
        'payload': {'chatId': 'chat-a'},
      });
      expect(transport.emits[5], {
        'event': 'presence.update',
        'payload': {'status': 'away'},
      });
    });

    test('joinChannel emits a channel room.join for announcements delivery', () {
      final transport = _FakeTransport();
      final connection = MagicRealtimeConnection(transport);

      connection.joinChannel('channel-a');

      expect(transport.emits.single, {
        'event': 'room.join',
        'payload': {'roomType': 'channel', 'roomId': 'channel-a'},
      });
    });

    test('onConnect fires on every (re)connect so rooms can be re-joined', () {
      final transport = _FakeTransport();
      final connection = MagicRealtimeConnection(transport);
      var connects = 0;

      connection.onConnect(() => connects++);
      transport.fire('connect', null);
      transport.fire('connect', null);

      expect(connects, 2);
    });

    test('maps socket payloads to string-keyed event maps', () {
      final transport = _FakeTransport();
      final connection = MagicRealtimeConnection(transport);
      final received = <Map<String, dynamic>>[];

      connection.onMessageCreated(received.add);
      transport.fire('message.created', {1: 'numeric-key', 'id': 'msg-a'});
      transport.fire('message.created', 'ignored');

      expect(received, [
        {'1': 'numeric-key', 'id': 'msg-a'},
      ]);
    });

    test('rejects connect without an authenticated session', () async {
      final service = MagicRealtimeService(
        api: _client(MemoryMagicTokenStore()),
        apiBaseUrl: 'https://api.phantom-net.ru/api',
        transportFactory: _FakeTransportFactory().call,
      );

      await expectLater(service.connect(), throwsStateError);
    });
  });
}

MagicApiClient _client(MagicTokenStore tokenStore) {
  return MagicApiClient(
    baseUrl: 'https://api.phantom-net.ru/api',
    tokenStore: tokenStore,
    dio: Dio(BaseOptions(baseUrl: 'https://api.phantom-net.ru/api')),
  );
}

class _FakeTransportFactory {
  late String origin;
  late Map<String, dynamic> options;
  final _FakeTransport transport = _FakeTransport();

  MagicRealtimeTransport call(String origin, Map<String, dynamic> options) {
    this.origin = origin;
    this.options = options;
    return transport;
  }
}

class _FakeTransport implements MagicRealtimeTransport {
  final emits = <Map<String, Object?>>[];
  final handlers = <String, void Function(Object? payload)>{};
  bool connected = false;
  bool disconnected = false;
  bool disposed = false;

  @override
  void connect() {
    connected = true;
  }

  @override
  void disconnect() {
    disconnected = true;
  }

  @override
  void dispose() {
    disposed = true;
  }

  @override
  void emit(String event, Object? payload) {
    emits.add({'event': event, 'payload': payload});
  }

  @override
  void on(String event, void Function(Object? payload) handler) {
    handlers[event] = handler;
  }

  @override
  void off(String event) {
    handlers.remove(event);
  }

  void fire(String event, Object? payload) {
    handlers[event]?.call(payload);
  }
}
