import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/entity_route_registry.dart';
import 'package:magic_music_crm/core/services/access_invalidation_provider.dart';
import 'package:magic_music_crm/core/security/capability_shell.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
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
import 'package:magic_music_crm/features/admin/presentation/screens/profile_detail_screen.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/manage_entities_widget.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/show_client_card.dart';
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
    case 'director':
      // KVA-239: Директор использует manager-оболочку CRM (с полным доступом
      // к общешкольным финансам — гейтится по реальной роли внутри).
      return '/manager';
    case 'teacher':
      return '/teacher';
    default:
      return '/client';
  }
}

ContextViewState _clientRouteViewState(GoRouterState state) {
  final query = state.uri.queryParameters;
  return ContextViewState(
    filters: {
      'section': query['section'] ?? 'overview',
      'clientCalendarMode': ?query['calendarMode'],
      'clientCalendarBranchId': ?query['branchId'],
    },
    date: DateTime.tryParse(query['calendarDate'] ?? ''),
  );
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
  // skipLoadingOnReload: a token refresh/login invalidates releaseGateStatusProvider,
  // flipping it to loading. Without keeping the previous value the router would
  // collapse to '/' on every re-validation and pop whatever dialog/route is open
  // (the "kicked out of the client card / Reports" bug). With this, a reload that
  // has a last-known-good gate stays on `data`; only the very first load shows
  // the loader.
  return gateState.when(
    skipLoadingOnReload: true,
    data: (status) {
      final requestToken = status.sessionAccessToken;
      return requestToken == null || requestToken == currentSession.accessToken
          ? _RouteGateState.ready(status)
          : const _RouteGateState.gateLoading();
    },
    error: (error, _) {
      if (!releaseGateErrorBelongsToSession(
        error,
        currentSession.accessToken,
      )) {
        return const _RouteGateState.gateLoading();
      }
      return _RouteGateState.gateError(error);
    },
    loading: () => const _RouteGateState.gateLoading(),
  );
});

bool _isUnauthorizedRouteError(Object? error) {
  final cause = error is SessionBoundReleaseGateError ? error.error : error;
  return cause is MagicApiException && cause.isUnauthorized;
}

// ── Router ───────────────────────────────────────────────────────────────────
/// Root navigator key — lets non-widget code (e.g. the Windows update prompt)
/// reach a live context to show an app-level dialog.
final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

