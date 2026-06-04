import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/features/auth/providers/release_gate_provider.dart';

class AccountDeletionScreen extends ConsumerStatefulWidget {
  const AccountDeletionScreen({super.key});

  @override
  ConsumerState<AccountDeletionScreen> createState() =>
      _AccountDeletionScreenState();
}

class _AccountDeletionScreenState extends ConsumerState<AccountDeletionScreen> {
  final _reasonController = TextEditingController();
  bool _confirmed = false;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _requestDeletion() async {
    if (!_confirmed) return;

    setState(() => _isSubmitting = true);
    try {
      await ref
          .read(supaReleaseGateServiceProvider)
          .requestAccountDeletion(reason: _reasonController.text.trim());
      ref.invalidate(releaseGateStatusProvider);
      ref.invalidate(pendingDeletionRequestProvider);

      if (mounted) context.go('/account-deletion-status');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Не удалось отправить запрос: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Удалить аккаунт')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Icon(
                Icons.delete_forever_outlined,
                size: 56,
                color: AppTheme.danger,
              ),
              const SizedBox(height: 20),
              Text(
                'Запрос на удаление аккаунта будет отправлен администрации Magic Music. Данные аккаунта будут удалены или обезличены, кроме записей, которые необходимо хранить по закону.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _reasonController,
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Причина обращения',
                  hintText: 'Необязательно',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                value: _confirmed,
                onChanged: (value) {
                  setState(() => _confirmed = value ?? false);
                },
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text(
                  'Я понимаю, что запрашиваю удаление аккаунта',
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _confirmed && !_isSubmitting
                    ? _requestDeletion
                    : null,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_outlined),
                label: const Text('Отправить запрос'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
