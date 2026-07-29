import 'dart:convert';

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

  /// Removes [handler] for [event]; with no [handler] removes all of them.
  void off(String event, [void Function(Object? payload)? handler]);
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
  void off(String event, [void Function(Object? payload)? handler]) =>
      _socket.off(event, handler);
}

/// Owns AT MOST ONE Socket.IO connection per app (the messenger shell and the
/// CRM invalidation stream used to each open их own socket — двойные
/// handshake'и и keepalive-трафик). [connect] hands out ref-counted views over
/// the shared transport; the socket closes when the last view is disposed.
class MagicRealtimeService {
  final MagicApiClient _api;
  final String _apiBaseUrl;
  final MagicRealtimeTransportFactory _transportFactory;

  MagicRealtimeService({
    required MagicApiClient api,
    required String apiBaseUrl,
    MagicRealtimeTransportFactory transportFactory =
        _defaultRealtimeTransportFactory,
  }) : _api = api,
       _apiBaseUrl = apiBaseUrl,
       _transportFactory = transportFactory;

  _SharedRealtimeSocket? _shared;

  /// Immediately severs every view of the current transport, regardless of
  /// its ref-count. Auth lifecycle code calls this before tokens are cleared or
  /// replaced so account B can never inherit account A's authenticated socket.
  void resetSession() {
    final shared = _shared;
    _shared = null;
    shared?.forceDispose();
  }

  Future<MagicRealtimeConnection> connect() async {
    final tokens = await _api.readTokens();
    final accessToken = tokens?.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      throw StateError('Realtime requires an authenticated v3 session.');
    }

    final sessionKey = _sessionKeyForAccessToken(accessToken);

    // Re-use the live shared socket only inside the same authenticated
    // identity (re-checked after the await above). Token refreshes keep the
    // same JWT `sub`; a different `sub` force-disposes the old transport.
    final existing = _shared;
    if (existing != null && !existing.isDisposed) {
      if (existing.sessionKey == sessionKey) return existing.acquire();
      _shared = null;
      existing.forceDispose();
    }

    final origin = realtimeOriginFromApiBaseUrl(_apiBaseUrl);
    final options = io.OptionBuilder()
        .setTransports(['websocket'])
        .setPath('/realtime')
        .setAuth({'token': accessToken})
        .disableAutoConnect()
        .build();
    // Auth as a CALLBACK, not a baked-in map: socket_io_client invokes it on
    // EVERY (re)connect handshake, so after a sleep/network drop longer than
    // the 15-minute access TTL the reconnect goes out with a refreshed JWT
    // instead of looping forever on the expired one (silent realtime death).
    final initialSubject = _jwtSubject(accessToken);
    _SharedRealtimeSocket? handshakeOwner;
    options['auth'] = (dynamic cb) {
      _api.readFreshAccessToken().then((fresh) {
        final candidate = fresh ?? accessToken;
        final freshSubject = _jwtSubject(candidate);
        if (initialSubject != null &&
            freshSubject != null &&
            freshSubject != initialSubject) {
          // A delayed reconnect callback from A must never authenticate with
          // B's freshly stored token. Dispose only its own socket; do not
          // tear down a newer B socket that may already exist.
          final owner = handshakeOwner;
          if (owner != null && identical(_shared, owner)) {
            _shared = null;
            owner.forceDispose();
          }
          (cb as Function)({'token': ''});
          return;
        }
        (cb as Function)({'token': candidate});
      }, onError: (Object _) => (cb as Function)({'token': accessToken}));
    };

    final transport = _transportFactory(origin, options);
    final shared = _SharedRealtimeSocket(
      transport,
      sessionKey: sessionKey,
      onFullyReleased: (s) {
        if (identical(_shared, s)) _shared = null;
      },
    );
    handshakeOwner = shared;
    _shared = shared;
    transport.connect();
    return shared.acquire();
  }
}

class _SharedRealtimeSocket {
  _SharedRealtimeSocket(
    this.transport, {
    required this.sessionKey,
    this.onFullyReleased,
  });

  final MagicRealtimeTransport transport;
  final String sessionKey;
  final void Function(_SharedRealtimeSocket socket)? onFullyReleased;
  int _refCount = 0;
  bool _disposed = false;

  bool get isDisposed => _disposed;

  MagicRealtimeConnection acquire() {
    _refCount++;
    return MagicRealtimeConnection._(this);
  }

  void release() {
    if (_disposed) return;
    _refCount--;
    if (_refCount > 0) return;
    _disposed = true;
    transport.dispose();
    onFullyReleased?.call(this);
  }

  void forceDispose() {
    if (_disposed) return;
    _disposed = true;
    _refCount = 0;
    // Detach all supported listeners before disposing the transport. This also
    // protects in-memory transports: a late A event cannot reach old handlers
    // after account B has logged in.
    for (final event in _magicRealtimeEvents) {
      transport.off(event);
    }
    transport.disconnect();
    transport.dispose();
    onFullyReleased?.call(this);
  }
}

