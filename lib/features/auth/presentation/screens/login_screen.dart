import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/app_logo.dart';
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
      backgroundColor: AppColor.sidebar,
      body: DecoratedBox(
        key: const ValueKey('login-backdrop'),
        decoration: const BoxDecoration(color: AppColor.sidebar),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 520;
              final short = constraints.maxHeight < 650;
              final alignAtTop = narrow || short;
              final viewportPadding = narrow
                  ? const EdgeInsets.symmetric(
                      horizontal: AppSpace.lg,
                      vertical: AppSpace.xl,
                    )
                  : const EdgeInsets.symmetric(
                      horizontal: AppSpace.xxl,
                      vertical: AppSpace.xxl + AppSpace.sm,
                    );
              final cardHorizontalPadding = narrow
                  ? AppSpace.xl
                  : AppSpace.xxl + AppSpace.sm;
              final cardVerticalPadding = narrow || short
                  ? AppSpace.xxl
                  : AppSpace.xxl + AppSpace.sm;

              return Align(
                alignment: alignAtTop ? Alignment.topCenter : Alignment.center,
                child: SingleChildScrollView(
                  padding: viewportPadding,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Container(
                        key: const ValueKey('login-form-card'),
                        width: double.infinity,
                        padding: EdgeInsets.symmetric(
                          horizontal: cardHorizontalPadding,
                          vertical: cardVerticalPadding,
                        ),
                        decoration: BoxDecoration(
                          color: AppColor.bg,
                          border: Border.all(color: AppColor.borderStrong),
                          borderRadius: BorderRadius.circular(AppRadius.card),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x0A302819),
                              blurRadius: 2,
                              offset: Offset(0, 1),
                            ),
                            BoxShadow(
                              color: Color(0x0F302819),
                              blurRadius: 34,
                              offset: Offset(0, 12),
                            ),
                          ],
                        ),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                key: const ValueKey('login-heading'),
                                padding: const EdgeInsets.only(
                                  bottom: AppSpace.xxl,
                                ),
                                decoration: const BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(color: AppColor.divider),
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    AppLogo(size: narrow ? 54 : 64),
                                    SizedBox(width: narrow ? 13 : AppSpace.lg),
                                    const Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Вход в систему',
                                            style: TextStyle(
                                              color: AppColor.text,
                                              fontSize: 24,
                                              height: 1.15,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: -0.45,
                                            ),
                                          ),
                                          SizedBox(height: 7),
                                          Text(
                                            'Рабочее пространство Magic Music',
                                            style: TextStyle(
                                              color: AppColor.text2,
                                              fontSize: 13,
                                              height: 1.45,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: AppSpace.xxl),
                              AuthField(
                                controller: _emailController,
                                label: 'Телефон или почта',
                                hint: 'user@example.com',
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                autocorrect: false,
                                autofillHints: const [AutofillHints.username],
                                fillColor: AppColor.surface,
                                borderColor: AppColor.borderStrong,
                                focusBorderColor: AppColor.focus,
                                labelColor: AppPalette.ink800,
                                validator: (value) =>
                                    _isValidEmail(value?.trim() ?? '')
                                    ? null
                                    : 'Введите корректную почту',
                              ),
                              const SizedBox(height: AppSpace.lg),
                              AuthField(
                                controller: _passwordController,
                                label: 'Пароль',
                                obscureText: _obscurePassword,
                                textInputAction: TextInputAction.done,
                                autocorrect: false,
                                autofillHints: const [AutofillHints.password],
                                fillColor: AppColor.surface,
                                borderColor: AppColor.borderStrong,
                                focusBorderColor: AppColor.focus,
                                labelColor: AppPalette.ink800,
                                onSubmitted: (_) =>
                                    _isLoading ? null : _signIn(),
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
                                validator: (value) =>
                                    (value == null || value.isEmpty)
                                    ? 'Введите пароль'
                                    : null,
                              ),
                              const SizedBox(height: AppSpace.xs),
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
                              const SizedBox(height: AppSpace.xs),
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
                              AuthPrimaryButton(
                                label: 'Войти',
                                loading: _isLoading,
                                onPressed: _isLoading ? null : _signIn,
                              ),
                              const SizedBox(height: AppSpace.md),
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
              );
            },
          ),
        ),
      ),
    );
  }
}
