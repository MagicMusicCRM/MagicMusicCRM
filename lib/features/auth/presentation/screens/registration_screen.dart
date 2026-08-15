// ignore_for_file: unused_element_parameter

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/app_logo.dart';
import 'package:magic_music_crm/core/widgets/responsive_constraint.dart';
import 'package:magic_music_crm/core/widgets/ru_phone_field.dart';
import 'package:magic_music_crm/features/auth/presentation/screens/email_otp_screen.dart';
import 'package:magic_music_crm/features/auth/providers/magic_auth_provider.dart';

class RegistrationScreen extends ConsumerStatefulWidget {
  const RegistrationScreen({super.key});

  @override
  ConsumerState<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends ConsumerState<RegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;
  String _canonicalPhone = '';

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    if (_canonicalPhone.isEmpty) {
      _showError('Введите корректный номер телефона в формате +7…');
      setState(() => _isLoading = false);
      return;
    }
    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text;
      final response = await ref
          .read(magicAuthServiceProvider)
          .signUpWithPassword(
            email: _emailController.text.trim(),
            password: password,
            fullName: _nameController.text.trim(),
            phone: _canonicalPhone,
          );
      if (!mounted) return;
      if (response.hasSession) {
        context.go('/');
      } else {
        context.go(
          '/email-otp',
          extra: EmailOtpRouteData(
            email: email,
            purpose: EmailOtpPurpose.signup,
          ),
        );
      }
    } on MagicApiException catch (e) {
      if (mounted) {
        _showError(
          e.toUserMessage(fallback: 'Не удалось завершить регистрацию.'),
        );
      }
    } catch (e) {
      if (mounted) _showError('Произошла ошибка при регистрации');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    setState(() => _errorMessage = message);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColor.bg,
      body: SafeArea(
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
                      const _AuthBrand(subtitle: 'Создание аккаунта'),
                      const SizedBox(height: AppSpace.xxl),
                      if (_errorMessage != null) ...[
                        _AuthErrorPill(message: _errorMessage!),
                        const SizedBox(height: AppSpace.lg),
                      ],
                      _V7Field(
                        controller: _nameController,
                        label: 'Имя',
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        autofillHints: const [AutofillHints.name],
                        validator: (v) =>
                            (v == null || v.isEmpty) ? 'Введите имя' : null,
                      ),
                      const SizedBox(height: AppSpace.lg),
                      _V7Field(
                        controller: _emailController,
                        label: 'Электронная почта',
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        autofillHints: const [AutofillHints.email],
                        validator: (v) => (v == null || !v.contains('@'))
                            ? 'Некорректная почта'
                            : null,
                      ),
                      const SizedBox(height: AppSpace.lg),
                      RuPhoneField(
                        labelText: 'Номер телефона',
                        onCanonicalChanged: (v) => _canonicalPhone = v,
                        decoration: InputDecoration(
                          hintStyle: const TextStyle(color: AppColor.text2),
                          filled: true,
                          fillColor: AppColor.input,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 13,
                            vertical: 12,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              AppRadius.control,
                            ),
                            borderSide: const BorderSide(
                              color: AppColor.divider,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              AppRadius.control,
                            ),
                            borderSide: const BorderSide(
                              color: AppColor.goldLine,
                              width: 2,
                            ),
                          ),
                          disabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              AppRadius.control,
                            ),
                            borderSide: const BorderSide(
                              color: AppColor.divider,
                            ),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              AppRadius.control,
                            ),
                            borderSide: const BorderSide(
                              color: AppColor.danger,
                            ),
                          ),
                          focusedErrorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              AppRadius.control,
                            ),
                            borderSide: const BorderSide(
                              color: AppColor.danger,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpace.lg),
                      _V7Field(
                        controller: _passwordController,
                        label: 'Пароль',
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        autofillHints: const [AutofillHints.newPassword],
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
                        validator: (v) => (v == null || v.length < 6)
                            ? 'Минимум 6 символов'
                            : null,
                      ),
                      const SizedBox(height: AppSpace.lg),
                      _V7Field(
                        controller: _confirmPasswordController,
                        label: 'Повторите пароль',
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.done,
                        autocorrect: false,
                        autofillHints: const [AutofillHints.newPassword],
                        onSubmitted: (_) => _register(),
                        validator: (v) => v != _passwordController.text
                            ? 'Пароли не совпадают'
                            : null,
                      ),
                      const SizedBox(height: AppSpace.xl),
                      _V7PrimaryButton(
                        label: 'Зарегистрироваться',
                        loading: _isLoading,
                        onPressed: _isLoading ? null : _register,
                      ),
                      const SizedBox(height: AppSpace.sm),
                      TextButton(
                        onPressed: () => context.go('/login'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColor.gold,
                          textStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          padding: const EdgeInsets.all(AppSpace.sm),
                          minimumSize: const Size(0, 0),
                        ),
                        child: const Text('Уже есть аккаунт? Войти'),
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
}

/// v7 auth brand block — gold-line tile + MagicMusic wordmark + subtitle.
class _AuthBrand extends StatelessWidget {
  const _AuthBrand({required this.subtitle});

  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const AppLogo(size: 92),
        const SizedBox(height: AppSpace.xs),
        Text(
          subtitle,
          style: const TextStyle(color: AppColor.text2, fontSize: 12.5),
        ),
      ],
    );
  }
}

/// v7 inline error pill (`.auth-err`).
class _AuthErrorPill extends StatelessWidget {
  const _AuthErrorPill({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
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
