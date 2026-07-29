import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:intl/intl.dart';

import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/widgets/v7/v7.dart';
import 'package:magic_music_crm/features/messenger/presentation/screens/crm_nav_rbac.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/manage_entities_widget.dart'
    show
        entitiesProvider,
        invalidateSubscriptionPackageCatalog,
        showPackageSheet;

final _packageMutationBusyProvider = StateProvider.autoDispose
    .family<bool, String>((ref, id) => false);

/// Versioned subscription-package catalog.
///
/// Admin/Manager consume only the active projection when issuing a package.
/// Director/system_admin receive the management projection and own every
/// create/edit/archive/restore affordance.
class SubscriptionCatalogWidget extends ConsumerWidget {
  final String role;
  const SubscriptionCatalogWidget({super.key, required this.role});

  bool get _canManage => crmCanManageSubscriptionPackages(role);
  String get _providerKey =>
      _canManage ? 'subscription_packages:all' : 'subscription_packages';

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final saved = await showPackageSheet(context, ref);
    if (saved == true) invalidateSubscriptionPackageCatalog(ref);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final providerKey = _providerKey;
    final async = ref.watch(entitiesProvider(providerKey));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Каталог абонементов',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              if (_canManage)
                FilledButton.icon(
                  key: const Key('subscription-catalog-create'),
                  onPressed: () => _create(context, ref),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryGold,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Создать'),
                ),
            ],
          ),
        ),
        Expanded(
          child: async.when(
            loading: () => const _CatalogSkeleton(),
            error: (error, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Не удалось загрузить каталог',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppTheme.danger),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$error',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      key: const Key('subscription-catalog-retry'),
                      onPressed: () =>
                          ref.invalidate(entitiesProvider(providerKey)),
                      child: const Text('Повторить'),
                    ),
                  ],
                ),
              ),
            ),
            data: (items) {
              if (items.isEmpty) {
                return _EmptyCatalog(
                  canManage: _canManage,
                  onCreate: _canManage ? () => _create(context, ref) : null,
                );
              }
              return RefreshIndicator(
                color: AppTheme.primaryGold,
                onRefresh: () async {
                  ref.invalidate(entitiesProvider(providerKey));
                  await ref.read(entitiesProvider(providerKey).future);
                },
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                  itemCount: items.length,
                  itemBuilder: (context, index) =>
                      _PackageRow(item: items[index], canManage: _canManage),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PackageRow extends ConsumerWidget {
  final Map<String, dynamic> item;
  final bool canManage;

  const _PackageRow({required this.item, required this.canManage});

  num _asNum(Object? value) =>
      value is num ? value : num.tryParse(value?.toString() ?? '') ?? 0;

  int get _version {
    final value = item['version'];
    return value is int ? value : int.tryParse('$value') ?? 0;
  }

  bool get _archived {
    final archivedAt = item['archivedAt'] ?? item['archived_at'];
    final active = item['active'] ?? item['isActive'] ?? item['is_active'];
    return archivedAt != null || active == false;
  }

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String message,
    required String action,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Отмена'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(action),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _archive(BuildContext context, WidgetRef ref) async {
    final id = item['id']?.toString();
    if (id == null || id.isEmpty || _version < 1) return;
    final busyProvider = _packageMutationBusyProvider(id);
    if (ref.read(busyProvider)) return;
    ref.read(busyProvider.notifier).state = true;
    final name = item['name']?.toString() ?? 'абонемент';
    try {
      final confirmed = await _confirm(
        context,
        title: 'Архивировать абонемент?',
        message:
            '«$name» исчезнет из новой выдачи. Уже выданные абонементы и '
            'их условия сохранятся; пакет можно будет восстановить.',
        action: 'Архивировать',
      );
      if (!confirmed || !context.mounted) return;
      await ref
          .read(magicCrmServiceProvider)
          .archiveSubscriptionPackage(id, expectedVersion: _version);
      invalidateSubscriptionPackageCatalog(ref);
      if (context.mounted) {
        MagicToast.show(
          context,
          'Пакет перемещён в архив',
          type: MagicToastType.success,
        );
      }
    } catch (error) {
      invalidateSubscriptionPackageCatalog(ref);
      if (context.mounted) _showMutationError(context, error);
    } finally {
      if (context.mounted) {
        ref.read(busyProvider.notifier).state = false;
      }
    }
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final id = item['id']?.toString();
    if (id == null || id.isEmpty || _version < 1) return;
    final busyProvider = _packageMutationBusyProvider(id);
    if (ref.read(busyProvider)) return;
    ref.read(busyProvider.notifier).state = true;
    try {
      await ref
          .read(magicCrmServiceProvider)
          .restoreSubscriptionPackage(id, expectedVersion: _version);
      invalidateSubscriptionPackageCatalog(ref);
      if (context.mounted) {
        MagicToast.show(
          context,
          'Пакет восстановлен',
          type: MagicToastType.success,
        );
      }
    } catch (error) {
      invalidateSubscriptionPackageCatalog(ref);
      if (context.mounted) _showMutationError(context, error);
    } finally {
      if (context.mounted) {
        ref.read(busyProvider.notifier).state = false;
      }
    }
  }

  void _showMutationError(BuildContext context, Object error) {
    final stale = error is MagicApiException && error.statusCode == 409;
    MagicToast.show(
      context,
      stale ? 'Каталог уже изменён' : 'Не удалось изменить пакет',
      detail: stale ? 'Данные обновлены. Повторите действие.' : '$error',
      type: MagicToastType.danger,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final id = item['id']?.toString() ?? '';
    final mutationBusy = id.isNotEmpty
        ? ref.watch(_packageMutationBusyProvider(id))
        : false;
    final name = item['name']?.toString() ?? 'Без названия';
    final unitsNum = _asNum(
      item['unitCount'] ?? item['lessonsTotal'] ?? item['lessons_total'],
    );
    final units = unitsNum % 1 == 0 ? unitsNum.toInt() : unitsNum;
    final validityRaw = item['validityDays'] ?? item['validity_days'];
    final validity = validityRaw == null ? null : _asNum(validityRaw).toInt();
    final money = _formatMinorRubles(
      item['basePriceMinor'] ?? item['base_price_minor'],
      legacyPrice: item['price'],
    );
    final archived = _archived;

    return Card(
      key: Key('subscription-package-$id'),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: canManage && !archived && !mutationBusy
            ? () async {
                final saved = await showPackageSheet(
                  context,
                  ref,
                  existing: item,
                );
                if (saved == true) {
                  invalidateSubscriptionPackageCatalog(ref);
                }
              }
            : null,
        leading: CircleAvatar(
          backgroundColor: AppTheme.primaryGold.withAlpha(40),
          child: Icon(
            archived
                ? Icons.inventory_2_outlined
                : Icons.card_membership_rounded,
            color: archived ? cs.onSurfaceVariant : AppTheme.primaryGold,
          ),
        ),
        title: Text(name),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _Chip(icon: Icons.schedule_rounded, label: 'Часов: $units'),
              _Chip(icon: Icons.payments_rounded, label: '$money ₽'),
              if (validity != null)
                _Chip(
                  icon: Icons.event_available_rounded,
                  label: 'Срок: $validity дн.',
                ),
              _Chip(
                icon: archived
                    ? Icons.inventory_2_outlined
                    : Icons.check_circle_outline_rounded,
                label: archived ? 'В архиве' : 'Активен',
                color: archived ? cs.onSurfaceVariant : AppTheme.success,
              ),
              _Chip(
                icon: Icons.history_rounded,
                label: 'Версия $_version',
                color: cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
        trailing: canManage
            ? IconButton(
                key: Key(
                  archived
                      ? 'subscription-package-restore-$id'
                      : 'subscription-package-archive-$id',
                ),
                icon: mutationBusy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        archived
                            ? Icons.restore_rounded
                            : Icons.archive_outlined,
                        color: archived
                            ? AppTheme.primaryGold
                            : AppTheme.danger,
                      ),
                tooltip: archived ? 'Восстановить' : 'Архивировать',
                onPressed: mutationBusy
                    ? null
                    : () => archived
                          ? _restore(context, ref)
                          : _archive(context, ref),
              )
            : null,
      ),
    );
  }
}

String _formatMinorRubles(Object? minorValue, {Object? legacyPrice}) {
  final minor = BigInt.tryParse(minorValue?.toString() ?? '');
  if (minor == null) {
    final legacy = legacyPrice is num
        ? legacyPrice
        : num.tryParse(legacyPrice?.toString() ?? '') ?? 0;
    return NumberFormat('#,##0.##', 'ru').format(legacy);
  }
  final whole = minor ~/ BigInt.from(100);
  final fraction = (minor % BigInt.from(100)).toInt();
  final formattedWhole = NumberFormat('#,##0', 'ru').format(whole.toInt());
  return fraction == 0
      ? formattedWhole
      : '$formattedWhole,${fraction.toString().padLeft(2, '0')}';
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  const _Chip({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final chipColor = color ?? AppTheme.primaryGold;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: chipColor.withAlpha(25),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: chipColor),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, color: chipColor)),
        ],
      ),
    );
  }
}

class _CatalogSkeleton extends StatelessWidget {
  const _CatalogSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      key: const Key('subscription-catalog-loading'),
      padding: const EdgeInsets.all(16),
      itemCount: 5,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, _) => const Row(
        children: [
          SkeletonBox(width: 42, height: 42, radius: 21),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonLine(width: 180),
                SizedBox(height: 8),
                SkeletonLine(width: 250),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyCatalog extends StatelessWidget {
  final bool canManage;
  final VoidCallback? onCreate;
  const _EmptyCatalog({required this.canManage, required this.onCreate});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.card_membership_rounded,
              size: 64,
              color: cs.onSurfaceVariant.withAlpha(80),
            ),
            const SizedBox(height: 16),
            Text(
              'Нет активных абонементов',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              canManage
                  ? 'Создайте первый пакет, чтобы сотрудники могли выдать его '
                        'клиенту.'
                  : 'Директор ещё не добавил пакеты, доступные для выдачи.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
            if (onCreate != null) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: onCreate,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primaryGold,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Создать абонемент'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
