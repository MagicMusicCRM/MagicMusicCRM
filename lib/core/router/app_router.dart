import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
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
      if (loc.startsWith('/admin') &&
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
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final gateState = ref.watch(_routeGateStateProvider);
    final isGateError =
        gateState.phase == _RouteGatePhase.gateError &&
        !_isUnauthorizedRouteError(gateState.error);

    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 450),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.primary,
                    ),
                    child: Icon(
                      Icons.music_note_rounded,
                      color: colors.onPrimary,
                      size: 42,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Magic Music CRM',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    isGateError
                        ? 'Не удалось проверить доступ'
                        : 'Проверяем сессию и доступ',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (isGateError) ...[
                    Text(
                      gateState.error?.toString() ??
                          'Проверьте подключение и попробуйте снова.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () =>
                            ref.invalidate(releaseGateStatusProvider),
                        child: const Text('Повторить'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () =>
                          ref.read(magicAuthServiceProvider).signOut(),
                      child: const Text('Выйти'),
                    ),
                  ] else
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        minHeight: 4,
                        backgroundColor: colors.primary.withValues(alpha: 0.16),
                        color: colors.primary,
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
