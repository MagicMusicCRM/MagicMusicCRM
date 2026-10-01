import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/models/commerce_projection.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/services/crm_realtime_provider.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';

final _clientBranchProvider = FutureProvider.autoDispose
    .family<String, (String, String, String?, bool)>((ref, client) async {
      final access = await ref.watch(capabilitySnapshotProvider.future);
      if (!access.allows('crm.client.read.basic') ||
          !access.allows('schedule.lesson.read.assigned')) {
        return 'Филиал недоступен';
      }
      ref.listen(crmRealtimeProvider, (_, event) {
        if (event.asData != null) ref.invalidateSelf();
      });
      final crm = ref.watch(magicCrmServiceProvider);
      final branchId = client.$4
          ? client.$3
          : (await crm.resolveClientRef(
              type: client.$1,
              id: client.$2,
            ))['branchId']?.toString();
      if (branchId == null || branchId.isEmpty) return 'Филиал не выбран';
      final branches = await ref.watch(_pickerBranchesProvider.future);
      final branch = branches
          .where((row) => row['id']?.toString() == branchId)
          .firstOrNull;
      return branch?['name']?.toString() ?? 'Филиал недоступен';
    });

final _pickerBranchesProvider = FutureProvider.autoDispose(
  (ref) => ref.watch(magicCrmServiceProvider).listBranches(),
);

final _clientBalanceProvider = FutureProvider.autoDispose
    .family<CommerceLessonBalance?, String>((ref, id) async {
      // ponytail: one scoped projection per rendered client; use a batch read
      // if measured picker latency outgrows the existing 50-result search cap.
      final access = await ref.watch(capabilitySnapshotProvider.future);
      if (!access.allows('commerce.client_finance.read') ||
          !{
            'admin',
            'manager',
            'director',
            'system_admin',
          }.contains(access.role)) {
        return null;
      }
      ref.listen(crmRealtimeProvider, (_, event) {
        if (event.asData != null) ref.invalidateSelf();
      });
      return (await ref
              .watch(magicCrmServiceProvider)
              .getStudentCommerceProjection(id))
          .student
          .lessonBalance;
    });

/// Client identity and balances remain separate, actor-scoped API projections.
class ClientSelectionDetails extends ConsumerWidget {
  const ClientSelectionDetails({
    super.key,
    required this.type,
    required this.id,
    this.subtitle,
    this.branchId,
    this.branchKnown = false,
  });
  final String type, id;
  final String? subtitle;
  final String? branchId;
  final bool branchKnown;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branch = ref
        .watch(_clientBranchProvider((type, id, branchId, branchKnown)))
        .when(
          skipLoadingOnRefresh: false,
          data: (value) => value,
          loading: () => 'Филиал: загрузка…',
          error: (_, _) => 'Филиал: не удалось загрузить',
        );
    final subscription = type == 'lead'
        ? 'Нет абонемента'
        : ref
              .watch(_clientBalanceProvider(id))
              .when(
                skipLoadingOnRefresh: false,
                data: (balance) => balance == null
                    ? 'Абонемент: нет доступа'
                    : balance.activeSubscriptionCount == 0
                    ? 'Нет абонемента'
                    : 'Есть абонемент · осталось ${NumberFormat('0.##', 'ru').format((balance.total - balance.used).clamp(0, double.infinity))} астр. ч',
                loading: () => 'Абонемент: загрузка…',
                error: (_, _) => 'Абонемент: не удалось загрузить',
              );
    final text =
        '${subtitle ?? (type == 'lead' ? 'Лид' : 'Ученик')} · $branch\n$subscription';
    return Tooltip(
      message: text,
      child: Text(
        text,
        key: ValueKey('client-details-$type-$id'),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}
