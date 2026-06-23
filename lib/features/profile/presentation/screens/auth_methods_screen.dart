import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/responsive_constraint.dart';
import 'package:magic_music_crm/features/auth/data/services/magic_auth_service.dart';
import 'package:magic_music_crm/features/auth/providers/magic_auth_provider.dart';

class AuthMethodsScreen extends ConsumerStatefulWidget {
  const AuthMethodsScreen({super.key});

  @override
  ConsumerState<AuthMethodsScreen> createState() => _AuthMethodsScreenState();
}

class _AuthMethodsScreenState extends ConsumerState<AuthMethodsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  late Future<_AuthMethodsData> _authMethodsFuture;
  bool _isSavingPassword = false;
  bool _isSavingMfa = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _authMethodsFuture = _loadAuthMethods();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<_AuthMethodsData> _loadAuthMethods() async {
    final service = ref.read(magicAuthServiceProvider);
    final profile = await service.currentProfile();
    final identities = await service.getUserIdentities();
    final emailOtpMfaEnabled = await service
        .isEmailOtpMfaEnabledForCurrentUser();
    return _AuthMethodsData(
      email: profile.email,
      identities: identities,
      emailOtpMfaEnabled: emailOtpMfaEnabled,
    );
  }

  void _refreshAuthMethods() {
    setState(() {
      _authMethodsFuture = _loadAuthMethods();
    });
  }

  Future<void> _setPassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSavingPassword = true);
    try {
      await ref
          .read(magicAuthServiceProvider)
          .setPassword(_passwordController.text);
      _passwordController.clear();
      _confirmPasswordController.clear();
      _refreshAuthMethods();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Пароль для входа по почте сохранен')),
        );
      }
    } on MagicApiException catch (error) {
      if (mounted) _showError(_mapAuthError(error.message));
    } catch (_) {
      if (mounted) _showError('Не удалось сохранить пароль.');
    } finally {
      if (mounted) setState(() => _isSavingPassword = false);
    }
  }

  Future<void> _setEmailOtpMfa(bool enabled) async {
    setState(() => _isSavingMfa = true);
    try {
      await ref.read(magicAuthServiceProvider).setEmailOtpMfaEnabled(enabled);
      _refreshAuthMethods();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              enabled
                  ? 'Код из письма для входа включен'
                  : 'Код из письма для входа выключен',
            ),
          ),
        );
      }
    } on MagicApiException catch (error) {
      if (mounted) _showError(_mapAuthError(error.message));
    } catch (_) {
      if (mounted) {
        _showError('Не удалось изменить настройку двухфакторной защиты.');
      }
    } finally {
      if (mounted) setState(() => _isSavingMfa = false);
    }
  }

  String _mapAuthError(String message) {
    if (message.contains('Password should be at least')) {
      return 'Пароль слишком короткий.';
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

  /// v7 input decoration: control radius (10), gold focus ring (2), theme-aware
  /// fill from the active [InputDecorationTheme] (falls back to the surface).
  InputDecoration _v7FieldDecoration(
    BuildContext context, {
    required String labelText,
    Widget? prefixIcon,
    Widget? suffixIcon,
  }) {
    final theme = Theme.of(context);
    final fill =
        theme.inputDecorationTheme.fillColor ?? theme.colorScheme.surface;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.control),
      borderSide: BorderSide(color: theme.dividerColor),
    );
    return InputDecoration(
      labelText: labelText,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: fill,
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: const BorderSide(color: AppColor.gold, width: 2),
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Способы входа')),
      body: ResponsiveConstraint(
        child: FutureBuilder<_AuthMethodsData>(
          future: _authMethodsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpace.xl),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Не удалось загрузить способы входа.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: AppSpace.lg),
                      TextButton(
                        onPressed: _refreshAuthMethods,
                        child: const Text('Повторить'),
                      ),
                    ],
                  ),
                ),
              );
            }

            final data = snapshot.data;
            final identities = data?.identities ?? const <MagicAuthIdentity>[];
            final userEmail = data?.email ?? '';
            final hasEmail = identities.any((item) => item.provider == 'email');
            final emailOtpMfaEnabled = data?.emailOtpMfaEnabled ?? false;

            return ListView(
              padding: const EdgeInsets.all(AppSpace.xl),
              children: [
                Text(
                  userEmail.isEmpty ? 'Аккаунт' : userEmail,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpace.lg),
                _Section(
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeThumbColor: AppColor.gold,
                    secondary: const Icon(Icons.verified_user_outlined),
                    title: const Text('Код из письма для входа'),
                    subtitle: Text(
                      hasEmail
                          ? 'После пароля приложение попросит 6-значный код из письма'
                          : 'Сначала установите пароль для входа по почте',
                    ),
                    value: emailOtpMfaEnabled,
                    onChanged: hasEmail && !_isSavingMfa
                        ? _setEmailOtpMfa
                        : null,
                  ),
                ),
                const SizedBox(height: AppSpace.lg),
                _Section(
                  child: Column(
                    children: [
                      _IdentityRow(
                        icon: Icons.email_outlined,
                        title: 'Почта и пароль',
                        subtitle: hasEmail
                            ? 'Можно входить по почте и паролю'
                            : 'Пароль еще не установлен',
                        enabled: hasEmail,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpace.xxl),
                _Section(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          hasEmail ? 'Обновить пароль' : 'Установить пароль',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: AppSpace.lg),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          decoration: _v7FieldDecoration(
                            context,
                            labelText: 'Новый пароль',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                            ),
                          ),
                          validator: (value) =>
                              (value == null || value.length < 10)
                              ? 'Минимум 10 символов'
                              : null,
                        ),
                        const SizedBox(height: AppSpace.md),
                        TextFormField(
                          controller: _confirmPasswordController,
                          obscureText: _obscurePassword,
                          decoration: _v7FieldDecoration(
                            context,
                            labelText: 'Повторите пароль',
                            prefixIcon: const Icon(Icons.lock_reset_outlined),
                          ),
                          validator: (value) =>
                              value != _passwordController.text
                              ? 'Пароли не совпадают'
                              : null,
                        ),
                        const SizedBox(height: AppSpace.lg),
                        _GoldButton(
                          loading: _isSavingPassword,
                          onPressed: _isSavingPassword ? null : _setPassword,
                          icon: Icons.password_outlined,
                          label: hasEmail
                              ? 'Сохранить пароль'
                              : 'Установить пароль',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AuthMethodsData {
  final String email;
  final List<MagicAuthIdentity> identities;
  final bool emailOtpMfaEnabled;

  const _AuthMethodsData({
    required this.email,
    required this.identities,
    required this.emailOtpMfaEnabled,
  });
}

class _Section extends StatelessWidget {
  final Widget child;

  const _Section({required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: child,
      ),
    );
  }
}

class _IdentityRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;

  const _IdentityRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: enabled ? AppColor.gold : null),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Icon(
        enabled ? Icons.check_circle_outline : Icons.radio_button_unchecked,
        color: enabled ? AppColor.gold : null,
      ),
    );
  }
}

/// Flat gold primary button — same look as login's primary button
/// (gold fill, [AppColor.onGold] text/spinner, no shadow, control radius).
class _GoldButton extends StatelessWidget {
  const _GoldButton({
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return Opacity(
      opacity: enabled ? 1.0 : 0.42,
      child: SizedBox(
        height: 52,
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
