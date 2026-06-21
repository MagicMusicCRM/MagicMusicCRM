import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';

import '../../../../core/theme/design_tokens.dart';
import '../../../../core/widgets/v7/v7.dart';

/// «Качество данных» (data quality) admin panel — P5-7 / KVA-198.
///
/// Closes the phone-review + lead-dedup orphan with two v7 sections:
///   1. «Очередь телефонов» — read-only phone review queue (flagged for manual
///      review) with a live count badge.
///   2. «Дубликаты лидов» — lead merge candidates with a confirm-then-merge
///      flow (winner picker + undo affordance via the returned merge-log id).
///
/// Surfaces come from [Theme.of]'s [ColorScheme] (light + dark aware); brand
/// accents come from the v7 [AppColor] tokens. Loading renders skeletons,
/// errors render a retry, and empty renders a friendly empty state.
class DataQualityWidget extends ConsumerStatefulWidget {
  const DataQualityWidget({super.key});

  @override
  ConsumerState<DataQualityWidget> createState() => _DataQualityWidgetState();
}

class _DataQualityWidgetState extends ConsumerState<DataQualityWidget> {
  // Phone review queue state.
  bool _phoneLoading = true;
  Object? _phoneError;
  List<Map<String, dynamic>> _phoneItems = const [];
  int _phoneCount = 0;

  // Merge candidates state.
  bool _mergeLoading = true;
  Object? _mergeError;
  List<Map<String, dynamic>> _mergeItems = const [];

  // Tracks the busy merge candidate (by row key) to disable its button.
  String? _mergingKey;

  @override
  void initState() {
    super.initState();
    _loadPhones();
    _loadMerges();
  }

  Future<void> _loadPhones() async {
    setState(() {
      _phoneLoading = true;
      _phoneError = null;
    });
    try {
      final crm = ref.read(magicCrmServiceProvider);
      final items = await crm.listPhoneReviewQueue(limit: 100);
      final count = await crm.countPhoneReviewQueue();
      if (!mounted) return;
      setState(() {
        _phoneItems = items;
        _phoneCount = count;
        _phoneLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phoneError = e;
        _phoneLoading = false;
      });
    }
  }

