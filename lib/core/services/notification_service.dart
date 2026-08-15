import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/providers/chat_providers.dart';
import 'package:magic_music_crm/core/services/magic_notifications_service.dart';
import 'package:magic_music_crm/firebase_options.dart';
import 'package:magic_music_crm/core/services/alert_policy.dart';
import 'package:magic_music_crm/core/services/alert_sound_service.dart';

void _logNotification(String message) {
  if (kDebugMode) {
    debugPrint(message);
  }
}

// Background message handler — runs in a separate isolate
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  _logNotification(
    'Background notification received: hasNotification=${message.notification != null}',
  );

  // If this is a data-only message (no notification field), show it manually.
  // Messages WITH notification field are shown automatically by Android.
  if (message.notification == null && message.data.containsKey('title')) {
    await _showBackgroundNotification(
      title: message.data['title'] ?? 'Новое сообщение',
      body: message.data['body'] ?? '',
      data: message.data,
    );
  }
}

/// Show a local notification from the background isolate.
/// Must create and initialize a fresh plugin instance since we're in a separate isolate.
Future<void> _showBackgroundNotification({
  required String title,
  required String body,
  Map<String, dynamic>? data,
}) async {
  const channel = AndroidNotificationChannel(
    'high_importance_channel',
    'Важные уведомления',
    description: 'Важные уведомления Magic Music.',
    importance: Importance.max,
    playSound: true,
  );

  final localNotifications = FlutterLocalNotificationsPlugin();

  // CRITICAL: Must initialize the plugin before calling show()
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosSettings = DarwinInitializationSettings();
  const initSettings = InitializationSettings(
    android: androidSettings,
    iOS: iosSettings,
  );
  await localNotifications.initialize(settings: initSettings);

  // Create the channel (required on Android 8+)
  final androidImpl = localNotifications
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();
  if (androidImpl != null) {
    await androidImpl.createNotificationChannel(channel);
  }

  // Encode payload as JSON for proper parsing on click
  final payloadStr = data != null ? jsonEncode(data) : null;

  await localNotifications.show(
    id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    title: title,
    body: body,
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        channel.id,
        channel.name,
        channelDescription: channel.description,
        importance: Importance.max,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
      iOS: const DarwinNotificationDetails(),
    ),
    payload: payloadStr,
  );
}

final notificationServiceProvider = Provider((ref) => NotificationService(ref));

class NotificationService {
  final Ref ref;
  NotificationService(this.ref);

