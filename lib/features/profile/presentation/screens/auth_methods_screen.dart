import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Способы входа')),
      body: ResponsiveConstraint(
        child: FutureBuilder<_AuthMethodsData>(
          future: _authMethodsFuture,
          builder: (context, snapshot) {
            final data = snapshot.data;
            final identities = data?.identities ?? const <MagicAuthIdentity>[];
            final userEmail = data?.email ?? '';
            final hasEmail = identities.any((item) => item.provider == 'email');
            final emailOtpMfaEnabled = data?.emailOtpMfaEnabled ?? false;

            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  userEmail.isEmpty ? 'Аккаунт' : userEmail,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                _Section(
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
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
                const SizedBox(height: 16),
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
                const SizedBox(height: 24),
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
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
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
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _confirmPasswordController,
                          obscureText: _obscurePassword,
                          decoration: const InputDecoration(
                            labelText: 'Повторите пароль',
                            prefixIcon: Icon(Icons.lock_reset_outlined),
                          ),
                          validator: (value) =>
                              value != _passwordController.text
                              ? 'Пароли не совпадают'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _isSavingPassword ? null : _setPassword,
                          icon: _isSavingPassword
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.password_outlined),
                          label: Text(
                            hasEmail ? 'Сохранить пароль' : 'Установить пароль',
                          ),
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
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
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
      leading: Icon(icon, color: enabled ? AppTheme.primaryGold : null),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Icon(
        enabled ? Icons.check_circle_outline : Icons.radio_button_unchecked,
        color: enabled ? AppTheme.primaryGold : null,
      ),
    );
  }
}
