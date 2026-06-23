import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/v7/magic_shimmer.dart';
import 'package:magic_music_crm/features/auth/presentation/screens/login_screen.dart';
import 'package:magic_music_crm/features/auth/presentation/screens/registration_screen.dart';
import 'package:magic_music_crm/features/auth/presentation/screens/onboarding_screen.dart';
import 'package:magic_music_crm/features/auth/presentation/screens/legal_consent_screen.dart';
import 'package:magic_music_crm/features/auth/data/models/release_gate_models.dart';
import 'package:magic_music_crm/features/auth/data/services/magic_auth_service.dart';
import 'package:magic_music_crm/features/auth/providers/magic_auth_provider.dart';
import 'package:magic_music_crm/features/auth/providers/release_gate_provider.dart';
import 'package:magic_music_crm/features/client/presentation/screens/client_dashboard_screen.dart';
import 'package:magic_music_crm/features/admin/presentation/screens/admin_dashboard_screen.dart';
import 'package:magic_music_crm/features/teacher/presentation/screens/teacher_dashboard_screen.dart';
import 'package:magic_music_crm/features/manager/presentation/screens/manager_dashboard_screen.dart';
import 'package:magic_music_crm/features/admin/presentation/screens/student_detail_screen.dart';
import 'package:magic_music_crm/features/admin/presentation/screens/profile_detail_screen.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_attendance_dialog.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/lead_detail_dialog.dart';
import 'package:magic_music_crm/features/manager/presentation/providers/leads_providers.dart';
import 'package:magic_music_crm/core/models/types.dart';
import 'package:magic_music_crm/core/utils/status_color.dart';
import 'package:magic_music_crm/features/profile/presentation/screens/profile_screen.dart';
import 'package:magic_music_crm/features/profile/presentation/screens/account_deletion_screen.dart';
import 'package:magic_music_crm/features/profile/presentation/screens/account_deletion_status_screen.dart';
import 'package:magic_music_crm/features/profile/presentation/screens/auth_methods_screen.dart';
import 'package:magic_music_crm/features/auth/presentation/screens/email_otp_screen.dart';
import 'package:magic_music_crm/features/auth/presentation/screens/password_reset_screen.dart';

String _roleToRoute(String role) {
  switch (role) {
    case 'system_admin':
    case 'admin':
      return '/admin';
    case 'manager':
      return '/manager';
    case 'teacher':
      return '/teacher';
    default:
      return '/client';
  }
}

enum _RouteGatePhase { authLoading, signedOut, gateLoading, gateError, ready }

class _RouteGateState {
  final _RouteGatePhase phase;
  final ReleaseGateStatus? gateStatus;
  final Object? error;

  const _RouteGateState._(this.phase, {this.gateStatus, this.error});

  const _RouteGateState.authLoading() : this._(_RouteGatePhase.authLoading);

  const _RouteGateState.signedOut() : this._(_RouteGatePhase.signedOut);

  const _RouteGateState.gateLoading() : this._(_RouteGatePhase.gateLoading);

  const _RouteGateState.gateError(Object error)
    : this._(_RouteGatePhase.gateError, error: error);

  const _RouteGateState.ready(ReleaseGateStatus gateStatus)
    : this._(_RouteGatePhase.ready, gateStatus: gateStatus);
}

final _routeGateStateProvider = Provider<_RouteGateState>((ref) {
  final authState = ref.watch(magicAuthStateProvider);
  final currentSession = authState.asData?.value;

  if (authState.isLoading && currentSession == null) {
    return const _RouteGateState.authLoading();
  }
  if (authState.hasError || currentSession == null) {
    return const _RouteGateState.signedOut();
  }

  final gateState = ref.watch(releaseGateStatusProvider);
  return gateState.when(
    data: _RouteGateState.ready,
    error: (error, _) => _RouteGateState.gateError(error),
    loading: () => const _RouteGateState.gateLoading(),
  );
});

bool _isUnauthorizedRouteError(Object? error) {
  return error is MagicApiException && error.isUnauthorized;
}

