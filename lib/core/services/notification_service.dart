import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Top-level background message handler for FCM
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // If you're going to use other Firebase services in the background,
  // make sure you call `initializeApp` before using other Firebase services.
  debugPrint("Handling a background message: ${message.messageId}");
}

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService();
});

class NotificationService {
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;

  Future<void> initialize() async {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Request permissions for iOS and web
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    debugPrint('User granted permission: ${settings.authorizationStatus}');

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      // Get the token each time the application loads
      String? token = await _firebaseMessaging.getToken();
      debugPrint('FCM Token: $token');

      // Save the initial token to the database
      _saveTokenToDatabase(token);

      // Any time the token refreshes, store this in the database too.
      _firebaseMessaging.onTokenRefresh.listen(_saveTokenToDatabase);

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('Got a message whilst in the foreground!');
        debugPrint('Message data: ${message.data}');

        if (message.notification != null) {
          debugPrint('Message also contained a notification: ${message.notification?.title}');
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
    
    // Save token to Supabase for the current user once authenticated
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user != null) {
      try {
        await supabase.from('fcm_tokens').upsert({
          'user_id': user.id,
          'token': token,
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'token');
        debugPrint('FCM token saved to database.');
      } catch (e) {
        debugPrint('Error saving FCM token: $e');
      }
    }
  }
  Future<void> sendNotification({
    required String userId,
    required String templateName,
    Map<String, String>? variables,
  }) async {
    final supabase = Supabase.instance.client;
    
    try {
      // 1. Fetch template
      final templateRes = await supabase
          .from('notification_templates')
          .select()
          .eq('name', templateName)
          .maybeSingle();
      
      if (templateRes == null) {
        debugPrint('Notification template not found: $templateName');
        return;
      }

      // 2. Perform variable replacement (simple string replacement for MVP)
      String title = templateRes['title_template'];
      String body = templateRes['body_template'];
      
      variables?.forEach((key, value) {
        title = title.replaceAll('{{$key}}', value);
        body = body.replaceAll('{{$key}}', value);
      });

      // 3. Record the notification in a queue (or send immediately via edge function)
      // For now, we simulate by logging and could insert into a 'notifications_queue' table
      debugPrint('Sending notification to $userId: $title - $body');
      
      // await supabase.from('notifications_log').insert({
      //   'user_id': userId,
      //   'title': title,
      //   'body': body,
      //   'status': 'sent',
      // });

    } catch (e) {
      debugPrint('Error sending notification: $e');
    }
  }
}
