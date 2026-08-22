import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/security/password_policy.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/app_logo.dart';
import 'package:magic_music_crm/core/widgets/responsive_constraint.dart';
import 'package:magic_music_crm/core/widgets/magic_toast.dart';
import 'package:magic_music_crm/features/auth/presentation/widgets/auth_form_controls.dart';
import 'package:magic_music_crm/features/auth/providers/magic_auth_provider.dart';

class PasswordResetScreen extends ConsumerStatefulWidget {
  const PasswordResetScreen({super.key});

  @override
  ConsumerState<PasswordResetScreen> createState() =>
      _PasswordResetScreenState();
}

class _PasswordResetScreenState extends ConsumerState<PasswordResetScreen> {
  final _emailController = TextEditingController();
  final _tokenController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _emailSent = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _tokenController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _requestReset() async {
    final email = _emailController.text.trim();
    if (!_isValidEmail(email)) {
      _showError('Введите корректную почту');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await ref
          .read(magicAuthServiceProvider)
          .requestPasswordReset(email: email);
      if (!mounted) return;
      setState(() => _emailSent = true);
      MagicToast.show(
        context,
        'Письмо для сброса пароля отправлено',
        type: MagicToastType.info,
      );
    } on MagicApiException catch (error) {
      if (mounted) _showError(_mapAuthError(error.message));
    } catch (_) {
      if (mounted) _showError('Не удалось отправить письмо.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _confirmReset() async {
    final token = _tokenController.text.trim();
    final password = _passwordController.text;
    if (token.isEmpty) {
      _showError('Введите код из письма');
      return;
    }
    if (password.length < minPasswordLength) {
      _showError(passwordMinimumError);
      return;
    }
    if (password != _confirmPasswordController.text) {
      _showError('Пароли не совпадают');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await ref
          .read(magicAuthServiceProvider)
          .resetPassword(token: token, password: password);
      if (!mounted) return;
      MagicToast.show(
        context,
        'Пароль изменен. Войдите заново.',
        type: MagicToastType.success,
      );
      context.go('/login');
    } on MagicApiException catch (error) {
      if (mounted) _showError(_mapAuthError(error.message));
    } catch (_) {
      if (mounted) _showError('Не удалось изменить пароль.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool _isValidEmail(String value) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
  }

  String _mapAuthError(String message) {
    if (message.contains('Token') ||
        message.contains('недействителен') ||
        message.contains('истек')) {
      return 'Код сброса недействителен или истек.';
    }
    if (message.contains('Too many requests')) {
      return 'Слишком много попыток. Подождите немного.';
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildBrand(),
                      const SizedBox(height: AppSpace.xxl),
                      _buildNote(),
                      const SizedBox(height: AppSpace.lg),
                      if (_errorMessage != null) ...[
                        _buildErrorPill(_errorMessage!),
                        const SizedBox(height: AppSpace.lg),
                      ],
                      AuthField(
                        controller: _emailController,
                        label: 'Почта или телефон',
                        keyboardType: TextInputType.emailAddress,
                        enabled: !_emailSent && !_isLoading,
                        autocorrect: false,
                        autofillHints: const [AutofillHints.email],
                      ),
                      if (_emailSent) ...[
                        const SizedBox(height: AppSpace.lg),
                        AuthField(
                          controller: _tokenController,
                          label: 'Код из письма',
                          keyboardType: TextInputType.number,
                          autocorrect: false,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                        ),
                        const SizedBox(height: AppSpace.lg),
                        AuthField(
                          controller: _passwordController,
                          label: 'Новый пароль',
                          obscureText: _obscurePassword,
                          autocorrect: false,
                          suffix: _buildVisibilityToggle(),
                        ),
                        const SizedBox(height: AppSpace.lg),
                        AuthField(
                          controller: _confirmPasswordController,
                          label: 'Повторите пароль',
                          obscureText: _obscurePassword,
                          autocorrect: false,
                          suffix: _buildVisibilityToggle(),
                        ),
                      ],
                      const SizedBox(height: AppSpace.xl),
                      AuthPrimaryButton(
                        label: _emailSent ? 'Сменить пароль' : 'Отправить код',
                        loading: _isLoading,
                        onPressed: _isLoading
                            ? null
                            : (_emailSent ? _confirmReset : _requestReset),
                      ),
                      const SizedBox(height: AppSpace.sm),
                      TextButton(
                        onPressed: _isLoading
                            ? null
                            : () => context.go('/login'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColor.gold,
                          textStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          padding: const EdgeInsets.all(AppSpace.sm),
                          minimumSize: const Size(0, 0),
                        ),
                        child: const Text('Назад ко входу'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBrand() {
    return Column(
      children: [
        const AppLogo(size: 84),
        const SizedBox(height: AppSpace.xs),
        const Text(
          'Восстановление доступа',
          style: TextStyle(color: AppColor.text2, fontSize: 12.5),
        ),
      ],
    );
  }

  Widget _buildNote() {
    return Text(
      _emailSent
          ? 'Введите код из письма и новый пароль'
          : 'Мы отправим код сброса на вашу почту',
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: 12.5,
        height: 1.5,
        color: AppColor.text2,
      ),
    );
  }

  Widget _buildVisibilityToggle() {
    return IconButton(
      tooltip: _obscurePassword ? 'Показать пароль' : 'Скрыть пароль',
      icon: Icon(
        _obscurePassword
            ? Icons.visibility_outlined
            : Icons.visibility_off_outlined,
        color: AppColor.text2,
      ),
      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
    );
  }

  Widget _buildErrorPill(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 11,
        vertical: AppSpace.sm,
      ),
      decoration: BoxDecoration(
        color: AppColor.dangerSoft,
        border: Border.all(color: const Color(0x52E53935)),
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Text(
        message,
        style: const TextStyle(color: Color(0xFFF4A3A1), fontSize: 12),
      ),
    );
  }
}