// ── Router ───────────────────────────────────────────────────────────────────
final routerProvider = Provider<GoRouter>((ref) {
  final routerRefreshNotifier = ValueNotifier<int>(0);
  ref.onDispose(routerRefreshNotifier.dispose);

  void refreshRouter() {
    routerRefreshNotifier.value++;
  }

  ref.listen<AsyncValue<MagicAuthSession?>>(magicAuthStateProvider, (
    previous,
    next,
  ) {
    final previousAccessToken = previous?.asData?.value?.accessToken;
    final nextAccessToken = next.asData?.value?.accessToken;
    if (previousAccessToken != nextAccessToken) {
      ref.invalidate(releaseGateStatusProvider);
    }
    refreshRouter();
  });

  ref.listen<_RouteGateState>(_routeGateStateProvider, (_, _) {
    refreshRouter();
  });

  ref.listen<_RouteGateState>(_routeGateStateProvider, (_, next) {
    if (next.phase == _RouteGatePhase.gateError &&
        _isUnauthorizedRouteError(next.error)) {
      unawaited(ref.read(magicAuthServiceProvider).signOut());
    }
  });

  return GoRouter(
    initialLocation: '/',
    refreshListenable: routerRefreshNotifier,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final isAuthRoute =
          loc == '/login' ||
          loc == '/register' ||
          loc == '/email-otp' ||
          loc == '/password-reset';

      final isGateRoute =
          loc == '/onboarding' ||
          loc == '/legal-consent' ||
          loc == '/account-deletion-status';

      final routeGateState = ref.read(_routeGateStateProvider);
      switch (routeGateState.phase) {
        case _RouteGatePhase.authLoading:
        case _RouteGatePhase.gateLoading:
          return loc == '/' ? null : '/';
        case _RouteGatePhase.signedOut:
          return isAuthRoute ? null : '/login';
        case _RouteGatePhase.gateError:
          if (_isUnauthorizedRouteError(routeGateState.error)) {
            return isAuthRoute ? null : '/login';
          }
          return loc == '/' ? null : '/';
        case _RouteGatePhase.ready:
          break;
      }

      final gateStatus = routeGateState.gateStatus!;
      final role = gateStatus.role.isEmpty ? 'client' : gateStatus.role;
      final roleRoute = _roleToRoute(role);

      if (gateStatus.deletionPending) {
        return loc == '/account-deletion-status'
            ? null
            : '/account-deletion-status';
      }

      if (!gateStatus.profileComplete) {
        return loc == '/onboarding' ? null : '/onboarding';
      }

      if (!gateStatus.legalAccepted) {
        return loc == '/legal-consent' ? null : '/legal-consent';
      }

      if (isGateRoute) {
        return roleRoute;
      }

      if (isAuthRoute || loc == '/') {
        return roleRoute;
      }

      // Proactive role-path enforcement.
      // `/admin/profiles/:id` (the shared user card) is opened from the
      // manager CRM (user-roles + tasks widgets), so it is exempt from the
      // admin-dashboard gate — managers reach it legitimately. The server
      // still authorizes the underlying profile fetch.
      if (loc.startsWith('/admin') &&
          !loc.startsWith('/admin/profiles/') &&
          role != 'admin' &&
          role != 'system_admin') {
        return roleRoute;
      }
      if (loc.startsWith('/manager') && role != 'manager') return roleRoute;
      if (loc.startsWith('/teacher') && role != 'teacher') return roleRoute;
      if (loc.startsWith('/client') && role != 'client') return roleRoute;

      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const _AppGateLoadingScreen(),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegistrationScreen(),
      ),
      GoRoute(
        path: '/email-otp',
        builder: (context, state) {
          final extra = state.extra;
          final data = extra is EmailOtpRouteData
              ? extra
              : EmailOtpRouteData(
                  email: extra is String ? extra : '',
                  purpose: EmailOtpPurpose.passwordMfa,
                );
          return EmailOtpScreen(data: data);
        },
      ),
      GoRoute(
        path: '/password-reset',
        builder: (context, state) => const PasswordResetScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/legal-consent',
        builder: (context, state) => const LegalConsentScreen(),
      ),
      GoRoute(
        path: '/legal-documents',
        builder: (context, state) =>
            const LegalConsentScreen(requireAcceptance: false),
      ),
      GoRoute(
        path: '/account-deletion-status',
        builder: (context, state) => const AccountDeletionStatusScreen(),
      ),
      GoRoute(
        path: '/client',
        builder: (context, state) => const ClientDashboardScreen(),
      ),
      GoRoute(
        path: '/admin',
        builder: (context, state) => const AdminDashboardScreen(),
      ),
      GoRoute(
        path: '/teacher',
        builder: (context, state) => const TeacherDashboardScreen(),
      ),
      GoRoute(
        path: '/manager',
        builder: (context, state) => const ManagerDashboardScreen(),
      ),
      GoRoute(
        path: '/student/:id',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return StudentDetailScreen(studentId: id);
        },
      ),
      GoRoute(
        path: '/admin/profiles/:id',
        builder: (context, state) =>
            ProfileDetailScreen(profileId: state.pathParameters['id']!),
      ),
      // ── Deep links (KVA-196) ────────────────────────────────────────────────
      // Open a lead/student/lesson directly by id. Students reuse the existing
      // rich detail screen; leads/lessons present their existing dialogs (the
      // KVA-175 pattern) over the active role dashboard via a thin host screen.
      GoRoute(
        path: '/students/:id',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return StudentDetailScreen(studentId: id);
        },
      ),
      GoRoute(
        path: '/leads/:id',
        builder: (context, state) =>
            _LeadDeepLinkScreen(leadId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/lessons/:id',
        builder: (context, state) =>
            _LessonDeepLinkScreen(lessonId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/profile',
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: '/auth-methods',
        builder: (context, state) => const AuthMethodsScreen(),
      ),
      GoRoute(
        path: '/delete-account',
        builder: (context, state) => const AccountDeletionScreen(),
      ),
    ],
  );
});

