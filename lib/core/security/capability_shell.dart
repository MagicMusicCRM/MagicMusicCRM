import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/v7/magic_shimmer.dart';

class CapabilityShellGate extends ConsumerWidget {
  const CapabilityShellGate({super.key, required this.builder});

  final Widget Function(BuildContext context, CapabilitySnapshot snapshot)
  builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(capabilitySnapshotProvider);
    return snapshot.when(
      skipLoadingOnReload: false,
      data: (value) => KeyedSubtree(
        key: ValueKey(value.cacheKey),
        child: builder(context, value),
      ),
      loading: () => Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.xl),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SkeletonBox(height: 52),
                SizedBox(height: 16),
                Expanded(child: SkeletonBox()),
              ],
            ),
          ),
        ),
      ),
      error: (_, _) => Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline_rounded, size: 36),
                  const SizedBox(height: 12),
                  const Text(
                    'Не удалось проверить доступ',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => ref.invalidate(capabilitySnapshotProvider),
                    child: const Text('Повторить'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
