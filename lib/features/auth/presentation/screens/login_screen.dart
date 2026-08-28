import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/app_logo.dart';
import 'package:magic_music_crm/core/widgets/responsive_constraint.dart';
import 'package:magic_music_crm/features/auth/presentation/screens/email_otp_screen.dart';
import 'package:magic_music_crm/features/auth/presentation/widgets/auth_form_controls.dart';
import 'package:magic_music_crm/features/auth/providers/magic_auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    final email = _emailController.text.trim();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final service = ref.read(magicAuthServiceProvider);
      final response = await service.signInWithPassword(
        email: email,
        password: _passwordController.text,
      );
      if (response.emailOtpRequired) {
        if (mounted) {
          context.go(
            '/email-otp',
            extra: EmailOtpRouteData(
              email: email,
              purpose: EmailOtpPurpose.passwordMfa,
            ),
          );
        }
      }
    } on MagicApiException catch (e) {
      final message = _mapAuthError(e.message);
      if (_isEmailUnverifiedError(e.message)) {
        try {
          await ref
              .read(magicAuthServiceProvider)
              .resendSignupOtp(email: email);
          if (mounted) {
            context.go(
              '/email-otp',
              extra: EmailOtpRouteData(
                email: email,
                purpose: EmailOtpPurpose.signup,
              ),
            );
          }
          return;
        } catch (_) {
          // Keep the original login error visible; resend can be retried there.
        }
      }
      if (mounted) _showError(message);
    } catch (e) {
      if (mounted) _showError('Произошла ошибка. Попробуйте снова.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool _isValidEmail(String value) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
  }

  bool _isEmailUnverifiedError(String message) {
    return message.contains('Email not confirmed') ||
        (message.contains('Подтвердите') && message.contains('перед входом'));
  }

  String _mapAuthError(String message) {
    if (message.contains('Invalid login credentials') ||
        message.contains('Неверная почта или пароль')) {
      return 'Неверная почта или пароль';
    }
    if (_isEmailUnverifiedError(message)) {
      return 'Подтвердите почту перед входом';
    }
    if (message.contains('Too many requests')) {
      return 'Слишком много попыток. Подождите немного';
    }
    return message;
  }

  void _showError(String message) {
    setState(() => _errorMessage = message);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColor.bg,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0.0, -1.0),
            radius: 1.1,
            colors: [AppColor.selectionBg, AppColor.bg],
            stops: [0.0, 0.6],
          ),
        ),
        child: SafeArea(
          child: ResponsiveConstraint(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.xxl,
                    vertical: 30,
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Brand block
                        Column(
                          children: [
                            const AppLogo(size: 92),
                            const SizedBox(height: AppSpace.xs),
                            const Text(
                              'Вход в систему',
                              style: TextStyle(
                                color: AppColor.text2,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpace.xxl),

                        // Email field
                        AuthField(
                          controller: _emailController,
                          label: 'Телефон или почта',
                          hint: 'user@example.com',
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autocorrect: false,
                          autofillHints: const [AutofillHints.username],
                          validator: (value) =>
                              _isValidEmail(value?.trim() ?? '')
                              ? null
                              : 'Введите корректную почту',
                        ),
                        const SizedBox(height: AppSpace.lg),

                        // Password field
                        AuthField(
                          controller: _passwordController,
                          label: 'Пароль',
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.done,
                          autocorrect: false,
                          autofillHints: const [AutofillHints.password],
                          onSubmitted: (_) => _isLoading ? null : _signIn(),
                          suffix: IconButton(
                            tooltip: _obscurePassword
                                ? 'Показать пароль'
                                : 'Скрыть пароль',
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: AppColor.text2,
                            ),
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                          ),
                          validator: (value) => (value == null || value.isEmpty)
                              ? 'Введите пароль'
                              : null,
                        ),
                        const SizedBox(height: AppSpace.sm),

                        // Forgot password link (right-aligned)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _isLoading
                                ? null
                                : () => context.push('/password-reset'),
                            style: TextButton.styleFrom(
                              foregroundColor: AppColor.gold,
                              textStyle: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                              padding: const EdgeInsets.all(AppSpace.sm),
                              minimumSize: const Size(0, 0),
                            ),
                            child: const Text('Забыли пароль?'),
                          ),
                        ),
                        const SizedBox(height: AppSpace.sm),

                        // Inline error pill
                        if (_errorMessage != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 11,
                              vertical: AppSpace.sm,
                            ),
                            decoration: BoxDecoration(
                              color: AppColor.dangerSoft,
                              border: Border.all(color: AppColor.danger),
                              borderRadius: BorderRadius.circular(
                                AppRadius.chip,
                              ),
                            ),
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(
                                color: AppColor.danger,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpace.lg),
                        ],

                        // Sign In button
                        AuthPrimaryButton(
                          label: 'Войти',
                          loading: _isLoading,
                          onPressed: _isLoading ? null : _signIn,
                        ),
                        const SizedBox(height: AppSpace.lg),

                        // Create account link
                        TextButton(
                          onPressed: () => context.push('/register'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColor.gold,
                            textStyle: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                            padding: const EdgeInsets.all(AppSpace.sm),
                            minimumSize: const Size(0, 0),
                          ),
                          child: const Text('Создать аккаунт'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
