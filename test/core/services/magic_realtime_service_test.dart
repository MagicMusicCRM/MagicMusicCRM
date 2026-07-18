import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_api_tokens.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/services/magic_realtime_service.dart';
import 'package:magic_music_crm/features/auth/providers/magic_auth_provider.dart';

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

    test('connects socket.io transport with per-handshake v3 bearer token and '
        'realtime path', () async {
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
      // Auth is a callback so every (re)connect handshake re-reads a fresh
      // token (the socket outlives the 15-minute access TTL — a baked-in
      // token made any reconnect after sleep loop with an expired JWT).
      final auth = fakeFactory.options['auth'] as Function;
      Map<dynamic, dynamic>? handshake;
      auth((dynamic payload) => handshake = payload as Map);
      await Future<void>.delayed(Duration.zero);
      expect(handshake, isNotNull);
      expect(handshake!['token'], 'access-token-a');

      expect(fakeFactory.transport.connected, true);
      connection.dispose();
      expect(fakeFactory.transport.disposed, true);
    });

    test(
      'shares one socket across consumers and closes it with the last one',
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

        // Messenger shell + crmRealtimeProvider previously opened two parallel
        // sockets; now the second connect() must re-use the first transport.
        final messenger = await service.connect();
        final crm = await service.connect();
        expect(fakeFactory.calls, 1);

        final messengerEvents = <Map<String, dynamic>>[];
        final crmEvents = <Map<String, dynamic>>[];
        messenger.onCrmChanged(messengerEvents.add);
        crm.onCrmChanged(crmEvents.add);

        fakeFactory.transport.fire('crm.changed', {'entity': 'lesson'});
        expect(messengerEvents, hasLength(1));
        expect(crmEvents, hasLength(1));

        // Disposing one view removes ONLY its handlers and keeps the socket.
        messenger.dispose();
        expect(fakeFactory.transport.disposed, false);
        fakeFactory.transport.fire('crm.changed', {'entity': 'lead'});
        expect(messengerEvents, hasLength(1));
        expect(crmEvents, hasLength(2));

        // The last consumer closes the socket; the next connect opens a new one.
        crm.dispose();
        expect(fakeFactory.transport.disposed, true);
        await service.connect();
        expect(fakeFactory.calls, 2);
      },
    );

    test(
      'logout A then login B force-disposes A transport and detaches handlers',
      () async {
        final tokenStore = MemoryMagicTokenStore(
          MagicApiTokens(
            accessToken: _jwt('user-a'),
            refreshToken: 'refresh-a',
            tokenType: 'Bearer',
            expiresIn: 900,
          ),
        );
        final api = _SessionApiClient(tokenStore);
        final fakeFactory = _FakeTransportFactory();
        final realtime = MagicRealtimeService(
          api: api,
          apiBaseUrl: 'https://api.phantom-net.ru/api',
          transportFactory: fakeFactory.call,
        );
        final container = ProviderContainer(
          overrides: [
            magicApiClientProvider.overrideWithValue(api),
            magicRealtimeServiceProvider.overrideWithValue(realtime),
          ],
        );
        addTearDown(container.dispose);
        final auth = container.read(magicAuthServiceProvider);

        final accountA = await realtime.connect();
        final aEvents = <Map<String, dynamic>>[];
        accountA.onMessageCreated(aEvents.add);
        final transportA = fakeFactory.transports.single;

        await auth.signOut();
        expect(transportA.disposed, isTrue);
        expect(transportA.disconnected, isTrue);

        api.nextLogin = MagicApiTokens(
          accessToken: _jwt('user-b'),
          refreshToken: 'refresh-b',
          tokenType: 'Bearer',
          expiresIn: 900,
        );
        await auth.signInWithPassword(email: 'b@example.com', password: 'pw');
        final accountB = await realtime.connect();
        final bEvents = <Map<String, dynamic>>[];
        accountB.onMessageCreated(bEvents.add);

        expect(fakeFactory.calls, 2);
        final transportB = fakeFactory.transports.last;
        expect(transportB, isNot(same(transportA)));

        transportA.fire('message.created', {'id': 'late-a'});
        expect(
          aEvents,
          isEmpty,
          reason: 'A handlers must be detached on logout',
        );
        expect(bEvents, isEmpty);
        transportB.fire('message.created', {'id': 'message-b'});
        expect(bEvents.single['id'], 'message-b');

        accountA.dispose();
        accountB.dispose();
      },
    );

    test(
      'connect refuses to reuse a shared socket with another JWT subject',
      () async {
        final tokenStore = MemoryMagicTokenStore(
          MagicApiTokens(
            accessToken: _jwt('user-a'),
            refreshToken: 'refresh-a',
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

        final accountA = await service.connect();
        final transportA = fakeFactory.transports.single;
        await tokenStore.write(
          MagicApiTokens(
            accessToken: _jwt('user-b'),
            refreshToken: 'refresh-b',
            tokenType: 'Bearer',
            expiresIn: 900,
          ),
        );
        final accountB = await service.connect();

        expect(transportA.disposed, isTrue);
        expect(fakeFactory.calls, 2);
        expect(fakeFactory.transports.last, isNot(same(transportA)));
        accountA.dispose();
        accountB.dispose();
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

    test(
      'joinChannel emits a channel room.join for announcements delivery',
      () {
        final transport = _FakeTransport();
        final connection = MagicRealtimeConnection(transport);

        connection.joinChannel('channel-a');

        expect(transport.emits.single, {
          'event': 'room.join',
          'payload': {'roomType': 'channel', 'roomId': 'channel-a'},
        });
      },
    );

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

    test('onChatCreated receives chat.created payloads', () {
      final transport = _FakeTransport();
      final connection = MagicRealtimeConnection(transport);
      Map<String, dynamic>? got;

      connection.onChatCreated((p) => got = p);
      transport.fire('chat.created', {
        'id': 'c9',
        'type': 'group',
        'title': 'Группа',
      });

      expect(got!['id'], 'c9');
      expect(got!['type'], 'group');
    });

    test('onChatRemoved receives chat.removed payloads', () {
      final transport = _FakeTransport();
      final connection = MagicRealtimeConnection(transport);
      String? removedId;

      connection.onChatRemoved((p) => removedId = p['id'] as String?);
      transport.fire('chat.removed', {'id': 'c9'});

      expect(removedId, 'c9');
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
  int calls = 0;
  _FakeTransport transport = _FakeTransport();
  final List<_FakeTransport> transports = [];

  MagicRealtimeTransport call(String origin, Map<String, dynamic> options) {
    this.origin = origin;
    this.options = options;
    calls++;
    if (transport.disposed) transport = _FakeTransport();
    transports.add(transport);
    return transport;
  }
}

class _FakeTransport implements MagicRealtimeTransport {
  final emits = <Map<String, Object?>>[];
  final handlers = <String, List<void Function(Object? payload)>>{};
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
    handlers.putIfAbsent(event, () => []).add(handler);
  }

  @override
  void off(String event, [void Function(Object? payload)? handler]) {
    if (handler == null) {
      handlers.remove(event);
      return;
    }
    handlers[event]?.remove(handler);
  }

  void fire(String event, Object? payload) {
    for (final handler in List.of(handlers[event] ?? const [])) {
      handler(payload);
    }
  }
}

String _jwt(String subject) {
  String part(Map<String, Object> value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'none', 'typ': 'JWT'})}.'
      '${part({'sub': subject, 'exp': 4102444800})}.signature';
}

class _SessionApiClient extends MagicApiClient {
  _SessionApiClient(this.store)
    : super(
        baseUrl: 'https://api.phantom-net.ru/api',
        tokenStore: store,
        dio: Dio(BaseOptions(baseUrl: 'https://api.phantom-net.ru/api')),
      );

  final MemoryMagicTokenStore store;
  MagicApiTokens? nextLogin;

  @override
  Future<T> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path != '/auth/login' || nextLogin == null) {
      throw UnimplementedError('POST $path');
    }
    final tokens = nextLogin!;
    nextLogin = null;
    return <String, dynamic>{
          'user': {
            'id': 'user-b',
            'email': 'b@example.com',
            'role': 'client',
            'emailVerified': true,
          },
          'session': {
            'accessToken': tokens.accessToken,
            'refreshToken': tokens.refreshToken,
            'tokenType': tokens.tokenType,
            'expiresIn': tokens.expiresIn,
          },
        }
        as T;
  }
}
