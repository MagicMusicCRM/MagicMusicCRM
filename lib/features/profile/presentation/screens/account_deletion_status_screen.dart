import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/widgets/magic_page_state.dart';
import 'package:magic_music_crm/features/auth/providers/magic_auth_provider.dart';
import 'package:magic_music_crm/features/auth/providers/release_gate_provider.dart';

class AccountDeletionStatusScreen extends ConsumerStatefulWidget {
  const AccountDeletionStatusScreen({super.key});

  @override
  ConsumerState<AccountDeletionStatusScreen> createState() =>
      _AccountDeletionStatusScreenState();
}

class _AccountDeletionStatusScreenState
    extends ConsumerState<AccountDeletionStatusScreen> {
  bool _cancelling = false;

  Future<void> _cancelRequest() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Отозвать запрос?'),
        content: const Text(
          'Запрос вернётся в историю со статусом «Отменён», '
          'а доступ к приложению будет восстановлен.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Оставить запрос'),
          ),
          FilledButton(
            key: const ValueKey('confirm-cancel-deletion-request'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Отозвать'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _cancelling = true);
    try {
      await ref.read(releaseGateServiceProvider).cancelAccountDeletion();
      ref.invalidate(pendingDeletionRequestProvider);
      ref.invalidate(releaseGateStatusProvider);
      if (mounted) context.go('/');
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userErrorMessage(error, fallback: 'Не удалось отозвать запрос.'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final requestAsync = ref.watch(pendingDeletionRequestProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Удаление аккаунта')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: requestAsync.when(
            loading: () => const MagicPageState.loading(),
            error: (error, _) => MagicPageState(
              kind: MagicPageStateKind.error,
              title: 'Не удалось загрузить статус',
              message: userErrorMessage(
                error,
                fallback: 'Не удалось загрузить статус удаления.',
              ),
              actionLabel: 'Повторить',
              onAction: () => ref.invalidate(pendingDeletionRequestProvider),
            ),
            data: (request) {
              if (request == null) {
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle_outline, size: 56),
                      const SizedBox(height: 16),
                      const Text('Активного запроса на удаление нет.'),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: () => context.go('/'),
                        child: const Text('Вернуться в приложение'),
                      ),
                    ],
                  ),
                );
              }

              return Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.hourglass_top, size: 56),
                    const SizedBox(height: 16),
                    Text(
                      request.status == 'processing'
                          ? 'Запрос обрабатывается'
                          : 'Запрос принят',
                      style: Theme.of(context).textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Администрация проверит запрос. До завершения обработки доступ к системе ограничен.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 24),
                    if (request.status == 'pending') ...[
                      OutlinedButton.icon(
                        key: const ValueKey('cancel-deletion-request'),
                        onPressed: _cancelling ? null : _cancelRequest,
                        icon: _cancelling
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.undo_rounded),
                        label: const Text('Отозвать запрос'),
                      ),
                      const SizedBox(height: 12),
                    ],
                    FilledButton.icon(
                      onPressed: () async {
                        await ref.read(magicAuthServiceProvider).signOut();
                        if (context.mounted) context.go('/login');
                      },
                      icon: const Icon(Icons.logout),
                      label: const Text('Выйти'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
