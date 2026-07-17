import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/widgets/v7/v7.dart';
import 'package:magic_music_crm/features/messenger/presentation/screens/crm_nav_rbac.dart';
// The package create/edit sheet and the packages provider already exist in the
// (otherwise un-mounted) admin entity manager. Reuse them so the manager's
// catalog stays in sync with the same backend и form, без дублирования.
import 'package:magic_music_crm/features/admin/presentation/widgets/manage_entities_widget.dart'
    show entitiesProvider, showPackageSheet;

/// Каталог абонементов. Управляющий его ВИДИТ (и выдаёт абонементы ученикам из
/// карточки → «Выдать абонемент», атомарно создающий платёж + подписку), но сам
/// каталог (создание/изменение/удаление пакетов с ценами) — это ценовая
/// конфигурация уровня Директора (общешкольные финансы, KVA-239). Поэтому
/// кнопки управления показываются только Директору/Администратору системы;
/// бэкенд гейтит их через assertCanManageSubscriptionPackages.
class SubscriptionCatalogWidget extends ConsumerWidget {
  final String role;
  const SubscriptionCatalogWidget({super.key, required this.role});

  bool get _canManage => crmHasSchoolFinanceAccess(role);

  static const _provider = 'subscription_packages';

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final saved = await showPackageSheet(context, ref);
    if (saved == true) ref.invalidate(entitiesProvider(_provider));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(entitiesProvider(_provider));
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
            loading: () => const Center(
              child: CircularProgressIndicator(color: AppTheme.primaryGold),
            ),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Ошибка: $e',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppTheme.danger),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () =>
                          ref.invalidate(entitiesProvider(_provider)),
                      child: const Text('Повторить'),
                    ),
                  ],
                ),
              ),
            ),
            data: (items) {
              if (items.isEmpty) {
                return _EmptyCatalog(
                  onCreate: _canManage ? () => _create(context, ref) : null,
                );
              }
              return RefreshIndicator(
                color: AppTheme.primaryGold,
                onRefresh: () async =>
                    ref.invalidate(entitiesProvider(_provider)),
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                  itemCount: items.length,
                  itemBuilder: (ctx, i) =>
                      _PackageRow(item: items[i], canManage: _canManage),
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

  num _asNum(Object? v) =>
      v is num ? v : num.tryParse(v?.toString() ?? '') ?? 0;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final id = item['id']?.toString();
    if (id == null || id.isEmpty) return;
    final name = item['name'] as String? ?? 'абонемент';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить абонемент?'),
        content: Text('«$name» будет удалён из каталога. Действие необратимо.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Удалить',
              style: TextStyle(color: AppTheme.danger),
            ),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;
    try {
      await ref.read(magicCrmServiceProvider).deleteSubscriptionPackage(id);
      ref.invalidate(entitiesProvider('subscription_packages'));
      if (context.mounted) {
        MagicToast.show(
          context,
          'Абонемент удалён',
          type: MagicToastType.success,
        );
      }
    } catch (e) {
      if (context.mounted) {
        MagicToast.show(
          context,
          'Не удалось удалить',
          detail: '$e',
          type: MagicToastType.danger,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final name = item['name'] as String? ?? 'Без названия';
    final hoursNum = _asNum(item['lessons_total'] ?? item['lessonsTotal']);
    final hours = hoursNum % 1 == 0 ? hoursNum.toInt() : hoursNum;
    final price = _asNum(item['price']);
    final validityRaw = item['validity_days'] ?? item['validityDays'];
    final validity = validityRaw == null ? null : _asNum(validityRaw).toInt();
    final isActive =
        item['is_active'] == true ||
        item['isActive'] == true ||
        (item['is_active'] == null && item['isActive'] == null);
    final money = NumberFormat('#,##0', 'ru').format(price);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        // View-only for a manager: tapping to edit is disabled and the delete
        // control is hidden. Only director/system_admin manage the catalog.
        onTap: canManage
            ? () async {
                final saved = await showPackageSheet(
                  context,
                  ref,
                  existing: item,
                );
                if (saved == true) {
                  ref.invalidate(entitiesProvider('subscription_packages'));
                }
              }
            : null,
        leading: CircleAvatar(
          backgroundColor: AppTheme.primaryGold.withAlpha(40),
          child: const Icon(
            Icons.card_membership_rounded,
            color: AppTheme.primaryGold,
          ),
        ),
        title: Text(name),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _Chip(icon: Icons.schedule_rounded, label: 'Часов: $hours'),
              _Chip(icon: Icons.payments_rounded, label: '$money ₽'),
              if (validity != null)
                _Chip(
                  icon: Icons.schedule_rounded,
                  label: 'Срок: $validity дн.',
                ),
              _Chip(
                icon: isActive
                    ? Icons.check_circle_outline_rounded
                    : Icons.pause_circle_outline_rounded,
                label: isActive ? 'Активен' : 'Неактивен',
                color: isActive ? AppTheme.success : cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
        trailing: canManage
            ? IconButton(
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppTheme.danger,
                ),
                tooltip: 'Удалить',
                onPressed: () => _delete(context, ref),
              )
            : null,
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  const _Chip({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.primaryGold;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withAlpha(25),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: c),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, color: c)),
        ],
      ),
    );
  }
}

class _EmptyCatalog extends StatelessWidget {
  // Null → view-only (manager): no «Создать» button, just the empty message.
  final VoidCallback? onCreate;
  const _EmptyCatalog({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
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
            'Нет абонементов',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 16),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'Создайте пакет (часы + срок + цена), затем выдайте его '
              'ученику из его карточки → «Выдать абонемент».',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
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
    );
  }
}
