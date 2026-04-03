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

  Future<void> _tryAutoLogin() async {
    final credentials = ref.read(registrationProvider);
    if (credentials == null) {
      context.go('/login');
      return;
    }

    setState(() => _isChecking = true);
    try {
      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: credentials.email,
        password: credentials.password,
      );
      if (response.session != null) {
        ref.read(registrationProvider.notifier).clear();
        if (mounted) context.go('/');
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppTheme.danger, behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 450),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: AppTheme.primaryGold),
                    child: const Icon(Icons.mark_email_unread_outlined, size: 50, color: Colors.white),
                  ),
                  const SizedBox(height: 32),
                  const Text('Проверьте почту', textAlign: TextAlign.center, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white)),
                  const SizedBox(height: 16),
                  Text('Мы отправили ссылку для подтверждения на\n${widget.email}', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.white.withAlpha(160))),
                  const SizedBox(height: 48),

                  Container(
                    height: 56,
                    width: double.infinity,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), color: AppTheme.primaryGold),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: _isChecking ? null : _tryAutoLogin,
                        child: Center(
                          child: _isChecking
                              ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Text('Я подтвердил(а) почту — Войти', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Если приложение не открылось само,\nнажмите кнопку выше и войдите в аккаунт.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.white.withAlpha(140), fontStyle: FontStyle.italic),
                  ),
                  const SizedBox(height: 64),
                  TextButton(
                    onPressed: () => context.go('/login'),
                    child: const Text('Вернуться ко входу', style: TextStyle(color: AppTheme.primaryGold, fontSize: 16)),
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
