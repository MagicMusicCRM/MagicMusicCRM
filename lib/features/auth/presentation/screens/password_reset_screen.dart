import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/widgets/responsive_constraint.dart';
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

    setState(() => _isLoading = true);
    try {
      await ref
          .read(magicAuthServiceProvider)
          .requestPasswordReset(email: email);
      if (!mounted) return;
      setState(() => _emailSent = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Письмо для сброса пароля отправлено')),
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
    if (password.length < 10) {
      _showError('Пароль должен быть не короче 10 символов');
      return;
    }
    if (password != _confirmPasswordController.text) {
      _showError('Пароли не совпадают');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await ref
          .read(magicAuthServiceProvider)
          .resetPassword(token: token, password: password);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Пароль изменен. Войдите заново.')),
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
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: ResponsiveConstraint(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),
              const Icon(
                Icons.lock_reset_rounded,
                size: 72,
                color: AppTheme.primaryGold,
              ),
              const SizedBox(height: 24),
              const Text(
                'Восстановление пароля',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _emailSent
                    ? 'Введите код из письма и новый пароль'
                    : 'Мы отправим код сброса на вашу почту',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withAlpha(160)),
              ),
              const SizedBox(height: 32),
              _buildTextField(
                controller: _emailController,
                label: 'Электронная почта',
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
                enabled: !_emailSent && !_isLoading,
              ),
              if (_emailSent) ...[
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _tokenController,
                  label: 'Код из письма',
                  icon: Icons.key_rounded,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _passwordController,
                  label: 'Новый пароль',
                  icon: Icons.lock_outline_rounded,
                  obscureText: _obscurePassword,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _confirmPasswordController,
                  label: 'Повторите пароль',
                  icon: Icons.lock_outline_rounded,
                  obscureText: _obscurePassword,
                  suffix: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: Colors.white.withAlpha(160),
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
              ],
              const SizedBox(height: 28),
              SizedBox(
                height: 56,
                child: FilledButton(
                  onPressed: _isLoading
                      ? null
                      : (_emailSent ? _confirmReset : _requestReset),
                  child: _isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_emailSent ? 'Сменить пароль' : 'Отправить код'),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _isLoading ? null : () => context.go('/login'),
                child: const Text('Вернуться ко входу'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscureText = false,
    bool enabled = true,
    Widget? suffix,
  }) {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      obscureText: obscureText,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppTheme.primaryGold),
        suffixIcon: suffix,
        filled: true,
        fillColor: AppTheme.cardDark,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppTheme.primaryGold, width: 2),
        ),
      ),
    );
  }
}