  Future<void> _loadMerges() async {
    setState(() {
      _mergeLoading = true;
      _mergeError = null;
    });
    try {
      final items = await ref
          .read(magicCrmServiceProvider)
          .listMergeCandidates(limit: 100);
      if (!mounted) return;
      setState(() {
        _mergeItems = items;
        _mergeLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _mergeError = e;
        _mergeLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppColor.gold,
      onRefresh: () async {
        await Future.wait([_loadPhones(), _loadMerges()]);
      },
      child: ListView(
        padding: const EdgeInsets.all(AppSpace.md),
        children: [
          _SectionHeader(
            icon: Icons.phone_in_talk_rounded,
            title: 'Очередь телефонов',
            subtitle: 'Номера, помеченные для ручной проверки',
            badge: _phoneLoading ? null : _phoneCount,
          ),
          const SizedBox(height: AppSpace.sm),
          _buildPhoneSection(),
          const SizedBox(height: AppSpace.xl),
          _SectionHeader(
            icon: Icons.merge_type_rounded,
            title: 'Дубликаты лидов',
            subtitle: 'Кандидаты на объединение по телефону и имени',
            badge: _mergeLoading ? null : _mergeItems.length,
          ),
          const SizedBox(height: AppSpace.sm),
          _buildMergeSection(),
        ],
      ),
    );
  }

  // ── Phone review queue ─────────────────────────────────────────────────────
  Widget _buildPhoneSection() {
    if (_phoneLoading) return const _CardListSkeleton();
    if (_phoneError != null) {
      return _ErrorRetry(error: _phoneError!, onRetry: _loadPhones);
    }
    if (_phoneItems.isEmpty) {
      return const _EmptyState(
        icon: Icons.check_circle_outline_rounded,
        message: 'Очередь пуста — все номера в порядке',
      );
    }
    return Column(
      children: [
        for (final item in _phoneItems) _PhoneReviewCard(item: item),
      ],
    );
  }

  // ── Merge candidates ───────────────────────────────────────────────────────
  Widget _buildMergeSection() {
    if (_mergeLoading) return const _CardListSkeleton();
    if (_mergeError != null) {
      return _ErrorRetry(error: _mergeError!, onRetry: _loadMerges);
    }
    if (_mergeItems.isEmpty) {
      return const _EmptyState(
        icon: Icons.verified_outlined,
        message: 'Дубликаты не найдены',
      );
    }
    return Column(
      children: [
        for (var i = 0; i < _mergeItems.length; i++)
          _MergeCandidateCard(
            item: _mergeItems[i],
            rowKey: _mergeKey(_mergeItems[i], i),
            busy: _mergingKey == _mergeKey(_mergeItems[i], i),
            onMerge: _confirmMerge,
          ),
      ],
    );
  }

  String _mergeKey(Map<String, dynamic> item, int index) {
    final winner = _readString(item, ['winnerId', 'winner_id']);
    final loser = _readString(item, ['loserId', 'loser_id']);
    if (winner.isNotEmpty || loser.isNotEmpty) return '$winner|$loser';
    return 'idx-$index';
  }

  Future<void> _confirmMerge(Map<String, dynamic> item, String rowKey) async {
    final idA = _readString(item, ['winnerId', 'winner_id']);
    final idB = _readString(item, ['loserId', 'loser_id']);
    if (idA.isEmpty || idB.isEmpty) {
      MagicToast.show(
        context,
        'Недостаточно данных для объединения',
        type: MagicToastType.danger,
      );
      return;
    }

    final name = _readString(item, ['name']);
    final phone = _readString(item, ['phone', 'phoneNormalized', 'phone_normalized']);

    // Let the operator pick the winner (default = the primary, idA).
    final winnerId = await showDialog<String>(
      context: context,
      builder: (ctx) => _MergeConfirmDialog(
        name: name,
        phone: phone,
        primaryId: idA,
        secondaryId: idB,
      ),
    );
    if (winnerId == null || !mounted) return;

    final loserId = winnerId == idA ? idB : idA;

    setState(() => _mergingKey = rowKey);
    try {
      final res = await ref
          .read(magicCrmServiceProvider)
          .mergeLeads(winnerId: winnerId, loserId: loserId);
      if (!mounted) return;
      setState(() => _mergingKey = null);

      final mergeLogId = _readString(res, ['mergeLogId', 'merge_log_id']);
      await _loadMerges();
      if (!mounted) return;

      MagicToast.show(
        context,
        'Лиды объединены',
        detail: name.isEmpty ? null : name,
        type: MagicToastType.success,
        actionLabel: mergeLogId.isEmpty ? null : 'Отменить',
        onAction: mergeLogId.isEmpty ? null : () => _undoMerge(mergeLogId),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _mergingKey = null);
      MagicToast.show(
        context,
        'Не удалось объединить',
        detail: '$e',
        type: MagicToastType.danger,
      );
    }
  }

  Future<void> _undoMerge(String mergeLogId) async {
    try {
      await ref.read(magicCrmServiceProvider).undoMerge(mergeLogId);
      await _loadMerges();
      if (!mounted) return;
      MagicToast.show(
        context,
        'Объединение отменено',
        type: MagicToastType.success,
      );
    } catch (e) {
      if (!mounted) return;
      MagicToast.show(
        context,
        'Не удалось отменить объединение',
        detail: '$e',
        type: MagicToastType.danger,
      );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Defensive readers (snake_case AND camelCase).
// ─────────────────────────────────────────────────────────────────────────────
String _readString(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value != null) {
      final str = value.toString().trim();
      if (str.isNotEmpty) return str;
    }
  }
  return '';
}

/// A short, readable identifier for a lead/entity row (id can be a long UUID).
String _shortId(String id) {
  if (id.length <= 10) return id;
  return '${id.substring(0, 8)}…';
}

// ─────────────────────────────────────────────────────────────────────────────
// Section header with optional count badge.
// ─────────────────────────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final int? badge;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColor.goldSoft,
            borderRadius: BorderRadius.circular(AppRadius.icon),
          ),
          child: Icon(icon, color: AppColor.gold, size: 20),
        ),
        const SizedBox(width: AppSpace.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
              ),
            ],
          ),
        ),
        if (badge != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: badge! > 0 ? AppColor.goldSoft : cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(
                color: badge! > 0 ? AppColor.goldLine : cs.outlineVariant,
              ),
            ),
            child: Text(
              '$badge',
              style: TextStyle(
                color: badge! > 0 ? AppColor.gold : cs.onSurfaceVariant,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Phone review queue card (read-only).
// ─────────────────────────────────────────────────────────────────────────────
class _PhoneReviewCard extends StatelessWidget {
  final Map<String, dynamic> item;
  const _PhoneReviewCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rawPhone = _readString(item, [
      'rawPhone',
      'raw_phone',
      'phone',
      'normalizedPhone',
      'normalized',
    ]);
    final normalized = _readString(item, ['normalizedPhone', 'normalized']);
    final reason = _readString(item, ['reason']);
    final entityType = _readString(item, ['entityType', 'entity_type', 'lead']);
    final entityId = _readString(item, ['entityId', 'entity_id', 'leadId', 'lead_id']);
    final id = _readString(item, ['id']);
    final name = _readString(item, ['name', 'entityName', 'entity_name', 'leadName']);

    final phoneLabel = rawPhone.isNotEmpty
        ? rawPhone
        : (normalized.isNotEmpty ? normalized : 'Без номера');

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColor.gold.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.icon),
              ),
              child: const Icon(
                Icons.phone_forwarded_rounded,
                color: AppColor.gold,
                size: 20,
              ),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    phoneLabel,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (normalized.isNotEmpty && normalized != rawPhone) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Нормализован: $normalized',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (name.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      name,
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (reason.isNotEmpty)
                        _Chip(
                          icon: Icons.flag_outlined,
                          label: reason,
                          color: AppColor.gold,
                        ),
                      if (entityType.isNotEmpty)
                        _Chip(
                          icon: Icons.category_outlined,
                          label: entityType,
                          color: cs.onSurfaceVariant,
                        ),
                      if (entityId.isNotEmpty)
                        _Chip(
                          icon: Icons.tag_rounded,
                          label: _shortId(entityId),
                          color: cs.onSurfaceVariant,
                        ),
                      if (entityId.isEmpty && id.isNotEmpty)
                        _Chip(
                          icon: Icons.tag_rounded,
                          label: _shortId(id),
                          color: cs.onSurfaceVariant,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Merge candidate card.
// ─────────────────────────────────────────────────────────────────────────────
class _MergeCandidateCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final String rowKey;
  final bool busy;
  final Future<void> Function(Map<String, dynamic> item, String rowKey) onMerge;

  const _MergeCandidateCard({
    required this.item,
    required this.rowKey,
    required this.busy,
    required this.onMerge,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = _readString(item, ['name']);
    final phone = _readString(item, [
      'phone',
      'phoneNormalized',
      'phone_normalized',
    ]);
    final winnerId = _readString(item, ['winnerId', 'winner_id']);
    final loserId = _readString(item, ['loserId', 'loser_id']);
    final displayName = name.isEmpty ? 'Без имени' : name;

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColor.gold.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.icon),
                  ),
                  child: const Icon(
                    Icons.people_alt_rounded,
                    color: AppColor.gold,
                    size: 20,
                  ),
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (phone.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          phone,
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.md),
            _LeadRow(label: 'Основной', id: winnerId, color: AppColor.success),
            const SizedBox(height: 6),
            _LeadRow(label: 'Дубликат', id: loserId, color: cs.onSurfaceVariant),
            const SizedBox(height: AppSpace.md),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: busy ? null : () => onMerge(item, rowKey),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColor.gold,
                  foregroundColor: AppColor.onGold,
                  disabledBackgroundColor: AppColor.gold.withValues(alpha: 0.5),
                  disabledForegroundColor: AppColor.onGold,
                  elevation: 0,
                  shadowColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                ),
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColor.onGold,
                        ),
                      )
                    : const Icon(Icons.merge_type_rounded, size: 18),
                label: const Text('Объединить'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LeadRow extends StatelessWidget {
  final String label;
  final String id;
  final Color color;

  const _LeadRow({required this.label, required this.id, required this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        Expanded(
          child: Text(
            id.isEmpty ? '—' : id,
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 12,
              fontFamily: 'monospace',
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Merge confirmation dialog with a winner picker.
// ─────────────────────────────────────────────────────────────────────────────
class _MergeConfirmDialog extends StatefulWidget {
  final String name;
  final String phone;
  final String primaryId;
  final String secondaryId;

  const _MergeConfirmDialog({
    required this.name,
    required this.phone,
    required this.primaryId,
    required this.secondaryId,
  });

  @override
  State<_MergeConfirmDialog> createState() => _MergeConfirmDialogState();
}

class _MergeConfirmDialogState extends State<_MergeConfirmDialog> {
  late String _winnerId = widget.primaryId;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final displayName = widget.name.isEmpty ? 'этих лидов' : '«${widget.name}»';
    return AlertDialog(
      title: const Text('Объединить лиды?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Данные $displayName будут объединены. '
            'Выберите, какой лид останется основным.',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: AppSpace.md),
          _WinnerOption(
            id: widget.primaryId,
            selected: _winnerId == widget.primaryId,
            label: 'Лид 1 (по умолчанию)',
            onTap: () => setState(() => _winnerId = widget.primaryId),
          ),
          const SizedBox(height: 8),
          _WinnerOption(
            id: widget.secondaryId,
            selected: _winnerId == widget.secondaryId,
            label: 'Лид 2',
            onTap: () => setState(() => _winnerId = widget.secondaryId),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _winnerId),
          child: const Text(
            'Объединить',
            style: TextStyle(
              color: AppColor.gold,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _WinnerOption extends StatelessWidget {
  final String id;
  final bool selected;
  final String label;
  final VoidCallback onTap;

  const _WinnerOption({
    required this.id,
    required this.selected,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.control),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColor.goldSoft : cs.surface,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(
            color: selected ? AppColor.goldLine : cs.outlineVariant,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 18,
              color: selected ? AppColor.gold : cs.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    id.isEmpty ? '—' : id,
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared: chip, skeleton, error, empty.
// ─────────────────────────────────────────────────────────────────────────────
class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _Chip({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CardListSkeleton extends StatelessWidget {
  const _CardListSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        3,
        (_) => Card(
          margin: const EdgeInsets.only(bottom: AppSpace.sm),
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.md),
            child: Row(
              children: const [
                SkeletonBox(width: 40, height: 40, radius: AppRadius.icon),
                SizedBox(width: AppSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonLine(width: 140),
                      SizedBox(height: 8),
                      SkeletonLine(width: 220),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const _ErrorRetry({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          children: [
            Icon(Icons.error_outline_rounded, color: AppColor.danger, size: 32),
            const SizedBox(height: AppSpace.sm),
            Text(
              'Не удалось загрузить',
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$error',
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
            const SizedBox(height: AppSpace.md),
            OutlinedButton.icon(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColor.gold,
                side: const BorderSide(color: AppColor.goldLine),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          children: [
            Icon(icon, color: AppColor.success, size: 34),
            const SizedBox(height: AppSpace.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
