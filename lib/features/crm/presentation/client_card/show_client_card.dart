import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/features/auth/providers/release_gate_provider.dart';
import 'client_card.dart';
import 'teacher_client_card.dart';

/// Responsive launcher for the unified «Карточка клиента».
///
/// - Desktop (width ≥ 720): a centered [Dialog] hosting [ClientCard].
/// - Mobile (< 720): a scroll-controlled bottom sheet (v7 `.sheet` sizing —
///   maxWidth ~600, maxHeight 85%) hosting the same [ClientCard].
///
/// Resolves to the `bool?` the card pops — `true` means "data changed" (the
/// board / list should refresh). Matches the former `LeadDetailDialog`
/// open contract.
///
/// [seed] is an optional board / list row used to render the card instantly;
/// the card still self-fetches its full data from [entityId]. When omitted the
/// card opens from a minimal `{'id': entityId}` stub.
Future<bool?> showClientCard(
  BuildContext context, {
  required String entityType,
  required String entityId,
  Map<String, dynamic>? seed,
}) {
  final lead = <String, dynamic>{...?seed, 'id': entityId};
  final card = _ClientCardEntry(
    lead: lead,
    entityType: entityType,
    entityId: entityId,
  );
  final isDesktop = MediaQuery.of(context).size.width >= 720;

  if (isDesktop) {
    return showDialog<bool>(context: context, builder: (_) => card);
  }

  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColor.scrim,
    builder: (ctx) {
      final media = MediaQuery.of(ctx);
      return Padding(
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 600,
              maxHeight: media.size.height * 0.85,
            ),
            child: card,
          ),
        ),
      );
    },
  );
}

class _ClientCardEntry extends ConsumerWidget {
  const _ClientCardEntry({
    required this.lead,
    required this.entityType,
    required this.entityId,
  });

  final Map<String, dynamic> lead;
  final String entityType;
  final String entityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gate = ref.watch(releaseGateStatusProvider);
    return gate.when(
      data: (status) => status.role == 'teacher'
          ? TeacherClientCard(entityType: entityType, entityId: entityId)
          : ClientCard(lead: lead, entityType: entityType),
      loading: () => const Dialog(
        child: SizedBox.square(
          dimension: 160,
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (error, _) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.xl),
          child: Text('Не удалось определить доступ: $error'),
        ),
      ),
    );
  }
}