class _AppGateLoadingScreen extends ConsumerWidget {
  const _AppGateLoadingScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gateState = ref.watch(_routeGateStateProvider);
    final isGateError =
        gateState.phase == _RouteGatePhase.gateError &&
        !_isUnauthorizedRouteError(gateState.error);

    return Scaffold(
      backgroundColor: AppColor.bg,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0.0, -1.0),
            radius: 1.1,
            colors: [Color(0x1AC5A059), AppColor.bg],
            stops: [0.0, 0.6],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.xxl,
                  vertical: 30,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Brand block (v7 — copied 1:1 from the login screen)
                    Column(
                      children: [
                        Container(
                          width: 62,
                          height: 62,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF2A2418), Color(0xFF1D1A12)],
                            ),
                            border: Border.all(color: AppColor.goldLine),
                          ),
                          child: const Icon(
                            Icons.music_note_rounded,
                            color: AppColor.gold,
                            size: 30,
                          ),
                        ),
                        const SizedBox(height: AppSpace.md),
                        RichText(
                          textAlign: TextAlign.center,
                          text: const TextSpan(
                            children: [
                              TextSpan(
                                text: 'Magic',
                                style: TextStyle(
                                  color: AppColor.text,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 21,
                                  letterSpacing: -0.4,
                                ),
                              ),
                              TextSpan(
                                text: 'Music',
                                style: TextStyle(
                                  color: AppColor.gold,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 21,
                                  letterSpacing: -0.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpace.xs),
                        Text(
                          isGateError
                              ? 'Не удалось проверить доступ'
                              : 'Проверяем сессию и доступ',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColor.text2,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpace.xxl),

                    if (isGateError) ...[
                      Text(
                        gateState.error?.toString() ??
                            'Проверьте подключение и попробуйте снова.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColor.text2,
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(height: AppSpace.xxl),
                      // Flat gold retry button (no shadow, radius AppRadius.control)
                      SizedBox(
                        height: 52,
                        width: double.infinity,
                        child: Material(
                          color: AppColor.gold,
                          borderRadius: BorderRadius.circular(
                            AppRadius.control,
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(
                              AppRadius.control,
                            ),
                            onTap: () =>
                                ref.invalidate(releaseGateStatusProvider),
                            child: const Center(
                              child: Text(
                                'Повторить',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: AppColor.onGold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpace.md),
                      // 'Выйти' as a gold text link
                      TextButton(
                        onPressed: () =>
                            ref.read(magicAuthServiceProvider).signOut(),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColor.gold,
                          textStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          padding: const EdgeInsets.all(AppSpace.sm),
                          minimumSize: const Size(0, 0),
                        ),
                        child: const Text('Выйти'),
                      ),
                    ] else ...[
                      // Boot affordance — v7 skeleton shimmer lines.
                      const SkeletonBox(
                        height: 12,
                        radius: AppRadius.sm,
                      ),
                      const SizedBox(height: AppSpace.md),
                      const SkeletonBox(
                        height: 12,
                        radius: AppRadius.sm,
                      ),
                      const SizedBox(height: AppSpace.md),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: SizedBox(
                          width: 160,
                          child: SkeletonBox(
                            height: 12,
                            radius: AppRadius.sm,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Destination to return to once a deep-linked dialog closes — the active
/// role dashboard, derived from the (already-loaded) release-gate status so the
/// back stack lands on a real screen instead of the boot loader.
String _deepLinkHomeRoute(WidgetRef ref) {
  final gate = ref.read(_routeGateStateProvider).gateStatus;
  final role = (gate == null || gate.role.isEmpty) ? 'client' : gate.role;
  return _roleToRoute(role);
}

/// Lightweight host that presents the existing [LeadDetailDialog] for a lead
/// opened by id (deep link). The dialog self-fetches its full data from the
/// minimal `{'id': …}` stub (the KVA-175 pattern); we only pre-resolve the
/// status list so the status chips render immediately.
class _LeadDeepLinkScreen extends ConsumerStatefulWidget {
  const _LeadDeepLinkScreen({required this.leadId});

  final String leadId;

  @override
  ConsumerState<_LeadDeepLinkScreen> createState() =>
      _LeadDeepLinkScreenState();
}

class _LeadDeepLinkScreenState extends ConsumerState<_LeadDeepLinkScreen> {
  bool _opened = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  Future<void> _open() async {
    if (_opened || !mounted) return;
    _opened = true;

    final statuses = <StatusRecord>[];
    try {
      final raw = await ref.read(leadStatusesProvider.future);
      for (final r in raw) {
        statuses.add((
          r['key'].toString(),
          r['label'].toString(),
          statusColorFromValue(r['color']),
        ));
      }
    } catch (_) {
      // Dialog still opens; it fetches its own data.
    }
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (_) => LeadDetailDialog(
        lead: <String, dynamic>{'id': widget.leadId},
        allStatuses: statuses,
      ),
    );

    if (!mounted) return;
    context.go(_deepLinkHomeRoute(ref));
  }

  @override
  Widget build(BuildContext context) => const _DeepLinkScaffold();
}

/// Lightweight host that presents the existing [LessonAttendanceDialog] for a
/// lesson opened by id (deep link). The sheet self-fetches attendance from the
/// minimal `{'id': …}` stub.
class _LessonDeepLinkScreen extends ConsumerStatefulWidget {
  const _LessonDeepLinkScreen({required this.lessonId});

  final String lessonId;

  @override
  ConsumerState<_LessonDeepLinkScreen> createState() =>
      _LessonDeepLinkScreenState();
}

class _LessonDeepLinkScreenState extends ConsumerState<_LessonDeepLinkScreen> {
  bool _opened = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  Future<void> _open() async {
    if (_opened || !mounted) return;
    _opened = true;

    await LessonAttendanceDialog.show(context, <String, dynamic>{
      'id': widget.lessonId,
    });

    if (!mounted) return;
    context.go(_deepLinkHomeRoute(ref));
  }

  @override
  Widget build(BuildContext context) => const _DeepLinkScaffold();
}

/// Theme-aware placeholder shown behind a deep-linked dialog while it resolves.
/// Surfaces follow the app theme; the boot affordance is a v7 skeleton row.
class _DeepLinkScaffold extends StatelessWidget {
  const _DeepLinkScaffold();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: const [
                  SkeletonBox(height: 12, radius: AppRadius.sm),
                  SizedBox(height: AppSpace.md),
                  SkeletonBox(height: 12, radius: AppRadius.sm),
                  SizedBox(height: AppSpace.md),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: 160,
                      child: SkeletonBox(height: 12, radius: AppRadius.sm),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
