import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:magic_music_crm/core/constants/env.dart';
import 'package:magic_music_crm/core/router/app_router.dart';
import 'package:magic_music_crm/core/update/update_check_gate.dart';
import 'package:magic_music_crm/core/update/update_center.dart';
import 'package:magic_music_crm/core/update/update_prompt.dart';
import 'package:magic_music_crm/core/update/update_provider.dart';
import 'package:magic_music_crm/core/update/windows_update_service.dart';
import 'package:magic_music_crm/core/widgets/auto_dismiss_scaffold_messenger.dart';
import 'package:magic_music_crm/core/services/lead_notification_listener.dart';
import 'package:magic_music_crm/core/services/notification_service.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/features/auth/providers/magic_auth_provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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

  // Warm the API connection during launch. The first TCP/TLS handshake to the
  // server can be slow on a cold network path; firing a throwaway /health hit
  // now (fire-and-forget) means that cost overlaps app startup instead of
  // stalling the first data screen the user opens (e.g. Расписание).
  unawaited(warmApiConnection());

  runApp(const ProviderScope(child: MagicMusicApp()));
}

Future<void> warmApiConnection([Future<void> Function()? probe]) async {
  try {
    if (probe != null) return await probe();
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 20),
      ),
    );
    await dio.get<dynamic>('${Env.magicApiBaseUrl}/health');
    dio.close(force: true);
  } catch (_) {
    // Best-effort warm-up only; never affect launch.
  }
}

/// `https://<api-host>/downloads/latest-v2.json` — the Windows update manifest.
/// Build 143 remains pinned to the legacy manifest because its updater cannot
/// install safely; build 144 is the one-time manual bridge to this v2 channel.
/// served as static files by the same Caddy that fronts the API.
String _windowsUpdateManifestUrl() {
  return windowsUpdateManifestUrlForApi(Env.magicApiBaseUrl);
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
  static const _updatePollingInterval = Duration(minutes: 15);

  final WindowsUpdateCheckGate _updateCheckGate = WindowsUpdateCheckGate();
  Timer? _initialUpdateTimer;
  Timer? _periodicUpdateTimer;
  int? _lastPromptedUpdateBuild;

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
      // The updater keeps its rollback snapshot until this exact first-frame
      // acknowledgement arrives. Do not put network/runtime initialization in
      // front of it: a slow Firebase or notification setup must not trigger a
      // healthy build's 45-second rollback watchdog.
      unawaited(publishWindowsUpdateHealthAckFromEnvironment());
      unawaited(
        _initializeRuntimeServices().catchError(
          (e) => debugPrint('Notification service init error: $e'),
        ),
      );
      // Check shortly after launch. Further checks run while the app remains
      // open, so a release published during the workday does not require a
      // restart before it becomes visible.
      _initialUpdateTimer = Timer(const Duration(seconds: 4), () {
        unawaited(_checkWindowsUpdate(force: true));
      });
      _periodicUpdateTimer = Timer.periodic(_updatePollingInterval, (_) {
        unawaited(_checkWindowsUpdate());
      });
    });
  }

  Future<void> _checkWindowsUpdate({bool force = false}) async {
    await _updateCheckGate.run(() async {
      await checkAndPromptWindowsUpdate(
        navigatorKey: rootNavigatorKey,
        manifestUrl: _windowsUpdateManifestUrl(),
        onUpdateAvailable: (manifest) {
          if (!mounted) return;
          ref.read(availableUpdateProvider.notifier).set(manifest);
        },
        shouldPrompt: (manifest) {
          if (_lastPromptedUpdateBuild == manifest.buildNumber) return false;
          _lastPromptedUpdateBuild = manifest.buildNumber;
          return true;
        },
      );
    }, force: force);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_checkWindowsUpdate());
    }
  }

  Future<void> _initializeRuntimeServices() async {
    await initializeDateFormatting('ru', null);
    await _initializeFirebase();
    await ref.read(notificationServiceProvider).setupNotifications();
  }

  @override
  void dispose() {
    _initialUpdateTimer?.cancel();
    _periodicUpdateTimer?.cancel();
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

    // KVA-240: app-level «new lead» sound notifications for desktop staff.
    // Activated only with a live session so the realtime socket is not opened
    // before login (the listener itself is a no-op outside Windows/Linux).
    if (ref.watch(magicAuthStateProvider).asData?.value != null) {
      ref.watch(leadNotificationListenerProvider);
      // #11: «У вас новая задача» desktop popup for the assignee.
      ref.watch(currentUserIdProvider); // keep the assignee id resolved
      ref.watch(taskNotificationListenerProvider);
    }

    final router = ref.watch(routerProvider);
    final availableUpdate = ref.watch(availableUpdateProvider);

    return ScrollConfiguration(
      behavior: NoGlowScrollBehavior(),
      child: MaterialApp.router(
        title: 'MagicMusic',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.production,
        themeMode: ThemeMode.light,
        routerConfig: router,
        // #16: every ScaffoldMessenger.of() in the app resolves to this
        // messenger, which strips Flutter 3.41's «action ⇒ persist forever»
        // snackbar default so «Занятие отменено/Перенесено» и прочие тосты
        // auto-dismiss again. See AutoDismissScaffoldMessenger.
        builder: (context, child) => AutoDismissScaffoldMessenger(
          child: WindowsUpdateOverlay(
            manifest: availableUpdate,
            navigatorKey: rootNavigatorKey,
            onVersionPressed: () {
              final updateContext = rootNavigatorKey.currentContext;
              if (updateContext == null) return;
              unawaited(
                showUpdatesCenter(
                  updateContext,
                  onInstall: (update) =>
                      showWindowsUpdateDialog(updateContext, update),
                ),
              );
            },
            child: child ?? const SizedBox.shrink(),
          ),
        ),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('ru'), Locale('en')],
        locale: const Locale('ru'),
      ),
    );
  }
}
