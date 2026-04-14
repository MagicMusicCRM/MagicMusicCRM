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
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:magic_music_crm/core/providers/chat_providers.dart';

// Background message handler — runs in a separate isolate
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  
  debugPrint("BG-HANDLER: messageId=${message.messageId}");
  debugPrint("BG-HANDLER: notification=${message.notification?.title}");
  debugPrint("BG-HANDLER: data=${message.data}");

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
    'High Importance Notifications',
    description: 'This channel is used for important notifications.',
    importance: Importance.max,
    playSound: true,
  );

  final localNotifications = FlutterLocalNotificationsPlugin();

  // CRITICAL: Must initialize the plugin before calling show()
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosSettings = DarwinInitializationSettings();
  const initSettings = InitializationSettings(android: androidSettings, iOS: iosSettings);
  await localNotifications.initialize(initSettings);

  // Create the channel (required on Android 8+)
  final androidImpl = localNotifications.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  if (androidImpl != null) {
    await androidImpl.createNotificationChannel(channel);
  }

  // Encode payload as JSON for proper parsing on click
  final payloadStr = data != null ? jsonEncode(data) : null;

  await localNotifications.show(
    DateTime.now().millisecondsSinceEpoch ~/ 1000,
    title,
    body,
    NotificationDetails(
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
      throw UnsupportedError('Firebase Messaging is not supported on this platform');
    }
    return FirebaseMessaging.instance;
  }
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'high_importance_channel',
    'High Importance Notifications',
    description: 'This channel is used for important notifications.',
    importance: Importance.max,
    playSound: true,
  );

  Future<void> setupNotifications() async {
    // 1. Desktop custom notification setup
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
      try {
        await localNotifier.setup(appName: 'Magic Music CRM', shortcutPolicy: ShortcutPolicy.requireCreate);
        _listenToDesktopMessages();
      } catch (e) {
        debugPrint('Error setting up local_notifier $e');
      }
      return; // Firebase messaging doesn't support Windows/Linux out of the box
    }

    if (Firebase.apps.isEmpty) {
      debugPrint('Firebase is not initialized. Notifications disabled.');
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
    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
    );
    
    await _localNotifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onLocalNotificationClick,
    );

    // Create notification channel (required on Android 8+)
    final androidImplementation = _localNotifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
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
      debugPrint('User granted permission');
    } else if (settings.authorizationStatus == AuthorizationStatus.provisional) {
      debugPrint('User granted provisional permission');
    } else {
      debugPrint('User declined or has not accepted permission');
    }

    // ── ALWAYS register click handlers (even without FCM token) ──────────

    // Handle when app is opened from a notification (background → foreground)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('📩 onMessageOpenedApp: ${message.data}');
      _handleNotificationClick(message.data);
    });

    // Handle when app is started from a notification (terminated → start)
    _firebaseMessaging.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        debugPrint('📩 getInitialMessage: ${message.data}');
        // Delay slightly to ensure providers and screens are ready
        Future.delayed(const Duration(milliseconds: 800), () {
          _handleNotificationClick(message.data);
        });
      }
    });

    // ── FCM Token management ──────────────────────────────────────────────

    String? token = await _firebaseMessaging.getToken();
    if (token != null) {
      _saveTokenToDatabase(token);
      _firebaseMessaging.onTokenRefresh.listen(_saveTokenToDatabase);
    }

    // ── Foreground message handling ───────────────────────────────────────

    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      debugPrint('📩 Foreground message: ${message.data}');

      final notification = message.notification;
      final title = notification?.title ?? message.data['title'] ?? 'Новое сообщение';
      final body = notification?.body ?? message.data['body'] ?? '';

      // Encode data as JSON payload so we can parse it on click
      final payloadStr = jsonEncode(message.data);

      await _localNotifications.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channel.id,
            _channel.name,
            channelDescription: _channel.description,
            icon: '@mipmap/ic_launcher',
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: payloadStr,
      );
    });
  }

  /// Called when user clicks a local notification (foreground or background-shown)
  void _onLocalNotificationClick(NotificationResponse response) {
    debugPrint('📩 Local notification clicked, payload: ${response.payload}');
    if (response.payload == null || response.payload!.isEmpty) return;

    try {
      final data = jsonDecode(response.payload!) as Map<String, dynamic>;
      _handleNotificationClick(data);
    } catch (e) {
      debugPrint('Error parsing notification payload: $e');
    }
  }

  /// Core navigation handler — extracts chat metadata and triggers UI navigation
  void _handleNotificationClick(Map<String, dynamic> data) {
    debugPrint('🎯 NOTIFICATION CLICK: $data');
    
    final senderId = data['sender_id']?.toString();
    final chatId = data['chat_id']?.toString();
    final receiverId = data['receiver_id']?.toString();

    // For direct chats: navigate to partner (sender)
    // For group chats: navigate by chat_id  
    final targetPartnerId = senderId ?? receiverId;
    
    debugPrint('🎯 Navigating to partner=$targetPartnerId, group=$chatId');
    
    ref.read(messengerNavigationProvider.notifier).navigateTo(
      MessengerNavigationState(
        partnerId: targetPartnerId,
        groupChatId: chatId,
      ),
    );
  }

  Future<void> _saveTokenToDatabase(String? token) async {
    if (token == null) return;
    
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      try {
        await Supabase.instance.client
            .from('profiles')
            .update({'fcm_token': token})
            .eq('id', user.id);
        debugPrint('FCM Token saved to database');
      } catch (e) {
        debugPrint('Error saving FCM token: $e');
      }
    }
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
