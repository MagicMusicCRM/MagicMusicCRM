import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/widgets/responsive_constraint.dart';
import 'package:magic_music_crm/features/auth/providers/supa_auth_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const int emailOtpCodeLength = 6;

enum EmailOtpPurpose { signup, passwordMfa }

class EmailOtpRouteData {
  final String email;
  final EmailOtpPurpose purpose;

  const EmailOtpRouteData({required this.email, required this.purpose});
}

class EmailOtpScreen extends ConsumerStatefulWidget {
  final EmailOtpRouteData data;

  const EmailOtpScreen({super.key, required this.data});

  @override
  ConsumerState<EmailOtpScreen> createState() => _EmailOtpScreenState();
}

class _EmailOtpScreenState extends ConsumerState<EmailOtpScreen> {
  final _codeController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _verifyCode() async {
    final code = _codeController.text.trim();
    if (code.length != emailOtpCodeLength) {
      _showError('Введите 6 цифр из письма');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final service = ref.read(supaAuthServiceProvider);
      if (widget.data.purpose == EmailOtpPurpose.signup) {
        await service.verifySignupOtp(email: widget.data.email, token: code);
      } else {
        await service.verifyEmailOtp(email: widget.data.email, token: code);
      }
      if (mounted) context.go('/');
    } on AuthException catch (error) {
      if (mounted) _showError(_mapAuthError(error.message));
    } catch (_) {
      if (mounted) _showError('Не удалось проверить код.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resendCode() async {
    setState(() => _isLoading = true);
    try {
      final service = ref.read(supaAuthServiceProvider);
      if (widget.data.purpose == EmailOtpPurpose.signup) {
        await service.resendSignupOtp(email: widget.data.email);
      } else {
        await service.sendEmailOtp(
          email: widget.data.email,
          shouldCreateUser: false,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Новый код отправлен на email')),
        );
      }
    } on AuthException catch (error) {
      if (mounted) _showError(_mapAuthError(error.message));
    } catch (_) {
      if (mounted) _showError('Не удалось отправить новый код.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _mapAuthError(String message) {
    if (message.contains('Token has expired')) {
      return 'Код истек. Запросите новый.';
    }
    if (message.contains('Invalid token')) {
      return 'Неверный код.';
    }
    if (message.contains('Too many requests')) {
      return 'Слишком много попыток. Подождите немного.';
    }
    return message;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.danger,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (widget.data.purpose) {
      EmailOtpPurpose.signup => 'Подтвердите email',
      EmailOtpPurpose.passwordMfa => 'Введите код 2FA',
    };
    final description = switch (widget.data.purpose) {
      EmailOtpPurpose.signup =>
        'Мы отправили код подтверждения регистрации на\n${widget.data.email}',
      EmailOtpPurpose.passwordMfa =>
        'Мы отправили одноразовый код входа на\n${widget.data.email}',
    };

    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: ResponsiveConstraint(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.primaryGold,
                ),
                child: const Icon(
                  Icons.mark_email_read_outlined,
                  color: Colors.white,
                  size: 46,
                ),
              ),
              const SizedBox(height: 32),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                description,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withAlpha(160),
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 36),
              TextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(emailOtpCodeLength),
                ],
                decoration: InputDecoration(
                  hintText: '000000',
                  hintStyle: TextStyle(color: Colors.white.withAlpha(80)),
                  filled: true,
                  fillColor: AppTheme.cardDark,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(
                      color: AppTheme.primaryGold,
                      width: 2,
                    ),
                  ),
                ),
                onSubmitted: (_) => _isLoading ? null : _verifyCode(),
              ),
              const SizedBox(height: 28),
              SizedBox(
                height: 56,
                child: FilledButton(
                  onPressed: _isLoading ? null : _verifyCode,
                  child: _isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Подтвердить код'),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _isLoading ? null : _resendCode,
                child: const Text('Отправить код повторно'),
              ),
              TextButton(
                onPressed: () => context.go('/login'),
                child: const Text('Вернуться ко входу'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
