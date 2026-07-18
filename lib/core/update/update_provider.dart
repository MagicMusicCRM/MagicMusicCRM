import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'windows_update_coordinator.dart';
import 'windows_update_service.dart';

/// The newer Windows build discovered by the startup manifest check, if any.
///
/// Set once by `checkAndPromptWindowsUpdate` (see `update_prompt.dart`) and
/// watched by the app-level `WindowsUpdateOverlay` to render a persistent
/// «Обновить» button on every route and for every role — so a user who dismissed
/// the startup dialog can still install without restarting the app.
final availableUpdateProvider =
    NotifierProvider<AvailableUpdateNotifier, UpdateManifest?>(
      AvailableUpdateNotifier.new,
    );

class AvailableUpdateNotifier extends Notifier<UpdateManifest?> {
  @override
  UpdateManifest? build() => null;

  void set(UpdateManifest? manifest) => state = manifest;
}

/// Mirrors the process-wide coordinator into Riverpod so the app-level
/// overlay disappears synchronously for startup, manual, and direct launches.
final windowsUpdateFlowActiveProvider =
    NotifierProvider<WindowsUpdateFlowActiveNotifier, bool>(
      WindowsUpdateFlowActiveNotifier.new,
    );

class WindowsUpdateFlowActiveNotifier extends Notifier<bool> {
  @override
  bool build() {
    final subscription = windowsUpdateCoordinator.activity.listen((active) {
      state = active;
    });
    ref.onDispose(subscription.cancel);
    return windowsUpdateCoordinator.isBusy;
  }
}