final routerProvider = Provider<GoRouter>((ref) {
  final routerRefreshNotifier = ValueNotifier<int>(0);
  ref.onDispose(routerRefreshNotifier.dispose);
  ref.watch(accessInvalidationProvider);

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
      ref.invalidate(capabilitySnapshotProvider);
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
    navigatorKey: rootNavigatorKey,
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

      if (loc == '/crm/configuration') {
        return _staffEntityLocation(
          roleRoute,
          section: 'configuration',
          entityType: 'configuration',
          entityId: '__section__',
          focus: 'section',
        );
      }

      if (loc.startsWith('/admin/profiles/')) {
        return _staffEntityLocation(
          roleRoute,
          section: 'configuration',
          entityType: 'user',
          entityId: state.uri.pathSegments.last,
          focus: 'profile',
        );
      }

      if (loc.startsWith('/lessons/')) {
        return role == 'client'
            ? roleRoute
            : _staffEntityLocation(
                roleRoute,
                section: 'schedule',
                entityType: 'lesson',
                entityId: state.uri.pathSegments.last,
                focus: 'lesson',
              );
      }

      // Proactive role-path enforcement. Legacy shared paths were already
      // normalized above, so only the canonical role shells reach this gate.
      if (loc.startsWith('/admin') &&
          role != 'admin' &&
          role != 'system_admin') {
        return roleRoute;
      }
      if (loc.startsWith('/manager') &&
          role != 'manager' &&
          role != 'director') {
        return roleRoute;
      }
      if (loc.startsWith('/teacher') && role != 'teacher') return roleRoute;
      if (loc.startsWith('/client') && role != 'client') return roleRoute;

      if (role != 'client' &&
          state.uri.pathSegments.length == 2 &&
          const {
            'student',
            'students',
            'leads',
          }.contains(state.uri.pathSegments.first)) {
        final rawType = state.uri.pathSegments.first == 'leads'
            ? 'lead'
            : 'student';
        return Uri(
          path: roleRoute,
          queryParameters: {
            'section': 'clients',
            'entityType': rawType,
            'entityId': state.uri.pathSegments[1],
            'f.section': ?state.uri.queryParameters['section'],
          },
        ).toString();
      }

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
        builder: (context, state) => CapabilityShellGate(
          builder: (_, _) => const ClientDashboardScreen(),
        ),
      ),
      GoRoute(
        path: '/admin',
        builder: (context, state) =>
            AdminDashboardScreen(initialLink: _dashboardEntityLink(state)),
      ),
      GoRoute(
        path: '/teacher',
        builder: (context, state) =>
            TeacherDashboardScreen(initialLink: _dashboardEntityLink(state)),
      ),
      GoRoute(
        path: '/manager',
        builder: (context, state) =>
            ManagerDashboardScreen(initialLink: _dashboardEntityLink(state)),
      ),
      GoRoute(
        path: '/student/:id',
        builder: (context, state) => ClientCardRouteScreen(
          entityType: 'student',
          entityId: state.pathParameters['id']!,
          initialSection: state.uri.queryParameters['section'] ?? 'overview',
          initialViewState: _clientRouteViewState(state),
        ),
      ),
      GoRoute(
        path: '/admin/profiles/:id',
        builder: (context, state) =>
            ProfileDetailScreen(profileId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/crm/configuration',
        builder: (context, state) =>
            const SystemSettingsRouteScreen(initialArea: 'crm'),
      ),
      // ── Deep links (KVA-196) ────────────────────────────────────────────────
      // Open a lead/student/lesson directly by id. Each presents the unified
      // «Карточка клиента» (students/leads) or the existing dialog (lessons,
      // the KVA-175 pattern) over the active role dashboard via a thin host
      // screen; a cold deep link lands on the role dashboard once closed.
      GoRoute(
        path: '/students/:id',
        builder: (context, state) => ClientCardRouteScreen(
          entityType: 'student',
          entityId: state.pathParameters['id']!,
          initialSection: state.uri.queryParameters['section'] ?? 'overview',
          initialViewState: _clientRouteViewState(state),
        ),
      ),
      GoRoute(
        path: '/leads/:id',
        builder: (context, state) => ClientCardRouteScreen(
          entityType: 'lead',
          entityId: state.pathParameters['id']!,
          initialSection: state.uri.queryParameters['section'] ?? 'overview',
          initialViewState: _clientRouteViewState(state),
        ),
      ),
      GoRoute(
        path: '/lessons/:id',
        builder: (context, state) => const _DeepLinkScaffold(),
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

EntityLink? _dashboardEntityLink(GoRouterState state) {
  final type = state.uri.queryParameters['entityType'];
  final id = state.uri.queryParameters['entityId'];
  if (type == null || id == null || id.isEmpty) {
    final section = state.uri.queryParameters['section'];
    if (section == null || section.isEmpty) return null;
    return EntityRouteRegistry.sectionRootLink(section);
  }
  final link = EntityLink.fromJson({
    'version': EntityLink.schemaVersion,
    'entityType': type,
    'entityId': id,
    if (state.uri.queryParameters['entityTitle']?.trim().isNotEmpty == true)
      'presentation': {
        'primary': state.uri.queryParameters['entityTitle'],
        if (state.uri.queryParameters['entityContext']?.trim().isNotEmpty ==
            true)
          'context': state.uri.queryParameters['entityContext'],
      },
    if (state.uri.queryParameters['focus']?.isNotEmpty == true ||
        state.uri.queryParameters.keys.any((key) => key.startsWith('f.')))
      'optionalFocus': {
        if (state.uri.queryParameters['focus']?.isNotEmpty == true)
          'focus': state.uri.queryParameters['focus'],
        'filter': {
          for (final entry in state.uri.queryParameters.entries)
            if (entry.key.startsWith('f.')) entry.key.substring(2): entry.value,
        },
      },
  });
  return link.isSupported ? link : null;
}

String _staffEntityLocation(
  String roleRoute, {
  required String section,
  required String entityType,
  required String entityId,
  String? focus,
}) {
  return Uri(
    path: roleRoute,
    queryParameters: {
      'section': section,
      'entityType': entityType,
      'entityId': entityId,
      'focus': ?focus,
    },
  ).toString();
}

class _AppGateLoadingScreen extends ConsumerStatefulWidget {
  const _AppGateLoadingScreen();

  @override
  ConsumerState<_AppGateLoadingScreen> createState() =>
      _AppGateLoadingScreenState();
}

class _AppGateLoadingScreenState extends ConsumerState<_AppGateLoadingScreen> {
  Timer? _retryTimer;
  int _retryAttempt = 0;

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  /// Auto-retry with exponential backoff (5 → 10 → 20 → 40 → 60 s cap): a
  /// flaky mobile start must not dead-end on a screen whose only recovery is a
  /// manual «Повторить» tap. The manual button stays and retries immediately.
  void _scheduleAutoRetry() {
    if (_retryTimer != null) return;
    final seconds = (5 << (_retryAttempt > 4 ? 4 : _retryAttempt)).clamp(5, 60);
    _retryTimer = Timer(Duration(seconds: seconds), () {
      _retryTimer = null;
      _retryAttempt++;
      if (!mounted) return;
      ref.invalidate(releaseGateStatusProvider);
    });
  }

  void _cancelAutoRetry({required bool resetBackoff}) {
    _retryTimer?.cancel();
    _retryTimer = null;
    if (resetBackoff) _retryAttempt = 0;
  }

  @override
  Widget build(BuildContext context) {
    final gateState = ref.watch(_routeGateStateProvider);
    final isGateError =
        gateState.phase == _RouteGatePhase.gateError &&
        !_isUnauthorizedRouteError(gateState.error);

    if (isGateError) {
      _scheduleAutoRetry();
    } else {
      // Loading (a retry in flight) keeps the backoff position; a real success
      // routes away from this screen and resets it via dispose anyway.
      _cancelAutoRetry(resetBackoff: gateState.phase == _RouteGatePhase.ready);
    }

    return Scaffold(
      backgroundColor: AppColor.bg,
      body: DecoratedBox(
        decoration: const BoxDecoration(color: AppColor.bg),
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
                    // Brand block — the real school logo (assets/icon.png).
                    Column(
                      children: [
                        Image.asset(
                          'assets/icon.png',
                          width: 140,
                          height: 140,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.medium,
                        ),
                        const SizedBox(height: AppSpace.lg),
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
                            onTap: () {
                              _cancelAutoRetry(resetBackoff: true);
                              ref.invalidate(releaseGateStatusProvider);
                            },
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
                      // Real loading indicator.
                      const Center(
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: AppColor.gold,
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

/// Unreachable safety placeholder while a legacy URL redirect resolves.
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
