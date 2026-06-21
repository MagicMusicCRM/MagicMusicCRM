// ignore_for_file: unused_element_parameter
// The shared _V7Field / _V7PrimaryButton helpers are pasted byte-identically
// across all six auth screens (v7 reskin spec §D-6); some optional parameters
// are unused on this particular screen but must stay for cross-screen parity.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/responsive_constraint.dart';
import 'package:magic_music_crm/core/widgets/v7/v7.dart';
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
    if (password.length < 10) {
      _showError('Пароль должен быть не короче 10 символов');
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
                      _V7Field(
                        controller: _emailController,
                        label: 'Email или телефон',
                        keyboardType: TextInputType.emailAddress,
                        enabled: !_emailSent && !_isLoading,
                        autocorrect: false,
                        autofillHints: const [AutofillHints.email],
                      ),
                      if (_emailSent) ...[
                        const SizedBox(height: AppSpace.lg),
                        _V7Field(
                          controller: _tokenController,
                          label: 'Код из письма',
                          keyboardType: TextInputType.number,
                          autocorrect: false,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                        ),
                        const SizedBox(height: AppSpace.lg),
                        _V7Field(
                          controller: _passwordController,
                          label: 'Новый пароль',
                          obscureText: _obscurePassword,
                          autocorrect: false,
                          suffix: _buildVisibilityToggle(),
                        ),
                        const SizedBox(height: AppSpace.lg),
                        _V7Field(
                          controller: _confirmPasswordController,
                          label: 'Повторите пароль',
                          obscureText: _obscurePassword,
                          autocorrect: false,
                          suffix: _buildVisibilityToggle(),
                        ),
                      ],
                      const SizedBox(height: AppSpace.xl),
                      _V7PrimaryButton(
                        label: _emailSent ? 'Сменить пароль' : 'Отправить код',
                        loading: _isLoading,
                        onPressed: _isLoading
                            ? null
                            : (_emailSent ? _confirmReset : _requestReset),
                      ),
                      const SizedBox(height: AppSpace.sm),
                      TextButton(
                        onPressed: _isLoading ? null : () => context.go('/login'),
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
        Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2A2418), Color(0xFF1D1A12)],
            ),
            border: Border.all(color: AppColor.goldLine),
          ),
          child: const Icon(
            Icons.music_note_rounded,
            color: AppColor.gold,
            size: 30,
          ),
        ),
        const SizedBox(height: AppSpace.md),
        RichText(
          text: const TextSpan(
            children: [
              TextSpan(
                text: 'Magic',
                style: TextStyle(
                  color: AppColor.text,
                  fontWeight: FontWeight.w800,
                  fontSize: 21,
                  letterSpacing: -0.4,
                ),
              ),
              TextSpan(
                text: 'Music',
                style: TextStyle(
                  color: AppColor.gold,
                  fontWeight: FontWeight.w800,
                  fontSize: 21,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),
        ),
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
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: AppSpace.sm),
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
      opacity: enabled ? 1.0 : 0.42,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Material(
          color: AppColor.gold,
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
                            color: AppColor.onGold,
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
