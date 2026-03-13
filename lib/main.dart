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
import 'package:magic_music_crm/core/widgets/updater_dialog.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ru', null);
  Intl.defaultLocale = 'ru';


  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('Firebase initialization failed (probably missing config): $e');
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
      ref.read(notificationServiceProvider).initialize().catchError((e) {
        debugPrint('Notification service init error: $e');
      });
      // Removed UpdaterDialog.checkAndShow from here to move it to individual screens
      // where Navigator context is guaranteed.
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Removed UpdaterDialog.checkAndShow from here as well
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'MagicMusic CRM',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      routerConfig: router,
    );
  }
}
