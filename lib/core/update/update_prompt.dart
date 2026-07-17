import 'package:flutter/material.dart';

import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'windows_update_service.dart';

/// Checks the Windows update manifest and, if a newer build is available, asks
/// the user whether to install it now. A no-op on non-Windows / unversioned
/// builds and on any network failure.
Future<void> checkAndPromptWindowsUpdate({
  required GlobalKey<NavigatorState> navigatorKey,
  required String manifestUrl,
  WindowsUpdateService? service,
}) async {
  final svc = service ?? WindowsUpdateService(manifestUrl: manifestUrl);
  if (!svc.isSupported) return;

  final manifest = await svc.check();
  if (manifest == null) return;

  final ctx = navigatorKey.currentContext;
  if (ctx == null || !ctx.mounted) return;

  final accepted = await showDialog<bool>(
    context: ctx,
    barrierDismissible: true,
    builder: (dialogCtx) {
      final cs = Theme.of(dialogCtx).colorScheme;
      return AlertDialog(
        icon: const Icon(Icons.system_update_alt_rounded, color: AppColor.gold),
        title: const Text('Доступно обновление'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Версия ${manifest.version} готова к установке.',
              style: const TextStyle(fontSize: 14),
            ),
            if ((manifest.notes ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: AppSpace.md),
              Text(
                manifest.notes!.trim(),
                style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: AppSpace.md),
            Text(
              'Приложение закроется, обновится и запустится снова — это займёт '
              'несколько секунд.',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Позже'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColor.gold,
              foregroundColor: AppColor.onGold,
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Обновить и перезапустить'),
          ),
        ],
      );
    },
  );

  if (accepted != true) return;

  // Brief blocking indicator; applyAndRestart quits the process shortly after.
  final ctx2 = navigatorKey.currentContext;
  if (ctx2 != null && ctx2.mounted) {
    showDialog<void>(
      context: ctx2,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            SizedBox(width: AppSpace.lg),
            Expanded(child: Text('Загружаем обновление…')),
          ],
        ),
      ),
    );
  }
  await svc.applyAndRestart(manifest);
}
