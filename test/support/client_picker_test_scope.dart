import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';

/// Isolated form tests retain their injected business callbacks and never read
/// client directory/finance APIs. Native HTTP journeys verify picker details.
Widget clientPickerTestScope(Widget child) => ProviderScope(
  overrides: [
    capabilitySnapshotProvider.overrideWith(
      (ref) async => const CapabilitySnapshot(
        accountId: 'form-test',
        role: 'admin',
        accessVersion: 1,
        capabilities: {},
        scopes: {},
      ),
    ),
  ],
  child: child,
);
