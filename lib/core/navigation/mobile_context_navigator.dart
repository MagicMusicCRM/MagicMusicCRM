import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/navigation/app_back_policy.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/core/navigation/mobile_context_stack.dart';

typedef MobileContextPageBuilder =
    Widget Function(BuildContext context, ContextRouteState route);

class MobileContextNavigator extends ConsumerWidget {
  const MobileContextNavigator({
    super.key,
    required this.pageBuilder,
    this.empty,
  });

  final MobileContextPageBuilder pageBuilder;
  final Widget? empty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stack = ref.watch(mobileContextStackProvider);
    final current = stack.current;
    if (current == null) {
      return empty ?? const SizedBox.shrink();
    }
    return AppBackScope(
      hasLocalHistory: stack.canPop,
      onBack: () => ref.read(mobileContextStackProvider.notifier).pop(),
      child: KeyedSubtree(
        key: ValueKey('${current.link.rawEntityType}:${current.link.entityId}'),
        child: pageBuilder(context, current),
      ),
    );
  }
}
