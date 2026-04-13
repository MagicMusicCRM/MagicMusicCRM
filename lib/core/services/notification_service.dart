import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Background message handler
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint("Handling a background message: ${message.messageId}");
}

final notificationServiceProvider = Provider((ref) => NotificationService());

class NotificationService {
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

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Initialize local notifications
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
    
    // Use named argument settings as required by the library
    await _localNotifications.initialize(settings: initializationSettings);

    final androidImplementation = _localNotifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidImplementation != null) {
      await androidImplementation.createNotificationChannel(_channel);
    }

    // iOS and Web
    await _firebaseMessaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // Request permissions for iOS
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

    // Get the token each time the application loads
    String? token = await _firebaseMessaging.getToken();
    if (token != null) {
      _saveTokenToDatabase(token);

      // Any time the token refreshes, store this in the database too.
      _firebaseMessaging.onTokenRefresh.listen(_saveTokenToDatabase);

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
        debugPrint('Got a message whilst in the foreground!');
        debugPrint('Message data: ${message.data}');

        RemoteNotification? notification = message.notification;

        if (notification != null) {
          debugPrint('Message also contained a notification: ${notification.title}');
          
          await _localNotifications.show(
            id: notification.hashCode,
            title: notification.title,
            body: notification.body,
            notificationDetails: NotificationDetails(
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
          );
        }
      });
      
      // Handle when app is opened from a notification (background state)
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('A new onMessageOpenedApp event was published!');
        debugPrint('Message data: ${message.data}');
      });
    }
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

  Future<void> showLocalNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
      LocalNotification notification = LocalNotification(
        title: title,
        body: body,
      );
      notification.show();
    } else {
      await _localNotifications.show(
        id: 0,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channel.id,
            _channel.name,
            channelDescription: _channel.description,
            importance: Importance.max,
            priority: Priority.high,
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        payload: payload,
      );
    }
  }
}
