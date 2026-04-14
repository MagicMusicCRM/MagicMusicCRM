import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:magic_music_crm/core/constants/env.dart';
import 'package:magic_music_crm/core/router/app_router.dart';
import 'package:magic_music_crm/core/services/notification_service.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/providers/theme_provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:syncfusion_localizations/syncfusion_localizations.dart';
import 'package:app_links/app_links.dart';
import 'package:magic_music_crm/firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ru', null);
  Intl.defaultLocale = 'ru';

  try {
    // Attempt to initialize Firebase with platform-specific options.
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('Firebase initialized successfully');
  } catch (e) {
    debugPrint('Firebase initialization skipped: $e');
    debugPrint('Tip: Run "flutterfire configure" to enable push notifications.');
  }

  await Supabase.initialize(
    url: Env.supabaseUrl,
    anonKey: Env.supabaseAnonKey,
  );

  runApp(
    const ProviderScope(
      child: MagicMusicApp(),
    ),
  );
}

class MagicMusicApp extends ConsumerStatefulWidget {
  const MagicMusicApp({super.key});

  @override
  ConsumerState<MagicMusicApp> createState() => _MagicMusicAppState();
}

class _MagicMusicAppState extends ConsumerState<MagicMusicApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _initDeepLinks();
      ref.read(notificationServiceProvider).setupNotifications().catchError((e) {
        debugPrint('Notification service init error: $e');
      });
    });
  }

  void _initDeepLinks() {
    final appLinks = AppLinks();
    
    // Handle initial link (if the app was started by a link)
    appLinks.getInitialLink().then((uri) {
      if (uri != null) _handleAuthLink(uri);
    });

    // Handle subsequent links (if the app is already running)
    appLinks.uriLinkStream.listen((uri) {
      _handleAuthLink(uri);
    });
  }

  void _handleAuthLink(Uri uri) {
    debugPrint('Received deep link: $uri');
    if (uri.scheme == 'magiccrm') {
      Supabase.instance.client.auth.getSessionFromUrl(uri);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);

    return ScrollConfiguration(
      behavior: NoGlowScrollBehavior(),
      child: MaterialApp.router(
        title: 'MagicMusic',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: themeMode,
        routerConfig: router,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          SfGlobalLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('ru'),
          Locale('en'),
        ],
        locale: const Locale('ru'),
      ),
    );
  }
}
