import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'windows_update_service.dart';

/// The newer Windows build discovered by an automatic or manual check, if any.
///
/// Updated by `checkAndPromptWindowsUpdate` and the updates center, then
/// watched by the app-level `WindowsUpdateOverlay` to mark the version action
/// with a gold notification dot on every desktop route and for every role.
final availableUpdateProvider =
    NotifierProvider<AvailableUpdateNotifier, UpdateManifest?>(
      AvailableUpdateNotifier.new,
    );

class AvailableUpdateNotifier extends Notifier<UpdateManifest?> {
  @override
  UpdateManifest? build() => null;

  void set(UpdateManifest? manifest) => state = manifest;
}
