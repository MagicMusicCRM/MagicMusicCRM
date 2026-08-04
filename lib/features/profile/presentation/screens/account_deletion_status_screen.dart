import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:magic_music_crm/core/widgets/v7/magic_page_state.dart';
import 'package:magic_music_crm/features/auth/providers/magic_auth_provider.dart';
import 'package:magic_music_crm/features/auth/providers/release_gate_provider.dart';

class AccountDeletionStatusScreen extends ConsumerWidget {
  const AccountDeletionStatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              message: error.toString(),
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
                      'Администрация проверит запрос и завершит удаление аккаунта. До завершения обработки доступ к CRM ограничен.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 24),
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