  FirebaseMessaging get _firebaseMessaging {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
      throw UnsupportedError(
        'Firebase Messaging is not supported on this platform',
      );
    }
    return FirebaseMessaging.instance;
  }

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  StreamSubscription<String>? _tokenRefreshSubscription;

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'high_importance_channel',
    'Важные уведомления',
    description: 'Важные уведомления Magic Music.',
    importance: Importance.max,
    playSound: true,
  );

  Future<void> setupNotifications() async {
    // 1. Desktop custom notification setup
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
      try {
        await localNotifier.setup(
          appName: 'Magic Music',
          shortcutPolicy: ShortcutPolicy.requireCreate,
        );
        _listenToDesktopMessages();
      } catch (e) {
        _logNotification('Error setting up local_notifier $e');
      }
      return; // Firebase messaging doesn't support Windows/Linux out of the box
    }

    if (Firebase.apps.isEmpty) {
      _logNotification('Firebase is not initialized. Notifications disabled.');
      return;
    }

    // Register background handler
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Initialize local notifications with click handler
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
          requestSoundPermission: true,
          requestBadgePermission: true,
          requestAlertPermission: true,
        );
    const InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsDarwin,
        );

    await _localNotifications.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: _onLocalNotificationClick,
    );

    // Create notification channel (required on Android 8+)
    final androidImplementation = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidImplementation != null) {
      await androidImplementation.createNotificationChannel(_channel);
    }

    // iOS foreground presentation
    await _firebaseMessaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // Request permissions for Android 13+
    if (Platform.isAndroid) {
      final status = await Permission.notification.status;
      if (status.isDenied) {
        await Permission.notification.request();
      }
    }

    // Request FCM permissions (also handles iOS)
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      _logNotification('User granted permission');
    } else if (settings.authorizationStatus ==
        AuthorizationStatus.provisional) {
      _logNotification('User granted provisional permission');
    } else {
      _logNotification('User declined or has not accepted permission');
    }

    // ── ALWAYS register click handlers (even without FCM token) ──────────

    // Handle when app is opened from a notification (background → foreground)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _logNotification('Notification opened.');
      _handleNotificationClick(message.data);
    });

    // Handle when app is started from a notification (terminated → start)
    _firebaseMessaging.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        _logNotification('Initial notification opened.');
        scheduleMicrotask(() {
          _handleNotificationClick(message.data);
        });
      }
    });

    // ── FCM Token management ──────────────────────────────────────────────

    _attachTokenRefreshListener();
    await syncCurrentDeviceToken();

    // ── Foreground message handling ───────────────────────────────────────

    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      _logNotification('Foreground notification received.');
      // The user is already looking at the app, so it plays its own tone and
      // does NOT raise a notification banner: a banner over the open app is
      // noise, and it would sound the system tone on top of ours. Backgrounded,
      // the system shows the push with the system sound instead — see
      // firebaseMessagingBackgroundHandler.
      //
      // ✔ Заказчик 17.07: молчим про то, на что человек смотрит. Push несёт
      // `entityType` (см. notifications.service.ts) — по нему и определяем
      // раздел. Событие без entityType озвучиваем: пропустить настоящее
      // уведомление хуже, чем звякнуть лишний раз.
      final entityType = message.data['entityType']?.toString();
      final chatId = message.data['chatId']?.toString();
      if (!shouldSoundFor(
        view: ref.read(activeViewProvider),
        section: sectionForEntity(entityType),
        chatId: chatId,
      )) {
        _logNotification('Sound suppressed: user is already on that section.');
        return;
      }
      await ref.read(alertSoundServiceProvider).play();
    });
  }

  Future<void> syncCurrentDeviceToken() async {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
      return;
    }
    if (Firebase.apps.isEmpty) {
      _logNotification(
        'Firebase is not initialized. Device token sync skipped.',
      );
      return;
    }

    try {
      final token = await _firebaseMessaging.getToken();
      if (token == null || token.isEmpty) {
        _logNotification('FCM token sync skipped: token is empty.');
        return;
      }
      await _saveTokenToDatabase(token);
    } catch (e) {
      _logNotification('Error syncing FCM token: $e');
    }
  }

  /// Called when user clicks a local notification (foreground or background-shown)
  void _onLocalNotificationClick(NotificationResponse response) {
    _logNotification('Local notification clicked.');
    if (response.payload == null || response.payload!.isEmpty) return;

    try {
      final data = jsonDecode(response.payload!) as Map<String, dynamic>;
      _handleNotificationClick(data);
    } catch (e) {
      _logNotification('Error parsing notification payload: $e');
    }
  }

  /// Core navigation handler — extracts chat metadata and triggers UI navigation
  void _handleNotificationClick(Map<String, dynamic> data) {
    final senderId = data['sender_id']?.toString();
    final chatId = data['chat_id']?.toString();
    final receiverId = data['receiver_id']?.toString();

    // For direct chats: navigate to partner (sender)
    // For group chats: navigate by chat_id
    final targetPartnerId = senderId ?? receiverId;

    _logNotification(
      'Notification navigation: hasPartner=${targetPartnerId != null}, hasChat=${chatId != null}',
    );

    ref
        .read(messengerNavigationProvider.notifier)
        .navigateTo(
          MessengerNavigationState(
            partnerId: targetPartnerId,
            groupChatId: chatId,
          ),
        );
  }

  Future<void> _saveTokenToDatabase(String? token) async {
    if (token == null) return;
    try {
      final api = ref.read(magicApiClientProvider);
      final tokens = await api.readTokens();
      if (tokens?.accessToken.isNotEmpty != true) {
        _logNotification('FCM token registration skipped: no v3 session.');
        return;
      }
      await ref
          .read(magicNotificationsServiceProvider)
          .registerDevice(token: token, platform: _platformName);
      _logNotification('FCM token registered through v3 API.');
    } catch (e) {
      _logNotification('Error registering FCM token: $e');
    }
  }

  void _attachTokenRefreshListener() {
    _tokenRefreshSubscription ??= _firebaseMessaging.onTokenRefresh.listen((
      refreshedToken,
    ) {
      unawaited(_saveTokenToDatabase(refreshedToken));
    });
  }

  String get _platformName {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  void _listenToDesktopMessages() {
    // This is for local_notifier on Windows/Linux
    // Custom implementation depends on how you want to show it
  }

  /// Static method kept for backward compatibility, now properly initializes plugin.
  static Future<void> showLocalNotification({
    required String title,
    required String body,
    Map<String, dynamic>? payload,
  }) async {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
      LocalNotification notification = LocalNotification(
        title: title,
        body: body,
      );
      notification.show();
    } else {
      await _showBackgroundNotification(
        title: title,
        body: body,
        data: payload,
      );
    }
  }
}
