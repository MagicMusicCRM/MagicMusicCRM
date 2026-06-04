import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:magic_music_crm/features/auth/presentation/screens/login_screen.dart';
import 'package:magic_music_crm/features/auth/presentation/screens/registration_screen.dart';
import 'package:magic_music_crm/features/auth/presentation/screens/onboarding_screen.dart';
import 'package:magic_music_crm/features/auth/presentation/screens/legal_consent_screen.dart';
import 'package:magic_music_crm/features/auth/providers/release_gate_provider.dart';
import 'package:magic_music_crm/features/client/presentation/screens/client_dashboard_screen.dart';
import 'package:magic_music_crm/features/admin/presentation/screens/admin_dashboard_screen.dart';
import 'package:magic_music_crm/features/teacher/presentation/screens/teacher_dashboard_screen.dart';
import 'package:magic_music_crm/features/manager/presentation/screens/manager_dashboard_screen.dart';
import 'package:magic_music_crm/features/admin/presentation/screens/student_detail_screen.dart';
import 'package:magic_music_crm/features/profile/presentation/screens/profile_screen.dart';
import 'package:magic_music_crm/features/profile/presentation/screens/account_deletion_screen.dart';
import 'package:magic_music_crm/features/profile/presentation/screens/account_deletion_status_screen.dart';
import 'package:magic_music_crm/features/auth/presentation/screens/check_email_screen.dart';

// ── Role cache ───────────────────────────────────────────────────────────────
String? _cachedRole;

Future<String> _fetchRole(String userId) async {
  if (_cachedRole != null) return _cachedRole!;
  try {
    final profile = await Supabase.instance.client
        .from('profiles')
        .select('role')
        .eq('id', userId)
        .maybeSingle();
    _cachedRole = (profile?['role'] as String?) ?? 'client';
  } catch (_) {
    _cachedRole = 'client';
  }
  return _cachedRole!;
}

String _roleToRoute(String role) {
  switch (role) {
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

// ── Role Stream ────────────────────────────────────────────────────────────────
final _roleStreamProvider = StreamProvider<String>((ref) {
  final session = Supabase.instance.client.auth.currentSession;
  if (session == null) return Stream.value('client');
  return Supabase.instance.client
      .from('profiles')
      .stream(primaryKey: ['id'])
      .eq('id', session.user.id)
      .map((event) {
        if (event.isNotEmpty) {
          return (event.first['role'] as String?) ?? 'client';
        }
        return 'client';
      });
});

// ── Auth state notifier ───────────────────────────────────────────────────────
final _authStateProvider = StreamProvider<AuthState>((ref) {
  return Supabase.instance.client.auth.onAuthStateChange;
});

// ── Router ───────────────────────────────────────────────────────────────────
final routerProvider = Provider<GoRouter>((ref) {
  final authNotifier = ValueNotifier<int>(0);

  ref.listen(_authStateProvider, (_, next) {
    next.whenData((authState) {
      if (authState.event == AuthChangeEvent.signedOut) {
        _cachedRole = null;
      }
    });
    authNotifier.value++;
  });

  ref.listen(_roleStreamProvider, (_, next) {
    next.whenData((role) {
      if (_cachedRole != role) {
        _cachedRole = role;
        authNotifier.value++;
      }
    });
  });

  return GoRouter(
    initialLocation: '/',
    refreshListenable: authNotifier,
    redirect: (context, state) async {
      final session = Supabase.instance.client.auth.currentSession;
      final isAuth = session != null;
      final loc = state.matchedLocation;
      final isAuthRoute =
          loc == '/login' || loc == '/register' || loc == '/check-email';
      final isGateRoute =
          loc == '/onboarding' ||
          loc == '/legal-consent' ||
          loc == '/account-deletion-status';

      if (!isAuth) {
        return isAuthRoute ? null : '/login';
      }

      final gateStatus = await ref
          .read(supaReleaseGateServiceProvider)
          .getGateStatus();
      final role = gateStatus.role.isEmpty
          ? await _fetchRole(session.user.id)
          : gateStatus.role;
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

      // Proactive role-path enforcement
      if (loc.startsWith('/admin') && role != 'admin') return roleRoute;
      if (loc.startsWith('/manager') && role != 'manager') return roleRoute;
      if (loc.startsWith('/teacher') && role != 'teacher') return roleRoute;
      if (loc.startsWith('/client') && role != 'client') return roleRoute;

      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const SizedBox.shrink()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegistrationScreen(),
      ),
      GoRoute(
        path: '/check-email',
        builder: (context, state) {
          final email = state.extra as String? ?? '';
          return CheckEmailScreen(email: email);
        },
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
        path: '/delete-account',
        builder: (context, state) => const AccountDeletionScreen(),
      ),
    ],
  );
});
