// The shared v7 auth helpers (_V7Field / _V7PrimaryButton) are pasted
// byte-for-byte identically across all 6 auth screens per the v7 spec, so a
// few of their parameters are intentionally unused on this particular screen.
// ignore_for_file: unused_element_parameter
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/app_logo.dart';
import 'package:magic_music_crm/core/widgets/responsive_constraint.dart';
import 'package:magic_music_crm/features/auth/presentation/screens/email_otp_screen.dart';
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
            colors: [Color(0x1AC5A059), AppColor.bg],
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
                        _V7Field(
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
                        _V7Field(
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
                              border: Border.all(
                                color: const Color(0x52E53935),
                              ),
                              borderRadius: BorderRadius.circular(
                                AppRadius.chip,
                              ),
                            ),
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(
                                color: Color(0xFFF4A3A1),
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpace.lg),
                        ],

                        // Sign In button
                        _V7PrimaryButton(
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

class _V7Field extends StatelessWidget {
  const _V7Field({
    required this.controller,
    required this.label,
    this.hint,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.enabled = true,
    this.autocorrect = true,
    this.suffix,
    this.validator,
    this.inputFormatters,
    this.onSubmitted,
    this.autofillHints,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool enabled;
  final bool autocorrect;
  final Widget? suffix;
  final String? Function(String?)? validator;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onSubmitted;
  final Iterable<String>? autofillHints;

  @override
  Widget build(BuildContext context) {
    final decoration = InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColor.text2),
      suffixIcon: suffix,
      filled: true,
      fillColor: AppColor.input,
      contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: const BorderSide(color: AppColor.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: const BorderSide(color: AppColor.goldLine, width: 2),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: const BorderSide(color: AppColor.divider),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: const BorderSide(color: AppColor.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: const BorderSide(color: AppColor.danger, width: 2),
      ),
    );

    final field = (validator != null)
        ? TextFormField(
            controller: controller,
            obscureText: obscureText,
            keyboardType: keyboardType,
            textInputAction: textInputAction,
            enabled: enabled,
            autocorrect: autocorrect,
            autofillHints: autofillHints,
            inputFormatters: inputFormatters,
            onFieldSubmitted: onSubmitted,
            style: const TextStyle(color: AppColor.text),
            decoration: decoration,
            validator: validator,
          )
        : TextField(
            controller: controller,
            obscureText: obscureText,
            keyboardType: keyboardType,
            textInputAction: textInputAction,
            enabled: enabled,
            autocorrect: autocorrect,
            autofillHints: autofillHints,
            inputFormatters: inputFormatters,
            onSubmitted: onSubmitted,
            style: const TextStyle(color: AppColor.text),
            decoration: decoration,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColor.text2,
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        field,
      ],
    );
  }
}

class _V7PrimaryButton extends StatelessWidget {
  const _V7PrimaryButton({
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
    this.height = 52,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;
  final double height;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return Opacity(
      opacity: enabled ? 1.0 : 0.42, // .btn[disabled]{opacity:.42}
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Material(
          color: AppColor.gold, // flat gold, NO shadow/elevation
          borderRadius: BorderRadius.circular(AppRadius.control),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.control),
            onTap: enabled ? onPressed : null,
            child: Center(
              child: loading
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColor.onGold,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icon != null) ...[
                          Icon(icon, size: 17, color: AppColor.onGold),
                          const SizedBox(width: AppSpace.sm),
                        ],
                        Text(
                          label,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColor.onGold, // #1A1408 on gold
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
