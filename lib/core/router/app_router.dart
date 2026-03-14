import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:magic_music_crm/features/auth/presentation/screens/login_screen.dart';
import 'package:magic_music_crm/features/client/presentation/screens/client_dashboard_screen.dart';
import 'package:magic_music_crm/features/admin/presentation/screens/admin_dashboard_screen.dart';
import 'package:magic_music_crm/features/teacher/presentation/screens/teacher_dashboard_screen.dart';
import 'package:magic_music_crm/features/manager/presentation/screens/manager_dashboard_screen.dart';
import 'package:magic_music_crm/features/admin/presentation/screens/student_detail_screen.dart';

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
      final isAuthRoute = loc == '/login';

      if (!isAuth) {
        return isAuthRoute ? null : '/login';
      }

      if (isAuth && isAuthRoute) {
        final role = await _fetchRole(session.user.id);
        return _roleToRoute(role);
      }

      if (isAuth && loc == '/') {
        final role = await _fetchRole(session.user.id);
        return _roleToRoute(role);
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const SizedBox.shrink(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
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
    ],
  );
});
