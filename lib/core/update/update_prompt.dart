import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'update_center.dart';
import 'windows_update_coordinator.dart';
import 'windows_update_service.dart';

/// Checks the Windows update manifest and, if a newer build is available,
/// reports it via [onUpdateAvailable] (→ the persistent global indicator) and
/// asks the user whether to install it now. A no-op on non-Windows /
/// unversioned builds and on any network failure.
Future<void> checkAndPromptWindowsUpdate({
  required GlobalKey<NavigatorState> navigatorKey,
  required String manifestUrl,
  WindowsUpdateService? service,
  void Function(UpdateManifest manifest)? onUpdateAvailable,
  bool Function(UpdateManifest manifest)? shouldPrompt,
}) async {
  final svc = service ?? WindowsUpdateService(manifestUrl: manifestUrl);
  if (!svc.isSupported) return;

  final manifest = await svc.check();
  if (manifest == null) return;

  // Keep the update reachable even when the dialog below is dismissed —
  // the app overlay shows a persistent «Обновить» button off this hook.
  onUpdateAvailable?.call(manifest);

  if (shouldPrompt != null && !shouldPrompt(manifest)) return;

  final ctx = navigatorKey.currentContext;
  if (ctx == null || !ctx.mounted) return;

  await showWindowsUpdateDialog(ctx, manifest, service: svc);
}

/// Shows the «Доступно обновление» dialog for [manifest]: install now
/// («Обновить и перезапустить»), download the zip in the browser («Скачать
/// вручную» — fallback for when the helper cannot run), or dismiss («Позже»).
///
/// Reused by both the startup check and the persistent global button.
Future<void> showWindowsUpdateDialog(
  BuildContext context,
  UpdateManifest manifest, {
  WindowsUpdateService? service,
}) async {
  await windowsUpdateCoordinator.runFlow(
    () => _showWindowsUpdateDialog(context, manifest, service: service),
  );
}

Future<void> _showWindowsUpdateDialog(
  BuildContext context,
  UpdateManifest manifest, {
  WindowsUpdateService? service,
}) async {
  final accepted = await showDialog<bool>(
    context: context,
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
              'Приложение закроется, обновится и запустится снова. Это займёт '
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
          // Fallback: fetch the zip in the browser and replace files by hand —
          // for machines where the detached helper cannot run (AV/policy).
          TextButton(
            onPressed: () {
              unawaited(
                launchUrl(
                  Uri.parse(manifest.url),
                  mode: LaunchMode.externalApplication,
                ).catchError((_) => false),
              );
            },
            child: const Text('Скачать вручную'),
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
  if (!context.mounted) return;

  // Brief blocking indicator; applyAndRestart normally quits the process. Keep
  // the route future so a synchronous launch failure can close it reliably.
  final progressClosed = showDialog<void>(
    context: context,
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
  final svc = service ?? WindowsUpdateService(manifestUrl: '');
  try {
    await svc.applyAndRestart(manifest);
    // A supported production updater exits. Returning means it could not take
    // over (or the dialog was invoked on an unsupported platform).
    throw StateError('Updater helper did not take over the application.');
  } catch (error) {
    if (!context.mounted) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    if (navigator.canPop()) navigator.pop();
    await progressClosed;
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (errorContext) => AlertDialog(
        icon: const Icon(Icons.error_outline_rounded, color: AppColor.danger),
        title: const Text('Не удалось запустить обновление'),
        content: const Text(
          'Приложение продолжит работать. Попробуйте ещё раз или скачайте '
          'обновление вручную.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              unawaited(
                launchUrl(
                  Uri.parse(manifest.url),
                  mode: LaunchMode.externalApplication,
                ).catchError((_) => false),
              );
            },
            child: const Text('Скачать вручную'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(errorContext).pop(),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }
}

/// Global, route-independent update affordance. It wraps the MaterialApp's
/// routed child, so it remains visible on login, client, teacher and CRM screens
/// instead of being tied to one desktop navigation rail.
class WindowsUpdateOverlay extends StatefulWidget {
  const WindowsUpdateOverlay({
    super.key,
    required this.child,
    required this.manifest,
    required this.onVersionPressed,
    required this.navigatorKey,
  });

  final Widget child;
  final UpdateManifest? manifest;
  final VoidCallback onVersionPressed;
  final GlobalKey<NavigatorState> navigatorKey;

  @override
  State<WindowsUpdateOverlay> createState() => _WindowsUpdateOverlayState();
}

class _WindowsUpdateOverlayState extends State<WindowsUpdateOverlay> {
  OverlayEntry? _entry;
  OverlayState? _overlay;
  bool _syncScheduled = false;

  @override
  void initState() {
    super.initState();
    _scheduleOverlaySync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleOverlaySync();
  }

  @override
  void didUpdateWidget(covariant WindowsUpdateOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleOverlaySync();
  }

  void _scheduleOverlaySync() {
    if (_syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (!mounted) return;
      final nextOverlay = widget.navigatorKey.currentState?.overlay;
      if (nextOverlay == null) {
        Future<void>.delayed(const Duration(milliseconds: 100), () {
          if (mounted) _scheduleOverlaySync();
        });
        return;
      }
      if (!identical(_overlay, nextOverlay)) {
        _removeEntry();
        _entry = OverlayEntry(builder: _buildOverlay);
        _overlay = nextOverlay;
        nextOverlay.insert(_entry!);
      } else {
        _entry?.markNeedsBuild();
      }
    });
  }

  Widget _buildOverlay(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showVersion = Platform.isWindows && constraints.maxWidth >= 840;
        return Stack(
          fit: StackFit.expand,
          children: [
            if (showVersion)
              Positioned(
                left: 7,
                bottom: 7,
                child: SafeArea(
                  minimum: const EdgeInsets.all(AppSpace.xs),
                  child: AppVersionButton(
                    hasUpdate: widget.manifest != null,
                    onPressed: widget.onVersionPressed,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  void _removeEntry() {
    final entry = _entry;
    if (entry != null) {
      entry.remove();
      entry.dispose();
    }
    _entry = null;
    _overlay = null;
  }

  @override
  void dispose() {
    _removeEntry();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
