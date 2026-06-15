import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:magic_music_crm/core/constants/env.dart';
import 'package:magic_music_crm/core/router/app_router.dart';
import 'package:magic_music_crm/core/services/notification_service.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/providers/theme_provider.dart';
import 'package:magic_music_crm/features/auth/providers/magic_auth_provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:syncfusion_localizations/syncfusion_localizations.dart';
import 'package:magic_music_crm/firebase_options.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

final Stopwatch _startupStopwatch = Stopwatch();

Future<void> main() async {
  if (Env.sentryEnabled) {
    await SentryFlutter.init((options) {
      options.dsn = Env.sentryDsn;
      options.environment = Env.sentryEnvironment;
      if (Env.sentryRelease.isNotEmpty) {
        options.release = Env.sentryRelease;
      }
      options.tracesSampleRate = Env.sentryTracesSampleRate;
      options.sendDefaultPii = false;
      options.beforeSend = (event, hint) {
        final apiHost = Uri.tryParse(Env.magicApiBaseUrl)?.host;
        return event.copyWith(
          tags: {
            ...?event.tags,
            if (apiHost != null && apiHost.isNotEmpty) 'api_base_url': apiHost,
          },
        );
      };
    }, appRunner: _bootstrap);
    return;
  }

  await _bootstrap();
}

Future<void> _bootstrap() async {
  _startupStopwatch
    ..reset()
    ..start();
  WidgetsFlutterBinding.ensureInitialized();
  Intl.defaultLocale = 'ru';

  runApp(const ProviderScope(child: MagicMusicApp()));
}

Future<void> _initializeFirebase() async {
  try {
    // Attempt to initialize Firebase with platform-specific options.
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('Firebase initialized successfully');
  } catch (e) {
    debugPrint('Firebase initialization skipped: $e');
    debugPrint(
      'Tip: Run "flutterfire configure" to enable push notifications.',
    );
  }
}

class MagicMusicApp extends ConsumerStatefulWidget {
  const MagicMusicApp({super.key});

  @override
  ConsumerState<MagicMusicApp> createState() => _MagicMusicAppState();
}

class _MagicMusicAppState extends ConsumerState<MagicMusicApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _startupStopwatch.stop();
      Sentry.addBreadcrumb(
        Breadcrumb(
          category: 'app.startup',
          level: SentryLevel.info,
          data: {'firstFrameMs': _startupStopwatch.elapsedMilliseconds},
        ),
      );
      unawaited(
        _initializeRuntimeServices().catchError(
          (e) => debugPrint('Notification service init error: $e'),
        ),
      );
    });
  }

  Future<void> _initializeRuntimeServices() async {
    await initializeDateFormatting('ru', null);
    await _initializeFirebase();
    await ref.read(notificationServiceProvider).setupNotifications();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(magicAuthStateProvider, (previous, next) {
      next.whenData((session) {
        if (session != null) {
          unawaited(
            ref.read(notificationServiceProvider).syncCurrentDeviceToken(),
          );
        }
      });
    });

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
        supportedLocales: const [Locale('ru'), Locale('en')],
        locale: const Locale('ru'),
      ),
    );
  }
}
