import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/features/auth/providers/release_gate_provider.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final service = ref.read(supaReleaseGateServiceProvider);
      await service.completeOnboarding(
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        phone: _phoneController.text.trim(),
      );
      await service.ensureAdminChatThread();
      ref.invalidate(releaseGateStatusProvider);

      if (mounted) context.go('/legal-consent');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Не удалось сохранить данные: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Заполните профиль')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 450),
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Icon(
                  Icons.account_circle_outlined,
                  size: 56,
                  color: colorScheme.primary,
                ),
                const SizedBox(height: 20),
                Text(
                  'Эти данные нужны школе для связи и корректной работы CRM.',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                TextFormField(
                  controller: _firstNameController,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.givenName],
                  decoration: const InputDecoration(
                    labelText: 'Имя',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Укажите имя'
                      : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _lastNameController,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.familyName],
                  decoration: const InputDecoration(
                    labelText: 'Фамилия',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Укажите фамилию'
                      : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  decoration: const InputDecoration(
                    labelText: 'Номер телефона',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                  validator: (value) => value == null || value.trim().length < 6
                      ? 'Укажите номер телефона'
                      : null,
                  onFieldSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _isSaving ? null : _submit,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.arrow_forward),
                  label: const Text('Продолжить'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
