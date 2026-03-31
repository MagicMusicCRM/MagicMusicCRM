import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/features/auth/providers/registration_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CheckEmailScreen extends ConsumerStatefulWidget {
  final String email;
  const CheckEmailScreen({super.key, required this.email});

  @override
  ConsumerState<CheckEmailScreen> createState() => _CheckEmailScreenState();
}

class _CheckEmailScreenState extends ConsumerState<CheckEmailScreen> {
  late StreamSubscription<AuthState> _authSubscription;
  bool _isChecking = false;

  @override
  void initState() {
    super.initState();
    // Listen for auth state changes (e.g. if deep link signs in the user)
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.session != null) {
        if (mounted) context.go('/');
      }
    });
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }

  void _goToLogin() {
    context.go('/login');
  }

  Future<void> _tryAutoLogin() async {
    final credentials = ref.read(registrationProvider);
    if (credentials == null) {
      _goToLogin();
      return;
    }

    setState(() => _isChecking = true);
    try {
      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: credentials.email,
        password: credentials.password,
      );

      if (response.session != null) {
        // Clear temporary credentials
        ref.read(registrationProvider.notifier).clear();
        if (mounted) context.go('/');
      }
    } on AuthException catch (e) {
      debugPrint('Auto-login error: ${e.message}');
      if (mounted) {
        String message = 'Произошла ошибка при входе';
        if (e.message.contains('Email not confirmed')) {
          message = 'Вы еще не подтвердили регистрацию. Пожалуйста, проверьте почту и перейдите по ссылке.';
        } else if (e.message.contains('Invalid login credentials')) {
          message = 'Ошибка данных. Пожалуйста, войдите вручную.';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: AppTheme.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.go('/login'),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1E1A29), Color(0xFF0F0C1B)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Icon
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [AppTheme.primaryPurple, Color(0xFF9333EA)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primaryPurple.withAlpha(80),
                          blurRadius: 30,
                          offset: const Offset(0, 10),
                        )
                      ],
                    ),
                    child: const Icon(Icons.mark_email_unread_outlined, size: 50, color: Colors.white),
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'Проверьте почту',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Мы отправили ссылку для подтверждения на\n${widget.email}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white.withAlpha(180),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 48),
                  if (_isChecking)
                    const CircularProgressIndicator(color: AppTheme.primaryPurple)
                  else
                    ElevatedButton(
                      onPressed: _tryAutoLogin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryPurple,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Я подтвердил(а) почту — Войти', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  const SizedBox(height: 24),
                  Text(
                    'Если приложение не открылось само,\nнажмите кнопку выше и войдите в аккаунт.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withAlpha(140),
                      fontStyle: FontStyle.italic,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 64),
                  TextButton(
                    onPressed: () => context.go('/login'),
                    child: const Text(
                      'Вернуться ко входу',
                      style: TextStyle(
                        color: AppTheme.primaryPurple,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
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