/// A ref-counted view over the (shared) realtime socket. Each view tracks its
/// own event subscriptions, so [dispose] detaches ONLY this consumer's
/// handlers and closes the underlying socket only when it was the last one.
class MagicRealtimeConnection {
  MagicRealtimeConnection._(this._shared);

  /// Wraps a dedicated [transport] as its sole owner — kept for tests and for
  /// call sites that manage their own transport lifecycle.
  MagicRealtimeConnection(MagicRealtimeTransport transport)
    : _shared = _SharedRealtimeSocket(transport, sessionKey: 'dedicated')
        .._refCount = 1;

  final _SharedRealtimeSocket _shared;
  final List<(String, void Function(Object?))> _subscriptions = [];
  bool _released = false;

  void connect() {
    if (!_released && !_shared.isDisposed) _shared.transport.connect();
  }

  /// Closes the socket only when this view is its sole owner — a shared
  /// transport keeps serving the other consumers.
  void disconnect() {
    if (!_released && !_shared.isDisposed && _shared._refCount <= 1) {
      _shared.transport.disconnect();
    }
  }

  void dispose() {
    if (_released) return;
    _released = true;
    for (final (event, handler) in _subscriptions) {
      _shared.transport.off(event, handler);
    }
    _subscriptions.clear();
    _shared.release();
  }

  void joinChat(String chatId) {
    _emit('room.join', {'roomType': 'chat', 'roomId': chatId});
  }

  /// Join a broadcast channel room (e.g. `Объявления`) so `channel.post_created`
  /// events are delivered. The backend authorizes this via channel read access.
  void joinChannel(String channelId) {
    _emit('room.join', {'roomType': 'channel', 'roomId': channelId});
  }

  void joinUserRoom(String userId) {
    _emit('room.join', {'roomType': 'user', 'roomId': userId});
  }

  void leaveRoom(String roomId) {
    _emit('room.leave', {'roomId': roomId});
  }

  void startTyping(String chatId) {
    _emit('typing.start', {'chatId': chatId});
  }

  void stopTyping(String chatId) {
    _emit('typing.stop', {'chatId': chatId});
  }

  void updatePresence({String status = 'online'}) {
    _emit('presence.update', {'status': status});
  }

  void onMessageCreated(MagicRealtimeHandler handler) {
    _onMap('message.created', handler);
  }

  void onMessageUpdated(MagicRealtimeHandler handler) {
    _onMap('message.updated', handler);
  }

  void onChatCreated(MagicRealtimeHandler handler) {
    _onMap('chat.created', handler);
  }

  void onChatRemoved(MagicRealtimeHandler handler) {
    _onMap('chat.removed', handler);
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

  /// Recipient-scoped client-finance invalidation. The payload contains no
  /// financial values; authorized views refetch their commerce projection.
  void onFinanceChanged(MagicRealtimeHandler handler) {
    _onMap('finance.changed', handler);
  }

  /// Access projection invalidation for every active session of this account.
  void onAccessInvalidated(MagicRealtimeHandler handler) {
    _onMap('access.invalidated', handler);
  }

  /// Fires on every (re)connect of the underlying socket. Use it to re-join all
  /// needed rooms after a network drop — Socket.IO restores only the server-side
  /// user/crm rooms, so chat/channel subscriptions must be re-issued by the app.
  void onConnect(void Function() handler) {
    if (_released || _shared.isDisposed) return;
    void wrapped(Object? _) => handler();
    _subscriptions.add(('connect', wrapped));
    _shared.transport.on('connect', wrapped);
  }

  /// Removes THIS view's handlers for [event] (other consumers keep theirs).
  void off(String event) {
    _subscriptions.removeWhere((sub) {
      if (sub.$1 != event) return false;
      _shared.transport.off(event, sub.$2);
      return true;
    });
  }

  void _onMap(String event, MagicRealtimeHandler handler) {
    if (_released || _shared.isDisposed) return;
    void wrapped(Object? payload) {
      final map = _asStringMap(payload);
      if (map != null) handler(map);
    }

    _subscriptions.add((event, wrapped));
    _shared.transport.on(event, wrapped);
  }

  void _emit(String event, Object? payload) {
    if (_released || _shared.isDisposed) return;
    _shared.transport.emit(event, payload);
  }
}

const _magicRealtimeEvents = <String>[
  'connect',
  'message.created',
  'message.updated',
  'chat.created',
  'chat.removed',
  'chat.updated',
  'channel.post_created',
  'typing.start',
  'typing.stop',
  'presence.updated',
  'crm.changed',
  'finance.changed',
  'access.invalidated',
];

String _sessionKeyForAccessToken(String token) {
  final subject = _jwtSubject(token);
  return subject == null ? 'token:$token' : 'sub:$subject';
}

String? _jwtSubject(String token) {
  final parts = token.split('.');
  if (parts.length < 2) return null;
  try {
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    if (payload is! Map) return null;
    final subject = payload['sub']?.toString().trim();
    return subject == null || subject.isEmpty ? null : subject;
  } catch (_) {
    return null;
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
